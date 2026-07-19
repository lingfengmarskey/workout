import Foundation

enum NutritionLabelField: String, CaseIterable, Identifiable {
    case energy
    case protein
    case fat
    case carbohydrates
    case sugar
    case fiber
    case sodium

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .energy: "能量"
        case .protein: "蛋白质"
        case .fat: "脂肪"
        case .carbohydrates: "碳水化合物"
        case .sugar: "糖"
        case .fiber: "膳食纤维"
        case .sodium: "钠"
        }
    }
}

struct NutritionLabelOCRResult: Equatable {
    var rawText: String
    var basisAmount: Double?
    var basisUnit: FoodNutritionBasisUnit?
    var calories: Double?
    var energyUnit: FoodEnergyUnit
    var protein: Double?
    var fat: Double?
    var carbohydrates: Double?
    var sugar: Double?
    var fiber: Double?
    var sodium: Double?
    var fieldConfidences: [NutritionLabelField: Double]

    var overallConfidence: Double {
        let values = fieldConfidences.values
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var hasRequiredNutrition: Bool {
        basisAmount != nil && basisUnit != nil && calories != nil
    }
}

enum NutritionLabelParser {
    private static let number = "([0-9０-９]+(?:[.,，][0-9０-９]+)?)"

    static func parse(_ rawText: String) -> NutritionLabelOCRResult {
        let normalizedText = normalize(rawText)
        let lines = normalizedText
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let basis = findBasis(in: normalizedText)
        var result = NutritionLabelOCRResult(
            rawText: rawText,
            basisAmount: basis.amount,
            basisUnit: basis.unit,
            calories: nil,
            energyUnit: .kcal,
            protein: nil,
            fat: nil,
            carbohydrates: nil,
            sugar: nil,
            fiber: nil,
            sodium: nil,
            fieldConfidences: [:]
        )

        for line in lines {
            parseEnergy(line, into: &result)
            parseNutrient(line, aliases: ["protein", "蛋白质", "蛋白", "たんぱく質", "タンパク質"], field: .protein, into: &result)
            parseNutrient(line, aliases: ["fat", "脂肪", "脂質"], field: .fat, into: &result)
            parseNutrient(line, aliases: ["carbohydrate", "carbs", "碳水化合物", "碳水", "炭水化物"], field: .carbohydrates, into: &result)
            parseNutrient(line, aliases: ["sugars", "sugar", "糖", "糖类", "糖類"], field: .sugar, into: &result)
            parseNutrient(line, aliases: ["fiber", "dietary fiber", "膳食纤维", "膳食纖維", "食物繊維"], field: .fiber, into: &result)
            parseNutrient(line, aliases: ["sodium", "钠", "鈉", "ナトリウム"], field: .sodium, into: &result, multiplier: 1)
        }

        if result.basisAmount != nil, result.basisUnit != nil {
            result.fieldConfidences[.energy, default: 0] += 0.1
        }
        return result
    }

    private static func parseEnergy(_ line: String, into result: inout NutritionLabelOCRResult) {
        let aliases = ["calories", "calorie", "energy", "能量", "热量", "熱量", "エネルギー"]
        guard containsAlias(line, aliases: aliases),
              let match = firstNumber(in: line, afterAliases: aliases) else { return }
        result.calories = match.value
        result.energyUnit = match.unit?.lowercased().contains("kj") == true || match.unit == "千焦" ? .kJ : .kcal
        result.fieldConfidences[.energy] = 0.85
    }

    private static func parseNutrient(
        _ line: String,
        aliases: [String],
        field: NutritionLabelField,
        into result: inout NutritionLabelOCRResult,
        multiplier: Double = 1
    ) {
        guard containsAlias(line, aliases: aliases),
              let match = firstNumber(in: line, afterAliases: aliases) else { return }
        let value = match.value * multiplier
        switch field {
        case .energy: result.calories = value
        case .protein: result.protein = value
        case .fat: result.fat = value
        case .carbohydrates: result.carbohydrates = value
        case .sugar: result.sugar = value
        case .fiber: result.fiber = value
        case .sodium: result.sodium = value
        }
        result.fieldConfidences[field] = 0.8
    }

    private static func findBasis(in text: String) -> (amount: Double?, unit: FoodNutritionBasisUnit?) {
        let pattern = "(?i)(?:每|per|pour|por)\\s*\(number)\\s*(g|克|ml|毫升|milliliter|serving|份|package|包装|pack)"
        guard let match = firstMatch(pattern, in: text),
              let amount = parseNumber(match[1]),
              let unit = FoodNutritionBasisUnit.parse(match[2]) else {
            return (nil, nil)
        }
        return (amount, unit)
    }

    private static func firstNumber(in line: String, afterAliases aliases: [String]) -> (value: Double, unit: String?)? {
        let lowered = line.lowercased()
        let start = aliases.compactMap { lowered.range(of: $0.lowercased())?.upperBound }.min() ?? lowered.startIndex
        let suffix = String(lowered[start...])
        guard let match = firstMatch("\(number)\\s*(kcal|千卡|kj|千焦|mg|毫克|g|克)?", in: suffix),
              let value = parseNumber(match[1]) else { return nil }
        return (value, match.count > 2 ? match[2] : nil)
    }

    private static func containsAlias(_ line: String, aliases: [String]) -> Bool {
        let lowered = line.lowercased()
        return aliases.contains { lowered.contains($0.lowercased()) }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private static func parseNumber(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: "０", with: "0")
            .replacingOccurrences(of: "１", with: "1")
            .replacingOccurrences(of: "２", with: "2")
            .replacingOccurrences(of: "３", with: "3")
            .replacingOccurrences(of: "４", with: "4")
            .replacingOccurrences(of: "５", with: "5")
            .replacingOccurrences(of: "６", with: "6")
            .replacingOccurrences(of: "７", with: "7")
            .replacingOccurrences(of: "８", with: "8")
            .replacingOccurrences(of: "９", with: "9")
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "／", with: "/")
    }
}

