import AppKit
import SwiftUI

@MainActor
extension EmailMessage {
    /// A missing subject is localised at display time, not baked in on fetch.
    var displaySubject: String { subject.isEmpty ? L10n.t(.mailNoSubject) : subject }
}

/// "Email" module: inbox list with unread dots; opening a message loads its
/// body and marks it read. Navigation chrome (back, search toggle, refresh,
/// archive, open-in-Mail) lives in the shared panel header.
struct EmailModuleView: View {
    var service: EmailService
    var speech: SpeechCaptureService

    var body: some View {
        if service.config == nil {
            setupPrompt
        } else if service.isComposeOpen {
            EmailComposeView(service: service, speech: speech)
        } else if let message = service.openMessage {
            EmailMessageView(service: service, speech: speech, message: message)
        } else {
            inbox
        }
    }

    private var setupPrompt: some View {
        ModuleSetupPrompt(title: L10n.t(.mailSetupTitle), sublabel: L10n.t(.mailSetupSub))
    }

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if service.isSearchOpen {
                searchRow
            }
            list
            statusFooter
        }
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(shown) { message in
                        row(message)
                    }
                }
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Theme.raisedFill.opacity(0.7),
            in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        )
    }

    /// Connection state, quietly at the bottom — it is status, not chrome.
    private var statusFooter: some View {
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
            if service.didSend {
                Label(L10n.t(.mailSent), systemImage: "checkmark")
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }
        }
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
                        .font(Theme.bodyFont)
                        .fontWeight(message.isUnread ? .semibold : .medium)
                        .lineLimit(1)
                        .foregroundStyle(message.isUnread ? Theme.textPrimary : Theme.textSecondary)
                    Text(message.displaySubject)
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textTertiary)
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

/// One opened message: sender/subject block, the body, a Reply button that
/// opens the compose form. Back, archive and open-in-Mail live in the panel
/// header.
struct EmailMessageView: View {
    var service: EmailService
    var speech: SpeechCaptureService
    let message: EmailMessage

    /// Images load by default — newsletters are unreadable without them.
    /// The escape hatch is per message: hiding them also stops the sender's
    /// tracking pixels for that view.
    @State private var showImages = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.fromName)
                        .font(Theme.headlineFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    Text(EmailModuleView.time(message.date))
                        .font(Theme.readoutSFont)
                        .foregroundStyle(Theme.textQuaternary)
                }
                Text(message.fromAddress)
                    .font(Theme.captionFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textQuaternary)
                Text(message.displaySubject)
                    .font(Theme.titleFont)
                    .lineLimit(2)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
            }
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
            .padding(10)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            HStack(spacing: 8) {
                GlassCapsuleButton(label: L10n.t(.mailReply), systemName: "arrowshape.turn.up.left", isPrimary: true) {
                    service.startReply()
                }
                if service.didSend {
                    Label(L10n.t(.mailSent), systemImage: "checkmark")
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .animation(Theme.stateSpring, value: service.didSend)
        }
        .onChange(of: message.uid) { showImages = true }
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
                fieldRow(
                    label: L10n.t(.mailToField),
                    text: Bindable(service).composeTo,
                    focus: $toFocused
                )
                Hairline()
                fieldRow(label: L10n.t(.mailSubjectField), text: Bindable(service).composeSubject)
            }
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            TextEditor(text: Bindable(service).draft)
                .scrollContentBackground(.hidden)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($bodyFocused)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if service.draft.isEmpty {
                        Text(L10n.t(.mailBodyPlaceholder))
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.textQuaternary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
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
                GlassCapsuleButton(label: L10n.t(.mailCancel)) {
                    service.discardCompose()
                }
                GlassCapsuleButton(
                    label: service.isSending ? L10n.t(.mailSending) : L10n.t(.mailSend),
                    isPrimary: true,
                    enabled: service.canSendCompose
                ) {
                    service.sendCompose()
                }
            }
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

    private func fieldRow(
        label: String,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textQuaternary)
                .frame(width: 52, alignment: .leading)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
