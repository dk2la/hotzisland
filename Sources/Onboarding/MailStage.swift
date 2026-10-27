import SwiftUI

/// Mail: refresh pulls in a new message, it opens, a reply types itself in
/// the composer and goes out — the unread readout ticking along.
struct MailStage: View {
    @State private var refreshTurns = 0.0
    @State private var arrived = false
    @State private var opened = false
    @State private var typed = 0
    @State private var sendPressed = false
    @State private var sent = false

    private struct MockMail: Identifiable {
        let id: Int
        let sender: String
        let subject: L10nKey
        let time: String
    }

    private static let incoming = MockMail(id: 0, sender: "Daniel Kim", subject: .obMockMail3, time: "12:41")
    private static let inbox: [MockMail] = [
        MockMail(id: 1, sender: "Priya Nair", subject: .obMockMail1, time: "11:58"),
        MockMail(id: 2, sender: "Olivia Chen", subject: .obMockMail2, time: "09:15"),
    ]

    private var reply: TypedText { TypedText(L10n.t(.obMockReply), byWord: false) }

    /// Priya's mail stays unread; the arrival adds one until it is opened.
    private var unread: Int { 1 + (arrived && !opened ? 1 : 0) }

    var body: some View {
        StagePanel(title: NotchTab.email.title, badge: "\(unread)") {
            StageGlyph("square.and.pencil")
            StageGlyph("magnifyingglass")
            StageGlyph("arrow.clockwise")
                .rotationEffect(.degrees(refreshTurns * 360))
        } content: {
            VStack(spacing: 6) {
                if arrived {
                    row(Self.incoming, unread: !opened, raised: opened)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                row(Self.inbox[0], unread: true, raised: false)
                row(Self.inbox[1], unread: false, raised: false)
                Spacer(minLength: 0)
                if opened {
                    composer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .storyboard(finalFrame: {
            arrived = true
            opened = true
            typed = reply.count
            sent = true
        }, loop: play)
    }

    private func row(_ mail: MockMail, unread: Bool, raised: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            StageAvatar(name: mail.sender)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Theme.critical)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                        .opacity(unread ? 1 : 0)
                        .scaleEffect(unread ? 1 : 0.4)
                        .animation(.easeOut(duration: 0.2), value: unread)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(mail.sender)
                    .font(Theme.bodyFont)
                    .fontWeight(unread ? .semibold : .medium)
                    .lineLimit(1)
                    .foregroundStyle(unread ? Theme.textPrimary : Theme.textSecondary)
                Text(L10n.t(mail.subject))
                    .font(Theme.subFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Text(mail.time)
                .font(Theme.readoutSFont)
                .foregroundStyle(Theme.textQuaternary)
        }
        .cardRow(raised: unread || raised)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.accentBorder, lineWidth: 1)
                .opacity(raised ? 1 : 0)
        )
        .animation(.easeOut(duration: 0.2), value: raised)
    }

    /// The reply field; once sent it settles into a quiet "✓ Sent".
    @ViewBuilder
    private var composer: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        if sent {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(L10n.t(.mailSent))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: Theme.inputHeight)
            .background(Theme.cardFill, in: shape)
            .transition(.opacity)
        } else {
            HStack(spacing: 6) {
                HStack(spacing: 1) {
                    if typed == 0 {
                        Text(L10n.t(.mailReplyPlaceholder))
                            .foregroundStyle(Theme.textQuaternary)
                    } else {
                        Text(reply.prefix(typed))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    StageCaret()
                }
                .font(Theme.bodyFont)
                .lineLimit(1)
                Spacer(minLength: 0)
                StageButton(systemName: "arrow.up", size: 26, solid: typed > 0, pressed: sendPressed)
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .frame(height: Theme.inputHeight)
            .background(Theme.raisedFill.opacity(0.7), in: shape)
            .transition(.opacity)
        }
    }

    private func play() async -> Bool {
        guard await beat(0.9) else { return false }
        withAnimation(.easeInOut(duration: 0.6)) { refreshTurns += 1 }
        guard await beat(0.55) else { return false }
        withAnimation(Theme.stateSpring) { arrived = true }
        guard await beat(1.1) else { return false }
        withAnimation(Theme.stateSpring) { opened = true }
        guard await beat(0.6) else { return false }
        for count in 1...reply.count {
            typed = count
            guard await beat(0.045) else { return false }
        }
        guard await beat(0.45) else { return false }
        sendPressed = true
        guard await beat(0.12) else { return false }
        sendPressed = false
        withAnimation(.easeOut(duration: 0.25)) { sent = true }
        guard await beat(2.4) else { return false }
        withAnimation(.easeIn(duration: 0.3)) {
            arrived = false
            opened = false
        }
        guard await beat(0.5) else { return false }
        typed = 0
        sent = false
        return await beat(0.3)
    }
}
