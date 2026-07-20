import Foundation
import SwiftData

/// V8 adds persisted, traceable activity additions to the daily workout plan.
/// The source meal and food-entry IDs remain part of the JSON snapshot so the
/// user can understand why an activity was added without changing historical
/// nutrition records.
enum WorkoutSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WorkoutSchemaV4.WeightLossPlan.self,
            WorkoutSchemaV4.DailyBodyRecord.self,
            WorkoutSchemaV5.DailyMealPlan.self,
            WorkoutSchemaV8.DailyWorkoutPlan.self,
            WorkoutSchemaV4.SyncTombstone.self,
            WorkoutSchemaV4.CloudSyncState.self,
            WorkoutSchemaV4.PhotoSyncMetadata.self,
            WorkoutSchemaV6.FoodTemplate.self,
            WorkoutSchemaV7.CompoundMealTemplate.self
        ]
    }
}

extension WorkoutSchemaV8 {
@Model
final class DailyWorkoutPlan {
    @Attribute(.unique) var id: UUID
    var planID: UUID
    var date: Date
    var workoutType: String
    var strengthDescription: String
    var cardioDescription: String
    var warmupDescription: String
    var cooldownDescription: String
    var plannedDurationMinutes: Int
    var targetSteps: Int
    var intensityDescription: String
    var statusRaw: String
    var actualDurationMinutes: Int?
    var actualSteps: Int?
    var fatigueLevel: Int?
    var painDescription: String
    var note: String
    /// JSON-encoded user-confirmed activities appended from actual food entries.
    var addedActivitiesJSON: String = "[]"
    var updatedAt: Date = Date.now
    var syncRevision: Int = 0

    init(
        id: UUID = UUID(),
        planID: UUID,
        date: Date,
        workoutType: String,
        strengthDescription: String,
        cardioDescription: String,
        warmupDescription: String,
        cooldownDescription: String,
        plannedDurationMinutes: Int,
        targetSteps: Int,
        intensityDescription: String
    ) {
        self.id = id
        self.planID = planID
        self.date = Calendar.current.startOfDay(for: date)
        self.workoutType = workoutType
        self.strengthDescription = strengthDescription
        self.cardioDescription = cardioDescription
        self.warmupDescription = warmupDescription
        self.cooldownDescription = cooldownDescription
        self.plannedDurationMinutes = plannedDurationMinutes
        self.targetSteps = targetSteps
        self.intensityDescription = intensityDescription
        self.statusRaw = CompletionStatus.notRecorded.rawValue
        self.painDescription = ""
        self.note = ""
        self.addedActivitiesJSON = "[]"
    }

    var status: CompletionStatus {
        get { CompletionStatus(rawValue: statusRaw) ?? .notRecorded }
        set { statusRaw = newValue.rawValue }
    }

    var addedActivities: [PlannedActivityAddition] {
        get {
            guard let data = addedActivitiesJSON.data(using: .utf8),
                  let values = try? JSONDecoder().decode([PlannedActivityAddition].self, from: data) else {
                return []
            }
            return values
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            addedActivitiesJSON = json
            updatedAt = .now
            syncRevision += 1
        }
    }
}

}

typealias DailyWorkoutPlan = WorkoutSchemaV8.DailyWorkoutPlan
