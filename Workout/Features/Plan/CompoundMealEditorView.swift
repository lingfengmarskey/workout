import SwiftData
import SwiftUI

struct CompoundMealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var foodTemplates: [FoodTemplate]

    let onSave: (String, [CompoundMealComponent]) -> Void
    @State private var name = ""
    @State private var components: [CompoundMealComponent] = []
    @State private var validationMessage: String?

    init(onSave: @escaping (String, [CompoundMealComponent]) -> Void) {
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("组合菜品") {
                    TextField("名称，例如鸡肉饭", text: $name)
                    Text("保存后会按一份记录。下次选择时可调整份数，所有食材会按同一比例缩放。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if components.isEmpty {
                        Text("还没有食材，请从下方选择模板添加。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($components) { $component in
                            componentRow($component)
                        }
                        .onDelete { components.remove(atOffsets: $0) }
                    }
                } header: {
                    Text("组合食材")
                } footer: {
                    if !components.isEmpty {
                        let nutrition = CompoundMealCalculator.nutrition(for: components)
                        Text("每份合计约 \\(nutrition.calories.formatted(.number.precision(.fractionLength(0...1)))) kcal")
                    }
                }

                Section("从食物模板添加") {
                    if foodTemplates.isEmpty {
                        Text("暂无食物模板。请先完成一次手动、条码或营养成分表记录并保存为模板。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(foodTemplates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { template in
                            Button {
                                add(template)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .foregroundStyle(.primary)
                                        Text("每 \\(template.basisAmount.formatted(.number.precision(.fractionLength(0...1))))\\(template.basisUnit.rawValue) · \\(template.caloriesPerBasis.formatted(.number.precision(.fractionLength(0...1)))) kcal")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("创建组合菜品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(validationMessage ?? "请检查组合菜品。")
            }
        }
    }

    private func componentRow(_ component: Binding<CompoundMealComponent>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(component.wrappedValue.foodName)
                    .font(.body.weight(.medium))
                Spacer()
                Text("每 \\(component.wrappedValue.caloriesPerBasis.formatted(.number.precision(.fractionLength(0...1)))) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("数量", text: numberBinding(component.amount))
                    .keyboardType(.decimalPad)
                Text(component.wrappedValue.unit)
                    .foregroundStyle(.secondary)
                Text("（基准 \\(component.wrappedValue.basisAmount.formatted(.number.precision(.fractionLength(0...1))))\\(component.wrappedValue.unit)）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func numberBinding(_ value: Binding<Double>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) },
            set: { value.wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        )
    }

    private func add(_ template: FoodTemplate) {
        components.append(
            CompoundMealComponent(
                foodName: template.name,
                amount: template.basisAmount,
                unit: template.basisUnit.rawValue,
                basisAmount: template.basisAmount,
                caloriesPerBasis: template.caloriesPerBasis,
                proteinPerBasis: template.proteinPerBasis,
                carbohydratesPerBasis: template.carbohydratesPerBasis,
                fatPerBasis: template.fatPerBasis,
                sodiumPerBasis: template.sodiumPerBasis
            )
        )
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "请输入组合菜品名称。"
            return
        }
        guard !components.isEmpty else {
            validationMessage = "至少添加一种食材。"
            return
        }
        guard components.allSatisfy({
            !$0.foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.amount.isFinite && $0.amount > 0
                && $0.basisAmount.isFinite && $0.basisAmount > 0
                && $0.caloriesPerBasis.isFinite && $0.caloriesPerBasis >= 0
        }) else {
            validationMessage = "每种食材的数量、营养基准和能量必须是有效数字。"
            return
        }
        onSave(trimmedName, components)
        dismiss()
    }
}

struct CompoundMealServingEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let template: CompoundMealTemplate
    let mealSlot: MealSlot
    let onSave: (ActualFoodEntry) -> Void
    @State private var servings = "1"
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("组合菜品") {
                    LabeledContent("餐次", value: mealSlot.displayName)
                    LabeledContent("名称", value: template.name)
                    TextField("份数", text: $servings)
                        .keyboardType(.decimalPad)
                }

                Section("每份食材") {
                    ForEach(template.components) { component in
                        LabeledContent {
                            Text("\(component.amount.formatted(.number.precision(.fractionLength(0...1)))) \(component.unit)")
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(component.foodName)
                        }
                    }
                }

                Section("本次摄入估算") {
                    let nutrition = previewNutrition
                    LabeledContent("能量", value: "\\(nutrition.calories.formatted(.number.precision(.fractionLength(0...1)))) kcal")
                    if let protein = nutrition.protein {
                        LabeledContent("蛋白质", value: "\\(protein.formatted(.number.precision(.fractionLength(0...1)))) g")
                    }
                    if let carbohydrates = nutrition.carbohydrates {
                        LabeledContent("碳水", value: "\\(carbohydrates.formatted(.number.precision(.fractionLength(0...1)))) g")
                    }
                    if let fat = nutrition.fat {
                        LabeledContent("脂肪", value: "\\(fat.formatted(.number.precision(.fractionLength(0...1)))) g")
                    }
                    if let sodium = nutrition.sodium {
                        LabeledContent("钠", value: "\\(sodium.formatted(.number.precision(.fractionLength(0...1)))) mg")
                    }
                    Text("份数会等比例缩放组合内所有食材，保存后营养值会作为本次进食快照保留。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("确认组合菜品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认并保存") { save() }
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(validationMessage ?? "请输入有效份数。")
            }
        }
    }

    private var parsedServings: Double? {
        let value = Double(servings.replacingOccurrences(of: ",", with: "."))
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private var previewNutrition: CompoundMealNutrition {
        template.nutrition.scaled(by: parsedServings ?? 0)
    }

    private func save() {
        guard let servings = parsedServings else {
            validationMessage = "份数必须是大于 0 的数字。"
            return
        }
        let nutrition = template.nutrition
        onSave(
            ActualFoodEntry(
                templateID: template.id,
                mealSlot: mealSlot,
                foodName: template.name,
                amount: servings,
                unit: "份",
                nutritionBasisAmount: 1,
                caloriesPerBasis: nutrition.calories,
                proteinPerBasis: nutrition.protein,
                carbohydratesPerBasis: nutrition.carbohydrates,
                fatPerBasis: nutrition.fat,
                sodiumPerBasis: nutrition.sodium,
                originalEnergyPerBasis: nutrition.calories,
                originalEnergyUnit: .kcal,
                dataSource: .template,
                confidence: 1,
                isConfirmed: true
            )
        )
        dismiss()
    }
}
