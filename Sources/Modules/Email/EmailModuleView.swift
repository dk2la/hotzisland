import AppKit
import SwiftUI

@MainActor
extension EmailMessage {
    /// A missing subject is localised at display time, not baked in on fetch.
    var displaySubject: String { subject.isEmpty ? L10n.t(.mailNoSubject) : subject }
}

@MainActor
extension Mailbox {
    var title: String {
        switch self {
        case .primary: L10n.t(.mailboxPrimary)
        case .starred: L10n.t(.mailboxStarred)
        case .important: L10n.t(.mailboxImportant)
        case .sent: L10n.t(.mailboxSent)
        case .spam: L10n.t(.mailboxSpam)
        }
    }

    var icon: String {
        switch self {
        case .primary: "tray"
        case .starred: "star"
        case .important: "bookmark"
        case .sent: "paperplane"
        case .spam: "xmark.bin"
        }
    }
}

/// "Email" module: inbox list with unread dots; opening a message loads its
/// body and marks it read. Navigation chrome (back, search toggle, refresh,
/// archive, open-in-Mail) lives in the shared panel header.
struct EmailModuleView: View {
    var service: EmailService
    var speech: SpeechCaptureService
    var avatars: SenderAvatarStore

    var body: some View {
        if service.config == nil {
            setupPrompt
        } else if service.isComposeOpen, service.composeMode == nil {
            EmailComposeView(service: service, speech: speech)
        } else if let message = service.openMessage {
            messageWithReplySheet(message)
        } else {
            inbox
        }
    }

    /// Below this panel height the reply form takes the whole panel: a
    /// split would leave neither half usable. Widen the widget to get both.
    private static let splitMinHeight: CGFloat = 520

