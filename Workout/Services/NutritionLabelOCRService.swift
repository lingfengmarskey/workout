import UIKit
import Vision

enum NutritionLabelOCRError: LocalizedError {
    case noImage
    case noText
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .noImage: "无法读取这张图片。"
        case .noText: "没有识别到营养成分文字，请重新拍摄或改为手动输入。"
        case .recognitionFailed: "营养成分识别失败，请重新拍摄或改为手动输入。"
        }
    }
}

enum NutritionLabelOCRService {
    static func recognize(image: UIImage) async throws -> NutritionLabelOCRResult {
        guard let cgImage = image.cgImage else { throw NutritionLabelOCRError.noImage }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    continuation.resume(throwing: NutritionLabelOCRError.recognitionFailed)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                guard !lines.isEmpty else {
                    continuation.resume(throwing: NutritionLabelOCRError.noText)
                    return
                }
                continuation.resume(returning: NutritionLabelParser.parse(lines.joined(separator: "\n")))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "ja-JP", "en-US"]
            request.minimumTextHeight = 0.012

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: NutritionLabelOCRError.recognitionFailed)
                }
            }
        }
    }
}

