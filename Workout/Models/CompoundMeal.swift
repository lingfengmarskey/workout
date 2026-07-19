import Foundation

/// A food item used by a compound meal template. The nutrition values are
/// stored per `basisAmount`, just like a regular food template, while
/// `amount` describes the default portion in the compound meal.
struct CompoundMealComponent: Codable, Equatable, Identifiable {
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

    init(
        id: UUID = UUID(),
        foodName: String,
        amount: Double,
        unit: String,
        basisAmount: Double,
        caloriesPerBasis: Double,
        proteinPerBasis: Double? = nil,
        carbohydratesPerBasis: Double? = nil,
        fatPerBasis: Double? = nil,
        sodiumPerBasis: Double? = nil
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

struct CompoundMealNutrition: Equatable {
    var calories: Double
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var sodium: Double?

    func scaled(by servings: Double) -> Self {
        Self(
            calories: calories * servings,
            protein: protein.map { $0 * servings },
            carbohydrates: carbohydrates.map { $0 * servings },
            fat: fat.map { $0 * servings },
            sodium: sodium.map { $0 * servings }
        )
    }
}

enum CompoundMealCalculator {
    static func nutrition(for components: [CompoundMealComponent]) -> CompoundMealNutrition {
        CompoundMealNutrition(
            calories: components.reduce(0) { $0 + $1.calories },
            protein: sumOptional(components.map(\.protein)),
            carbohydrates: sumOptional(components.map(\.carbohydrates)),
            fat: sumOptional(components.map(\.fat)),
            sodium: sumOptional(components.map(\.sodium))
        )
    }

    private static func sumOptional(_ values: [Double?]) -> Double? {
        guard values.contains(where: { $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }
}
