import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct BodyRecordView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var record: DailyBodyRecord
    let plan: WeightLossPlan
    @AppStorage("healthkit.weight.authorizationRequested") private var healthWeightAuthorizationRequested = false

    @State private var cameraAngle: BodyPhotoAngle?
    @State private var pendingCameraAngle: BodyPhotoAngle?
    @State private var previewAngle: BodyPhotoAngle?
    @State private var errorMessage: String?
    @State private var isSyncingHealthWeight = false
    @State private var importedHealthWeight: Double?
    @State private var showOverwriteWeightConfirmation = false
    @State private var showWriteWeightConfirmation = false
    @State private var healthWeightMessage: String?

    var body: some View {
        Form {
            Section("体重") {
                LabeledContent("今日计划") {
                    Text(plan.plannedWeight(on: record.date), format: .number.precision(.fractionLength(1)))
                    Text(" kg")
                }

                TextField("早晨体重（kg）", text: doubleBinding(\DailyBodyRecord.actualWeight))
                    .keyboardType(.decimalPad)

                HStack {
                    Button {
                        Task { await importWeightFromHealth() }
                    } label: {
                        Label("从健康读取", systemImage: "arrow.down.heart")
                    }
                    Spacer()
                    Button {
                        showWriteWeightConfirmation = true
                    } label: {
                        Label("保存到健康", systemImage: "arrow.up.heart")
                    }
                    .disabled(record.actualWeight == nil)
                }
                .disabled(isSyncingHealthWeight || !HealthKitWeightService.isAvailable)

                if isSyncingHealthWeight {
                    ProgressView("正在同步体重…")
                }

                TextField("腰围（cm）", text: doubleBinding(\DailyBodyRecord.waist))
                    .keyboardType(.decimalPad)
            }

            Section("身体状态") {
                TextField("睡眠时间（小时）", text: doubleBinding(\DailyBodyRecord.sleepHours))
                    .keyboardType(.decimalPad)

                Picker(
                    "晨起精神",
                    selection: Binding(
                        get: { record.morningEnergy ?? 3 },
                        set: { record.morningEnergy = $0 }
                    )
                ) {
                    ForEach(1...5, id: \.self) { score in
                        Text("\(score) 分").tag(score)
                    }
                }
            }

            Section("体型照片") {
                photoRow(angle: .front)
                photoRow(angle: .side)
                photoRow(angle: .back)

                Text("照片会压缩后保存在 App 私有目录，不会上传到第三方服务。建议保持相同光线、距离、衣着和站姿。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("备注") {
                TextEditor(text: $record.note)
                    .frame(minHeight: 100)
            }

            Section {
                Text("建议每天起床、上厕所后、未进食饮水前称重。体型照片尽量保持相同光线、距离和衣着。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(record.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            record.updatedAt = .now
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, pendingCameraAngle != nil else { return }
            presentPendingCameraAfterActivation()
        }
        .fullScreenCover(item: $cameraAngle) { angle in
            CameraPicker(
                guideTitle: "拍摄\(angle.title)体型照片",
                progressText: angle.progressText,
                onImage: { image in
                    cameraAngle = nil
                    guard let data = image.jpegData(compressionQuality: 1) else {
                        errorMessage = BodyPhotoStore.StoreError.encodingFailed.localizedDescription
                        return
                    }
                    do {
                        try save(data, for: angle)
                    } catch {
                        errorMessage = readableMessage(for: error)
                    }
                },
                onRetake: {
                    cameraAngle = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        cameraAngle = angle
                    }
                },
                onCancel: { cameraAngle = nil }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $previewAngle) { angle in
            if let image = BodyPhotoStore.shared.image(for: photoIdentifier(for: angle)) {
                BodyPhotoPreviewView(image: image, title: "\(angle.title)体型照片")
            } else {
                BodyPhotoUnavailablePreviewView()
            }
        }
        .alert("无法处理照片", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
        .alert("覆盖当前体重？", isPresented: $showOverwriteWeightConfirmation) {
            Button("使用健康体重") {
                if let importedHealthWeight {
                    record.actualWeight = importedHealthWeight
                    record.updatedAt = .now
                }
                importedHealthWeight = nil
            }
            Button("取消", role: .cancel) { importedHealthWeight = nil }
        } message: {
            Text("当前记录为 \(formattedWeight(record.actualWeight))，健康 App 中为 \(formattedWeight(importedHealthWeight))。")
        }
        .alert("保存体重到健康 App？", isPresented: $showWriteWeightConfirmation) {
            Button("确认保存") { Task { await writeWeightToHealth() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将保存 \(formattedWeight(record.actualWeight))，日期为 \(record.date.formatted(date: .abbreviated, time: .omitted))。重复保存会使用同一同步标识更新记录。")
        }
        .alert("健康体重同步", isPresented: Binding(
            get: { healthWeightMessage != nil },
            set: { if !$0 { healthWeightMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(healthWeightMessage ?? "")
        }
    }

    private func importWeightFromHealth() async {
        isSyncingHealthWeight = true
        defer { isSyncingHealthWeight = false }
        do {
            try await ensureHealthWeightAuthorization()
            let weight = try await HealthKitWeightService.latestWeight(on: record.date)
            if let current = record.actualWeight, abs(current - weight) >= 0.05 {
                importedHealthWeight = weight
                showOverwriteWeightConfirmation = true
            } else {
                record.actualWeight = weight
                record.updatedAt = .now
            }
        } catch {
            healthWeightMessage = error.localizedDescription
        }
    }

    private func writeWeightToHealth() async {
        guard let weight = record.actualWeight else { return }
        isSyncingHealthWeight = true
        defer { isSyncingHealthWeight = false }
        do {
            try await ensureHealthWeightAuthorization()
            record.updatedAt = .now
            try await HealthKitWeightService.saveWeight(
                weight,
                on: record.date,
                recordID: record.id,
                syncVersion: Int(record.updatedAt.timeIntervalSince1970)
            )
            healthWeightMessage = "已保存到健康 App。"
        } catch {
            healthWeightMessage = error.localizedDescription
        }
    }

    private func ensureHealthWeightAuthorization() async throws {
        guard !healthWeightAuthorizationRequested else { return }
        try await HealthKitWeightService.requestAuthorization()
        healthWeightAuthorizationRequested = true
    }

    private func formattedWeight(_ value: Double?) -> String {
        guard let value else { return "未填写" }
        return "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private func doubleBinding(
        _ keyPath: ReferenceWritableKeyPath<DailyBodyRecord, Double?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = record[keyPath: keyPath] else { return "" }
                return value.formatted(.number.precision(.fractionLength(0...1)))
            },
            set: { text in
                let normalized = text.replacingOccurrences(of: ",", with: ".")
                record[keyPath: keyPath] = Double(normalized)
            }
        )
    }

    private func photoRow(angle: BodyPhotoAngle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                photoThumbnail(for: angle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(angle.title).font(.headline)
                    Text(photoIdentifier(for: angle) == nil ? "未添加" : "已安全保存")
                        .font(.caption)
                        .foregroundStyle(photoIdentifier(for: angle) == nil ? Color.secondary : Color.green)
                }
                Spacer()
            }

            HStack {
                BodyPhotoPickerButton(
                    title: photoIdentifier(for: angle) == nil ? "从相册选择" : "替换"
                ) { result in
                    do {
                        try save(result.get(), for: angle)
                    } catch {
                        errorMessage = readableMessage(for: error)
                    }
                }

                Spacer()

                Button {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        errorMessage = "当前设备没有可用相机。你仍可以从相册选择照片。"
                        return
                    }
                    requestCamera(for: angle)
                } label: {
                    Label("拍摄", systemImage: "camera")
                }

                if photoIdentifier(for: angle) != nil {
                    Spacer()
                    Button("删除", role: .destructive) { deletePhoto(for: angle) }
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func photoThumbnail(for angle: BodyPhotoAngle) -> some View {
        if let image = BodyPhotoStore.shared.image(for: photoIdentifier(for: angle)) {
            Button {
                previewAngle = angle
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("预览\(angle.title)体型照片")
            .accessibilityHint("全屏打开照片，可放大和拖动")
        } else {
            Image(systemName: "person.crop.rectangle")
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 96)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func save(_ data: Data, for angle: BodyPhotoAngle) throws {
        let identifier = try BodyPhotoStore.shared.save(
            imageData: data,
            replacing: photoIdentifier(for: angle)
        )
        setPhotoIdentifier(identifier, for: angle)
        record.updatedAt = .now
    }

    private func deletePhoto(for angle: BodyPhotoAngle) {
        do {
            try BodyPhotoStore.shared.delete(identifier: photoIdentifier(for: angle))
            setPhotoIdentifier(nil, for: angle)
            record.updatedAt = .now
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    private func requestCamera(for angle: BodyPhotoAngle) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentCamera(for: angle)
        case .notDetermined:
            pendingCameraAngle = angle
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    if scenePhase == .active {
                        presentPendingCameraAfterActivation()
                    }
                } else {
                    pendingCameraAngle = nil
                    errorMessage = "未获得相机权限。请在系统“设置”中允许减脂计划访问相机，或改从相册选择。"
                }
            }
        case .denied, .restricted:
            errorMessage = "相机权限不可用。请在系统“设置”中允许减脂计划访问相机，或改从相册选择。"
        @unknown default:
            errorMessage = "目前无法使用相机，请改从相册选择照片。"
        }
    }

    private func presentCamera(for angle: BodyPhotoAngle) {
        guard scenePhase == .active else {
            pendingCameraAngle = angle
            return
        }
        cameraAngle = angle
    }

    private func presentPendingCameraAfterActivation() {
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard scenePhase == .active, let angle = pendingCameraAngle else { return }
            pendingCameraAngle = nil
            cameraAngle = angle
        }
    }

    private func photoIdentifier(for angle: BodyPhotoAngle) -> String? {
        switch angle {
        case .front: record.frontPhotoPath
        case .side: record.sidePhotoPath
        case .back: record.backPhotoPath
        }
    }

    private func setPhotoIdentifier(_ identifier: String?, for angle: BodyPhotoAngle) {
        switch angle {
        case .front: record.frontPhotoPath = identifier
        case .side: record.sidePhotoPath = identifier
        case .back: record.backPhotoPath = identifier
        }
    }

    private func readableMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "无法访问或保存照片。请检查照片/相机权限，并重试。"
    }
}

private struct BodyPhotoPickerButton: View {
    let title: String
    let onResult: (Result<Data, Error>) -> Void

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw BodyPhotoStore.StoreError.invalidImage
                    }
                    onResult(.success(data))
                } catch {
                    onResult(.failure(error))
                }
                selectedItem = nil
            }
        }
    }
}

private enum BodyPhotoAngle: String, Identifiable {
    case front
    case side
    case back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "正面"
        case .side: "侧面"
        case .back: "背面"
        }
    }

    var progressText: String {
        switch self { case .front: "1/3"; case .side: "2/3"; case .back: "3/3" }
    }
}
