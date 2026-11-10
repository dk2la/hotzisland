import SwiftUI

struct CapsuleRootView: View {
    var viewModel: CapsuleViewModel
    var services: ModuleServices
    var settings: AppSettings
    let closedSize: CGSize

    private var isExpanded: Bool { viewModel.state == .expanded }

    /// The capsule around the housing: housing-sized at rest, wider for a
    /// live event or the compact indicators. Never wider while expanded —
    /// the panel grows below the menu bar instead.
    private var capsuleSize: CGSize {
        if isExpanded { return closedSize }
        if viewModel.activeEvent != nil {
            return CapsuleGeometry.capsule(closedSize, side: CapsuleMetrics.eventSideWidth)
        }
        if viewModel.state == .compact,
           services.timerService.isRunning || services.mediaCenter.track != nil {
            return CapsuleGeometry.capsule(closedSize, side: CapsuleMetrics.compactSideWidth)
        }
        return closedSize
    }

    private static var fillet: CGFloat { CapsuleMetrics.dropFillet }

    /// The housing itself, without the capsule's flares: the neck through
    /// the menu bar is exactly this wide, never more.
    private var housingWidth: CGFloat {
        max(0, closedSize.width - 2 * CapsuleMetrics.closedTopRadius)
    }

    /// The drop: a neck exactly the housing's width through the menu bar,
    /// concave shoulders just below it, then the panel. Collapsed it is
    /// exactly the housing — black on black, invisible — and both axes
    /// animate from there, so the menu bar beside the camera housing is never
    /// covered at any point.
    private var dropSize: CGSize {
        if isExpanded {
            let panel = viewModel.panelSize(for: viewModel.content, settings: settings)
            return CGSize(
                width: panel.width,
                height: panel.height + closedSize.height + Self.fillet
            )
        }
        // Shorter than the capsule by its bottom radius: the sliver's square
        // bottom stays hidden above the capsule's rounded corners.
        return CGSize(
            width: housingWidth,
            height: max(0, closedSize.height - CapsuleMetrics.closedBottomRadius - 2)
        )
    }

    private var capsuleShape: CapsuleShape {
        CapsuleShape(
            topRadius: CapsuleMetrics.closedTopRadius,
            bottomRadius: CapsuleMetrics.closedBottomRadius
        )
    }

    private var dropShape: CapsuleDropShape {
        CapsuleDropShape(
            neckWidth: housingWidth,
            neckHeight: closedSize.height + Self.fillet,
            cornerRadius: CapsuleMetrics.dropRadius,
            fillet: Self.fillet
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            drop
            // The flared capsule belongs to the resting states; expanded,
            // the exact-width neck takes over and the flares fade away.
            capsule
                .opacity(isExpanded ? 0 : 1)
                .animation(Theme.stateSpring, value: isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The resting capsule: live events and compact indicators live here.
    private var capsule: some View {
        InstrumentShell(
            shape: capsuleShape,
            theme: settings.theme,
            accent: services.mediaCenter.artworkAccent
        )
            .overlay {
                if isExpanded {
                    EmptyView()
                } else if let event = viewModel.activeEvent {
                    LiveEventView(event: event)
                        .transition(.opacity)
                } else if viewModel.state == .compact, services.timerService.isRunning {
                    // A running timer outranks media: it is the thing the
                    // user explicitly started and it has a deadline.
                    CompactTimerView(timer: services.timerService)
                        .transition(.opacity)
                } else if viewModel.state == .compact, let track = services.mediaCenter.track {
                    CompactMediaView(track: track)
                        .transition(.opacity)
                }
            }
            .clipShape(capsuleShape)
            .contentShape(capsuleShape)
            // A click on the resting capsule opens the settings; the expanded
            // panel hosts its own controls, so the tap is inert there.
            .onTapGesture {
                if !isExpanded { viewModel.onCapsuleTapped?() }
            }
            .contextMenu {
                Button(L10n.t(.menuSettings)) {
                    viewModel.onCapsuleTapped?()
                }
                Button(L10n.t(.obTour)) {
                    requestOnboarding()
                }
                Divider()
                Button(L10n.t(.menuQuit)) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .frame(width: capsuleSize.width, height: capsuleSize.height)
            .animation(Theme.stateSpring, value: viewModel.state)
            // Files dropped on the camera housing still land on the shelf (which
            // lives in the widget).
            .dropDestination(for: URL.self) { urls, _ in
                services.shelfStore.add(urls)
                return !urls.isEmpty
            }
            .animation(Theme.eventSpring, value: viewModel.activeEvent)
    }

    /// The falling drop: one shape whose frame animates from a sliver
    /// behind the housing to the full panel, so nothing ever jumps. It is
    /// the widget's glass, born black out of the housing.
    private var drop: some View {
        CapsuleGlass(shape: dropShape, inkHeight: closedSize.height + Self.fillet)
            .overlay {
                if isExpanded {
                    expandedContent
                        .transition(.opacity)
                }
            }
            .clipShape(dropShape)
            .contentShape(dropShape)
            .frame(width: dropSize.width, height: dropSize.height)
            .animation(Theme.stateSpring, value: isExpanded)
            // Settings ⇄ tour morphs the open drop to the other body size.
            .animation(Theme.stateSpring, value: viewModel.content)
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch viewModel.content {
        case .settings:
            CapsuleSettingsView(
                viewModel: viewModel,
                services: services,
                settings: settings,
                housingHeight: closedSize.height + Self.fillet
            )
            .transition(.opacity)
        case .onboarding:
            CapsuleOnboardingView(
                viewModel: viewModel,
                services: services,
                settings: settings,
                housingHeight: closedSize.height + Self.fillet
            )
            .transition(.opacity)
        }
    }
}

/// The expanded capsule's material: the widget's dark glass recipe, with
/// the housing's black running down the neck and fading out below the menu
/// bar — the drop leaves the hardware as ink and becomes glass. The glass
/// stroke fades in the opposite way, so no outline is drawn around the
/// neck.
private struct CapsuleGlass<S: Shape>: View {
    let shape: S
    /// Menu-bar band plus shoulders: solid black down to here.
    let inkHeight: CGFloat

    var body: some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Theme.capsuleGlassTint))
            .overlay(
                shape.fill(Color.black)
                    .mask(alignment: .top) { fade(from: .white, to: .clear) }
            )
            .overlay(
                shape.stroke(Theme.glassStrokeDark, lineWidth: 1)
                    .mask(alignment: .top) { fade(from: .clear, to: .white) }
            )
    }

    /// `from` down to the end of the ink band, a ramp to `to`, then `to`.
    private func fade(from start: Color, to end: Color) -> some View {
        let ramp = CapsuleMetrics.dropInkFade
        return VStack(spacing: 0) {
            start.frame(height: inkHeight)
            LinearGradient(colors: [start, end], startPoint: .top, endPoint: .bottom)
                .frame(height: ramp)
            end
        }
    }
}
