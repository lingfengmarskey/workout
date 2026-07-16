import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    let guideTitle: String
    let progressText: String
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        controller.cameraOverlayView = BodyCameraGuideView(title: guideTitle, progress: progressText)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onCancel()
                return
            }
            parent.onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

private final class BodyCameraGuideView: UIView {
    private let outlineLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()

    init(title: String, progress: String) {
        super.init(frame: UIScreen.main.bounds)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        outlineLayer.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        outlineLayer.fillColor = UIColor.clear.cgColor
        outlineLayer.lineWidth = 2
        outlineLayer.lineDashPattern = [8, 6]
        layer.addSublayer(outlineLayer)

        titleLabel.text = "\(progress) · \(title)"
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        titleLabel.layer.cornerRadius = 14
        titleLabel.clipsToBounds = true
        addSubview(titleLabel)

        hintLabel.text = "头顶和脚底完整入镜 · 保持相同距离 · 正常呼吸"
        hintLabel.textColor = .white
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.48)
        hintLabel.layer.cornerRadius = 12
        hintLabel.clipsToBounds = true
        addSubview(hintLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.frame = CGRect(x: 28, y: safeAreaInsets.top + 18, width: bounds.width - 56, height: 44)
        hintLabel.frame = CGRect(x: 28, y: bounds.height - safeAreaInsets.bottom - 190, width: bounds.width - 56, height: 48)

        let centerX = bounds.midX
        let top = safeAreaInsets.top + 85
        let bottom = bounds.height - safeAreaInsets.bottom - 215
        let height = max(bottom - top, 220)
        let shoulder = min(bounds.width * 0.28, height * 0.18)
        let hip = shoulder * 0.72
        let path = UIBezierPath()
        path.addArc(withCenter: CGPoint(x: centerX, y: top + height * 0.07), radius: height * 0.055, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        path.move(to: CGPoint(x: centerX - shoulder, y: top + height * 0.19))
        path.addLine(to: CGPoint(x: centerX - hip, y: top + height * 0.52))
        path.addLine(to: CGPoint(x: centerX - hip * 0.72, y: top + height * 0.96))
        path.move(to: CGPoint(x: centerX + shoulder, y: top + height * 0.19))
        path.addLine(to: CGPoint(x: centerX + hip, y: top + height * 0.52))
        path.addLine(to: CGPoint(x: centerX + hip * 0.72, y: top + height * 0.96))
        path.move(to: CGPoint(x: centerX - shoulder, y: top + height * 0.19))
        path.addQuadCurve(to: CGPoint(x: centerX + shoulder, y: top + height * 0.19), controlPoint: CGPoint(x: centerX, y: top + height * 0.13))
        outlineLayer.path = path.cgPath
    }
}
