import SwiftUI

// MARK: - Animated Custom Vector Fan View
struct SpinningFanView: View {
    let currentSpeed: Double
    let maxSpeed: Double
    @State private var angle: Double = 0.0
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                
                // Draw housing ring
                context.stroke(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(Color.gray.opacity(0.2)),
                    lineWidth: 3
                )
                
                // Rotate canvas context for fan blades using struct value copying
                var rotatedContext = context
                rotatedContext.translateBy(x: center.x, y: center.y)
                rotatedContext.rotate(by: .degrees(angle))
                
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
            .onChange(of: timeline.date) { _ in
                // Standardize rotation step to speed
                // 1000 RPM -> ~4 deg per frame
                let delta = max(currentSpeed, 200.0) / 1000.0 * 3.5
                angle += delta
                if angle >= 360 { angle -= 360 }
            }
        }
    }
}
