import SwiftData

/// The schema shipped before explicit migration support was introduced.
///
/// Keep this model list unchanged. Future persisted-model changes belong in a
/// new `VersionedSchema` so existing stores can be migrated predictably.
enum WorkoutSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WorkoutSchemaV1.WeightLossPlan.self,
            WorkoutSchemaV1.DailyBodyRecord.self,
            WorkoutSchemaV1.DailyMealPlan.self,
            WorkoutSchemaV1.DailyWorkoutPlan.self
        ]
    }
}

enum WorkoutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WorkoutSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
