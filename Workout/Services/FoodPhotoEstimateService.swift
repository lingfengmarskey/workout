import Foundation
import UIKit

struct FoodPhotoEstimateCandidate: Codable, Equatable, Identifiable {
    var id: UUID
    var foodName: String
    var amount: Double
    var unit: String
    var basisAmount: Double
    var caloriesPerBasis: Double
    var proteinPerBasis: Double?
    var carbohydratesPerBasis: Double?
    var fatPerBasis: Double?
    var sodiumPerBasis: Double?
    var confidence: Double

    init(
        id: UUID = UUID(),
        foodName: String,
        amount: Double,
        unit: String = "g",
        basisAmount: Double = 100,
        caloriesPerBasis: Double,
        proteinPerBasis: Double? = nil,
        carbohydratesPerBasis: Double? = nil,
        fatPerBasis: Double? = nil,
        sodiumPerBasis: Double? = nil,
        confidence: Double
    ) {
        self.id = id
        self.foodName = foodName
        self.amount = amount
        self.unit = unit
        self.basisAmount = basisAmount
        self.caloriesPerBasis = caloriesPerBasis
        self.proteinPerBasis = proteinPerBasis
        self.carbohydratesPerBasis = carbohydratesPerBasis
        self.fatPerBasis = fatPerBasis
        self.sodiumPerBasis = sodiumPerBasis
        self.confidence = confidence
    }

    var multiplier: Double {
        guard basisAmount > 0 else { return 0 }
        return amount / basisAmount
    }

    var calories: Double { max(0, caloriesPerBasis * multiplier) }
    var protein: Double? { proteinPerBasis.map { max(0, $0 * multiplier) } }
    var carbohydrates: Double? { carbohydratesPerBasis.map { max(0, $0 * multiplier) } }
    var fat: Double? { fatPerBasis.map { max(0, $0 * multiplier) } }
    var sodium: Double? { sodiumPerBasis.map { max(0, $0 * multiplier) } }
}

protocol FoodPhotoEstimateProviding {
    func estimate(image: UIImage) async throws -> [FoodPhotoEstimateCandidate]
}

enum FoodPhotoEstimateError: LocalizedError {
    case noCandidates

    var errorDescription: String? {
        switch self {
        case .noCandidates: "没有识别到明确的食物，请改用模板或手动输入。"
        }
    }
}

/// Demonstration provider for the MVP. It keeps the UI and confirmation flow
/// independent of a future on-device or server vision model.
struct MockFoodPhotoEstimateProvider: FoodPhotoEstimateProviding {
    func estimate(image: UIImage) async throws -> [FoodPhotoEstimateCandidate] {
        guard image.size.width > 0, image.size.height > 0 else {
            throw FoodPhotoEstimateError.noCandidates
        }
        return [
            FoodPhotoEstimateCandidate(
                foodName: "米饭（示例估算）",
                amount: 200,
                unit: "g",
                basisAmount: 100,
                caloriesPerBasis: 116,
                proteinPerBasis: 2.6,
                carbohydratesPerBasis: 25.9,
                fatPerBasis: 0.3,
                confidence: 0.45
            )
        ]
    }
}
