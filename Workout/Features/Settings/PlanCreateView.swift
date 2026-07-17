import SwiftData
import SwiftUI

struct PlanCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [WeightLossPlan]

    @State private var name = "新的 8 周减脂计划"
    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var durationWeeks = 8
    @State private var startWeight = 97.0
    @State private var phaseTargetWeight = 89.0
    @State private var finalTargetWeight = 80.0
    @State private var dailyCalories = 1900
    @State private var dailyProtein = 140
    @State private var dailyWater = 2.3
    @State private var validationMessage: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("计划") {
                TextField("计划名称", text: $name)
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                Stepper("周期：\(durationWeeks) 周", value: $durationWeeks, in: 1...52)
            }

            Section("体重目标") {
                numberField("起始体重（kg）", value: $startWeight)
                numberField("阶段目标（kg）", value: $phaseTargetWeight)
                numberField("长期目标（kg）", value: $finalTargetWeight)
            }

            Section("每日目标") {
                TextField("热量（kcal）", value: $dailyCalories, format: .number)
                    .keyboardType(.numberPad)
                TextField("蛋白质（g）", value: $dailyProtein, format: .number)
                    .keyboardType(.numberPad)
                numberField("饮水（L）", value: $dailyWater)
            }

            Section {
                Text("创建后会自动生成 \(durationWeeks * 7) 天的身体记录、饮食和锻炼计划。已有进行中计划时，请先由你手动暂停、完成或放弃该计划。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("创建新计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建", action: createPlan).disabled(isSaving)
            }
        }
        .alert("无法创建", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "请检查输入。")
        }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(1)))
            .keyboardType(.decimalPad)
    }

    private func createPlan() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { validationMessage = "计划名称不能为空。"; return }
        guard (40...300).contains(startWeight) else { validationMessage = "起始体重请输入 40–300 kg。"; return }
        guard (40...startWeight).contains(phaseTargetWeight),
              (40...phaseTargetWeight).contains(finalTargetWeight) else {
            validationMessage = "阶段目标应不高于起始体重，长期目标应不高于阶段目标。"
            return
        }
        guard (1_200...5_000).contains(dailyCalories) else { validationMessage = "每日热量请输入 1200–5000 kcal。"; return }
        guard (40...300).contains(dailyProtein) else { validationMessage = "每日蛋白质请输入 40–300 g。"; return }
        guard (0.5...6).contains(dailyWater) else { validationMessage = "每日饮水请输入 0.5–6 L。"; return }
        guard !plans.contains(where: { $0.status == .active }) else {
            validationMessage = "目前还有进行中的计划。请返回设置，由你亲自决定暂停、完成或放弃它，再创建新计划。"
            return
        }

        isSaving = true
        do {
            let plan = WeightLossPlan(
                name: trimmedName,
                startDate: startDate,
                durationDays: durationWeeks * 7,
                startWeight: startWeight,
                phaseTargetWeight: phaseTargetWeight,
                finalTargetWeight: finalTargetWeight,
                dailyCalorieTarget: dailyCalories,
                dailyProteinTarget: dailyProtein,
                dailyWaterTarget: dailyWater
            )
            try SeedData.create(plan: plan, in: modelContext)
            dismiss()
        } catch {
            modelContext.rollback()
            isSaving = false
            validationMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}
