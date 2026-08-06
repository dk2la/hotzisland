import SwiftUI

struct NotchRootView: View {
    var viewModel: NotchViewModel
    let closedSize: CGSize

    private var isExpanded: Bool { viewModel.state == .expanded }

    private var islandSize: CGSize {
        isExpanded ? NotchMetrics.expandedSize : closedSize
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
            .fill(.black)
            .overlay {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                }
            }
            .clipShape(shape)
            .frame(width: islandSize.width, height: islandSize.height)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: viewModel.state)
    }

    /// Expanded panel placeholder — will be replaced by modules in later phases.
    private var expandedContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "capsule.portrait.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("HotzIsland")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Modules coming soon")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, closedSize.height / 2)
    }
}
