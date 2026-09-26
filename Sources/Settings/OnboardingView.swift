import AppKit
import EventKit
import SwiftUI

/// First-launch onboarding, three steps: power on → permissions → arrange
/// the panel. Shown once; `--onboarding` relaunches it for testing.
struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let onDone: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var step = 0
    @State private var calendarGranted =
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @State private var automationGranted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(28)
        .frame(width: 480, height: 420)
        .background(Palette.panel)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: powerOn
        case 1: permissions
        default: arrange
        }
    }

    // MARK: - Step 1: power on

    private var powerOn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BlinkingDot(color: Palette.accent, size: 6)
                InstrumentLabel("power on", color: Palette.accent)
            }
            Text("Hotzisland")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 16)
            Text("Вырез становится прибором: метрики, плейбуки, музыка, файлы.")
                .font(Theme.bodyFont)
                .foregroundStyle(Palette.ink60)
                .padding(.top, 10)
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    // MARK: - Step 2: permissions

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Разрешения")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text("Без доступа модуль скрыт, а не пуст.")
                .font(Theme.subFont)
                .foregroundStyle(Palette.ink40)
                .padding(.top, 6)
                .padding(.bottom, 18)

            permissionRow(title: "Календарь", granted: calendarGranted) {
                Task {
                    let granted = (try? await EKEventStore().requestFullAccessToEvents()) ?? false
                    calendarGranted = granted
                }
            }
            Hairline(color: Palette.hairline)
            permissionRow(title: "Apple Events", granted: automationGranted) {
                NSWorkspace.shared.openPrivacyPane("Automation")
            }
            Hairline(color: Palette.hairline)
            SettingRow(title: "Спец. возможности", subtitle: "Сейчас не требуется") {
                InstrumentLabel("later", color: Palette.ink40)
            }
        }
        // AEDeterminePermissionToAutomateTarget can block for as long as the
        // target app ignores Apple Events — probe off the main thread, and
        // keep polling so the row flips to "ok" after granting in System
        // Settings.
        .task {
            let spotifyID = SpotifySource.bundleID
            let musicID = MusicSource.bundleID
            while !Task.isCancelled {
                automationGranted = await Task.detached {
                    AutomationPermission.status(towardsBundleID: spotifyID) == .granted
                        || AutomationPermission.status(towardsBundleID: musicID) == .granted
                }.value
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func permissionRow(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        SettingRow(title: title) {
            if granted {
                InstrumentLabel("ok", color: Palette.ink40)
            } else {
                Button(action: action) {
                    InstrumentLabel("grant", color: Palette.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: - Step 3: arrange

    private var arrange: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Соберите панель")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text("Порядок вкладок — перетаскиванием.")
                .font(Theme.subFont)
                .foregroundStyle(Palette.ink40)
                .padding(.top, 6)
                .padding(.bottom, 10)
            ModulesOrderList(settings: settings)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Palette.accent : Palette.ink40.opacity(0.4))
                        .frame(width: 5, height: 5)
                }
            }
            Spacer()
            Button {
                if step < 2 {
                    step += 1
                } else {
                    onDone()
                }
            } label: {
                Text(step == 0 ? "Включить" : (step == 1 ? "Дальше" : "Готово"))
                    .font(Theme.headlineFont)
                    .foregroundStyle(scheme == .light ? Color.white : Theme.inkOnAccent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }
}

/// Owns the one-shot onboarding window.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(settings: AppSettings, onDone: @escaping () -> Void) {
        let hosting = NSHostingController(
            rootView: OnboardingView(settings: settings) { [weak self] in
                self?.window?.close()
                onDone()
            }
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Hotzisland"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
