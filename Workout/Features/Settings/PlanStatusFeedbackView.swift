import SwiftUI

struct PlanStatusFeedback: Identifiable {
    let id = UUID()
    let status: PlanStatus
    let planName: String
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
                ForEach(0..<18, id: \.self) { index in
                    Circle()
                        .fill(index.isMultiple(of: 2) ? .yellow : .white)
                        .frame(width: 8, height: 8)
                        .offset(x: isVisible ? CGFloat((index % 6) - 3) * 52 : 0,
                                y: isVisible ? CGFloat((index / 6) - 1) * 150 : 0)
                        .opacity(isVisible ? 0.75 : 0)
                }
            }

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
                        .foregroundStyle(.secondary)
                }

                Button("完成", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(32)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.7, dampingFraction: 0.68)) {
                isVisible = true
            }
        }
    }

    private var title: String {
        switch feedback.status {
        case .completed: "太棒了，计划完成！"
        case .paused: "计划已暂停"
        case .abandoned: "这段计划已结束"
        default: "状态已更新"
        }
    }

    private var message: String {
        switch feedback.status {
        case .completed: "每一天的坚持都算数。你的记录和成果已经完整保存。"
        case .paused: "休息不是退步。所有记录都已保存，准备好时可以再次出发。"
        case .abandoned: "有些计划会改变，但你的努力不会消失。历史记录会一直保留。"
        default: "计划状态已经由你确认更新。"
        }
    }

    private var icon: String {
        switch feedback.status {
        case .completed: "trophy.fill"
        case .paused: "pause.circle.fill"
        case .abandoned: "cloud.rain.fill"
        default: "checkmark.circle.fill"
        }
    }

    private var colors: [Color] {
        switch feedback.status {
        case .completed: [.yellow.opacity(0.75), .orange.opacity(0.35), Color(uiColor: .systemBackground)]
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
