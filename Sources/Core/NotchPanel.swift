import AppKit

/// Borderless non-activating panel over the notch: above the menu bar,
/// on all Spaces, visible over fullscreen apps.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Must come after `isFloatingPanel`, which silently resets the level
        // to `.floating` — otherwise the island ends up below menu bar icons.
        level = .screenSaver
    }

    /// Text input (Notes editor, Email reply, Assistant composer) needs key
    /// status. `.nonactivatingPanel` + key gives Spotlight-style typing: the
    /// panel becomes key without activating the app. Controllers flip this
    /// only while a module panel is open.
    var allowsKeyFocus = false

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }

    /// LSUIElement apps have no main menu, so ⌘C/⌘V/⌘A/⌘Z resolve to
    /// nothing. Route the standard editing selectors to the responder chain.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        let selector: Selector? = switch event.charactersIgnoringModifiers {
        case "x": #selector(NSText.cut(_:))
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": Selector(("undo:"))
        default: nil
        }
        if let selector, NSApp.sendAction(selector, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// By default macOS keeps windows out of the menu bar territory —
    /// a window living in the notch must opt out of that constraint.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