    /// Reply/forward: the panel splits — the message keeps the top part and
    /// stays fully scrollable there, the form owns the bottom part. Nothing
    /// overlaps: the message's bottom edge is the form's top edge.
    private func messageWithReplySheet(_ message: EmailMessage) -> some View {
        GeometryReader { proxy in
            let split = proxy.size.height >= Self.splitMinHeight
            VStack(spacing: 0) {
                if !service.isComposeOpen || split {
                    EmailMessageView(service: service, speech: speech, avatars: avatars, message: message)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                if service.isComposeOpen {
                    EmailReplySheet(service: service, speech: speech, roundedTop: split)
                        .frame(height: split ? max(220, proxy.size.height * 0.55) : nil)
                        .frame(maxHeight: split ? nil : .infinity)
                        .transition(
                            Theme.reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Theme.stateSpring, value: service.isComposeOpen)
    }

    private var setupPrompt: some View {
        ModuleSetupPrompt(title: L10n.t(.mailSetupTitle), sublabel: L10n.t(.mailSetupSub))
    }

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 14) {
            mailboxRow
            if service.isSearchOpen {
                searchRow
            }
            list
            statusFooter
        }
    }

    /// Gmail-like sections as a row of equal tiles; the selected one is the
    /// light tile.
    private var mailboxRow: some View {
        HStack(spacing: 6) {
            ForEach(service.availableMailboxes, id: \.self) { mailbox in
                MailboxTile(
                    mailbox: mailbox,
                    selected: mailbox == service.selectedMailbox
                ) {
                    service.select(mailbox)
                }
            }
        }
        .animation(Theme.stateSpring, value: service.availableMailboxes)
    }

    @ViewBuilder
    private var list: some View {
        let shown = service.searchResults ?? service.messages
        if shown.isEmpty {
            EmptyStateZone(
                label: L10n.t(service.searchResults != nil ? .mailNoResults : .mailInboxEmpty)
            )
            .frame(maxHeight: 90)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Search results stay one list; the mailbox splits into what is
            // new and what has been read.
            let unread = service.searchResults == nil ? shown.filter(\.isUnread) : []
            let read = service.searchResults == nil ? shown.filter { !$0.isUnread } : shown
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if !unread.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: L10n.t(.mailSectionNew), trailing: "\(unread.count)")
                            group(unread)
                        }
                    }
                    if !read.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if !unread.isEmpty {
                                SectionHeader(title: L10n.t(.mailSectionEarlier))
                            }
                            group(read)
                        }
                    }
                }
            }
        }
    }

    private func group(_ messages: [EmailMessage]) -> some View {
        GroupedCard {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                row(message, isLast: index == messages.count - 1)
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            SearchQueryField(service: service)
            if service.isSearching {
                BlinkingDot(size: 5)
            } else if service.searchResults != nil {
                Button {
                    service.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textQuaternary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    /// Connection state, quietly at the bottom — it is status, not chrome.
    private var statusFooter: some View {
        HStack(spacing: 8) {
            StatusDot(color: statusColor)
            Text(statusText)
                .font(Theme.subFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            if service.didSend {
                Label(L10n.t(.mailSent), systemImage: "checkmark")
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .animation(Theme.stateSpring, value: service.didSend)
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

    private func row(_ message: EmailMessage, isLast: Bool) -> some View {
        // Sent mail is about who it went to, not who wrote it (that is us).
        let isSent = service.isSentMessage(message)
        let name = isSent ? message.recipientDisplay : message.fromName
        let address = isSent ? (message.to.first ?? "") : message.fromAddress
        return Button {
            service.open(message)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                SenderAvatarView(name: name, address: address, size: 34, store: avatars)
                    .opacity(message.isUnread ? 1 : 0.8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Theme.bodyFont)
                        .fontWeight(message.isUnread ? .semibold : .medium)
                        .lineLimit(1)
                        .foregroundStyle(message.isUnread ? Theme.textPrimary : Theme.textSecondary)
                    Text(message.displaySubject)
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(message.isUnread ? Theme.textSecondary : Theme.textTertiary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 7) {
                    Text(Self.time(message.date))
                        .font(Theme.subFont)
                        .monospacedDigit()
                        .foregroundStyle(message.isUnread ? Theme.textSecondary : Theme.textTertiary)
                    StatusDot(size: 7)
                        .opacity(message.isUnread ? 1 : 0)
                }
            }
            .groupedRow(isLast: isLast)
        }
        .buttonStyle(PressableStyle())
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: date)
    }
}

/// One mailbox tile: icon over the name. The selected one is the light
/// tile; the rest sit on card fill.
private struct MailboxTile: View {
    let mailbox: Mailbox
    let selected: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: selected ? "\(mailbox.icon).fill" : mailbox.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: 16)
                Text(mailbox.title)
                    .font(Theme.captionFont)
                    .fontWeight(selected ? .semibold : .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.inkOnAccent : Theme.textSecondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(shape.fill(selected ? Theme.lightFill : Theme.cardFill))
            .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: selected ? 0 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
    }
}

/// The query field grabs focus the moment the search row appears.
private struct SearchQueryField: View {
    var service: EmailService
    @FocusState private var focused: Bool

    var body: some View {
        TextField(L10n.t(.mailSearchPlaceholder), text: Bindable(service).searchQuery)
            .textFieldStyle(.plain)
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.textPrimary)
            .focused($focused)
            .onSubmit { service.runSearch() }
            .onAppear { focused = true }
    }
}

/// One opened message: sender/subject block, the body, and Reply / Reply
/// all / Forward buttons that open the reply sheet. Back, archive and
/// open-in-Mail live in the panel header.
struct EmailMessageView: View {
    var service: EmailService
    var speech: SpeechCaptureService
    var avatars: SenderAvatarStore
    let message: EmailMessage

    /// Remote content stays off until the user asks for it, per message —
    /// a tracking pixel must not fire just because the mail was opened.
    @State private var showImages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    SenderAvatarView(name: message.fromName, address: message.fromAddress, size: 38, store: avatars)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.fromName)
                            .font(Theme.headlineFont)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textPrimary)
                        Text(message.fromAddress)
                            .font(Theme.captionFont)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textQuaternary)
                    }
                    Spacer(minLength: 0)
                    Text(EmailModuleView.time(message.date))
                        .font(Theme.subFont)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(message.displaySubject)
                    .font(Theme.heroFont)
                    .lineLimit(2)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 4)
            Group {
                if service.isLoadingBody, message.bodyPlain == nil {
                    Text("…")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if let html = currentHTML {
                    // HTML mail goes through a real web engine, like Mail.app.
                    EmailBodyWebView(html: html, loadImages: showImages)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            GlassCapsuleButton(
                                label: L10n.t(showImages ? .mailHideImages : .mailShowImages),
                                systemName: showImages ? "photo.slash" : "photo"
                            ) {
                                showImages.toggle()
                            }
                            .padding(6)
                        }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(displayBody)
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
                    .stroke(Theme.hairlineSoft, lineWidth: 1)
            )
            if !service.isComposeOpen {
                HStack(spacing: 6) {
                    ModuleButton(label: L10n.t(.mailReplyAll), systemName: "arrowshape.turn.up.left.2") {
                        service.startReply(.replyAll)
                    }
                    ModuleButton(label: L10n.t(.mailForward), systemName: "arrowshape.turn.up.right") {
                        service.startReply(.forward)
                    }
                    Spacer(minLength: 0)
                    if service.didSend {
                        Label(L10n.t(.mailSent), systemImage: "checkmark")
                            .font(Theme.subFont)
                            .foregroundStyle(Theme.accent)
                            .transition(.opacity)
                    }
                }
                .animation(Theme.stateSpring, value: service.didSend)
                replyBar
            }
        }
        .onChange(of: message.key) { showImages = false }
    }

    /// Reads like an input, opens the reply form: the whole bar is the
    /// Reply button.
    private var replyBar: some View {
        Button {
            service.startReply(.reply)
        } label: {
            ComposerBar {
                Text(L10n.f(.mailReplyTo, firstName))
                    .font(Theme.bodyFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 9)
                Spacer(minLength: 0)
                Text(L10n.t(.mailReply))
                    .font(Theme.subFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.inkOnAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Theme.lightFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var firstName: String {
        let name = message.fromName.isEmpty ? message.fromAddress : message.fromName
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// The HTML travels in through the service as the body downloads.
    private var currentHTML: String? {
        service.openMessage?.bodyHTML ?? message.bodyHTML
    }

    private var displayBody: String {
        let current = service.openMessage?.bodyPlain ?? message.bodyPlain
        let text = current?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? L10n.t(.mailNoBody) : text
    }
}

/// Gmail-style compose form: To / Subject rows over a body editor. Serves
/// both replies (prefilled, threaded) and new mail. Back in the panel
/// header keeps the draft; Cancel discards it.
struct EmailComposeView: View {
    var service: EmailService
    var speech: SpeechCaptureService

    @FocusState private var toFocused: Bool
    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                MailFieldRow(label: L10n.t(.mailToField), text: Bindable(service).composeTo, focus: $toFocused)
                Hairline()
                MailFieldRow(label: L10n.t(.mailSubjectField), text: Bindable(service).composeSubject)
            }
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            MailDraftBody(service: service, speech: speech, focus: $bodyFocused, inset: 8, placeholder: .mailBodyPlaceholder)
        }
        .animation(Theme.stateSpring, value: speech.isRecording)
        .onAppear {
            if service.composeTo.isEmpty {
                toFocused = true
            } else {
                bodyFocused = true
            }
        }
    }
}

/// Compact reply/forward form shown as a bottom sheet over the open
/// message: mode title with a close button, To / Cc / Subject rows, the
/// body editor, then dictation and Cancel / Send. Close keeps the draft,
/// Cancel discards it.
struct EmailReplySheet: View {
    var service: EmailService
    var speech: SpeechCaptureService
    /// Rounded top when the sheet sits under the message; square when it
    /// fills the panel.
    var roundedTop = true

    @FocusState private var toFocused: Bool
    @FocusState private var bodyFocused: Bool
    /// Cc stays hidden until asked for or already filled (Reply all).
    @State private var showCc = false

    private var sheetShape: UnevenRoundedRectangle {
        let radius: CGFloat = roundedTop ? Theme.cardRadius : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: radius,
            style: .continuous
        )
    }

    private var title: String {
        switch service.composeMode {
        case .replyAll: L10n.t(.mailReplyAll)
        case .forward: L10n.t(.mailForward)
        case .reply, nil: L10n.t(.mailReply)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                HeaderIconButton("xmark", help: L10n.t(.mailCancel)) {
                    service.closeCompose()
                }
            }
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    MailFieldRow(label: L10n.t(.mailToField), text: Bindable(service).composeTo, focus: $toFocused, compact: true)
                    if !ccVisible {
                        Button {
                            showCc = true
                        } label: {
                            Text(L10n.t(.mailCc))
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.raisedFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .padding(.trailing, 10)
                    }
                }
                if ccVisible {
                    Hairline()
                    MailFieldRow(label: L10n.t(.mailCc), text: Bindable(service).composeCc, compact: true)
                }
                Hairline()
                MailFieldRow(label: L10n.t(.mailSubjectField), text: Bindable(service).composeSubject, compact: true)
            }
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            MailDraftBody(service: service, speech: speech, focus: $bodyFocused, inset: 6, placeholder: .mailReplyPlaceholder)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque on purpose: text being typed must never compete with the
        // message underneath — that one is scrolled in its own half.
        .background(sheetShape.fill(Theme.sheetFill))
        .overlay(alignment: .top) {
            Hairline(color: Theme.hairline)
        }
        .clipShape(sheetShape)
        .animation(Theme.stateSpring, value: speech.isRecording)
        .animation(Theme.stateSpring, value: ccVisible)
        .onAppear {
            showCc = !service.composeCc.isEmpty
            if service.composeTo.isEmpty {
                toFocused = true
            } else {
                bodyFocused = true
            }
        }
        .onChange(of: service.composeMode) {
            if !service.composeCc.isEmpty { showCc = true }
        }
    }

    private var ccVisible: Bool {
        showCc || !service.composeCc.isEmpty
    }
}

