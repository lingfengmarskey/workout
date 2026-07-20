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

enum WorkoutSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        // V3 was shipped with the V2 model types plus the photo metadata
        // model. Keep that exact list so stores created by that release can
        // be migrated to the corrected V4 schema below.
        WorkoutSchemaV2.models + [WorkoutSchemaV3.PhotoSyncMetadata.self]
    }
}

enum WorkoutSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WorkoutSchemaV4.WeightLossPlan.self,
            WorkoutSchemaV4.DailyBodyRecord.self,
            WorkoutSchemaV4.DailyMealPlan.self,
            WorkoutSchemaV4.DailyWorkoutPlan.self,
            WorkoutSchemaV4.SyncTombstone.self,
            WorkoutSchemaV4.CloudSyncState.self,
            WorkoutSchemaV4.PhotoSyncMetadata.self
        ]
    }
}

enum WorkoutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WorkoutSchemaV1.self, WorkoutSchemaV2.self, WorkoutSchemaV3.self, WorkoutSchemaV4.self, WorkoutSchemaV5.self, WorkoutSchemaV6.self, WorkoutSchemaV7.self, WorkoutSchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: WorkoutSchemaV1.self, toVersion: WorkoutSchemaV2.self),
            .lightweight(fromVersion: WorkoutSchemaV2.self, toVersion: WorkoutSchemaV3.self),
            .lightweight(fromVersion: WorkoutSchemaV3.self, toVersion: WorkoutSchemaV4.self),
            .lightweight(fromVersion: WorkoutSchemaV4.self, toVersion: WorkoutSchemaV5.self),
            .lightweight(fromVersion: WorkoutSchemaV5.self, toVersion: WorkoutSchemaV6.self),
            .lightweight(fromVersion: WorkoutSchemaV6.self, toVersion: WorkoutSchemaV7.self),
            .lightweight(fromVersion: WorkoutSchemaV7.self, toVersion: WorkoutSchemaV8.self)
        ]
    }
}
