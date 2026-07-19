import Foundation
import SwiftData

@MainActor
enum SyncDeletionService {
    static func stageDeletion(
        id: UUID,
        entityType: SyncEntityType,
        in context: ModelContext,
        deletedAt: Date = .now
    ) throws {
        let recordName = entityType.recordName(for: id)
        let descriptor = FetchDescriptor<SyncTombstone>(
            predicate: #Predicate { $0.recordName == recordName }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = max(existing.deletedAt, deletedAt)
            existing.deviceID = SyncDeviceIdentity.current
            existing.isUploaded = false
        } else {
            context.insert(SyncTombstone(
                recordName: recordName,
                entityType: entityType,
                deletedAt: deletedAt
            ))
        }
    }

    static func deletePlanGraph(
        plan: WeightLossPlan,
        bodyRecords: [DailyBodyRecord],
        mealPlans: [DailyMealPlan],
        workoutPlans: [DailyWorkoutPlan],
        from context: ModelContext
    ) throws {
        let deletedAt = Date.now
        try stageDeletion(id: plan.id, entityType: .plan, in: context, deletedAt: deletedAt)

        for record in bodyRecords {
            try stageDeletion(id: record.id, entityType: .bodyRecord, in: context, deletedAt: deletedAt)
            context.delete(record)

            // Photo metadata is an independent sync entity. Stage the
            // per-angle tombstones after removing the body record so SwiftData
            // cannot treat the pending body deletion as an object-graph change
            // and drop newly inserted metadata during the same save.
            for angle in CloudPhotoAngle.allCases {
                try CloudPhotoSyncService.stageLocalMutation(
                    bodyID: record.id,
                    angle: angle,
                    contentHash: nil,
                    at: deletedAt,
                    in: context
                )
            }
        }
        for meal in mealPlans {
            try stageDeletion(id: meal.id, entityType: .mealPlan, in: context, deletedAt: deletedAt)
            context.delete(meal)
        }
        for workout in workoutPlans {
            try stageDeletion(id: workout.id, entityType: .workoutPlan, in: context, deletedAt: deletedAt)
            context.delete(workout)
        }
        context.delete(plan)
    }
}
