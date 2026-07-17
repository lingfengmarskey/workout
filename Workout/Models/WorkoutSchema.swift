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

enum WorkoutSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WorkoutSchemaV2.WeightLossPlan.self,
            WorkoutSchemaV2.DailyBodyRecord.self,
            WorkoutSchemaV2.DailyMealPlan.self,
            WorkoutSchemaV2.DailyWorkoutPlan.self,
            WorkoutSchemaV2.SyncTombstone.self,
            WorkoutSchemaV2.CloudSyncState.self
        ]
    }
}

enum WorkoutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WorkoutSchemaV1.self, WorkoutSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: WorkoutSchemaV1.self, toVersion: WorkoutSchemaV2.self)
        ]
    }
}
