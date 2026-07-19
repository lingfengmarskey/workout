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
                        dismiss()
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
                        dismiss()
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

