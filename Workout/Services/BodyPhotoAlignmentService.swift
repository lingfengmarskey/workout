import UIKit
import Vision

enum BodyPhotoAlignmentResult {
    case success(first: UIImage, second: UIImage)
    case failure(message: String)
}

enum BodyPhotoAlignmentService {
    static func align(first: UIImage, second: UIImage) async -> BodyPhotoAlignmentResult {
        await Task.detached(priority: .userInitiated) {
            let normalizedFirst = first.normalizedOrientation()
            let normalizedSecond = second.normalizedOrientation()
            guard
                let firstBounds = detectPrimaryHuman(in: normalizedFirst),
                let secondBounds = detectPrimaryHuman(in: normalizedSecond)
            else {
                return .failure(message: "未能在两张照片中检测到完整人体，已显示原图。")
            }

            let canvasSize = CGSize(width: 1_200, height: 1_600)
            guard
                let alignedFirst = render(normalizedFirst, humanBounds: firstBounds, canvasSize: canvasSize),
                let alignedSecond = render(normalizedSecond, humanBounds: secondBounds, canvasSize: canvasSize)
            else {
                return .failure(message: "照片对齐失败，已显示原图。")
            }
            return .success(first: alignedFirst, second: alignedSecond)
        }.value
    }

    private static func detectPrimaryHuman(in image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
            return request.results?.max { subjectScore($0.boundingBox) < subjectScore($1.boundingBox) }?.boundingBox
        } catch {
            return nil
        }
    }

    private static func subjectScore(_ bounds: CGRect) -> CGFloat {
        let centerDistance = hypot(bounds.midX - 0.5, bounds.midY - 0.5)
        return bounds.width * bounds.height - centerDistance * 0.12
    }

    private static func render(
        _ image: UIImage,
        humanBounds normalizedBounds: CGRect,
        canvasSize: CGSize
    ) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0, normalizedBounds.height > 0.05 else { return nil }

        let bodyBounds = CGRect(
            x: normalizedBounds.minX * image.size.width,
            y: (1 - normalizedBounds.maxY) * image.size.height,
            width: normalizedBounds.width * image.size.width,
            height: normalizedBounds.height * image.size.height
        )
        let targetBodyHeight = canvasSize.height * 0.82
        let targetBodyBottom = canvasSize.height * 0.92
        let scale = targetBodyHeight / bodyBounds.height
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawOrigin = CGPoint(
            x: canvasSize.width / 2 - bodyBounds.midX * scale,
            y: targetBodyBottom - bodyBounds.maxY * scale
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
