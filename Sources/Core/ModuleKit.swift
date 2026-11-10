import SwiftUI

// Building blocks of the everyday modules (calendar, mail, playbooks,
// clipboard, notes, assistant): a hero card for the one thing worth seeing
// first, grouped lists under quiet section captions, an input bar at the
// bottom. Neutral surfaces; the accent is spent on a single action per
// screen and on "new / done" dots.

/// Small caps caption over a grouped list, with an optional note on the
/// right ("TODAY ……… 4").
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Theme.sectionFont)
                .kerning(0.8)
                .lineLimit(1)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// The large card on top of a module.
struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
        .contentShape(shape)
    }
}

/// Rows sharing one card, hairlines between them — each row applies
/// `groupedRow(isLast:)`.
struct GroupedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        VStack(spacing: 0) {
            content
        }
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
        .clipShape(shape)
    }
}

extension View {
    /// One row of a `GroupedCard`: 14/10 padding, a hairline under every
    /// row but the last.
    func groupedRow(isLast: Bool) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Hairline().padding(.leading, 14)
                }
            }
    }

    /// The caption line at the top of a hero card: an optional dot, then
    /// the label.
    func heroCaption() -> some View {
        font(Theme.subFont)
            .fontWeight(.medium)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }
}

/// A row's leading glyph on a raised square — playbook symbols, clipboard
/// kinds. `dashed` is the "add" placeholder.
struct IconTile: View {
    let systemName: String
    var size: CGFloat = 32
    var dashed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(dashed ? Theme.textTertiary : Theme.textPrimary)
            .frame(width: size, height: size)
            .background(shape.fill(dashed ? .clear : Theme.raisedFill))
            .overlay(
                shape.stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .opacity(dashed ? 1 : 0)
            )
    }
}

/// Small round status dot: unread mail, the next meeting, a live account.
struct StatusDot: View {
    var color: Color = Theme.accent
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// Text button of the everyday modules. `accent` is the screen's one main
/// action (Join, Run), `light` the neutral primary (Send, Copy), `ghost`
/// everything else. With no label it is a square icon button.
struct ModuleButton: View {
    enum Kind {
        case accent, light, ghost
    }

    var label: String?
    var systemName: String?
    var kind: Kind = .ghost
    var height: CGFloat = 32
    var enabled = true
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let label {
                    Text(label)
                        .font(Theme.subFont)
                        .fontWeight(kind == .ghost ? .medium : .semibold)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(kind == .ghost ? Theme.textPrimary : Theme.inkOnAccent)
            .padding(.horizontal, label == nil ? 0 : 14)
            .frame(minWidth: height, minHeight: height)
            .background(shape.fill(fill))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }

    private var fill: Color {
        switch kind {
        case .accent: Theme.accent
        case .light: Theme.lightFill
        case .ghost: Theme.raisedFill
        }
    }
}

/// The input row at the bottom of a module: mic, field and buttons on one
/// card.
struct ComposerBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        HStack(spacing: 8) {
            content
        }
        .padding(5)
        .frame(minHeight: Theme.inputHeight + 6)
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairline, lineWidth: 1))
    }
}

/// "in 12 min" with the digits set large — works for any language's word
/// order, since only the digit runs change size.
struct CountdownText: View {
    let text: String

    var body: some View {
        runs.reduce(Text("")) { result, run in
            result + (run.isNumber
                ? Text(run.text).font(Theme.countdownFont).foregroundColor(Theme.textPrimary)
                : Text(run.text).font(Theme.subFont).foregroundColor(Theme.textTertiary))
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    private var runs: [(text: String, isNumber: Bool)] {
        var result: [(text: String, isNumber: Bool)] = []
        for character in text {
            let isNumber = character.isNumber
            if let last = result.last, last.isNumber == isNumber {
                result[result.count - 1].text.append(character)
            } else {
                result.append((String(character), isNumber))
            }
        }
        return result
    }
}

/// Up to three avatars overlapping, then "+N".
struct AvatarStack: View {
    let names: [String]
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { _, name in
                avatar {
                    Text(SenderAvatarView.initials(name: name, address: ""))
                        .foregroundStyle(Color.white)
                }
                .background(SenderAvatarView.color(for: name), in: Circle())
            }
            if names.count > 3 {
                avatar {
                    Text("+\(names.count - 3)")
                        .foregroundStyle(Theme.textSecondary)
                }
                .background(Theme.raisedFill, in: Circle())
            }
        }
    }

    private func avatar<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        label()
            .font(.system(size: size * 0.38, weight: .semibold))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 2))
    }
}
