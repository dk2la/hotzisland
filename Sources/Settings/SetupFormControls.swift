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

/// Runs a form's connectivity probe and mirrors its progress into `state`.
@MainActor
func probeSetup(_ state: Binding<SetupCheckState>, _ probe: @escaping @Sendable () async -> Result<Void, Error>) {
    state.wrappedValue = .checking
    Task {
        switch await probe() {
        case .success: state.wrappedValue = .ok
        case .failure(let error): state.wrappedValue = .failed(error.localizedDescription)
        }
    }
}

/// A SettingRow whose control is a fixed-width "input box" of text fields.
struct SetupFieldRow<Fields: View>: View {
    let title: String
    var subtitle: String?
    var width: CGFloat = 260
    @ViewBuilder var fields: () -> Fields

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) {
            HStack(spacing: 6) {
                fields()
            }
            .textFieldStyle(.plain)
            .font(Theme.bodyFont)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: width)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// Check (with inline result/error text) · Remove (only when something is
/// saved) · Save.
struct SetupActionRow: View {
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
                PaletteButton(L10n.t(.mailRemove), color: Theme.critical.opacity(0.9), action: onRemove)
            }
            PaletteButton(L10n.t(.calSave), filled: true, action: onSave)
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
        case .ok: Palette.accent
        case .idle, .checking: Palette.ink60
        }
    }
}
