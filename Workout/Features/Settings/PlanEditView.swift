import SwiftData
import SwiftUI

struct PlanEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var plan: WeightLossPlan
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]

    @State private var name: String
    @State private var phaseTargetWeight: Double
    @State private var finalTargetWeight: Double
    @State private var dailyCalories: Int
    @State private var dailyProtein: Int
    @State private var dailyWater: Double
    @State private var validationMessage: String?

    init(plan: WeightLossPlan) {
        self.plan = plan
        _name = State(initialValue: plan.name)
        _phaseTargetWeight = State(initialValue: plan.phaseTargetWeight)
        _finalTargetWeight = State(initialValue: plan.finalTargetWeight)
        _dailyCalories = State(initialValue: plan.dailyCalorieTarget)
        _dailyProtein = State(initialValue: plan.dailyProteinTarget)
        _dailyWater = State(initialValue: plan.dailyWaterTarget)
    }

    var body: some View {
        Form {
            Section("计划") {
                TextField("计划名称", text: $name)
                LabeledContent("开始日期", value: plan.startDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("周期", value: "\(plan.durationDays) 天")
            }

            Section("体重目标") {
                TextField("阶段目标（kg）", value: $phaseTargetWeight, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                TextField("长期目标（kg）", value: $finalTargetWeight, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
            }

            Section("每日目标") {
                TextField("热量（kcal）", value: $dailyCalories, format: .number)
                    .keyboardType(.numberPad)
                TextField("蛋白质（g）", value: $dailyProtein, format: .number)
                    .keyboardType(.numberPad)
                TextField("饮水（L）", value: $dailyWater, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
            }

            Section {
                Text("开始日期和周期暂不可编辑，避免已生成的每日计划发生错位。修改每日目标不会重写历史记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("编辑计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
        .alert("无法保存", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "请检查输入。")
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { validationMessage = "计划名称不能为空。"; return }
        guard (40...plan.startWeight).contains(phaseTargetWeight),
              (40...phaseTargetWeight).contains(finalTargetWeight) else {
            validationMessage = "长期目标应不高于阶段目标，两个目标都应在 40 kg 与起始体重之间。"
            return
        }
        guard (1_200...5_000).contains(dailyCalories) else { validationMessage = "每日热量请输入 1200–5000 kcal。"; return }
        guard (40...300).contains(dailyProtein) else { validationMessage = "每日蛋白质请输入 40–300 g。"; return }
        guard (0.5...6).contains(dailyWater) else { validationMessage = "每日饮水请输入 0.5–6 L。"; return }

        plan.name = trimmedName
        plan.phaseTargetWeight = phaseTargetWeight
        plan.finalTargetWeight = finalTargetWeight
        plan.dailyCalorieTarget = dailyCalories
        plan.dailyProteinTarget = dailyProtein
        plan.dailyWaterTarget = dailyWater
        plan.updatedAt = .now
        let today = Calendar.current.startOfDay(for: .now)
        mealPlans.filter { $0.planID == plan.id && $0.date >= today }.forEach {
            $0.plannedCalories = dailyCalories
            $0.plannedProtein = dailyProtein
            $0.waterTarget = dailyWater
        }
        dismiss()
    }
}
