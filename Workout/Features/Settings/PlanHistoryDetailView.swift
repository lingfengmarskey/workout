import SwiftData
import SwiftUI

struct PlanHistoryDetailView: View {
    let plan: WeightLossPlan
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query private var mealPlans: [DailyMealPlan]
    @Query private var workoutPlans: [DailyWorkoutPlan]

    private var records: [DailyBodyRecord] {
        bodyRecords.filter { $0.planID == plan.id }
    }

    private var recordedWeights: [DailyBodyRecord] {
        records.filter { $0.actualWeight != nil }
    }

    private var latestWeight: Double? {
        recordedWeights.last?.actualWeight
    }

    var body: some View {
        Form {
            Section("计划信息") {
                LabeledContent("状态", value: plan.status.displayName)
                LabeledContent("开始日期", value: plan.startDate.formatted(date: .long, time: .omitted))
                LabeledContent("结束日期", value: plan.endDate.formatted(date: .long, time: .omitted))
                LabeledContent("周期", value: "\(plan.durationDays) 天")
            }

            Section("体重目标") {
                LabeledContent("起始体重", value: weight(plan.startWeight))
                LabeledContent("阶段目标", value: weight(plan.phaseTargetWeight))
                LabeledContent("长期目标", value: weight(plan.finalTargetWeight))
                LabeledContent("最后记录", value: latestWeight.map(weight) ?? "未记录")
                LabeledContent("体重记录", value: "\(recordedWeights.count) 天")
            }

            Section("每日目标") {
                LabeledContent("热量", value: "\(plan.dailyCalorieTarget) kcal")
                LabeledContent("蛋白质", value: "\(plan.dailyProteinTarget) g")
                LabeledContent("饮水", value: "\(plan.dailyWaterTarget.formatted(.number.precision(.fractionLength(1)))) L")
            }

            Section("计划数据") {
                LabeledContent("身体记录", value: "\(records.count) 天")
                LabeledContent("饮食计划", value: "\(mealPlans.filter { $0.planID == plan.id }.count) 天")
                LabeledContent("锻炼计划", value: "\(workoutPlans.filter { $0.planID == plan.id }.count) 天")
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func weight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }
}
