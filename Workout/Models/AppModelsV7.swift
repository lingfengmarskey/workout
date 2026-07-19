import Foundation
import SwiftData

/// V7 adds persisted compound meal templates without changing any existing
/// model. A compound meal stores its component nutrition snapshot as JSON so
/// changing a source food template cannot alter historical records.
enum WorkoutSchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        WorkoutSchemaV6.models + [WorkoutSchemaV7.CompoundMealTemplate.self]
    }
}

extension WorkoutSchemaV7 {
    @Model
    final class CompoundMealTemplate {
        @Attribute(.unique) var id: UUID
        var name: String
        var componentsJSON: String
        var isFavorite: Bool
        var lastUsedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            name: String,
            components: [CompoundMealComponent],
            isFavorite: Bool = false,
            lastUsedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.componentsJSON = Self.encode(components)
            self.isFavorite = isFavorite
            self.lastUsedAt = lastUsedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        var components: [CompoundMealComponent] {
            get { Self.decode(componentsJSON) }
            set {
                componentsJSON = Self.encode(newValue)
                updatedAt = .now
            }
        }

        var nutrition: CompoundMealNutrition {
            CompoundMealCalculator.nutrition(for: components)
        }

        func markUsed(at date: Date = .now) {
            lastUsedAt = date
            updatedAt = date
        }

        private static func encode(_ components: [CompoundMealComponent]) -> String {
            guard let data = try? JSONEncoder().encode(components),
                  let json = String(data: data, encoding: .utf8) else { return "[]" }
            return json
        }

        private static func decode(_ json: String) -> [CompoundMealComponent] {
            guard let data = json.data(using: .utf8),
                  let components = try? JSONDecoder().decode([CompoundMealComponent].self, from: data)
            else { return [] }
            return components
        }
    }
}

typealias CompoundMealTemplate = WorkoutSchemaV7.CompoundMealTemplate
