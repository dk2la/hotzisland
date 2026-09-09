import SwiftUI

/// The one header every module panel gets: `[back?] TITLE …… [actions] [✕]`.
/// Modules draw no chrome of their own — their navigation state lives in the
/// services and this view reads it, so every tab speaks the same grammar:
/// chevron to go up, module title, the module's few actions on the right.
/// The island's expanded panel embeds the same back/actions pieces next to
/// its tab row.
struct PanelHeaderView: View {
    let tab: NotchTab
    var services: ModuleServices
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ModuleBackButton(tab: tab, services: services)
            Text(tab.title.uppercased())
                .font(Theme.labelFont)
                .kerning(1.2)
                .foregroundStyle(Theme.accent)
            if tab == .email, let badge = services.emailService.unreadBadge {
                Text(badge)
                    .font(Theme.readoutSFont)
                    .foregroundStyle(Theme.critical)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
            ModuleAccessoriesView(tab: tab, services: services)
            HeaderIconButton("xmark", action: onClose)
        }
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Hairline(color: Theme.hairline)
        }
    }
}

/// Chevron shown whenever the module is one level deep; always returns to
/// the module's root.
struct ModuleBackButton: View {
    let tab: NotchTab
    var services: ModuleServices

    var body: some View {
        if let back = backAction {
            HeaderIconButton("chevron.left", action: back)
        }
    }

    private var backAction: (() -> Void)? {
        switch tab {
        case .email:
            if services.emailService.isComposeOpen {
                { services.emailService.closeCompose() }
            } else if services.emailService.openMessage != nil {
                { services.emailService.closeMessage() }
            } else {
                nil
            }
        case .notes:
            services.notesStore.openNote != nil
                ? {
                    services.notesStore.commitTitle()
                    services.notesStore.closeEditor()
                }
                : nil
        case .calendar:
            services.calendarService.showingPicker
                ? { services.calendarService.showingPicker = false }
                : nil
        default:
            nil
        }
    }
}

/// The module's few header actions — the same set on the widget panel and
/// the island.
struct ModuleAccessoriesView: View {
    let tab: NotchTab
    var services: ModuleServices

    var body: some View {
        switch tab {
        case .email:
            emailAccessories
        case .calendar:
            calendarAccessories
        case .assistant:
            assistantAccessories
        case .notes:
            if services.notesStore.openNote == nil {
                HeaderIconButton("plus", help: L10n.t(.notesNew)) {
                    services.notesStore.create()
                }
            }
        case .clipboard:
            if !services.clipboardStore.entries.isEmpty {
                HeaderIconButton("trash", help: L10n.t(.clipClear)) {
                    services.clipboardStore.clear()
                }
            }
        case .playbooks:
            HeaderIconButton("plus", help: L10n.t(.playAdd)) {
                NotificationCenter.default.post(name: .hotzOpenSettings, object: nil)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var emailAccessories: some View {
        let service = services.emailService
        if service.config != nil, !service.isComposeOpen {
            if let message = service.openMessage {
                HeaderIconButton("archivebox", help: L10n.t(.mailArchive)) {
                    service.archive(message)
                }
                HeaderIconButton("arrow.up.forward.app", help: L10n.t(.mailOpenInApp)) {
                    service.openInMailApp()
                }
            } else {
                HeaderIconButton("square.and.pencil", help: L10n.t(.mailNewMessage)) {
                    service.startNewMail()
                }
                HeaderIconButton(
                    "magnifyingglass",
                    help: L10n.t(.mailSearch),
                    active: service.isSearchOpen
                ) {
                    service.toggleSearch()
                }
                HeaderIconButton("arrow.clockwise", help: L10n.t(.mailRefresh)) {
                    service.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private var calendarAccessories: some View {
        let service = services.calendarService
        if service.access == .granted, !service.showingPicker {
            ForEach(CalendarDisplayMode.allCases) { mode in
                HeaderIconButton(mode.icon, active: service.displayMode == mode) {
                    service.setDisplayMode(mode)
                }
            }
            HeaderIconButton("line.3.horizontal.decrease") {
                service.showingPicker = true
            }
        }
    }

    @ViewBuilder
    private var assistantAccessories: some View {
        let assistant = services.assistantService
        if assistant.config != nil {
            HeaderIconButton("waveform", active: assistant.isVoiceMode) {
                let enabled = !assistant.isVoiceMode
                assistant.setVoiceMode(enabled)
                if !enabled {
                    services.speechSynthesis.stop()
                }
            }
            if !assistant.transcript.isEmpty {
                HeaderIconButton("trash") {
                    services.speechSynthesis.stop()
                    assistant.clearTranscript()
                }
            }
        }
    }
}

struct HeaderIconButton: View {
    let systemName: String
    var help: String?
    var active = false
    let action: () -> Void

    @State private var hovered = false

    init(
        _ systemName: String,
        help: String? = nil,
        active: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.help = help
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : hovered ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered ? Theme.raisedFill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(help ?? "")
    }
}
