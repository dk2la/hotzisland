import SwiftUI

/// Shared scaffolding for the account forms on the Settings → Accounts page
/// (mail, assistant, and whatever connects next): the check-probe state,
/// the boxed text-field row, and the Check / Remove / Save action row.

/// State of the form's connectivity probe.
enum SetupCheckState: Equatable {
    case idle
    case checking
    case ok
    case failed(String)
}

/// A SettingRow whose control is a fixed-width "input box" of text fields.
struct SetupFieldRow<Fields: View>: View {
    let title: String
    var subtitle: String?
    let palette: WindowPalette
    var width: CGFloat = 260
    @ViewBuilder var fields: () -> Fields

    var body: some View {
        SettingRow(title: title, subtitle: subtitle, palette: palette) {
            HStack(spacing: 6) {
                fields()
            }
            .textFieldStyle(.plain)
            .font(Theme.bodyFont)
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: width)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// Check (with inline result/error text) · Remove (only when something is
/// saved) · Save.
struct SetupActionRow: View {
    let palette: WindowPalette
    let checkState: SetupCheckState
    let canCheck: Bool
    let canSave: Bool
    let showRemove: Bool
    let onCheck: () -> Void
    let onRemove: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCheck) {
                Text(checkLabel)
                    .font(Theme.subFont)
                    .foregroundStyle(checkColor)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(checkState == .checking || !canCheck)
            Spacer(minLength: 0)
            if showRemove {
                Button(action: onRemove) {
                    Text(L10n.t(.mailRemove))
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.critical.opacity(0.9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            Button(action: onSave) {
                Text(L10n.t(.mailSave))
                    .font(Theme.subFont)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.accentWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSave)
        }
        .padding(.top, 12)
    }

    private var checkLabel: String {
        switch checkState {
        case .idle: L10n.t(.mailCheck)
        case .checking: L10n.t(.mailChecking)
        case .ok: L10n.t(.mailCheckOk)
        case .failed(let message): message
        }
    }

    private var checkColor: Color {
        switch checkState {
        case .failed: Theme.critical.opacity(0.9)
        case .ok: palette.accent
        case .idle, .checking: palette.ink60
        }
    }
}
