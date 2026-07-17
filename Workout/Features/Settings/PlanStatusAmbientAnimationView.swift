import SwiftUI

/// A quiet, semantic background animation for non-completion plan transitions.
/// Completion keeps its dedicated fireworks celebration.
struct PlanStatusAmbientAnimationView: View {
    let status: PlanStatus

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    switch status {
                    case .active:
                        forwardMotion(in: proxy.size, elapsed: elapsed)
                    case .paused:
                        breathingRings(in: proxy.size, elapsed: elapsed)
                    case .abandoned:
                        gentleRain(in: proxy.size, elapsed: elapsed)
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func forwardMotion(in size: CGSize, elapsed: TimeInterval) -> some View {
        ForEach(0..<9, id: \.self) { index in
            let cycle = positiveRemainder(elapsed * 0.13 + Double(index) / 9, modulus: 1)
            Image(systemName: "chevron.up")
                .font(.system(size: 14 + CGFloat(index % 3) * 4, weight: .bold))
                .foregroundStyle(Color.green.opacity(0.08 + 0.22 * (1 - cycle)))
                .position(
                    x: size.width * (0.1 + 0.1 * CGFloat(index)),
                    y: size.height * (1.08 - cycle * 1.16)
                )
        }
    }

    private func breathingRings(in size: CGSize, elapsed: TimeInterval) -> some View {
        ForEach(0..<4, id: \.self) { index in
            let phase = positiveRemainder(elapsed * 0.16 + Double(index) / 4, modulus: 1)
            Circle()
                .stroke(Color.blue.opacity(0.24 * (1 - phase)), lineWidth: 2)
                .frame(width: size.width * (0.18 + phase * 1.15))
                .position(x: size.width / 2, y: size.height * 0.34)
        }
    }

    private func gentleRain(in size: CGSize, elapsed: TimeInterval) -> some View {
        ForEach(0..<18, id: \.self) { index in
            let speed = 0.1 + Double(index % 4) * 0.018
            let cycle = positiveRemainder(elapsed * speed + Double(index) / 18, modulus: 1)
            Capsule()
                .fill(Color.blue.opacity(0.09 + 0.12 * (1 - cycle)))
                .frame(width: 2, height: 16 + CGFloat(index % 3) * 7)
                .rotationEffect(.degrees(8))
                .position(
                    x: size.width * (0.04 + 0.055 * CGFloat(index)),
                    y: size.height * (-0.08 + cycle * 1.16)
                )
        }
    }

    private func positiveRemainder(_ value: Double, modulus: Double) -> CGFloat {
        CGFloat(value.truncatingRemainder(dividingBy: modulus))
    }
}
