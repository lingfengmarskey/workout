import SwiftUI

struct WeeklyReviewRow: View {
    let summary: WeeklyReviewSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("第 \(summary.weekIndex) 周\(summary.isComplete ? "" : " · 进行中")").font(.headline)
                Text(summary.startDate.formatted(date: .numeric, time: .omitted) + " – " + summary.endDate.formatted(date: .numeric, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                Text("饮食 \(summary.mealCompletionRate, format: .percent.precision(.fractionLength(0))) · 锻炼 \(summary.workoutCompletionRate, format: .percent.precision(.fractionLength(0)))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(summary.averageWeight.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "--")
                    .font(.headline)
                Text(summary.weightLoss.map { "下降 \($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "数据不足")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct WeeklyReviewDetailView: View {
    let summary: WeeklyReviewSummary
    @Bindable var plan: WeightLossPlan
    let mealPlans: [DailyMealPlan]
    let workoutPlans: [DailyWorkoutPlan]

    @State private var proposedAdjustment: Adjustment?

    var body: some View {
        List {
            Section("体重与身体") {
                metric("平均体重", summary.averageWeight, "kg")
                metric("周末体重", summary.endWeight, "kg")
                metric("本周下降", summary.weightLoss, "kg")
                metric("平均腰围", summary.averageWaist, "cm")
            }
            Section("执行情况") {
                LabeledContent("饮食执行率", value: summary.mealCompletionRate.formatted(.percent.precision(.fractionLength(0))))
                LabeledContent("锻炼执行率", value: summary.workoutCompletionRate.formatted(.percent.precision(.fractionLength(0))))
                metric("平均步数", summary.averageSteps, "步", digits: 0)
            }
            Section("状态") {
                metric("平均睡眠", summary.averageSleep, "小时")
                metric("平均饥饿感", summary.averageHunger, "分")
                metric("平均晨起精神", summary.averageEnergy, "分")
                metric("平均疲劳程度", summary.averageFatigue, "分")
                if summary.painSummary.isEmpty { Text("没有记录疼痛或不适").foregroundStyle(.secondary) }
                else { ForEach(summary.painSummary, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") } }
            }
            if !summary.photoRecords.isEmpty {
                Section("本周体型照片") {
                    ForEach(summary.photoRecords) { record in
                        NavigationLink {
                            BodyRecordView(record: record, plan: plan)
                        } label: {
                            Label(
                                record.date.formatted(date: .complete, time: .omitted),
                                systemImage: "photo.on.rectangle"
                            )
                        }
                    }
                }
            }
            Section("调整建议") { recommendationContent }
        }
        .navigationTitle("第 \(summary.weekIndex) 周复盘")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认调整后续计划？", isPresented: Binding(get: { proposedAdjustment != nil }, set: { if !$0 { proposedAdjustment = nil } })) {
            if let adjustment = proposedAdjustment {
                Button(adjustment.confirmTitle) { apply(adjustment) }
                Button("取消", role: .cancel) { proposedAdjustment = nil }
            }
        } message: {
            Text(proposedAdjustment?.detail ?? "")
        }
    }

    @ViewBuilder private var recommendationContent: some View {
        switch summary.recommendation {
        case .maintain:
            Label("下降速度和状态正常，建议维持当前计划。", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .plateau:
            Text("连续两周下降不足 0.4 kg，可选择一项调整。")
            Button("每日热量减少约 150 kcal") { proposedAdjustment = .reduceCalories }
            Button("每日目标增加约 2000 步") { proposedAdjustment = .increaseSteps }
        case .tooFast:
            Text("下降较快且状态存在压力，建议增加摄入或降低训练量。")
            Button("每日热量增加约 175 kcal") { proposedAdjustment = .increaseCalories }
            Button("后续训练时长降低约 10 分钟") { proposedAdjustment = .reduceTraining }
        case .insufficientData:
            Text("有效体重或状态数据不足，暂不调整计划。").foregroundStyle(.secondary)
        }
        Text("系统不会自动修改；只有确认后才应用到本周之后的计划。")
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func metric(_ title: String, _ value: Double?, _ unit: String, digits: Int = 1) -> some View {
        LabeledContent(title, value: value.map { "\($0.formatted(.number.precision(.fractionLength(digits)))) \(unit)" } ?? "--")
    }

    private func apply(_ adjustment: Adjustment) {
        let futureMeals = mealPlans.filter { $0.planID == plan.id && $0.date > summary.endDate }
        let futureWorkouts = workoutPlans.filter { $0.planID == plan.id && $0.date > summary.endDate }
        switch adjustment {
        case .reduceCalories:
            plan.dailyCalorieTarget = max(1_200, plan.dailyCalorieTarget - 150)
            futureMeals.forEach { $0.plannedCalories = max(1_200, $0.plannedCalories - 150) }
        case .increaseSteps:
            futureWorkouts.forEach { $0.targetSteps += 2_000 }
        case .increaseCalories:
            plan.dailyCalorieTarget += 175
            futureMeals.forEach { $0.plannedCalories += 175 }
        case .reduceTraining:
            futureWorkouts.forEach { $0.plannedDurationMinutes = max(10, $0.plannedDurationMinutes - 10) }
        }
        plan.updatedAt = .now
        plan.syncRevision += 1
        futureMeals.forEach {
            $0.updatedAt = .now
            $0.syncRevision += 1
        }
        futureWorkouts.forEach {
            $0.updatedAt = .now
            $0.syncRevision += 1
        }
        proposedAdjustment = nil
    }
}

private enum Adjustment {
    case reduceCalories, increaseSteps, increaseCalories, reduceTraining
    var confirmTitle: String { "确认应用" }
    var detail: String {
        switch self {
        case .reduceCalories: "将后续每日计划热量减少约 150 kcal。"
        case .increaseSteps: "将后续每日目标步数增加约 2000 步。"
        case .increaseCalories: "将后续每日计划热量增加约 175 kcal。"
        case .reduceTraining: "将后续每日计划训练时长减少约 10 分钟。"
        }
    }
}
