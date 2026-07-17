import SwiftUI
import UIKit

struct CelebrationFireworksView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { FireworksEmitterHostView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class FireworksEmitterHostView: UIView {
    private let emitter = CAEmitterLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY + 8)
        emitter.emitterSize = CGSize(width: bounds.width * 0.82, height: 1)
        CATransaction.commit()
    }

    private func configure() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        emitter.emitterShape = .line
        emitter.emitterMode = .surface
        emitter.renderMode = .additive
        emitter.seed = UInt32.random(in: .min ... .max)
        emitter.emitterCells = [
            rocket(color: .systemPink, delay: 0),
            rocket(color: .systemYellow, delay: 0.45),
            rocket(color: .systemCyan, delay: 0.9),
            rocket(color: .systemPurple, delay: 1.35)
        ]
        layer.addSublayer(emitter)
    }

    private func rocket(color: UIColor, delay: TimeInterval) -> CAEmitterCell {
        let rocket = CAEmitterCell()
        rocket.birthRate = 0.72
        rocket.beginTime = delay
        rocket.lifetime = 1.55
        rocket.lifetimeRange = 0.18
        rocket.velocity = 300
        rocket.velocityRange = 55
        rocket.emissionLongitude = -.pi / 2
        rocket.emissionRange = .pi / 8
        rocket.yAcceleration = 115
        rocket.scale = 0
        rocket.color = color.cgColor

        let trail = CAEmitterCell()
        trail.contents = sparkImage
        trail.birthRate = 55
        trail.lifetime = 0.45
        trail.lifetimeRange = 0.12
        trail.velocity = 32
        trail.velocityRange = 20
        trail.emissionRange = .pi * 2
        trail.scale = 0.07
        trail.scaleRange = 0.025
        trail.alphaSpeed = -1.7
        trail.color = UIColor.white.withAlphaComponent(0.9).cgColor

        let explosion = CAEmitterCell()
        explosion.contents = sparkImage
        explosion.birthRate = 1_100
        explosion.beginTime = 1.18
        explosion.duration = 0.08
        explosion.lifetime = 1.7
        explosion.lifetimeRange = 0.35
        explosion.velocity = 155
        explosion.velocityRange = 55
        explosion.emissionRange = .pi * 2
        explosion.yAcceleration = 95
        explosion.scale = 0.085
        explosion.scaleRange = 0.035
        explosion.scaleSpeed = -0.025
        explosion.alphaSpeed = -0.62
        explosion.color = color.cgColor
        explosion.redRange = 0.25
        explosion.greenRange = 0.25
        explosion.blueRange = 0.25

        rocket.emitterCells = [trail, explosion]
        return rocket
    }

    private lazy var sparkImage: CGImage? = {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.65).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.28, 1]
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
