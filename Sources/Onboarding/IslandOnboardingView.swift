import AppKit
import SwiftUI

/// The welcome tour, hosted in the expanded island like the settings and
/// built as the widget itself: a glass strip of page cells, a panel that
/// opens beside it, and the words to the right. Every page's panel plays a
/// short looping storyboard of the real module, drawn with the module's
/// own grammar — so the tour already looks like what it explains.
struct IslandOnboardingView: View {
    var viewModel: NotchViewModel
    var services: ModuleServices
    @Bindable var settings: AppSettings
    let notchHeight: CGFloat

    @Namespace private var railSpace
    /// Entry choreography: the strip's cells pop in, the panel opens out of
    /// the strip, then the words arrive.
    @State private var appeared = false

    static let stageSize = CGSize(width: 320, height: 356)

    private var step: OnboardingStep { viewModel.onboardingStep }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(alignment: .center, spacing: 0) {
                strip
                stage
                    .padding(.leading, WidgetMetrics.panelGap)
                copy
                    .padding(.leading, 30)
                    .padding(.trailing, 12)
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .topTrailing) {
            HeaderIconButton("xmark", help: L10n.t(.mailCancel)) {
                viewModel.onClose?()
            }
            .keyboardShortcut(.cancelAction)
            .padding(.top, notchHeight + 8)
            .padding(.trailing, 10)
        }
        .onAppear {
            guard !appeared else { return }
            // One tick later, so the entry runs as its own transaction on
            // top of the island's drop instead of merging into it.
            Task { appeared = true }
        }
    }

    private func go(to target: OnboardingStep) {
        guard target != step else { return }
        withAnimation(Theme.stateSpring) {
            viewModel.onboardingStep = target
        }
    }

    // MARK: - Strip

    /// The widget's own ornament: grip dots, then one cell per page. The
    /// active wash slides between cells like a selection on the widget.
    private var strip: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous)
        return VStack(spacing: WidgetMetrics.spacing) {
            gripDots
            ForEach(OnboardingStep.allCases) { item in
                StepCell(step: item, isActive: item == step, namespace: railSpace) {
                    go(to: item)
                }
                .scaleEffect(appeared || Theme.reduceMotion ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
                .animation(
                    Self.entrySpring.delay(0.08 + Double(item.rawValue) * 0.045),
                    value: appeared
                )
            }
        }
        .padding(.vertical, WidgetMetrics.endPadding)
        .frame(width: WidgetMetrics.thickness)
        .background(GlassSurface(shape: shape, dark: true))
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: appeared)
    }

    private var gripDots: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Theme.textPrimary.opacity(0.4))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(width: WidgetMetrics.cell, height: WidgetMetrics.gripSize)
    }

    /// Entry pops carry a touch of overshoot — the one place in the tour
    /// that bounces, like the live-event bulge on the island.
    private static var entrySpring: Animation {
        Theme.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.68)
    }

    // MARK: - Stage

    /// The panel the strip opens: one persistent glass window whose header
    /// and content swap per page, the way the widget's panel swaps modules.
    private var stage: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.windowRadius, style: .continuous)
        return ZStack {
            stageContent
                .id(step)
                .transition(Self.swap)
        }
        .frame(width: Self.stageSize.width, height: Self.stageSize.height)
        .background(GlassSurface(shape: shape, dark: true))
        .clipShape(shape)
        // A picture, not a control: clicks belong to the strip and buttons.
        .allowsHitTesting(false)
        .scaleEffect(appeared || Theme.reduceMotion ? 1 : 0.94, anchor: .leading)
        .opacity(appeared ? 1 : 0)
        .animation(Theme.stateSpring.delay(0.22), value: appeared)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch step {
        case .welcome: WelcomeStage()
        case .calendar: CalendarStage()
        case .mail: MailStage()
        case .playbooks: PlaybooksStage()
        case .notes: NotesStage()
        case .assistant: AssistantStage()
        case .ready: ReadyStage()
        }
    }

    /// Page swap: the old page gets out of the way fast, the new one
    /// settles in a beat later — the widget's opening grammar, smaller.
    private static var swap: AnyTransition {
        Theme.reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    .animation(.easeOut(duration: 0.28).delay(0.08)),
                removal: .opacity.animation(.easeOut(duration: 0.12))
            )
    }

    // MARK: - Copy

    private var copy: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 0) {
                InstrumentLabel(step.counter, color: Theme.textQuaternary)
                Text(step.title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(step.body)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                OnboardingAction(step: step, services: services)
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(step)
            .transition(Self.copySwap)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || Theme.reduceMotion ? 0 : 8)
        .animation(Theme.stateSpring.delay(0.32), value: appeared)
    }

    private static var copySwap: AnyTransition {
        Theme.reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8))
                    .animation(.easeOut(duration: 0.3).delay(0.1)),
                removal: .opacity.animation(.easeOut(duration: 0.12))
            )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            LaunchCheckbox(isOn: $settings.showOnboardingAtLaunch)
            Spacer(minLength: 0)
            if let previous = step.previous {
                GlassCapsuleButton(label: L10n.t(.obBack)) {
                    go(to: previous)
                }
                .transition(.opacity)
            }
            GlassCapsuleButton(label: L10n.t(step.isLast ? .obStart : .obNext), isPrimary: true) {
                if let next = step.next {
                    go(to: next)
                } else {
                    viewModel.onClose?()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Hairline(color: Theme.hairlineSoft)
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(0.4), value: appeared)
    }
}

