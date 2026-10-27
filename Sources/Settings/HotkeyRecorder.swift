import SwiftUI

/// A shortcut you can rebind: shows its key caps; click, and it listens for
/// the next combination (Esc or a second click cancels). A rejected
/// combination flashes the reason in place; a rebound shortcut gets a
/// reset key beside it.
struct HotkeyRecorder: View {
    let action: HotkeyService.Action
    var hotkeys: HotkeyService

    @State private var hovered = false

    private var isRecording: Bool { hotkeys.recording == action }

    private var rejection: String? {
        guard let rejection = hotkeys.rejection, rejection.action == action else { return nil }
        return rejection.error.message
    }

    var body: some View {
        HStack(spacing: 6) {
            if hotkeys.isCustomized(action), !isRecording {
                resetButton
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            Button {
                if isRecording {
                    hotkeys.cancelRecording()
                } else {
                    hotkeys.startRecording(action)
                }
            } label: {
                label
                    .padding(.horizontal, 5)
                    .frame(minWidth: 108, minHeight: 32)
                    .background(Capsule().fill(fill))
                    .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .onHover { hovered = $0 }
        }
        .animation(.easeOut(duration: 0.15), value: isRecording)
        .animation(.easeOut(duration: 0.15), value: hotkeys.isCustomized(action))
        .animation(.easeOut(duration: 0.2), value: rejection)
        // Leaving the page (or the island closing) must hand the shortcuts
        // back — they are switched off while recording.
        .onDisappear {
            if isRecording { hotkeys.cancelRecording() }
        }
    }

    @ViewBuilder
    private var label: some View {
        if isRecording {
            HStack(spacing: 7) {
                BlinkingDot(color: Theme.accent, size: 5)
                Text(L10n.t(.hkRecord))
                    .font(Theme.subFont)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
        } else if let rejection {
            Text(rejection)
                .font(Theme.subFont)
                .fontWeight(.medium)
                .foregroundStyle(Theme.critical)
                .lineLimit(1)
                .padding(.horizontal, 7)
        } else {
            HStack(spacing: 3) {
                ForEach(hotkeys.combo(for: action).keyCaps, id: \.self) { cap in
                    KeyCap(symbol: cap)
                }
            }
        }
    }

    private var fill: Color {
        if isRecording { return Theme.accentWash }
        return Theme.textPrimary.opacity(hovered ? 0.10 : 0.05)
    }

    private var stroke: Color {
        if isRecording { return Theme.accent.opacity(0.7) }
        if rejection != nil { return Theme.critical.opacity(0.6) }
        return Theme.textPrimary.opacity(hovered ? 0.18 : 0.10)
    }

    private var resetButton: some View {
        Button {
            hotkeys.reset(action)
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.textPrimary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(L10n.t(.hkReset))
    }
}
