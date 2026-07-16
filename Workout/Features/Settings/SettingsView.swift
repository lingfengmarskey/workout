import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]
    @Query(sort: \DailyWorkoutPlan.date) private var workoutPlans: [DailyWorkoutPlan]

    @State private var showTestDataConfirmation = false
    @State private var testDataMessage: String?

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

#if DEBUG
            if activePlan != nil {
                Section("开发与测试") {
                    Button("生成 4 周周报测试数据", role: .destructive) {
                        showTestDataConfirmation = true
                    }
                    Text("仅 Debug 构建显示。会把当前计划移动到 28 天前，并覆盖最近 29 天的身体、饮食和锻炼记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
#endif
        }
        .navigationTitle("设置")
#if DEBUG
        .confirmationDialog("生成测试数据？", isPresented: $showTestDataConfirmation, titleVisibility: .visible) {
            Button("确认生成", role: .destructive) { generateTestData() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会覆盖当前计划最近 29 天的测试字段，请勿用于真实记录。")
        }
        .alert("周报测试数据", isPresented: Binding(
            get: { testDataMessage != nil },
            set: { if !$0 { testDataMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(testDataMessage ?? "")
        }
#endif
    }

    private func formattedWeight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }

#if DEBUG
    private func generateTestData() {
        guard let plan = activePlan else { return }
        do {
            try WeeklyReviewTestData.generate(
                plan: plan,
                bodyRecords: bodyRecords,
                mealPlans: mealPlans,
                workoutPlans: workoutPlans,
                in: modelContext
            )
            testDataMessage = "已生成 29 天数据。请打开“进度”查看 4 个周报和不同调整建议。"
        } catch {
            testDataMessage = "生成失败：\(error.localizedDescription)"
        }
    }
#endif
}
