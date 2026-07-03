import SwiftUI

// MARK: - Static Vector Fan View
// Previously animated via TimelineView(.animation), which redrew this Canvas
// on every display refresh (up to 120Hz) forever — the main source of this
// app's idle CPU usage. The rotation was purely decorative (speed is already
// shown as an RPM number and via blade color), so it's drawn once instead.
struct SpinningFanView: View, Equatable {
    let currentSpeed: Double
    let maxSpeed: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            // Draw housing ring
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Color.gray.opacity(0.2)),
                lineWidth: 3
            )

            var rotatedContext = context
            rotatedContext.translateBy(x: center.x, y: center.y)

            // Draw 4 blades
            for i in 0..<4 {
                var bladeContext = rotatedContext
                bladeContext.rotate(by: .degrees(Double(i) * 90))

                // Draw blade shape
                var path = Path()
                path.move(to: .zero)
                path.addCurve(
                    to: CGPoint(x: 10, y: -(radius - 5)),
                    control1: CGPoint(x: 18, y: -radius * 0.4),
                    control2: CGPoint(x: 25, y: -radius * 0.7)
                )
                path.addCurve(
                    to: CGPoint(x: -10, y: -(radius - 5)),
                    control1: CGPoint(x: 0, y: -radius - 8),
                    control2: CGPoint(x: -8, y: -radius)
                )
                path.addCurve(
                    to: .zero,
                    control1: CGPoint(x: -12, y: -radius * 0.7),
                    control2: CGPoint(x: -15, y: -radius * 0.4)
                )

                let ratio = currentSpeed / (maxSpeed > 0 ? maxSpeed : 6000.0)
                let bladeGradient = Gradient(colors: [
                    Color.blue.opacity(0.85 - ratio * 0.25),
                    Color.teal.opacity(0.6),
                    Color.purple.opacity(0.3 + ratio * 0.4)
                ])
                bladeContext.fill(
                    path,
                    with: .linearGradient(
                        bladeGradient,
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: -radius)
                    )
                )
            }
        }
        .frame(width: 80, height: 80)
    }
}
