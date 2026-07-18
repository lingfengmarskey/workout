import Foundation
import SwiftData

/// V5 keeps the existing V4 entities and adds a JSON nutrition snapshot to
/// each daily meal plan. The snapshot is part of the meal record so it follows
/// the existing CloudKit conflict and deletion semantics.
enum WorkoutSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WorkoutSchemaV4.WeightLossPlan.self,
            WorkoutSchemaV4.DailyBodyRecord.self,
            WorkoutSchemaV5.DailyMealPlan.self,
            WorkoutSchemaV4.DailyWorkoutPlan.self,
            WorkoutSchemaV4.SyncTombstone.self,
            WorkoutSchemaV4.CloudSyncState.self,
            WorkoutSchemaV4.PhotoSyncMetadata.self
        ]
    }
}

extension WorkoutSchemaV5 {
    @Model
    final class DailyMealPlan {
        @Attribute(.unique) var id: UUID
        var planID: UUID
        var date: Date
        var breakfast: String
        var lunch: String
        var dinner: String
        var snack: String
        var plannedCalories: Int
        var plannedProtein: Int
        var waterTarget: Double
        var breakfastStatusRaw: String
        var lunchStatusRaw: String
        var dinnerStatusRaw: String
        var snackStatusRaw: String
        var hungerLevel: Int?
        var actualWater: Double?
        var note: String
        var actualFoodEntriesJSON: String = "[]"
        var updatedAt: Date = Date.now
        var syncRevision: Int = 0

        init(
            id: UUID = UUID(),
            planID: UUID,
            date: Date,
            breakfast: String,
            lunch: String,
            dinner: String,
            snack: String,
            plannedCalories: Int,
            plannedProtein: Int,
            waterTarget: Double
        ) {
            self.id = id
            self.planID = planID
            self.date = Calendar.current.startOfDay(for: date)
            self.breakfast = breakfast
            self.lunch = lunch
            self.dinner = dinner
            self.snack = snack
            self.plannedCalories = plannedCalories
            self.plannedProtein = plannedProtein
            self.waterTarget = waterTarget
            self.breakfastStatusRaw = CompletionStatus.notRecorded.rawValue
            self.lunchStatusRaw = CompletionStatus.notRecorded.rawValue
            self.dinnerStatusRaw = CompletionStatus.notRecorded.rawValue
            self.snackStatusRaw = CompletionStatus.notRecorded.rawValue
            self.note = ""
        }

        var breakfastStatus: CompletionStatus {
            get { CompletionStatus(rawValue: breakfastStatusRaw) ?? .notRecorded }
            set { breakfastStatusRaw = newValue.rawValue }
        }
        var lunchStatus: CompletionStatus {
            get { CompletionStatus(rawValue: lunchStatusRaw) ?? .notRecorded }
            set { lunchStatusRaw = newValue.rawValue }
        }
        var dinnerStatus: CompletionStatus {
            get { CompletionStatus(rawValue: dinnerStatusRaw) ?? .notRecorded }
            set { dinnerStatusRaw = newValue.rawValue }
        }
        var snackStatus: CompletionStatus {
            get { CompletionStatus(rawValue: snackStatusRaw) ?? .notRecorded }
            set { snackStatusRaw = newValue.rawValue }
        }
        var completedMealCount: Int {
            [breakfastStatus, lunchStatus, dinnerStatus, snackStatus].filter { $0 == .completed }.count
        }

        var actualFoodEntries: [ActualFoodEntry] {
            get {
                guard let data = actualFoodEntriesJSON.data(using: .utf8),
                      let entries = try? JSONDecoder().decode([ActualFoodEntry].self, from: data) else {
                    return []
                }
                return entries
            }
            set {
                guard let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) else { return }
                actualFoodEntriesJSON = json
            }
        }

        var actualCalories: Double { actualFoodEntries.reduce(0) { $0 + $1.calories } }
        var actualProtein: Double? { sumOptional(actualFoodEntries.map(\.protein)) }
        var actualCarbohydrates: Double? { sumOptional(actualFoodEntries.map(\.carbohydrates)) }
        var actualFat: Double? { sumOptional(actualFoodEntries.map(\.fat)) }
        var actualSodium: Double? { sumOptional(actualFoodEntries.map(\.sodium)) }

        private func sumOptional(_ values: [Double?]) -> Double? {
            guard values.contains(where: { $0 != nil }) else { return nil }
            return values.compactMap { $0 }.reduce(0, +)
        }
    }
}
