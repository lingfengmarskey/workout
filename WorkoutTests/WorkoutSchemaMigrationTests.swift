import SwiftData
import XCTest
@testable import Workout

final class WorkoutSchemaMigrationTests: XCTestCase {
    func testMigratesV1StoreToV2WithoutLosingExistingRecords() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-migration-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: storeURL) }

        let planID = UUID()
        try autoreleasepool {
            let v1Schema = Schema(versionedSchema: WorkoutSchemaV1.self)
            let configuration = ModelConfiguration("MigrationTest", schema: v1Schema, url: storeURL)
            let container = try ModelContainer(for: v1Schema, configurations: [configuration])
            let context = ModelContext(container)

            context.insert(WorkoutSchemaV1.WeightLossPlan(
                id: planID,
                name: "迁移测试计划",
                startDate: .now,
                durationDays: 56,
                startWeight: 97,
                phaseTargetWeight: 88.5,
                finalTargetWeight: 80,
                dailyCalorieTarget: 1_900,
                dailyProteinTarget: 140,
                dailyWaterTarget: 2.2
            ))
            context.insert(WorkoutSchemaV1.DailyBodyRecord(planID: planID, date: .now))
            context.insert(WorkoutSchemaV1.DailyMealPlan(
                planID: planID,
                date: .now,
                breakfast: "早餐",
                lunch: "午餐",
                dinner: "晚餐",
                snack: "加餐",
                plannedCalories: 1_900,
                plannedProtein: 140,
                waterTarget: 2.2
            ))
            context.insert(WorkoutSchemaV1.DailyWorkoutPlan(
                planID: planID,
                date: .now,
                workoutType: "快走",
                strengthDescription: "",
                cardioDescription: "45 分钟",
                warmupDescription: "热身",
                cooldownDescription: "拉伸",
                plannedDurationMinutes: 45,
                targetSteps: 8_000,
                intensityDescription: "中等"
            ))
            try context.save()
        }

        let v2Schema = Schema(versionedSchema: WorkoutSchemaV2.self)
        let configuration = ModelConfiguration("MigrationTest", schema: v2Schema, url: storeURL)
        let container = try ModelContainer(
            for: v2Schema,
            migrationPlan: WorkoutMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        let plans = try context.fetch(FetchDescriptor<WorkoutSchemaV2.WeightLossPlan>())
        let bodies = try context.fetch(FetchDescriptor<WorkoutSchemaV2.DailyBodyRecord>())
        let meals = try context.fetch(FetchDescriptor<WorkoutSchemaV2.DailyMealPlan>())
        let workouts = try context.fetch(FetchDescriptor<WorkoutSchemaV2.DailyWorkoutPlan>())

        XCTAssertEqual(plans.map(\.id), [planID])
        XCTAssertEqual(bodies.count, 1)
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(plans.first?.syncRevision, 0)
        XCTAssertEqual(meals.first?.syncRevision, 0)
        XCTAssertNotNil(meals.first?.updatedAt)
        XCTAssertNotNil(workouts.first?.updatedAt)
        XCTAssertNil(bodies.first?.frontPhotoHash)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSchemaV2.SyncTombstone>()).isEmpty)
    }

    private func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fileManager.removeItem(atPath: url.path + suffix)
        }
    }
}
