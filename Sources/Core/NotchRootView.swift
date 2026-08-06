import SwiftUI

struct NotchRootView: View {
    var viewModel: NotchViewModel
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor
    let closedSize: CGSize

    private var isExpanded: Bool { viewModel.state == .expanded }

    private var islandSize: CGSize {
        if isExpanded { return NotchMetrics.expandedSize }
        if viewModel.activeEvent != nil {
            return CGSize(
                width: closedSize.width + NotchMetrics.eventSideWidth * 2,
                height: closedSize.height
            )
        }
        return closedSize
    }

    private var shape: NotchShape {
        NotchShape(
            topRadius: isExpanded ? NotchMetrics.expandedTopRadius : NotchMetrics.closedTopRadius,
            bottomRadius: isExpanded ? NotchMetrics.expandedBottomRadius : NotchMetrics.closedBottomRadius
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        shape
            .fill(Theme.islandFill)
            .overlay {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                } else if let event = viewModel.activeEvent {
                    LiveEventView(event: event)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .frame(width: islandSize.width, height: islandSize.height)
            .animation(Theme.stateSpring, value: viewModel.state)
            .animation(Theme.eventSpring, value: viewModel.activeEvent)
    }

    private var expandedContent: some View {
        ExpandedPanelView(
            viewModel: viewModel,
            power: power,
            audio: audio,
            notchHeight: closedSize.height
        )
    }
}
