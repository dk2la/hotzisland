import AppKit
import SwiftUI

/// "Email" module: inbox list with unread dots; opening a message loads its
/// plain-text body and marks it read. Reply lands in the send phase.
struct EmailModuleView: View {
    var service: EmailService

    var body: some View {
        if service.config == nil {
            setupPrompt
        } else if let message = service.openMessage {
            EmailMessageView(service: service, message: message)
        } else {
            inbox
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            DashedZone(
                label: L10n.t(.mailSetupTitle),
                sublabel: L10n.t(.mailSetupSub)
            )
            .frame(maxHeight: 110)
            GlassCapsuleButton(label: L10n.t(.mailSetupAction), isPrimary: true) {
                NotificationCenter.default.post(
                    name: .hotzOpenSettings,
                    object: nil,
                    userInfo: ["page": SettingsView.Page.accounts.rawValue]
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow
            if service.messages.isEmpty {
                DashedZone(label: L10n.t(.mailInboxEmpty))
                    .frame(maxHeight: 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(service.messages) { message in
                            row(message)
                        }
                    }
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(Theme.subFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            if service.unreadCount > 0 {
                Text("\(service.unreadCount)")
                    .font(Theme.readoutSFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            CircleGlassButton(systemName: "arrow.clockwise", size: 26) {
                service.refresh()
            }
        }
    }

    private var statusColor: Color {
        switch service.connection {
        case .online: Theme.accent
        case .failed: Theme.critical
        case .connecting, .offline: Theme.textQuaternary
        }
    }

    private var statusText: String {
        switch service.connection {
        case .online: service.config?.email ?? ""
        case .connecting, .offline: L10n.t(.mailChecking)
        case .failed(let message): message
        }
    }

    private func row(_ message: EmailMessage) -> some View {
        Button {
            service.open(message)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(message.isUnread ? Theme.critical : .clear)
                    .frame(width: 5, height: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.fromName)
                        .font(.system(size: 12.5, weight: message.isUnread ? .semibold : .medium))
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary.opacity(message.isUnread ? 0.95 : 0.8))
                    Text(message.subject)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                Spacer(minLength: 0)
                Text(Self.time(message.date))
                    .font(Theme.readoutSFont)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                message.isUnread ? Theme.raisedFill.opacity(0.7) : Theme.cardFill,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: date)
    }
}

/// One opened message: headers, plain-text body, open-in-mail escape hatch.
struct EmailMessageView: View {
    var service: EmailService
    let message: EmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CircleGlassButton(systemName: "chevron.left", size: 28) {
                    service.closeMessage()
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.fromName)
                        .font(Theme.headlineFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary.opacity(0.95))
                    Text(message.fromAddress)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .foregroundStyle(Theme.textQuaternary)
                }
                Spacer(minLength: 0)
                GlassCapsuleButton(label: L10n.t(.mailOpenInApp)) {
                    openInMailApp()
                }
            }
            Text(message.subject)
                .font(Theme.titleFont)
                .lineLimit(2)
                .foregroundStyle(Theme.textPrimary.opacity(0.92))
            ScrollView(.vertical, showsIndicators: false) {
                if service.isLoadingBody, message.bodyPlain == nil {
                    Text("…")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Text(displayBody)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private var displayBody: String {
        let current = service.openMessage?.bodyPlain ?? message.bodyPlain
        let text = current?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? L10n.t(.mailNoBody) : text
    }

    private func openInMailApp() {
        if let raw = message.messageID?
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
            let url = URL(string: "message://%3C\(raw)%3E") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "mailto:") {
            NSWorkspace.shared.open(url)
        }
    }
}
