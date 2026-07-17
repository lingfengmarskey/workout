import CloudKit
import XCTest
@testable import Workout

final class CloudRecordCodecTests: XCTestCase {
    func testPlanRecordUsesStableIdentityAndRoundTripsCommonMetadata() throws {
        let id = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = WeightLossPlan(
            id: id,
            name: "同步测试",
            startDate: updatedAt,
            durationDays: 56,
            startWeight: 97,
            phaseTargetWeight: 88.5,
            finalTargetWeight: 80,
            dailyCalorieTarget: 1_900,
            dailyProteinTarget: 140,
            dailyWaterTarget: 2.2,
            updatedAt: updatedAt
        )
        plan.syncRevision = 7

        let first = CloudRecordCodec.record(for: plan)
        let second = CloudRecordCodec.record(for: plan)
        let identity = try CloudRecordCodec.identity(from: first)

        XCTAssertEqual(first.recordType, CloudRecordType.plan.rawValue)
        XCTAssertEqual(first.recordID, second.recordID)
        XCTAssertEqual(first.recordID.zoneID, CloudKitConstants.zoneID)
        XCTAssertEqual(first["name"] as? String, "同步测试")
        XCTAssertEqual(identity, CloudRecordIdentity(id: id, updatedAt: updatedAt, syncRevision: 7))
    }

    func testBodyRecordDoesNotUploadLocalPhotoPaths() {
        let body = DailyBodyRecord(planID: UUID(), date: .now)
        body.frontPhotoPath = "private-local-filename.jpg"
        body.frontPhotoHash = "abc123"

        let record = CloudRecordCodec.record(for: body)

        XCTAssertNil(record["frontPhotoPath"])
        XCTAssertEqual(record["frontPhotoHash"] as? String, "abc123")
    }

    func testTombstoneRecordNameIsStable() {
        let tombstone = SyncTombstone(recordName: "bodyrecord-deadbeef", entityType: .bodyRecord)
        let first = CloudRecordCodec.record(for: tombstone)
        let second = CloudRecordCodec.record(for: tombstone)

        XCTAssertEqual(first.recordID, second.recordID)
        XCTAssertEqual(first.recordType, CloudRecordType.tombstone.rawValue)
        XCTAssertEqual(first["recordName"] as? String, tombstone.recordName)
    }

    func testEveryTombstoneTargetsTheStructuredRecordName() {
        let id = UUID()
        let mappings: [(SyncEntityType, CloudRecordType)] = [
            (.plan, .plan),
            (.bodyRecord, .body),
            (.mealPlan, .meal),
            (.workoutPlan, .workout)
        ]

        for (entityType, recordType) in mappings {
            XCTAssertEqual(
                entityType.recordName(for: id),
                CloudRecordCodec.recordName(type: recordType, id: id)
            )
        }
    }
}
