import SwiftUI

/// The illustration card's wallpaper, black and white: light above, night
/// below. The widget's glass picks it up as it does a desk — bright along
/// its top edge, dark lower down — and a slow drifting light keeps the
/// horizon from sitting perfectly still.
struct TourBackdrop: View {
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: Color(white: 0.94), location: 0.22),
                        .init(color: Color(white: 0.38), location: 0.40),
                        .init(color: .black, location: 0.56),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Ellipse()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: size.width * 0.7, height: size.height * 0.45)
                    .blur(radius: 50)
                    .position(x: size.width * (drift ? 0.66 : 0.34), y: size.height * 0.22)
            }
        }
        .onAppear {
            guard !Theme.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}
