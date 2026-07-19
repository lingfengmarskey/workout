import SwiftUI

struct BarcodeFoodConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    let product: BarcodeFoodProduct
    let onConfirm: (FoodTemplate) -> Void
    let onManualEntry: () -> Void

    @State private var name: String
    @State private var brand: String
    @State private var basisAmount: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbohydrates: String
    @State private var fat: String
    @State private var sodium: String
    @State private var errorMessage: String?

    init(
        product: BarcodeFoodProduct,
        onConfirm: @escaping (FoodTemplate) -> Void,
        onManualEntry: @escaping () -> Void
    ) {
        self.product = product
        self.onConfirm = onConfirm
        self.onManualEntry = onManualEntry
        _name = State(initialValue: product.name)
        _brand = State(initialValue: product.brand)
        _basisAmount = State(initialValue: String(product.basisAmount))
        _calories = State(initialValue: String(product.caloriesPerBasis))
        _protein = State(initialValue: product.proteinPerBasis.map { String($0) } ?? "")
        _carbohydrates = State(initialValue: product.carbohydratesPerBasis.map { String($0) } ?? "")
        _fat = State(initialValue: product.fatPerBasis.map { String($0) } ?? "")
        _sodium = State(initialValue: product.sodiumPerBasis.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("食品名称", text: $name)
                    TextField("品牌（可选）", text: $brand)
                    LabeledContent("条码", value: product.barcode)
                } header: {
                    Text("扫描结果")
                } footer: {
                    Text("结果来自食品数据库，请核对包装上的营养成分表。修改后才会保存为本地模板。")
                }

                Section("每 \(product.basisAmount.formatted(.number.precision(.fractionLength(0...1)))) \(product.basisUnit.rawValue)") {
                    numericField("基准数量", text: $basisAmount)
                    numericField("能量（kcal）", text: $calories)
                    numericField("蛋白质（g，可选）", text: $protein)
                    numericField("碳水（g，可选）", text: $carbohydrates)
                    numericField("脂肪（g，可选）", text: $fat)
                    numericField("钠（mg，可选）", text: $sodium)
                }

                Section {
                    Label("来源：条码数据库 · 可信度：中", systemImage: "barcode.viewfinder")
                        .foregroundStyle(.secondary)
                    Text("这一步只创建可复用的食物模板，下一步仍需填写本次实际吃了多少。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("确认条码食品")
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

    @ViewBuilder
    private func numericField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
    }

    private func confirm() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { errorMessage = "请输入食品名称。"; return }
        guard let basis = positive(basisAmount), let energy = nonNegative(calories) else {
            errorMessage = "基准数量必须大于 0，能量必须是有效数字。"
            return
        }
        guard [protein, carbohydrates, fat, sodium].allSatisfy({ optionalNonNegative($0) != nil || $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            errorMessage = "营养成分必须是 0 或更大的数字，或留空。"
            return
        }

        let template = FoodTemplate(
            name: trimmedName,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            barcode: product.barcode,
            locale: Locale.current.identifier,
            basisAmount: basis,
            basisUnit: product.basisUnit,
            caloriesPerBasis: energy,
            proteinPerBasis: optionalNonNegative(protein),
            fatPerBasis: optionalNonNegative(fat),
            carbohydratesPerBasis: optionalNonNegative(carbohydrates),
            sodiumPerBasis: optionalNonNegative(sodium),
            source: .barcodeDatabase,
            confidence: .medium
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
}

