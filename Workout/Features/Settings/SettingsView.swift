import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]

    private var activePlan: WeightLossPlan? {
        plans.first(where: { $0.status == .active }) ?? plans.first
    }

    var body: some View {
        Form {
            if let plan = activePlan {
                Section("当前计划") {
                    LabeledContent("名称", value: plan.name)
                    LabeledContent("开始日期", value: plan.startDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("结束日期", value: plan.endDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("起始体重", value: formattedWeight(plan.startWeight))
                    LabeledContent("阶段目标", value: formattedWeight(plan.phaseTargetWeight))
                    LabeledContent("长期目标", value: formattedWeight(plan.finalTargetWeight))
                }

                Section("每日目标") {
                    LabeledContent("热量", value: "\(plan.dailyCalorieTarget) kcal")
                    LabeledContent("蛋白质", value: "\(plan.dailyProteinTarget) g")
                    LabeledContent("饮水", value: "\(plan.dailyWaterTarget.formatted(.number.precision(.fractionLength(1)))) L")
                }

                Section("计划状态") {
                    Picker(
                        "状态",
                        selection: Binding(
                            get: { plan.status },
                            set: { plan.status = $0; plan.updatedAt = .now }
                        )
                    ) {
                        ForEach(PlanStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }
            }

            Section("后续功能") {
                Label("本地通知", systemImage: "bell")
                Label("HealthKit 步数与体重", systemImage: "heart.text.square")
                Label("iCloud 同步", systemImage: "icloud")
                Label("Face ID", systemImage: "faceid")
                Label("CSV 导出", systemImage: "square.and.arrow.up")
            }
            .foregroundStyle(.secondary)

            Section("隐私") {
                Text("当前版本的数据仅使用 SwiftData 保存在本地。体型照片功能接入后，也应默认保存在 App 私有目录，不上传第三方服务器。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }

    private func formattedWeight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }
}
