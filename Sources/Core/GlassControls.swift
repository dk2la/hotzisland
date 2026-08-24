import SwiftUI

/// Widget material appearance. The island is always dark glass — this only
/// affects the edge widget; `.auto` follows the system appearance.
enum GlassAppearance: String, CaseIterable, Identifiable {
    case light
    case dark
    case auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .auto: "Auto"
        }
    }

    func resolvedDark(for colorScheme: ColorScheme) -> Bool {
        switch self {
        case .light: false
        case .dark: true
        case .auto: colorScheme == .dark
        }
    }
}

/// visionOS-style glass: system blur behind the window plus an appearance
/// tint and a 1px inner stroke. One recipe for every V3 surface.
struct GlassSurface<S: Shape>: View {
    let shape: S
    var dark = true

    var body: some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(dark ? Theme.glassTintDark : Theme.glassTintLight))
            .overlay(shape.stroke(dark ? Theme.glassStrokeDark : Theme.glassStrokeLight, lineWidth: 1))
    }
}

/// Square-ish glass icon button: ghost (raised glass) or solid (acid accent
/// with a dark glyph).
struct CircleGlassButton: View {
    let systemName: String
    var size: CGFloat = 32
    var solid = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(solid ? Theme.inkOnAccent : Theme.textPrimary.opacity(0.85))
                .frame(width: size, height: size)
                .background(shape.fill(solid ? Theme.accent : Theme.raisedFill))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Text button on raised glass: primary is solid acid green with dark label.
struct GlassCapsuleButton: View {
    let label: String
    var systemName: String?
    var isPrimary = false
    var enabled = true
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12.5, weight: isPrimary ? .semibold : .medium))
            }
            .foregroundStyle(isPrimary ? Theme.inkOnAccent : Theme.textPrimary.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(shape.fill(isPrimary ? Theme.accent : Theme.raisedFill))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

/// Thin continuous progress track (V3): 4px, white 18% track, white fill,
/// optional knob. Values jump — no animation by design.
struct GlassProgressBar: View {
    let fraction: Double
    var showsKnob = false
    var fillColor: Color = Color.white.opacity(0.9)

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(1, fraction))
            let x = proxy.size.width * clamped
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                    .frame(height: 4)
                Capsule().fill(fillColor)
                    .frame(width: max(4, x), height: 4)
                if showsKnob {
                    Circle().fill(Color.white)
                        .frame(width: 11, height: 11)
                        .offset(x: min(max(0, x - 5.5), proxy.size.width - 11))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: showsKnob ? 12 : 4)
    }
}

/// Empty state for modules whose service is not wired up yet (Email, Notes,
/// Chats). Ships disabled by default; the tile explains itself when enabled.
struct ComingSoonModuleView: View {
    let tab: NotchTab

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: tab.icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(tab.title)
                .font(Theme.titleFont)
                .foregroundStyle(Theme.textSecondary)
            Text(L10n.t(.comingSoonSub))
                .font(Theme.subFont)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
        )
    }
}
