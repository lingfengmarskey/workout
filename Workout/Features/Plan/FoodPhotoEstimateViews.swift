import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct FoodPhotoEstimateCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void
    let onError: (String) -> Void
    @State private var photoItem: PhotosPickerItem?
    @State private var cameraPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "camera.macro")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                Text("拍摄本次进食")
                    .font(.title3.weight(.semibold))
                Text("照片估算只提供大致范围，不能替代称重或包装营养信息。照片默认只在本机内存中处理，不会自动上传。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Button {
                    presentCamera()
                } label: {
                    Label("拍摄食物照片", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("照片估算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $cameraPresented) {
                NutritionLabelCameraPicker(
                    onImage: { image in
                        cameraPresented = false
                        onImage(image)
                    },
                    onError: { message in
                        cameraPresented = false
                        onError(message)
                    },
                    onCancel: { cameraPresented = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else {
                            onError("无法读取所选图片，请重试或改用相机拍摄。")
                            return
                        }
                        onImage(image)
                    } catch {
                        onError("无法读取所选图片，请重试。")
                    }
                }
            }
        }
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            onError("当前设备没有可用摄像头，请从相册选择或改用手动输入。")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPresented = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        cameraPresented = true
                    } else {
                        onError("相机权限未开启，请在系统设置中允许访问相机，或改用相册选择和手动输入。")
                    }
                }
            }
        case .denied, .restricted:
            onError("相机权限未开启，请在系统设置中允许访问相机，或改用相册选择和手动输入。")
        @unknown default:
            onError("无法访问相机，请改用相册选择或手动输入。")
        }
    }
}

struct FoodPhotoEstimateFlowView: View {
    let mealSlot: MealSlot
    let onConfirm: ([ActualFoodEntry]) -> Void
    let onManualEntry: () -> Void
    let provider: any FoodPhotoEstimateProviding
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [FoodPhotoEstimateCandidate]?
    @State private var isEstimating = false
    @State private var errorMessage: String?

    init(
        mealSlot: MealSlot,
        onConfirm: @escaping ([ActualFoodEntry]) -> Void,
        onManualEntry: @escaping () -> Void,
        provider: any FoodPhotoEstimateProviding = MockFoodPhotoEstimateProvider()
    ) {
        self.mealSlot = mealSlot
        self.onConfirm = onConfirm
        self.onManualEntry = onManualEntry
        self.provider = provider
    }

    var body: some View {
        Group {
            if let candidates {
                FoodPhotoEstimateConfirmationView(
                    mealSlot: mealSlot,
                    candidates: candidates,
                    onConfirm: { entries in
                        onConfirm(entries)
                        dismiss()
                    },
                    onManualEntry: {
                        onManualEntry()
                        dismiss()
                    }
                )
            } else {
                FoodPhotoEstimateCaptureView(
                    onImage: estimate,
                    onError: { message in errorMessage = message }
                )
            }
        }
        .overlay {
            if isEstimating {
                ProgressView("正在估算照片中的食物…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("无法估算食物", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("手动精确输入") {
                errorMessage = nil
                onManualEntry()
                dismiss()
            }
            Button("取消", role: .cancel) {
                errorMessage = nil
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "可以重试，或改用模板和手动输入。")
        }
    }

    private func estimate(_ image: UIImage) {
        isEstimating = true
        Task {
            defer { isEstimating = false }
            do {
                let result = try await provider.estimate(image: image)
                guard !result.isEmpty else { throw FoodPhotoEstimateError.noCandidates }
                candidates = result
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct FoodPhotoEstimateConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let mealSlot: MealSlot
    @State private var candidates: [FoodPhotoEstimateCandidate]
    let onConfirm: ([ActualFoodEntry]) -> Void
    let onManualEntry: () -> Void
    @State private var validationMessage: String?

    init(
        mealSlot: MealSlot,
        candidates: [FoodPhotoEstimateCandidate],
        onConfirm: @escaping ([ActualFoodEntry]) -> Void,
        onManualEntry: @escaping () -> Void
    ) {
        self.mealSlot = mealSlot
        _candidates = State(initialValue: candidates)
        self.onConfirm = onConfirm
        self.onManualEntry = onManualEntry
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("以下是照片估算结果。请删除不正确的候选并修正数量；确认前不会写入历史记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if candidates.isEmpty {
                        Text("没有保留候选，请改用手动输入。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($candidates) { $candidate in
                            FoodPhotoEstimateCandidateEditor(candidate: $candidate)
                        }
                        .onDelete { candidates.remove(atOffsets: $0) }
                    }
                } header: {
                    Text("候选食物")
                } footer: {
                    Text("来源：照片估算（演示 provider）。估算值不是精确测量，不用于医疗诊断。")
                }

                Section("本次合计") {
                    LabeledContent("能量", value: "\(totalCalories.formatted(.number.precision(.fractionLength(0...1)))) kcal")
                    if let protein = totalOptional(candidates.map(\.protein)) {
                        LabeledContent("蛋白质", value: "\(protein.formatted(.number.precision(.fractionLength(0...1)))) g")
                    }
                }

                Section {
                    Button("改为手动精确输入") { onManualEntry(); dismiss() }
                }
            }
            .navigationTitle("确认照片估算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认并记录") { save() }
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(validationMessage ?? "请检查候选。")
            }
        }
    }

    private var totalCalories: Double { candidates.reduce(0) { $0 + $1.calories } }

