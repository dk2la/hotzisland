import AppKit
import SwiftUI

/// The welcome tour, hosted in the expanded island like the settings, on
/// the same glass. One card per page: an illustration on top — the widget
/// itself, alive, over a colourful wallpaper its glass picks up — then the
/// words, then the way on.
struct IslandOnboardingView: View {
    var viewModel: NotchViewModel
    var services: ModuleServices
    @Bindable var settings: AppSettings
    let notchHeight: CGFloat

    /// Entry choreography: the card settles, the widget's strip pops in,
    /// its panel opens, then the words arrive.
    @State private var appeared = false

    static let cardHeight: CGFloat = 330

    private var step: OnboardingStep { viewModel.onboardingStep }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: notchHeight)
            illustration
                .padding(.horizontal, 14)
                .padding(.top, 14)
            copy
                .padding(.horizontal, 28)
                .padding(.top, 22)
            Spacer(minLength: 0)
            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
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

    // MARK: - Illustration

    private var illustration: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack {
            TourBackdrop()
            TourScene(step: step, appeared: appeared, hotkeys: services.hotkeys)
        }
        // A picture, not a control: only the close key takes clicks.
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity)
        .frame(height: Self.cardHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            GlassCloseButton {
                viewModel.onClose?()
            }
            .keyboardShortcut(.cancelAction)
            .padding(12)
        }
        .scaleEffect(appeared || Theme.reduceMotion ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .animation(Theme.stateSpring, value: appeared)
    }

    // MARK: - Copy

    private var copy: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.body)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                OnboardingAction(step: step, services: services)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(step)
            .transition(Self.copySwap)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || Theme.reduceMotion ? 0 : 8)
        .animation(Theme.stateSpring.delay(0.3), value: appeared)
    }

    private static var copySwap: AnyTransition {
        Theme.reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 6))
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
                PillButton(L10n.t(.obBack)) {
                    go(to: previous)
                }
                .transition(.opacity)
            }
            PillButton(L10n.t(step.isLast ? .obStart : .obNext), style: .primary) {
                if let next = step.next {
                    go(to: next)
                } else {
                    viewModel.onClose?()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .overlay {
            PageDots(current: step, onSelect: go(to:))
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.3).delay(0.4), value: appeared)
    }
}

// MARK: - Footer controls

/// Where the tour is: a dot per page, the current one stretched into a
/// pill. Each dot jumps to its page.
private struct PageDots: View {
    let current: OnboardingStep
    let onSelect: (OnboardingStep) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { item in
                let isCurrent = item == current
                Button {
                    onSelect(item)
                } label: {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(isCurrent ? 0.9 : item.rawValue < current.rawValue ? 0.45 : 0.2))
                        .frame(width: isCurrent ? 18 : 6, height: 6)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.panelTitle)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: current)
    }
}

/// "Show at launch" — the welcome-window checkbox, on glass.
private struct LaunchCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                let box = RoundedRectangle(cornerRadius: 5, style: .continuous)
                box.fill(isOn ? Theme.accent : Theme.textPrimary.opacity(0.08))
                    .overlay(box.strokeBorder(isOn ? .clear : Theme.textPrimary.opacity(0.25), lineWidth: 1))
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
                    .lineLimit(1)
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
                PillButton(L10n.t(.obConnect), systemName: "at", size: .small) {
                    requestSettings(page: .accounts)
                }
            }
        case .playbooks:
            PillButton(L10n.t(.playAdd), systemName: "plus", size: .small) {
                requestSettings(page: .playbooks)
            }
        case .notes:
            notesFolder
        case .assistant:
            if let config = services.assistantService.config {
                StatusChip(text: config.provider.title)
            } else {
                PillButton(L10n.t(.obConnect), systemName: "sparkles", size: .small) {
                    requestSettings(page: .accounts)
                }
            }
        case .welcome, .ready:
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
            PillButton(L10n.t(.obOpenPrivacy), systemName: "lock", size: .small) {
                NSWorkspace.shared.openPrivacyPane("Calendars")
            }
        case .unknown:
            PillButton(L10n.t(.obAllowAccess), systemName: "calendar", size: .small) {
                Task { await calendar.requestAccess() }
            }
        }
    }

    private var notesFolder: some View {
        let path = services.notesStore.folderURL.path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Text(path)
                    .font(Theme.readoutSFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(Theme.textPrimary.opacity(0.06)))
            PillButton(L10n.t(.notesChange), size: .small) {
                services.notesStore.pickFolder(activating: false)
            }
        }
    }
}

/// "● done" — the connected state, as the settings' integrations read it.
private struct StatusChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.accent.opacity(0.7), radius: 3)
            Text(text)
                .font(Theme.subFont)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Capsule().fill(Theme.textPrimary.opacity(0.06)))
    }
}
