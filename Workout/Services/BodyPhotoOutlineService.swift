import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

enum BodyPhotoOutlineService {
    static func makeOutline(for image: UIImage, color: UIColor) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

            do {
                try handler.perform([request])
                guard let pixelBuffer = request.results?.first?.pixelBuffer else { return nil }
                return renderOutline(
                    mask: CIImage(cvPixelBuffer: pixelBuffer),
                    canvasSize: image.size,
                    color: color
                )
            } catch {
                return nil
            }
        }.value
    }

    private static func renderOutline(mask: CIImage, canvasSize: CGSize, color: UIColor) -> UIImage? {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let scaledMask = mask.transformed(by: CGAffineTransform(
            scaleX: canvasSize.width / mask.extent.width,
            y: canvasSize.height / mask.extent.height
        ))
        let edges = scaledMask
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 7.0])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.8,
                kCIInputBrightnessKey: -0.18
            ])
            .cropped(to: canvasRect)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let colored = edges.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": zero,
            "inputGVector": zero,
            "inputBVector": zero,
            "inputAVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: red, y: green, z: blue, w: 0)
        ])

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let output = context.createCGImage(colored, from: canvasRect) else { return nil }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }
}
