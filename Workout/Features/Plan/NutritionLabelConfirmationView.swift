import SwiftUI
import UIKit

struct NutritionLabelConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let result: NutritionLabelOCRResult
    let onConfirm: (FoodTemplate) -> Void
    let onManualEntry: () -> Void

    @State private var name = ""
    @State private var basisAmount: String
    @State private var basisUnit: FoodNutritionBasisUnit
    @State private var calories: String
    @State private var energyUnit: FoodEnergyUnit
    @State private var protein: String
    @State private var fat: String
    @State private var carbohydrates: String
    @State private var sodium: String
    @State private var verified = false
    @State private var errorMessage: String?

    init(
        image: UIImage,
        result: NutritionLabelOCRResult,
        onConfirm: @escaping (FoodTemplate) -> Void,
        onManualEntry: @escaping () -> Void
    ) {
        self.image = image
        self.result = result
        self.onConfirm = onConfirm
        self.onManualEntry = onManualEntry
        _basisAmount = State(initialValue: result.basisAmount.map { NutritionDecimalInput.text(from: $0) } ?? "100")
        _basisUnit = State(initialValue: result.basisUnit ?? .gram)
        _calories = State(initialValue: NutritionDecimalInput.text(from: result.calories))
        _energyUnit = State(initialValue: result.energyUnit)
        _protein = State(initialValue: NutritionDecimalInput.text(from: result.protein))
        _fat = State(initialValue: NutritionDecimalInput.text(from: result.fat))
        _carbohydrates = State(initialValue: NutritionDecimalInput.text(from: result.carbohydrates))
        _sodium = State(initialValue: NutritionDecimalInput.text(from: result.sodium))
    }

    private var requiresVerification: Bool {
        !result.hasRequiredNutrition || result.overallConfidence < 0.75
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("原始照片") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("OCR 只提供估算结果，请以包装上的原始标签为准。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("食物信息") {
                    TextField("食物名称，例如牛奶", text: $name)
                    LabeledContent("营养基准数量") {
                        HStack {
                            TextField("例如 100", text: $basisAmount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: basisAmount) { _, newValue in
                                    let clamped = NutritionDecimalInput.clamp(newValue)
                                    if clamped != newValue { basisAmount = clamped }
                                }
                            Picker("单位", selection: $basisUnit) {
                                ForEach(FoodNutritionBasisUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }

                Section("营养快照") {
                    LabeledContent("能量") {
                        HStack {
                            TextField("例如 116", text: $calories)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: calories) { _, newValue in
                                    let clamped = NutritionDecimalInput.clamp(newValue)
                                    if clamped != newValue { calories = clamped }
                                }
                            Picker("能量单位", selection: $energyUnit) {
                                ForEach(FoodEnergyUnit.allCases) { unit in
                                    Text(unit.displayName).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    NutritionNumberField(label: "蛋白质（g）", placeholder: "可选", text: $protein)
                    NutritionNumberField(label: "脂肪（g）", placeholder: "可选", text: $fat)
                    NutritionNumberField(label: "碳水化合物（g）", placeholder: "可选", text: $carbohydrates)
                    NutritionNumberField(label: "钠（mg）", placeholder: "可选", text: $sodium)
                    if let sugar = result.sugar {
                        LabeledContent("识别到糖", value: "\(sugar.formatted(.number.precision(.fractionLength(0...1)))) g")
                    }
                    if let fiber = result.fiber {
                        LabeledContent("识别到膳食纤维", value: "\(fiber.formatted(.number.precision(.fractionLength(0...1)))) g")
                    }
                }

                Section("识别可信度") {
                    LabeledContent("总体可信度", value: confidenceText(result.overallConfidence))
                    if requiresVerification {
                        Toggle("我已对照原始包装核对以上数据", isOn: $verified)
                    } else {
                        Label("字段已基本识别，仍建议对照包装核对。", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("确认 OCR 结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认并继续") { confirm() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("改为手动输入") { onManualEntry() }
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请检查输入。")
            }
        }
    }


    private func confirm() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { errorMessage = "请输入食物名称。"; return }
        guard let basis = positive(basisAmount), let energyInput = nonNegative(calories) else {
            errorMessage = "营养基准和能量不能为空。"
            return
        }
        guard !requiresVerification || verified else {
            errorMessage = "请先对照原始包装核对 OCR 数据。"
            return
        }
        guard [protein, fat, carbohydrates, sodium].allSatisfy(isValidOptionalNumber) else {
            errorMessage = "营养成分必须是 0 或更大的数字，或留空。"
            return
        }

        let template = FoodTemplate(
            name: trimmedName,
            basisAmount: basis,
            basisUnit: basisUnit,
            caloriesPerBasis: energyUnit.calories(from: energyInput),
            proteinPerBasis: optionalNonNegative(protein),
            fatPerBasis: optionalNonNegative(fat),
            carbohydratesPerBasis: optionalNonNegative(carbohydrates),
            sodiumPerBasis: optionalNonNegative(sodium),
            source: .labelOCR,
            confidence: result.overallConfidence >= 0.75 ? .medium : .low
        )
        do {
            try template.validateForSave()
            onConfirm(template)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func positive(_ text: String) -> Double? {
        guard let value = nonNegative(text), value > 0 else { return nil }
        return value
    }

    private func nonNegative(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func optionalNonNegative(_ text: String) -> Double? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return nonNegative(text)
    }

    private func isValidOptionalNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || optionalNonNegative(trimmed) != nil
    }

    private func confidenceText(_ value: Double) -> String {
        switch value {
        case ..<0.5: "低"
        case ..<0.75: "中"
        default: "较高"
        }
    }
}

