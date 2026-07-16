import ImageIO
import UIKit
import Vision

struct BodyPhotoQualityResult: Sendable {
    let warnings: [String]

    var isAcceptable: Bool { warnings.isEmpty }
}

enum BodyPhotoQualityAnalyzer {
    static func analyze(_ image: UIImage) async -> BodyPhotoQualityResult {
        guard image.size.width >= 720, image.size.height >= 1_000 else {
            return BodyPhotoQualityResult(warnings: ["照片分辨率较低，请使用相机重新拍摄。"])
        }
        guard let cgImage = image.cgImage else {
            return BodyPhotoQualityResult(warnings: ["无法读取照片，请重新拍摄。"])
        }

        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.imageOrientation.cgImageOrientation
            )

            do {
                try handler.perform([request])
                guard let observation = request.results?.first else {
                    return BodyPhotoQualityResult(warnings: ["没有检测到完整人物，请确保全身清楚入镜。"])
                }
                return evaluate(observation)
            } catch {
                return BodyPhotoQualityResult(warnings: ["暂时无法检查照片质量，你可以重拍或仍然使用。"])
            }
        }.value
    }

    private static func evaluate(_ observation: VNHumanBodyPoseObservation) -> BodyPhotoQualityResult {
        guard let points = try? observation.recognizedPoints(.all) else {
            return BodyPhotoQualityResult(warnings: ["无法识别人体关键位置，请重新拍摄。"])
        }

        func point(_ name: VNHumanBodyPoseObservation.JointName) -> VNRecognizedPoint? {
            guard let point = points[name], point.confidence >= 0.25 else { return nil }
            return point
        }

        let head = point(.nose) ?? point(.neck)
        let shoulders = [point(.leftShoulder), point(.rightShoulder)].compactMap { $0 }
        let hips = [point(.leftHip), point(.rightHip)].compactMap { $0 }
        let knees = [point(.leftKnee), point(.rightKnee)].compactMap { $0 }
        let ankles = [point(.leftAnkle), point(.rightAnkle)].compactMap { $0 }
        var warnings: [String] = []

        if head == nil { warnings.append("头部未完整识别，请确认头顶没有超出画面。") }
        if shoulders.isEmpty || hips.isEmpty { warnings.append("肩部或髋部不清楚，请面向引导方向并避免遮挡身体。") }
        if knees.isEmpty || ankles.isEmpty { warnings.append("腿部或脚部未完整识别，请后退一步，让脚底进入画面。") }

        let visiblePoints = points.values.filter { $0.confidence >= 0.25 }
        if !visiblePoints.isEmpty {
            let xs = visiblePoints.map(\.location.x)
            let ys = visiblePoints.map(\.location.y)
            if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
                let height = maxY - minY
                let centerX = (minX + maxX) / 2
                if minX < 0.025 || maxX > 0.975 || minY < 0.02 || maxY > 0.98 {
                    warnings.append("身体太靠近画面边缘，请后退并留出少量上下左右空间。")
                }
                if centerX < 0.35 || centerX > 0.65 {
                    warnings.append("人物没有居中，请移动到人体引导线中央。")
                }
                if height < 0.5 {
                    warnings.append("人物在画面中太小，请适当靠近手机。")
                }
            }
        }

        return BodyPhotoQualityResult(warnings: Array(warnings.prefix(3)))
    }
}

private extension UIImage.Orientation {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
