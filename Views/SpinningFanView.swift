import AppKit
import QuartzCore
import SwiftUI

// MARK: - Hardware-composited fan indicator
//
// The blades are created once as Core Animation layers. Their rotation is then
// performed by the window server rather than by asking SwiftUI to redraw a
// Canvas on every display refresh.
struct SpinningFanView: NSViewRepresentable {
    let currentSpeed: Double
    let maxSpeed: Double

    func makeNSView(context: Context) -> FanAnimationView {
        FanAnimationView(currentSpeed: currentSpeed, maxSpeed: maxSpeed)
    }

    func updateNSView(_ view: FanAnimationView, context: Context) {
        view.update(currentSpeed: currentSpeed, maxSpeed: maxSpeed)
    }
}

final class FanAnimationView: NSView {
    private let ringLayer = CAShapeLayer()
    private let fanLayer = CALayer()
    private let bladeGradientLayer = CAGradientLayer()
    private let bladeMaskLayer = CAShapeLayer()
    private let hubLayer = CAShapeLayer()

    private var currentSpeed: Double
    private var maxSpeed: Double
    private var isAnimationPaused = false
    private var notificationObservers: [NSObjectProtocol] = []

    init(currentSpeed: Double, maxSpeed: Double) {
        self.currentSpeed = currentSpeed
        self.maxSpeed = maxSpeed
        super.init(frame: CGRect(x: 0, y: 0, width: 80, height: 80))

        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        buildLayers()
        observeApplicationActivity()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 80, height: 80)
    }

    override func layout() {
        super.layout()
        let drawingBounds = bounds
        ringLayer.frame = drawingBounds
        fanLayer.frame = drawingBounds
        bladeGradientLayer.frame = fanLayer.bounds
        hubLayer.frame = drawingBounds
        updatePaths(in: drawingBounds)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        [ringLayer, fanLayer, bladeGradientLayer, bladeMaskLayer, hubLayer].forEach {
            $0.contentsScale = scale
        }
        configureRotation(preservingCurrentAngle: false)
    }

    func update(currentSpeed: Double, maxSpeed: Double) {
        let hasSpeedChange = abs(self.currentSpeed - currentSpeed) >= 1
            || abs(self.maxSpeed - maxSpeed) >= 1
        self.currentSpeed = currentSpeed
        self.maxSpeed = maxSpeed

        guard hasSpeedChange else { return }
        updateBladeColors()

        // While inactive the layer is paused. Its current rate is applied only
        // when it returns to the foreground, avoiding any background animation.
        guard !isAnimationPaused else { return }
        configureRotation(preservingCurrentAngle: true)
    }

    private func buildLayers() {
        guard let rootLayer = layer else { return }

        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor.gray.withAlphaComponent(0.2).cgColor
        ringLayer.lineWidth = 3
        rootLayer.addSublayer(ringLayer)

        bladeGradientLayer.startPoint = CGPoint(x: 0.35, y: 0.0)
        bladeGradientLayer.endPoint = CGPoint(x: 0.65, y: 1.0)
        bladeGradientLayer.mask = bladeMaskLayer
        fanLayer.addSublayer(bladeGradientLayer)
        rootLayer.addSublayer(fanLayer)

        hubLayer.fillColor = NSColor.white.withAlphaComponent(0.16).cgColor
        hubLayer.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
        hubLayer.lineWidth = 1
        rootLayer.addSublayer(hubLayer)

        updateBladeColors()
    }

    private func updatePaths(in bounds: CGRect) {
        guard !bounds.isEmpty else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2

        ringLayer.path = CGPath(
            ellipseIn: CGRect(
                x: center.x - radius + 1.5,
                y: center.y - radius + 1.5,
                width: radius * 2 - 3,
                height: radius * 2 - 3
            ),
            transform: nil
        )

        let baseBlade = CGMutablePath()
        baseBlade.move(to: center)
        baseBlade.addCurve(
            to: CGPoint(x: center.x + 10, y: center.y + radius - 5),
            control1: CGPoint(x: center.x + 18, y: center.y + radius * 0.4),
            control2: CGPoint(x: center.x + 25, y: center.y + radius * 0.7)
        )
        baseBlade.addCurve(
            to: CGPoint(x: center.x - 10, y: center.y + radius - 5),
            control1: CGPoint(x: center.x, y: center.y + radius + 8),
            control2: CGPoint(x: center.x - 8, y: center.y + radius)
        )
        baseBlade.addCurve(
            to: center,
            control1: CGPoint(x: center.x - 12, y: center.y + radius * 0.7),
            control2: CGPoint(x: center.x - 15, y: center.y + radius * 0.4)
        )
        baseBlade.closeSubpath()

        let allBlades = CGMutablePath()
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2
            var transform = CGAffineTransform(translationX: center.x, y: center.y)
            transform = transform.rotated(by: angle)
            transform = transform.translatedBy(x: -center.x, y: -center.y)
            allBlades.addPath(baseBlade, transform: transform)
        }
        bladeMaskLayer.path = allBlades
        bladeMaskLayer.frame = bounds

        hubLayer.path = CGPath(
            ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14),
            transform: nil
        )
    }

    private func updateBladeColors() {
        let ratio = min(max(currentSpeed / max(maxSpeed, 1), 0), 1)
        bladeGradientLayer.colors = [
            NSColor.systemBlue.withAlphaComponent(0.85 - ratio * 0.25).cgColor,
            NSColor.systemTeal.withAlphaComponent(0.6).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.3 + ratio * 0.4).cgColor
        ]
    }

    private func configureRotation(preservingCurrentAngle: Bool) {
        guard fanLayer.bounds.width > 0 else { return }

        let currentAngle: CGFloat
        if preservingCurrentAngle,
           let presentationLayer = fanLayer.presentation(),
           let presentationAngle = presentationLayer.value(forKeyPath: "transform.rotation.z") as? CGFloat {
            currentAngle = presentationAngle
        } else {
            currentAngle = fanLayer.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
        }

        // The real fan can turn thousands of times per minute. Map its speed through
        // a concave response curve: zero RPM remains motionless, while low RPM values
        // are still visible and the top of the physical range does not become a blur.
        let ratio = min(max(currentSpeed / max(maxSpeed, 1), 0), 1)
        let visualRevolutionsPerSecond = 2.0 * pow(ratio, 0.55)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fanLayer.removeAnimation(forKey: "fanRotation")
        fanLayer.setValue(currentAngle, forKeyPath: "transform.rotation.z")
        CATransaction.commit()

        // A stopped physical fan must be represented by a stopped indicator.
        guard visualRevolutionsPerSecond > 0 else { return }

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = currentAngle
        rotation.toValue = currentAngle + .pi * 2
        rotation.duration = 1 / visualRevolutionsPerSecond
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        fanLayer.add(rotation, forKey: "fanRotation")
    }

    private func observeApplicationActivity() {
        let notificationCenter = NotificationCenter.default
        notificationObservers = [
            notificationCenter.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                self?.pauseAnimation()
            },
            notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                self?.resumeAnimation()
            }
        ]
    }

    private func pauseAnimation() {
        guard !isAnimationPaused else { return }
        let pausedTime = fanLayer.convertTime(CACurrentMediaTime(), from: nil)
        fanLayer.speed = 0
        fanLayer.timeOffset = pausedTime
        isAnimationPaused = true
    }

    private func resumeAnimation() {
        guard isAnimationPaused else { return }
        let pausedTime = fanLayer.timeOffset
        fanLayer.speed = 1
        fanLayer.timeOffset = 0
        fanLayer.beginTime = 0
        fanLayer.beginTime = fanLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        isAnimationPaused = false
        configureRotation(preservingCurrentAngle: true)
    }
}