/// One labelled line of the mail forms; `compact` is the reply sheet's
/// tighter metrics.
private struct MailFieldRow: View {
    let label: String
    let text: Binding<String>
    var focus: FocusState<Bool>.Binding?
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Text(label)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textQuaternary)
                .frame(width: compact ? 44 : 52, alignment: .leading)
            Group {
                if let focus {
                    TextField("", text: text).focused(focus)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 7 : 9)
    }
}

/// Shared lower half of the mail forms: body editor with its placeholder,
/// the send error, dictation, Cancel / Send. A multi-child view, so the
/// parent stack's spacing still applies between the pieces.
private struct MailDraftBody: View {
    var service: EmailService
    var speech: SpeechCaptureService
    let focus: FocusState<Bool>.Binding
    let inset: CGFloat
    let placeholder: L10nKey

    var body: some View {
        TextEditor(text: Bindable(service).draft)
            .scrollContentBackground(.hidden)
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.textPrimary)
            .focused(focus)
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if service.draft.isEmpty {
                    Text(L10n.t(placeholder))
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textQuaternary)
                        .padding(.horizontal, inset + 5)
                        .padding(.vertical, inset + 8)
                        .allowsHitTesting(false)
                }
            }
        if let error = service.sendError {
            Text(error)
                .font(Theme.subFont)
                .lineLimit(2)
                .foregroundStyle(Theme.critical)
        }
        SpeechStatusRow(speech: speech)
        HStack(spacing: 8) {
            SpeechMicControl(speech: speech) { text in
                service.draft = service.draft.isEmpty ? text : service.draft + " " + text
            }
            Spacer(minLength: 0)
            ModuleButton(label: L10n.t(.mailCancel)) {
                service.discardCompose()
            }
            ModuleButton(
                label: service.isSending ? L10n.t(.mailSending) : L10n.t(.mailSend),
                kind: .light,
                enabled: service.canSendCompose
            ) {
                service.sendCompose()
            }
        }
    }
}
