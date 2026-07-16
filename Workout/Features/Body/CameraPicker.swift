import SwiftUI
import Speech
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
        let controller = VoiceShutterImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        let guideView = BodyCameraGuideView(title: guideTitle, progress: progressText)
        controller.cameraOverlayView = guideView
        controller.onDidAppear = { [weak controller, weak coordinator = context.coordinator] in
            guard let controller else { return }
            coordinator?.startVoiceShutter(for: controller, guideView: guideView)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker
        private let voiceShutter = VoiceShutterController()
        private var rearmWorkItem: DispatchWorkItem?

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            stopVoiceShutter()
            guard let image = info[.originalImage] as? UIImage else {
                parent.onCancel()
                return
            }
            parent.onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            stopVoiceShutter()
            parent.onCancel()
        }

        fileprivate func startVoiceShutter(for picker: UIImagePickerController, guideView: BodyCameraGuideView) {
            voiceShutter.start(
                statusChanged: { status in guideView.setVoiceStatus(status) },
                capture: { [weak picker, weak guideView] in
                    guideView?.setVoiceStatus("已识别“拍照”，正在拍摄…")
                    picker?.takePicture()
                    self.scheduleVoiceShutterRearm(for: picker, guideView: guideView)
                }
            )
        }

        private func scheduleVoiceShutterRearm(
            for picker: UIImagePickerController?,
            guideView: BodyCameraGuideView?
        ) {
            rearmWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak picker, weak guideView] in
                guard let self, let picker, let guideView else { return }
                guideView.setVoiceStatus("如需重拍，说“拍照”或“茄子”即可再次拍摄")
                self.startVoiceShutter(for: picker, guideView: guideView)
            }
            rearmWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        }

        private func stopVoiceShutter() {
            rearmWorkItem?.cancel()
            rearmWorkItem = nil
            voiceShutter.stop()
        }
    }
}

private final class VoiceShutterImagePickerController: UIImagePickerController {
    var onDidAppear: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDidAppear?()
    }
}

private final class VoiceShutterController {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasCaptured = false
    private var isStartingOrRunning = false

    func start(statusChanged: @escaping (String) -> Void, capture: @escaping () -> Void) {
        guard !isStartingOrRunning else { return }
        stop()
        isStartingOrRunning = true
        hasCaptured = false
        statusChanged("正在准备语音快门…")

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.isStartingOrRunning = false
                    statusChanged("语音识别未授权，请使用屏幕快门")
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.isStartingOrRunning = false
                            statusChanged("麦克风未授权，请使用屏幕快门")
                            return
                        }
                        self.beginRecognition(statusChanged: statusChanged, capture: capture)
                    }
                }
            }
        }
    }

    func stop() {
        isStartingOrRunning = false
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecognition(statusChanged: @escaping (String) -> Void, capture: @escaping () -> Void) {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            isStartingOrRunning = false
            statusChanged("当前设备不支持本地语音快门，请使用屏幕快门")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stop()
            statusChanged("无法启动语音快门，请使用屏幕快门")
            return
        }

        statusChanged("说“拍照”或“茄子”即可拍摄")
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.hasCaptured else { return }
            let text = result?.bestTranscription.formattedString.replacingOccurrences(of: " ", with: "") ?? ""
            let commands = ["拍照", "茄子"]
            if commands.contains(where: text.contains) {
                self.hasCaptured = true
                self.stop()
                DispatchQueue.main.async(execute: capture)
            } else if error != nil {
                self.stop()
                DispatchQueue.main.async {
                    statusChanged("语音监听已停止，请使用屏幕快门")
                }
            }
        }
    }
}

private final class BodyCameraGuideView: UIView {
    private let outlineLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let voiceLabel = UILabel()

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

        voiceLabel.text = "正在准备语音快门…"
        voiceLabel.textColor = .white
        voiceLabel.font = .preferredFont(forTextStyle: .caption1)
        voiceLabel.textAlignment = .center
        voiceLabel.numberOfLines = 2
        voiceLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.72)
        voiceLabel.layer.cornerRadius = 12
        voiceLabel.clipsToBounds = true
        addSubview(voiceLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.frame = CGRect(x: 28, y: safeAreaInsets.top + 18, width: bounds.width - 56, height: 44)
        hintLabel.frame = CGRect(x: 28, y: bounds.height - safeAreaInsets.bottom - 190, width: bounds.width - 56, height: 48)
        voiceLabel.frame = CGRect(x: 28, y: bounds.height - safeAreaInsets.bottom - 136, width: bounds.width - 56, height: 40)

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

    func setVoiceStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.voiceLabel.text = text
        }
    }
}
