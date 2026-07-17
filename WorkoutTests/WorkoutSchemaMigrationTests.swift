import SwiftData
import XCTest
@testable import Workout

final class WorkoutSchemaMigrationTests: XCTestCase {
    func testMigratesV2StoreToV3AndAddsPhotoMetadataTable() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-v3-migration-\(UUID().uuidString).store")
        defer { removeStoreFiles(at: storeURL) }

        let planID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: WorkoutSchemaV2.self)
            let configuration = ModelConfiguration("V3MigrationTest", schema: schema, url: storeURL)
            let context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
            context.insert(WorkoutSchemaV2.WeightLossPlan(
                id: planID, name: "V2 计划", startDate: .now, durationDays: 7,
                startWeight: 90, phaseTargetWeight: 88, finalTargetWeight: 80,
                dailyCalorieTarget: 1_900, dailyProteinTarget: 140, dailyWaterTarget: 2.2
            ))
            try context.save()
        }

        let schema = Schema(versionedSchema: WorkoutSchemaV3.self)
        let configuration = ModelConfiguration("V3MigrationTest", schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: WorkoutMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSchemaV2.WeightLossPlan>()).first?.id, planID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSchemaV3.PhotoSyncMetadata>()).isEmpty)
    }

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
            let body = WorkoutSchemaV1.DailyBodyRecord(planID: planID, date: .now)
            body.actualWeight = 94.6
            body.waist = 101.2
            body.frontPhotoPath = "existing-front.jpg"
            body.note = "迁移后应保留"
            context.insert(body)
            let meal = WorkoutSchemaV1.DailyMealPlan(
                planID: planID,
                date: .now,
                breakfast: "早餐",
                lunch: "午餐",
                dinner: "晚餐",
                snack: "加餐",
                plannedCalories: 1_900,
                plannedProtein: 140,
                waterTarget: 2.2
            )
            meal.breakfastStatus = .completed
            meal.actualWater = 1.8
            context.insert(meal)
            let workout = WorkoutSchemaV1.DailyWorkoutPlan(
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
            )
            workout.status = .partial
            workout.actualSteps = 7_654
            context.insert(workout)
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
        XCTAssertEqual(bodies.first?.actualWeight, 94.6)
        XCTAssertEqual(bodies.first?.waist, 101.2)
        XCTAssertEqual(bodies.first?.frontPhotoPath, "existing-front.jpg")
        XCTAssertEqual(bodies.first?.note, "迁移后应保留")
        XCTAssertEqual(meals.first?.syncRevision, 0)
        XCTAssertEqual(meals.first?.breakfastStatus, .completed)
        XCTAssertEqual(meals.first?.actualWater, 1.8)
        XCTAssertEqual(workouts.first?.status, .partial)
        XCTAssertEqual(workouts.first?.actualSteps, 7_654)
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
