import SwiftUI
import UIKit

struct CelebrationFireworksView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { FireworksEmitterHostView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class FireworksEmitterHostView: UIView {
    private var launchWorkItem: DispatchWorkItem?
    private var launchIndex = 0
    private let colors: [UIColor] = [.systemPink, .systemYellow, .systemCyan, .systemPurple, .systemOrange]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            launchWorkItem?.cancel()
            launchWorkItem = nil
        } else if launchWorkItem == nil {
            scheduleNextLaunch(after: 0.15)
        }
    }

    private func scheduleNextLaunch(after delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil, self.bounds.width > 0, self.bounds.height > 0 else {
                self?.scheduleNextLaunch(after: 0.2)
                return
            }
            self.launchFirework()
            self.scheduleNextLaunch(after: 0.55)
        }
        launchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func launchFirework() {
        let color = colors[launchIndex % colors.count]
        launchIndex += 1
        let start = CGPoint(x: bounds.midX + CGFloat.random(in: -bounds.width * 0.32 ... bounds.width * 0.32), y: bounds.maxY + 12)
        let destination = CGPoint(x: CGFloat.random(in: bounds.width * 0.16 ... bounds.width * 0.84), y: CGFloat.random(in: bounds.height * 0.12 ... bounds.height * 0.5))
        let flightDuration = Double.random(in: 0.75 ... 1.05)

        let trailLayer = CAEmitterLayer()
        trailLayer.frame = bounds
        trailLayer.emitterShape = .point
        trailLayer.emitterMode = .points
        trailLayer.renderMode = .additive
        trailLayer.emitterPosition = destination
        trailLayer.emitterCells = [trailCell(color: color)]
        layer.addSublayer(trailLayer)

        let flight = CABasicAnimation(keyPath: "emitterPosition")
        flight.fromValue = start
        flight.toValue = destination
        flight.duration = flightDuration
        flight.timingFunction = CAMediaTimingFunction(name: .easeOut)
        trailLayer.add(flight, forKey: "flight")

        DispatchQueue.main.asyncAfter(deadline: .now() + flightDuration) { [weak self, weak trailLayer] in
            trailLayer?.birthRate = 0
            self?.explode(at: destination, color: color)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + flightDuration + 1) { [weak trailLayer] in
            trailLayer?.removeFromSuperlayer()
        }
    }

    private func explode(at point: CGPoint, color: UIColor) {
        let burstLayer = CAEmitterLayer()
        burstLayer.frame = bounds
        burstLayer.emitterShape = .point
        burstLayer.emitterMode = .points
        burstLayer.renderMode = .additive
        burstLayer.emitterPosition = point
        burstLayer.emitterCells = [burstCell(color: color), burstCell(color: .white, scale: 0.045)]
        layer.addSublayer(burstLayer)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak burstLayer] in
            burstLayer?.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak burstLayer] in
            burstLayer?.removeFromSuperlayer()
        }
    }

    private func trailCell(color: UIColor) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = sparkImage
        cell.birthRate = 95
        cell.lifetime = 0.5
        cell.lifetimeRange = 0.15
        cell.velocity = 18
        cell.velocityRange = 12
        cell.emissionRange = .pi * 2
        cell.scale = 0.055
        cell.scaleRange = 0.02
        cell.alphaSpeed = -1.7
        cell.color = color.cgColor
        return cell
    }

    private func burstCell(color: UIColor, scale: CGFloat = 0.075) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = sparkImage
        cell.birthRate = 850
        cell.lifetime = 1.65
        cell.lifetimeRange = 0.25
        cell.velocity = 135
        cell.velocityRange = 45
        cell.emissionRange = .pi * 2
        cell.yAcceleration = 85
        cell.scale = scale
        cell.scaleRange = 0.025
        cell.scaleSpeed = -0.025
        cell.alphaSpeed = -0.7
        cell.color = color.cgColor
        return cell
    }

    private lazy var sparkImage: CGImage? = {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.72).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.3, 1]
            ) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: .drawsAfterEndLocation
            )
        }.cgImage
    }()
}
