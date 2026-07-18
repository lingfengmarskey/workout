import Foundation

/// The supported nutrition basis for a food template. The raw values are
/// persisted so templates remain stable across localization changes.
enum FoodNutritionBasisUnit: String, Codable, CaseIterable, Identifiable {
    case gram = "g"
    case milliliter = "ml"
    case serving
    case package

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gram: "克"
        case .milliliter: "毫升"
        case .serving: "份"
        case .package: "包装"
        }
    }
}

/// Where the nutrition values for a template came from. Recognition and
/// database integrations are intentionally represented now, but are implemented
/// by later issues.
enum FoodTemplateSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case template
    case barcodeDatabase
    case labelOCR
    case photoEstimate
    case planned

    var id: String { rawValue }
}

enum FoodTemplateConfidence: String, Codable, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }
}

enum FoodTemplateValidationError: LocalizedError, Equatable {
    case emptyName
    case invalidBasisAmount
    case unsupportedBasisUnit
    case invalidCalories
    case invalidNutrient(String)
    case unsupportedSource
    case unsupportedConfidence

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入食物名称。"
        case .invalidBasisAmount: "营养基准数量必须大于 0。"
        case .unsupportedBasisUnit: "营养基准单位不受支持。"
        case .invalidCalories: "能量必须是大于或等于 0 的有效数值。"
        case .invalidNutrient(let name): "\(name)必须是大于或等于 0 的有效数值。"
        case .unsupportedSource: "数据来源不受支持。"
        case .unsupportedConfidence: "数据可信度不受支持。"
        }
    }
}

enum FoodTemplateValidation {
    static func validate(
        name: String,
        basisAmount: Double,
        basisUnitRaw: String,
        caloriesPerBasis: Double,
        proteinPerBasis: Double?,
        fatPerBasis: Double?,
        carbohydratesPerBasis: Double?,
        sodiumPerBasis: Double?,
        sourceRaw: String,
        confidenceRaw: String
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FoodTemplateValidationError.emptyName
        }
        guard basisAmount.isFinite, basisAmount > 0 else {
            throw FoodTemplateValidationError.invalidBasisAmount
        }
        guard FoodNutritionBasisUnit(rawValue: basisUnitRaw) != nil else {
            throw FoodTemplateValidationError.unsupportedBasisUnit
        }
        guard caloriesPerBasis.isFinite, caloriesPerBasis >= 0 else {
            throw FoodTemplateValidationError.invalidCalories
        }
        try validateNutrient(proteinPerBasis, name: "蛋白质")
        try validateNutrient(fatPerBasis, name: "脂肪")
        try validateNutrient(carbohydratesPerBasis, name: "碳水化合物")
        try validateNutrient(sodiumPerBasis, name: "钠")
        guard FoodTemplateSource(rawValue: sourceRaw) != nil else {
            throw FoodTemplateValidationError.unsupportedSource
        }
        guard FoodTemplateConfidence(rawValue: confidenceRaw) != nil else {
            throw FoodTemplateValidationError.unsupportedConfidence
        }
    }

    private static func validateNutrient(_ value: Double?, name: String) throws {
        guard let value else { return }
        guard value.isFinite, value >= 0 else {
            throw FoodTemplateValidationError.invalidNutrient(name)
        }
    }
}
