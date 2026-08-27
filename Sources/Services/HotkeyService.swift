import Carbon.HIToolbox
import Foundation
import OSLog

/// Global hotkeys via Carbon's RegisterEventHotKey — the one macOS API that
/// gives system-wide shortcuts without Accessibility or Input Monitoring
/// permissions. NSEvent global monitors would need those; CGEventTap too.
///
/// Carbon delivers hotkey events on the main run loop, so the C callback can
/// assume MainActor and call straight into the registered handlers.
@MainActor
final class HotkeyService {
    /// The app's shortcuts. Raw values are the Carbon hotkey ids.
    enum Action: UInt32, CaseIterable {
        /// ⌃⌥H — collapse the widget to a small square / restore it.
        case toggleWidgetHidden = 1
        /// ⌃⌥P — pin the panel: flips close-on-outside-click.
        case togglePanelPin = 2

        var keyCode: UInt32 {
            switch self {
            case .toggleWidgetHidden: UInt32(kVK_ANSI_H)
            case .togglePanelPin: UInt32(kVK_ANSI_P)
            }
        }

        /// Carbon modifier mask (all shortcuts share ⌃⌥ — it is virtually
        /// never taken by other apps, unlike ⌘-based combos).
        var carbonModifiers: UInt32 { UInt32(controlKey | optionKey) }

        /// Display form for the settings page.
        var keyCaps: [String] {
            switch self {
            case .toggleWidgetHidden: ["⌃", "⌥", "H"]
            case .togglePanelPin: ["⌃", "⌥", "P"]
            }
        }
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "hotkeys")

    /// Four-char-code namespace for our hotkey ids ("HTZI").
    private static let signature: OSType = 0x48545A49

    func register(_ action: Action, handler: @escaping () -> Void) {
        installEventHandlerIfNeeded()
        handlers[action.rawValue] = handler

        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            action.keyCode,
            action.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotkeyRefs.append(ref)
            log.info("registered hotkey id=\(action.rawValue, privacy: .public)")
        } else {
            log.error("hotkey registration failed id=\(action.rawValue, privacy: .public) status=\(status, privacy: .public)")
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