    private func totalOptional(_ values: [Double?]) -> Double? {
        guard values.contains(where: { $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }

    private func save() {
        guard !candidates.isEmpty else {
            validationMessage = "至少保留一种食物，或改用手动输入。"
            return
        }
        guard candidates.allSatisfy({
            !$0.foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && FoodNutritionBasisUnit.parse($0.unit) != nil
                && $0.amount.isFinite && $0.amount > 0
                && $0.basisAmount.isFinite && $0.basisAmount > 0
                && $0.caloriesPerBasis.isFinite && $0.caloriesPerBasis >= 0
                && [$0.proteinPerBasis, $0.carbohydratesPerBasis, $0.fatPerBasis, $0.sodiumPerBasis]
                    .compactMap { $0 }
                    .allSatisfy { $0.isFinite && $0 >= 0 }
                && [$0.calories, $0.protein, $0.carbohydrates, $0.fat, $0.sodium]
                    .compactMap { $0 }
                    .allSatisfy { $0.isFinite && $0 >= 0 }
                && $0.confidence.isFinite && (0...1).contains($0.confidence)
        }) else {
            validationMessage = "食物名称、单位、数量、营养基准、营养值和可信度必须是有效值。"
            return
        }

        let entries = candidates.map { candidate in
            ActualFoodEntry(
                mealSlot: mealSlot,
                foodName: candidate.foodName,
                amount: candidate.amount,
                unit: candidate.unit,
                nutritionBasisAmount: candidate.basisAmount,
                caloriesPerBasis: candidate.caloriesPerBasis,
                proteinPerBasis: candidate.proteinPerBasis,
                carbohydratesPerBasis: candidate.carbohydratesPerBasis,
                fatPerBasis: candidate.fatPerBasis,
                sodiumPerBasis: candidate.sodiumPerBasis,
                originalEnergyPerBasis: candidate.caloriesPerBasis,
                originalEnergyUnit: .kcal,
                dataSource: .photoEstimate,
                confidence: candidate.confidence,
                isConfirmed: true
            )
        }
        onConfirm(entries)
        dismiss()
    }
}

private struct FoodPhotoEstimateCandidateEditor: View {
    @Binding var candidate: FoodPhotoEstimateCandidate
    @State private var showsNutritionDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("食物名称", text: $candidate.foodName)
                Text("可信度 \(Int(candidate.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                TextField("数量", text: amountBinding)
                    .keyboardType(.decimalPad)
                TextField("单位", text: $candidate.unit)
                    .frame(width: 52)
                Text("· \(candidate.calories.formatted(.number.precision(.fractionLength(0...1)))) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("编辑营养快照", isExpanded: $showsNutritionDetails) {
                NutritionNumberField(label: "营养基准数量", text: basisAmountBinding)
                NutritionNumberField(label: "每基准量能量（kcal）", text: caloriesBinding)
                NutritionNumberField(label: "蛋白质（g）", placeholder: "可选", text: proteinBinding)
                NutritionNumberField(label: "碳水（g）", placeholder: "可选", text: carbohydratesBinding)
                NutritionNumberField(label: "脂肪（g）", placeholder: "可选", text: fatBinding)
                NutritionNumberField(label: "钠（mg）", placeholder: "可选", text: sodiumBinding)
                NutritionNumberField(label: "可信度（%）", text: confidenceBinding)
            }
        }
    }

    private var amountBinding: Binding<String> {
        Binding(
            get: { candidate.amount.formatted(.number.precision(.fractionLength(0...2))) },
            set: { candidate.amount = Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        )
    }

    private var basisAmountBinding: Binding<String> {
        numberBinding(get: { candidate.basisAmount }, set: { candidate.basisAmount = $0 })
    }

    private var caloriesBinding: Binding<String> {
        numberBinding(get: { candidate.caloriesPerBasis }, set: { candidate.caloriesPerBasis = $0 })
    }

    private var proteinBinding: Binding<String> {
        optionalNumberBinding(get: { candidate.proteinPerBasis }, set: { candidate.proteinPerBasis = $0 })
    }

    private var carbohydratesBinding: Binding<String> {
        optionalNumberBinding(get: { candidate.carbohydratesPerBasis }, set: { candidate.carbohydratesPerBasis = $0 })
    }

    private var fatBinding: Binding<String> {
        optionalNumberBinding(get: { candidate.fatPerBasis }, set: { candidate.fatPerBasis = $0 })
    }

    private var sodiumBinding: Binding<String> {
        optionalNumberBinding(get: { candidate.sodiumPerBasis }, set: { candidate.sodiumPerBasis = $0 })
    }

    private var confidenceBinding: Binding<String> {
        Binding(
            get: { NutritionDecimalInput.text(from: candidate.confidence * 100) },
            set: {
                let percentage = Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0
                candidate.confidence = min(max(percentage / 100, 0), 1)
            }
        )
    }

    private func numberBinding(
        get: @escaping () -> Double,
        set: @escaping (Double) -> Void
    ) -> Binding<String> {
        Binding(
            get: { NutritionDecimalInput.text(from: get()) },
            set: { set(Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0) }
        )
    }

    private func optionalNumberBinding(
        get: @escaping () -> Double?,
        set: @escaping (Double?) -> Void
    ) -> Binding<String> {
        Binding(
            get: { NutritionDecimalInput.text(from: get()) },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : Double(trimmed.replacingOccurrences(of: ",", with: ".")))
            }
        )
    }
}
