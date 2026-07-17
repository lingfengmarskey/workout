import SwiftUI

struct PlanStatusFeedback: Identifiable {
    let id = UUID()
    let status: PlanStatus
    let planName: String
    var completionSummary: PlanCompletionSummary? = nil
}

struct PlanCompletionSummary {
    let executedDays: Int
    let startWeight: Double
    let latestWeight: Double?
    let mealCompletionRate: Double?
    let workoutCompletionRate: Double?
}

struct PlanStatusFeedbackView: View {
    let feedback: PlanStatusFeedback
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            if feedback.status == .completed && !reduceMotion {
                CelebrationFireworksView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            ScrollView {
            VStack(spacing: 24) {
                Image(systemName: icon)
                    .font(.system(size: 88, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(isVisible || reduceMotion ? 1 : 0.35)

                VStack(spacing: 10) {
                    Text(title).font(.largeTitle.bold())
                    Text(feedback.planName).font(.title3.weight(.semibold))
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(feedback.status == .completed ? Color.white.opacity(0.82) : Color.secondary)
                }

                if let summary = feedback.completionSummary, feedback.status == .completed {
                    completionSummary(summary)
                }

                Button("完成", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(32)
            .foregroundStyle(feedback.status == .completed ? Color.white : Color.primary)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.7, dampingFraction: 0.68)) {
                isVisible = true
            }
        }
    }

    private func completionSummary(_ summary: PlanCompletionSummary) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                achievementMetric("执行天数", "\(summary.executedDays) 天")
                achievementMetric("起始体重", weight(summary.startWeight))
            }
            HStack(spacing: 12) {
                if let latest = summary.latestWeight {
                    achievementMetric("最后体重", weight(latest))
                    achievementMetric("累计减重", signedWeight(summary.startWeight - latest))
                }
            }
            HStack(spacing: 12) {
                if let rate = summary.mealCompletionRate {
                    achievementMetric("饮食执行率", rate.formatted(.percent.precision(.fractionLength(0))))
                }
                if let rate = summary.workoutCompletionRate {
                    achievementMetric("锻炼执行率", rate.formatted(.percent.precision(.fractionLength(0))))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func achievementMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(feedback.status == .completed ? Color.white.opacity(0.75) : Color.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func weight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private func signedWeight(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private var title: String {
        switch feedback.status {
        case .active: "重新出发！"
        case .completed: "太棒了，计划完成！"
        case .paused: "计划已暂停"
        case .abandoned: "这段计划已结束"
        default: "状态已更新"
        }
    }

    private var message: String {
        switch feedback.status {
        case .active: "计划已经重新开启。按自己的节奏，继续向前。"
        case .completed: "每一天的坚持都算数。你的记录和成果已经完整保存。"
        case .paused: "休息不是退步。所有记录都已保存，准备好时可以再次出发。"
        case .abandoned: "有些计划会改变，但你的努力不会消失。历史记录会一直保留。"
        default: "计划状态已经由你确认更新。"
        }
    }

    private var icon: String {
        switch feedback.status {
        case .active: "figure.run.circle.fill"
        case .completed: "trophy.fill"
        case .paused: "pause.circle.fill"
        case .abandoned: "cloud.rain.fill"
        default: "checkmark.circle.fill"
        }
    }

    private var colors: [Color] {
        switch feedback.status {
        case .active: [.green.opacity(0.35), .mint.opacity(0.2), Color(uiColor: .systemBackground)]
        case .completed: [Color(red: 0.03, green: 0.05, blue: 0.16), Color(red: 0.15, green: 0.06, blue: 0.28)]
        case .paused: [.blue.opacity(0.28), Color(uiColor: .systemBackground)]
        case .abandoned: [.gray.opacity(0.4), .blue.opacity(0.15), Color(uiColor: .systemBackground)]
        default: [.green.opacity(0.25), Color(uiColor: .systemBackground)]
        }
    }
}

extension PlanStatus {
    var confirmationTitle: String {
        switch self {
        case .paused: "暂停当前计划？"
        case .completed: "确认完成当前计划？"
        case .abandoned: "真的要放弃当前计划吗？"
        default: "更改计划状态？"
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .paused: "确认暂停计划"
        case .completed: "确认完成计划"
        case .abandoned: "确认放弃计划"
        default: "确认更改"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .paused: "暂停后所有数据都会保留，以后可以从历史计划恢复。"
        case .completed: "完成代表你主动结束了这个阶段。体重、照片和执行记录都会保留。"
        case .abandoned: "放弃后计划不会继续执行，但所有历史记录仍会保留。这个操作不会删除数据。"
        default: "历史数据不会被删除。"
        }
    }
}
