import PhotosUI
import SwiftUI
import UIKit

struct NutritionLabelCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    let onImage: (UIImage) -> Void
    let onError: (String) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var cameraPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                Text("拍摄或选择营养成分表")
                    .font(.title3.weight(.semibold))
                Text("尽量让整张营养成分表清晰、正向、完整入镜。照片只在识别期间保留在本机内存中，不会上传。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Button {
                    cameraPresented = true
                } label: {
                    Label("拍摄营养成分表", systemImage: "camera")
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
            .navigationTitle("识别营养成分表")
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
}

struct NutritionLabelCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onError: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: NutritionLabelCameraPicker

        init(_ parent: NutritionLabelCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onError("无法读取拍摄的图片，请重试。")
                return
            }
            parent.onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

struct NutritionLabelOCRDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    let result: NutritionLabelOCRResult
}

/// Drives the whole capture → recognize → confirm flow inside a *single* sheet,
/// swapping content by internal state instead of dismissing one sheet and
/// presenting a sibling one. Presenting a new sheet while another is dismissing
/// leaves the sheet visible but non-interactive (can't scroll or edit), which is
/// why this is one presentation rather than two.
struct NutritionLabelOCRFlowView: View {
    let onConfirm: (FoodTemplate) -> Void
    let onManualEntry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: NutritionLabelOCRDraft?
    @State private var isRecognizing = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let draft {
                NutritionLabelConfirmationView(
                    image: draft.image,
                    result: draft.result,
                    onConfirm: { template in
                        onConfirm(template)
                        dismiss()
                    },
                    onManualEntry: {
                        onManualEntry()
                        dismiss()
                    }
                )
            } else {
                NutritionLabelCaptureView(
                    onImage: { image in recognize(image) },
                    onError: { message in errorMessage = message }
                )
            }
        }
        .overlay {
            if isRecognizing {
                ProgressView("正在识别营养成分…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("无法识别营养成分表", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("手动输入") {
                errorMessage = nil
                onManualEntry()
                dismiss()
            }
            Button("取消", role: .cancel) {
                errorMessage = nil
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "可以重新拍摄，或改为手动输入。")
        }
    }

    private func recognize(_ image: UIImage) {
        isRecognizing = true
        Task {
            defer { isRecognizing = false }
            do {
                let result = try await NutritionLabelOCRService.recognize(image: image)
                draft = NutritionLabelOCRDraft(image: image, result: result)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

