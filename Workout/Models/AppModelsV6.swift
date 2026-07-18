import Foundation
import SwiftData

/// V6 adds the local food-template catalog. Existing model types are reused
/// unchanged so migrating a V5 store only creates the new table and preserves
/// all plans, meal snapshots, body records and sync metadata.
enum WorkoutSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        WorkoutSchemaV5.models + [WorkoutSchemaV6.FoodTemplate.self]
    }
}

extension WorkoutSchemaV6 {
    @Model
    final class FoodTemplate {
        @Attribute(.unique) var id: UUID
        var name: String
        var brand: String
        var barcode: String?
        var locale: String
        var basisAmount: Double
        var basisUnitRaw: String
        var caloriesPerBasis: Double
        var proteinPerBasis: Double?
        var fatPerBasis: Double?
        var carbohydratesPerBasis: Double?
        var sodiumPerBasis: Double?
        var sourceRaw: String
        var confidenceRaw: String
        var isFavorite: Bool
        var lastUsedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            name: String,
            brand: String = "",
            barcode: String? = nil,
            locale: String = Locale.current.identifier,
            basisAmount: Double,
            basisUnit: FoodNutritionBasisUnit,
            caloriesPerBasis: Double,
            proteinPerBasis: Double? = nil,
            fatPerBasis: Double? = nil,
            carbohydratesPerBasis: Double? = nil,
            sodiumPerBasis: Double? = nil,
            source: FoodTemplateSource = .manual,
            confidence: FoodTemplateConfidence = .high,
            isFavorite: Bool = false,
            lastUsedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.brand = brand
            self.barcode = barcode
            self.locale = locale
            self.basisAmount = basisAmount
            self.basisUnitRaw = basisUnit.rawValue
            self.caloriesPerBasis = caloriesPerBasis
            self.proteinPerBasis = proteinPerBasis
            self.fatPerBasis = fatPerBasis
            self.carbohydratesPerBasis = carbohydratesPerBasis
            self.sodiumPerBasis = sodiumPerBasis
            self.sourceRaw = source.rawValue
            self.confidenceRaw = confidence.rawValue
            self.isFavorite = isFavorite
            self.lastUsedAt = lastUsedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        var basisUnit: FoodNutritionBasisUnit {
            get { FoodNutritionBasisUnit(rawValue: basisUnitRaw) ?? .gram }
            set { basisUnitRaw = newValue.rawValue }
        }

        var source: FoodTemplateSource {
            get { FoodTemplateSource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }

        var confidence: FoodTemplateConfidence {
            get { FoodTemplateConfidence(rawValue: confidenceRaw) ?? .low }
            set { confidenceRaw = newValue.rawValue }
        }

        var isValidForSave: Bool {
            (try? validateForSave()) != nil
        }

        func validateForSave() throws {
            try FoodTemplateValidation.validate(
                name: name,
                basisAmount: basisAmount,
                basisUnitRaw: basisUnitRaw,
                caloriesPerBasis: caloriesPerBasis,
                proteinPerBasis: proteinPerBasis,
                fatPerBasis: fatPerBasis,
                carbohydratesPerBasis: carbohydratesPerBasis,
                sodiumPerBasis: sodiumPerBasis,
                sourceRaw: sourceRaw,
                confidenceRaw: confidenceRaw
            )
        }

        func markUsed(at date: Date = .now) {
            lastUsedAt = date
            updatedAt = date
        }
    }
}
