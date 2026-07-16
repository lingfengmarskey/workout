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
        let orientation = image.imageOrientation.cgImageOrientation

        return await Task.detached(priority: .userInitiated) {
            let poseRequest = VNDetectHumanBodyPoseRequest()
            let rectangleRequest = VNDetectHumanRectanglesRequest()
            rectangleRequest.upperBodyOnly = false
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation
            )

            do {
                try handler.perform([poseRequest, rectangleRequest])
                guard let observation = selectPrimaryPose(from: poseRequest.results ?? []) else {
                    return BodyPhotoQualityResult(warnings: ["没有检测到完整人物，请确保全身清楚入镜。"])
                }
                let humanBounds = matchingHumanBounds(
                    for: observation,
                    candidates: rectangleRequest.results ?? []
                )
                return evaluate(observation, humanBounds: humanBounds)
            } catch {
                return BodyPhotoQualityResult(warnings: ["暂时无法检查照片质量，你可以重拍或仍然使用。"])
            }
        }.value
    }

    private static func selectPrimaryPose(
        from observations: [VNHumanBodyPoseObservation]
    ) -> VNHumanBodyPoseObservation? {
        observations.max { primarySubjectScore($0) < primarySubjectScore($1) }
    }

    private static func primarySubjectScore(_ observation: VNHumanBodyPoseObservation) -> CGFloat {
        guard let points = try? observation.recognizedPoints(.all) else { return 0 }
        let visible = points.values.filter { $0.confidence >= 0.25 }
        guard
            let minX = visible.map(\.location.x).min(),
            let maxX = visible.map(\.location.x).max(),
            let minY = visible.map(\.location.y).min(),
            let maxY = visible.map(\.location.y).max()
        else { return 0 }

        let extent = max(maxX - minX, 0.05) * max(maxY - minY, 0.05)
        let centerX = (minX + maxX) / 2
        let centerPenalty = abs(centerX - 0.5) * 0.35
        let coverageBonus = min(CGFloat(visible.count) / 20, 1) * 0.15
        return extent + coverageBonus - centerPenalty
    }

    private static func matchingHumanBounds(
        for pose: VNHumanBodyPoseObservation,
        candidates: [VNHumanObservation]
    ) -> CGRect? {
        guard let points = try? pose.recognizedPoints(.all) else { return nil }
        let visible = points.values.filter { $0.confidence >= 0.25 }
        guard
            let minX = visible.map(\.location.x).min(),
            let maxX = visible.map(\.location.x).max(),
            let minY = visible.map(\.location.y).min(),
            let maxY = visible.map(\.location.y).max()
        else { return nil }

        let poseCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        return candidates.min { lhs, rhs in
            lhs.boundingBox.centerDistance(to: poseCenter) < rhs.boundingBox.centerDistance(to: poseCenter)
        }?.boundingBox
    }

    private static func evaluate(
        _ observation: VNHumanBodyPoseObservation,
        humanBounds: CGRect?
    ) -> BodyPhotoQualityResult {
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
                let estimatedHeadTop = maxY + max(height * 0.08, 0.025)
                let estimatedFootBottom = minY - max(height * 0.04, 0.015)
                let humanTouchesEdge = humanBounds.map {
                    $0.minX < 0.025 || $0.maxX > 0.975 || $0.minY < 0.02 || $0.maxY > 0.98
                } ?? false
                if humanTouchesEdge || estimatedHeadTop > 0.98 || estimatedFootBottom < 0.02 {
                    warnings.append("头顶或脚底可能贴近画面边缘，请后退并留出完整身体的安全空间。")
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

private extension CGRect {
    func centerDistance(to point: CGPoint) -> CGFloat {
        hypot(midX - point.x, midY - point.y)
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
