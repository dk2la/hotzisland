import AppKit
import Carbon.HIToolbox
import Observation
import OSLog

/// Global hotkeys via Carbon's RegisterEventHotKey — the one macOS API that
/// gives system-wide shortcuts without Accessibility or Input Monitoring
/// permissions. NSEvent global monitors would need those; CGEventTap too.
///
/// Carbon delivers hotkey events on the main run loop, so the C callback can
/// assume MainActor and call straight into the registered handlers.
///
/// Every shortcut can be rebound from Settings → Hotkeys: the recorder
/// there captures the next key press, and the new combination replaces the
/// old registration at once. Rebindings persist; the factory set is ⌃⌥.
@MainActor
@Observable
final class HotkeyService {
    /// The app's shortcuts. Raw values are the Carbon hotkey ids.
    enum Action: UInt32, CaseIterable, Identifiable {
        /// Collapse the widget to a small square / restore it.
        case toggleWidgetHidden = 1
        /// Pin the panel: flips close-on-outside-click.
        case togglePanelPin = 2
        /// Open/close the settings island.
        case toggleSettings = 3

        var id: UInt32 { rawValue }

        /// Factory binding — ⌃⌥ is virtually never taken by other apps,
        /// unlike ⌘-based combos.
        var defaultCombo: KeyCombo {
            let key = switch self {
            case .toggleWidgetHidden: kVK_ANSI_H
            case .togglePanelPin: kVK_ANSI_P
            case .toggleSettings: kVK_ANSI_M
            }
            return KeyCombo(keyCode: UInt32(key), modifiers: UInt32(controlKey | optionKey))
        }

        @MainActor var title: String {
            switch self {
            case .toggleWidgetHidden: L10n.t(.setHideWidget)
            case .togglePanelPin: L10n.t(.setPinPanel)
            case .toggleSettings: L10n.t(.setModeToggle)
            }
        }

        fileprivate var defaultsKey: String { "hotkeys.binding.\(rawValue)" }
    }

    /// Why a combination was not taken.
    enum BindingError: Equatable {
        case needsModifier
        case taken(by: Action)
        case refused

        @MainActor var message: String {
            switch self {
            case .needsModifier: L10n.t(.hkNeedsModifier)
            case .taken(let other): L10n.f(.hkTaken, other.title)
            case .refused: L10n.t(.hkRefused)
            }
        }
    }

    /// User rebindings; actions without one use their default.
    private(set) var overrides: [Action: KeyCombo] = [:]

    /// The shortcut the recorder is capturing, if any. While it is set
    /// every hotkey is unregistered, so the combination being typed reaches
    /// the recorder instead of firing.
    private(set) var recording: Action?

    /// The last rejected attempt, shown on its row for a moment.
    private(set) var rejection: (action: Action, error: BindingError)?

    @ObservationIgnored private var handlers: [UInt32: () -> Void] = [:]
    @ObservationIgnored private var hotkeyRefs: [Action: EventHotKeyRef] = [:]
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var rejectionTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "hotkeys")

    /// Four-char-code namespace for our hotkey ids ("HTZI").
    private static let signature: OSType = 0x48545A49

    init() {
        for action in Action.allCases {
            if let combo = KeyCombo(storedValue: defaults.object(forKey: action.defaultsKey)) {
                overrides[action] = combo
            }
        }
    }

    func combo(for action: Action) -> KeyCombo {
        overrides[action] ?? action.defaultCombo
    }

    func isCustomized(_ action: Action) -> Bool {
        combo(for: action) != action.defaultCombo
    }

    func register(_ action: Action, handler: @escaping () -> Void) {
        installEventHandlerIfNeeded()
        handlers[action.rawValue] = handler
        activate(action)
    }

    // MARK: - Rebinding

    /// Binds `combo` to `action` and registers it right away. Returns why
    /// it could not, leaving the previous binding in place.
    @discardableResult
    func setCombo(_ combo: KeyCombo, for action: Action) -> BindingError? {
        guard combo.isAcceptable else { return .needsModifier }
        if let other = Action.allCases.first(where: { $0 != action && self.combo(for: $0) == combo }) {
            return .taken(by: other)
        }
        let previous = overrides[action]
        overrides[action] = combo
        guard activate(action) else {
            overrides[action] = previous
            activate(action)
            return .refused
        }
        if combo == action.defaultCombo {
            overrides[action] = nil
            defaults.removeObject(forKey: action.defaultsKey)
        } else {
            defaults.set(combo.storedValue, forKey: action.defaultsKey)
        }
        log.info("hotkey id=\(action.rawValue, privacy: .public) -> key=\(combo.keyCode, privacy: .public) mods=\(combo.modifiers, privacy: .public)")
        return nil
    }

    func reset(_ action: Action) {
        setCombo(action.defaultCombo, for: action)
    }

    /// Starts capturing the next key press for `action` — keyDown events
    /// of our key window (the island's panel) go to the recorder until a
    /// combination lands, Esc cancels, or `cancelRecording` is called.
    func startRecording(_ action: Action) {
        cancelRecording()
        clearRejection()
        recording = action
        for registered in Array(hotkeyRefs.keys) {
            deactivate(registered)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            MainActor.assumeIsolated {
                self?.capture(keyCode: keyCode, flags: flags)
            }
            return nil
        }
    }

    func cancelRecording() {
        guard recording != nil else { return }
        finishRecording()
    }

    private func capture(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let action = recording else { return }
        if Int(keyCode) == kVK_Escape, flags.intersection([.control, .option, .command, .shift]).isEmpty {
            finishRecording()
            return
        }
        guard let combo = KeyCombo(keyCode: keyCode, flags: flags) else { return }
        finishRecording()
        if let error = setCombo(combo, for: action) {
            reject(action, error)
        }
    }

    /// Ends capture and brings every shortcut back.
    private func finishRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        recording = nil
        for action in Action.allCases {
            activate(action)
        }
    }

    private func reject(_ action: Action, _ error: BindingError) {
        rejection = (action, error)
        rejectionTask?.cancel()
        rejectionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.rejection = nil
        }
    }

    private func clearRejection() {
        rejectionTask?.cancel()
        rejection = nil
    }

    // MARK: - Carbon

    /// (Re)registers `action` under its current combination. True when
    /// Carbon took it — or when nothing is to be registered yet.
    @discardableResult
    private func activate(_ action: Action) -> Bool {
        deactivate(action)
        guard handlers[action.rawValue] != nil, recording == nil else { return true }
        let combo = combo(for: action)
        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.error("hotkey registration failed id=\(action.rawValue, privacy: .public) status=\(status, privacy: .public)")
            return false
        }
        hotkeyRefs[action] = ref
        log.info("registered hotkey id=\(action.rawValue, privacy: .public)")
        return true
    }

    private func deactivate(_ action: Action) {
        if let ref = hotkeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
    }

    fileprivate func fire(id: UInt32) {
        log.info("hotkey fired id=\(id, privacy: .public)")
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventCallback,
            1,
            &spec,
            selfPointer,
            &eventHandler
        )
    }

    // No deinit: the service lives for the app's lifetime, and the OS tears
    // Carbon registrations down with the process. (A Swift 6 nonisolated
    // deinit could not touch the isolated refs anyway.)
}

/// C callback for Carbon. Fired on the main run loop, hence the assumption.
private func hotkeyEventCallback(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr else { return status }
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        service.fire(id: hotkeyID.id)
    }
    return noErr
}
