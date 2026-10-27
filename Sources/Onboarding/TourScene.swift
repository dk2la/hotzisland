import SwiftUI

/// What stands on the illustration card: the widget — strip and open
/// panel — for every page but the last, where the card becomes a desktop
/// and the strip is carried around its edges.
struct TourScene: View {
    let step: OnboardingStep
    let appeared: Bool
    var hotkeys: HotkeyService

    var body: some View {
        ZStack {
            if step == .ready {
                ReadyScene(scale: MiniWidget.scale, hotkeys: hotkeys)
                    .transition(.opacity.animation(.easeInOut(duration: 0.35)))
            } else {
                MiniWidget(step: step, appeared: appeared)
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The widget at card scale: its strip of module cells and, beside it, the
/// panel the strip opened — drawn with the real materials and metrics.
/// One persistent view across pages: the strip's selection slides to the
/// page's module, the panel swaps its content as the real one does.
struct MiniWidget: View {
    let step: OnboardingStep
    let appeared: Bool

    /// Built at the widget's true size, shown at this scale.
    static let scale: CGFloat = 0.84
    static let panelSize = CGSize(width: 320, height: 356)
    static let tabs: [NotchTab] = [.calendar, .email, .playbooks, .notes, .assistant]

    @Namespace private var selection

    private var size: CGSize {
        CGSize(
            width: WidgetMetrics.thickness + WidgetMetrics.panelGap + Self.panelSize.width,
            height: Self.panelSize.height
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: WidgetMetrics.panelGap) {
            MiniStrip(
                tabs: Self.tabs,
                active: step.tab,
                appeared: appeared,
                namespace: selection
            )
            panel
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(Self.scale)
        .frame(width: size.width * Self.scale, height: size.height * Self.scale)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }

    /// Opens out of the strip the way the widget's panel does: a small
    /// scale from the strip's side, with a fade.
    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.windowRadius, style: .continuous)
        return ZStack {
            stage
                .id(step)
                .transition(Self.swap)
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background(GlassSurface(shape: shape, dark: true))
        .clipShape(shape)
        .scaleEffect(appeared || Theme.reduceMotion ? 1 : 0.94, anchor: .leading)
        .opacity(appeared ? 1 : 0)
        .animation(Theme.stateSpring.delay(0.3), value: appeared)
    }

    @ViewBuilder
    private var stage: some View {
        switch step {
        case .welcome: WelcomeStage()
        case .calendar: CalendarStage()
        case .mail: MailStage()
        case .playbooks: PlaybooksStage()
        case .notes: NotesStage()
        case .assistant: AssistantStage()
        case .ready: EmptyView()
        }
    }

    /// Page swap: the old page gets out of the way fast, the new one
    /// settles in a beat later.
    private static var swap: AnyTransition {
        Theme.reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    .animation(.easeOut(duration: 0.28).delay(0.08)),
                removal: .opacity.animation(.easeOut(duration: 0.12))
            )
    }
}

/// The widget's ornament strip: grip dots, then a cell per module, the
/// open one washed in the accent. Vertical or horizontal, like the real
/// one on a side or on the top/bottom edge.
struct MiniStrip: View {
    let tabs: [NotchTab]
    let active: NotchTab?
    var vertical = true
    var appeared = true
    var namespace: Namespace.ID?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous)
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: WidgetMetrics.spacing))
            : AnyLayout(HStackLayout(spacing: WidgetMetrics.spacing))
        return layout {
            gripDots
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                cell(tab)
                    .scaleEffect(appeared || Theme.reduceMotion ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)
                    .animation(Self.pop.delay(0.08 + Double(index) * 0.05), value: appeared)
            }
        }
        .padding(vertical ? .vertical : .horizontal, WidgetMetrics.endPadding)
        .frame(
            width: vertical ? WidgetMetrics.thickness : nil,
            height: vertical ? nil : WidgetMetrics.thickness
        )
        .background(GlassSurface(shape: shape, dark: true))
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: appeared)
    }

    private var gripDots: some View {
        let dots = vertical
            ? AnyLayout(HStackLayout(spacing: 3))
            : AnyLayout(VStackLayout(spacing: 3))
        return dots {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Theme.textPrimary.opacity(0.4))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(
            width: vertical ? WidgetMetrics.cell : WidgetMetrics.gripSize,
            height: vertical ? WidgetMetrics.gripSize : WidgetMetrics.cell
        )
    }

    private func cell(_ tab: NotchTab) -> some View {
        let isActive = tab == active
        let cellShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Image(systemName: tab.icon)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
            .frame(width: WidgetMetrics.cell, height: WidgetMetrics.cell)
            .background {
                if isActive {
                    if let namespace {
                        cellShape.fill(Theme.accentWash)
                            .matchedGeometryEffect(id: "active", in: namespace)
                    } else {
                        cellShape.fill(Theme.accentWash)
                    }
                }
            }
    }

    /// Entry pops carry a touch of overshoot, like the live-event bulge.
    private static var pop: Animation {
        Theme.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.68)
    }
}
