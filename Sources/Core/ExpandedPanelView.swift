import OSLog
import SwiftUI

/// Content of the expanded island: channel-selector tab row on top (under
/// the camera housing), module content below.
struct ExpandedPanelView: View {
    var viewModel: NotchViewModel
    var services: ModuleServices
    var settings: AppSettings
    var playbooks: PlaybookStore
    let notchHeight: CGFloat

    @State private var resizeStartSize: CGSize?
    @State private var resizeStartGlobal: CGPoint?

    private var enabledTabs: [NotchTab] {
        settings.orderedEnabledTabs
    }

    /// The selected tab may have been disabled in settings — fall back to
    /// the first enabled one.
    private var effectiveTab: NotchTab {
        settings.isEnabled(viewModel.selectedTab)
            ? viewModel.selectedTab
            : (enabledTabs.first ?? .metrics)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            channelSelector
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.panelInset)
                .padding(.top, Theme.panelInset)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .bottomTrailing) {
            resizeGrip
                // Kept clear of the capsule's rounded corner: clipShape also
                // clips hit-testing.
                .padding(.trailing, 16)
                .padding(.bottom, 6)
        }
    }

    /// V3 tab row: a glass segment capsule of circular icon cells. The
    /// active module is a solid white circle with a dark glyph.
    private var channelSelector: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(enabledTabs) { tab in
                    let isActive = effectiveTab == tab
                    let cellShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    Button {
                        viewModel.selectTab(tab)
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(isActive ? Theme.accent : Theme.textPrimary.opacity(0.6))
                            .frame(width: 40, height: 28)
                            .background(cellShape.fill(isActive ? Theme.accentWash : .clear))
                            .contentShape(cellShape)
                    }
                    .buttonStyle(PressableStyle())
                    .help(tab.title)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardFill))
            Spacer(minLength: 0)
            Text(effectiveTab.title)
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.panelInset)
        .padding(.vertical, 8)
    }

    private var content: some View {
        ModuleContentView(tab: effectiveTab, services: services, playbooks: playbooks)
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
