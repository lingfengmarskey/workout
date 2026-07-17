import SwiftData
import XCTest
@testable import Workout

@MainActor
final class CloudRecordMergeServiceTests: XCTestCase {
    func testRemoteNewerPlanUpdatesExistingModel() throws {
        let context = try makeContext()
        let id = UUID()
        let local = makePlan(id: id, name: "本机", updatedAt: Date(timeIntervalSince1970: 100))
        context.insert(local)
        try context.save()

        let remote = makePlan(id: id, name: "云端", updatedAt: Date(timeIntervalSince1970: 200))
        remote.syncRevision = 2
        let summary = try CloudRecordMergeService.apply(
            changedRecords: [CloudRecordCodec.record(for: remote)],
            deletedRecords: [],
            in: context
        )

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<WeightLossPlan>()).first)
        XCTAssertEqual(stored.name, "云端")
        XCTAssertEqual(stored.syncRevision, 2)
        XCTAssertEqual(summary.updated, 1)
    }

    func testOlderRemotePlanDoesNotOverwriteLocalChange() throws {
        let context = try makeContext()
        let id = UUID()
        let local = makePlan(id: id, name: "较新的本机", updatedAt: Date(timeIntervalSince1970: 300))
        context.insert(local)
        try context.save()

        let remote = makePlan(id: id, name: "较旧的云端", updatedAt: Date(timeIntervalSince1970: 200))
        let summary = try CloudRecordMergeService.apply(
            changedRecords: [CloudRecordCodec.record(for: remote)],
            deletedRecords: [],
            in: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightLossPlan>()).first?.name, "较新的本机")
        XCTAssertEqual(summary.ignored, 1)
    }

    func testTombstoneInSameBatchPreventsResurrection() throws {
        let context = try makeContext()
        let plan = makePlan(id: UUID(), name: "将删除", updatedAt: Date(timeIntervalSince1970: 100))
        context.insert(plan)
        try context.save()

        let changedRecord = CloudRecordCodec.record(for: plan)
        let tombstone = SyncTombstone(
            recordName: SyncEntityType.plan.recordName(for: plan.id),
            entityType: .plan,
            deletedAt: Date(timeIntervalSince1970: 200)
        )
        let summary = try CloudRecordMergeService.apply(
            changedRecords: [changedRecord, CloudRecordCodec.record(for: tombstone)],
            deletedRecords: [],
            in: context
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<WeightLossPlan>()).isEmpty)
        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(summary.ignored, 1)
    }

    func testPersistedTombstonePreventsStaleRecordInLaterBatchFromResurrecting() throws {
        let context = try makeContext()
        let id = UUID()
        let recordName = SyncEntityType.plan.recordName(for: id)
        let tombstone = SyncTombstone(
            recordName: recordName,
            entityType: .plan,
            deletedAt: Date(timeIntervalSince1970: 200),
            deviceID: "device-b"
        )

        _ = try CloudRecordMergeService.apply(
            changedRecords: [CloudRecordCodec.record(for: tombstone)],
            deletedRecords: [],
            in: context
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncTombstone>()).count, 1)

        let stalePlan = makePlan(id: id, name: "离线旧记录", updatedAt: Date(timeIntervalSince1970: 150))
        let secondBatch = try CloudRecordMergeService.apply(
            changedRecords: [CloudRecordCodec.record(for: stalePlan)],
            deletedRecords: [],
            in: context
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<WeightLossPlan>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncTombstone>()).count, 1)
        XCTAssertEqual(secondBatch.ignored, 1)
    }

    func testNewerServerEntitySupersedesOlderDeletion() {
        XCTAssertTrue(CloudDeletionConflictResolver.entity(
            updatedAt: Date(timeIntervalSince1970: 300),
            deviceID: "device-a",
            isNewerThanDeletionAt: Date(timeIntervalSince1970: 200),
            deletionDeviceID: "device-z"
        ))
        XCTAssertFalse(CloudDeletionConflictResolver.entity(
            updatedAt: Date(timeIntervalSince1970: 100),
            deviceID: "device-z",
            isNewerThanDeletionAt: Date(timeIntervalSince1970: 200),
            deletionDeviceID: "device-a"
        ))
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: WorkoutSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContext(ModelContainer(for: schema, configurations: [configuration]))
    }

    private func makePlan(id: UUID, name: String, updatedAt: Date) -> WeightLossPlan {
        WeightLossPlan(
            id: id,
            name: name,
            startDate: Date(timeIntervalSince1970: 0),
            durationDays: 56,
            startWeight: 97,
            phaseTargetWeight: 88,
            finalTargetWeight: 80,
            dailyCalorieTarget: 1_900,
            dailyProteinTarget: 140,
            dailyWaterTarget: 2.2,
            updatedAt: updatedAt
        )
    }
}
