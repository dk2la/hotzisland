import SwiftUI

/// Content of the expanded island: the app's settings, under the camera
/// housing, with a close button and a corner resize grip. The island is
/// the settings surface — modules live in the edge widget.
struct IslandSettingsView: View {
    var viewModel: NotchViewModel
    var services: ModuleServices
    var settings: AppSettings
    var playbooks: PlaybookStore
    let notchHeight: CGFloat

    @State private var resizeStartSize: CGSize?
    @State private var resizeStartGlobal: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            SettingsView(
                settings: settings,
                playbooks: playbooks,
                services: services,
                pageSelection: viewModel.pageSelection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            HeaderIconButton("xmark") {
                viewModel.onClose?()
            }
            .padding(.top, notchHeight + 8)
            .padding(.trailing, 10)
        }
        .overlay(alignment: .bottomTrailing) {
            resizeGrip
                // Kept clear of the capsule's rounded corner: clipShape also
                // clips hit-testing.
                .padding(.trailing, 16)
                .padding(.bottom, 6)
        }
    }

    /// Corner grip: drag to resize the panel like an app window. Tracking
    /// uses the global cursor position — the window moves mid-drag, so local
    /// gesture coordinates would feed back into themselves.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.textFaint)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        let now = NSEvent.mouseLocation
                        guard let start = resizeStartGlobal, let startSize = resizeStartSize else {
                            resizeStartGlobal = now
                            resizeStartSize = settings.expandedPanelSize
                            viewModel.isResizingPanel = true
                            return
                        }
                        // Cocoa coordinates: dragging down means decreasing y.
                        settings.setPanelSize(CGSize(
                            width: startSize.width + (now.x - start.x) * 2,
                            height: startSize.height + (start.y - now.y)
                        ))
                    }
                    .onEnded { _ in
                        resizeStartGlobal = nil
                        resizeStartSize = nil
                        viewModel.isResizingPanel = false
                    }
            )
    }
}