// MARK: - Strip cell

/// One page cell — the widget's rail cell, with the selection wash shared
/// across cells so it slides instead of blinking.
private struct StepCell: View {
    let step: OnboardingStep
    let isActive: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        let cellShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            Image(systemName: step.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
                .frame(width: WidgetMetrics.cell, height: WidgetMetrics.cell)
                .background {
                    if isActive {
                        cellShape
                            .fill(Theme.accentWash)
                            .overlay(cellShape.stroke(Theme.accent.opacity(0.18), lineWidth: 1))
                            .matchedGeometryEffect(id: "active", in: namespace)
                    } else if hovered {
                        cellShape.fill(Theme.raisedFill)
                    }
                }
                .contentShape(cellShape)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(step.panelTitle)
    }
}

// MARK: - Footer controls

/// "Show at launch" — the welcome-window checkbox, in the rack's palette.
private struct LaunchCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? Theme.accent : Theme.raisedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isOn ? .clear : Theme.dashedBorder, lineWidth: 1)
                    )
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Theme.inkOnAccent)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                    .frame(width: 16, height: 16)
                Text(L10n.t(.obShowAtLaunch))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

// MARK: - Page actions

/// The one real thing a page can do: grant access, connect an account,
/// pick the notes folder. Shows the state once it is done.
private struct OnboardingAction: View {
    let step: OnboardingStep
    var services: ModuleServices

    var body: some View {
        switch step {
        case .calendar:
            calendarAction
        case .mail:
            if let config = services.emailService.config {
                StatusChip(text: config.email)
            } else {
                GlassCapsuleButton(label: L10n.t(.obConnect), systemName: "at", isPrimary: false) {
                    requestSettings(page: .accounts)
                }
            }
        case .playbooks:
            GlassCapsuleButton(label: L10n.t(.playAdd), systemName: "plus") {
                requestSettings(page: .playbooks)
            }
        case .notes:
            notesFolder
        case .assistant:
            if let config = services.assistantService.config {
                StatusChip(text: config.provider.title)
            } else {
                GlassCapsuleButton(label: L10n.t(.obConnect), systemName: "sparkles") {
                    requestSettings(page: .accounts)
                }
            }
        case .ready:
            hotkeys
        case .welcome:
            EmptyView()
        }
    }

    @ViewBuilder
    private var calendarAction: some View {
        let calendar = services.calendarService
        switch calendar.access {
        case .granted:
            StatusChip(text: L10n.t(.obAccessGranted))
        case .denied:
            GlassCapsuleButton(label: L10n.t(.obOpenPrivacy), systemName: "lock") {
                NSWorkspace.shared.openPrivacyPane("Calendars")
            }
        case .unknown:
            GlassCapsuleButton(label: L10n.t(.obAllowAccess), systemName: "calendar") {
                Task { await calendar.requestAccess() }
            }
        }
    }

    private var notesFolder: some View {
        let path = services.notesStore.folderURL.path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(path)
                .font(Theme.readoutSFont)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            PaletteButton(L10n.t(.notesChange)) {
                services.notesStore.pickFolder(activating: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    /// The three global shortcuts worth knowing on day one.
    private var hotkeys: some View {
        VStack(alignment: .leading, spacing: 10) {
            hotkeyRow(HotkeyService.Action.toggleWidgetHidden.keyCaps, L10n.t(.setHideWidget))
            hotkeyRow(HotkeyService.Action.togglePanelPin.keyCaps, L10n.t(.setPinPanel))
            hotkeyRow(HotkeyService.Action.toggleSettings.keyCaps, L10n.t(.setOpenSettings))
        }
    }

    private func hotkeyRow(_ caps: [String], _ title: String) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(caps, id: \.self) { KeyCap(symbol: $0) }
            }
            .frame(width: 92, alignment: .leading)
            Text(title)
                .font(Theme.subFont)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// "✓ done" readout for a page whose action is already taken care of.
private struct StatusChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(Theme.subFont)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}
