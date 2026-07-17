import CloudKit
import CryptoKit
import SwiftData
import UIKit
import XCTest
@testable import Workout

@MainActor
final class CloudPhotoSyncServiceTests: XCTestCase {
    func testPhotoRecordNameIsStablePerBodyAndAngle() {
        let id = UUID()
        XCTAssertEqual(
            CloudPhotoSyncService.recordName(bodyID: id, angle: .front),
            CloudPhotoSyncService.recordName(bodyID: id, angle: .front)
        )
        XCTAssertNotEqual(
            CloudPhotoSyncService.recordName(bodyID: id, angle: .front),
            CloudPhotoSyncService.recordName(bodyID: id, angle: .side)
        )
    }

    func testDownloadedAssetIsValidatedAndInstalledForExpectedBodyHash() throws {
        let context = try makeContext()
        let body = DailyBodyRecord(planID: UUID(), date: .now)
        let data = try XCTUnwrap(UIImage(systemName: "person.fill")?.pngData())
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        body.frontPhotoHash = hash
        context.insert(body)
        try context.save()

        let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-photo-\(UUID().uuidString).png")
        try data.write(to: assetURL)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let record = makePhotoRecord(bodyID: body.id, angle: .front, hash: hash, assetURL: assetURL)

        try CloudPhotoSyncService.applyDownloadedRecords([record], in: context)

        let identifier = try XCTUnwrap(body.frontPhotoPath)
        defer { try? BodyPhotoStore.shared.delete(identifier: identifier) }
        XCTAssertEqual(BodyPhotoStore.shared.contentHash(for: identifier), hash)
    }

    func testHashMismatchPreservesExistingPath() throws {
        let context = try makeContext()
        let body = DailyBodyRecord(planID: UUID(), date: .now)
        body.frontPhotoHash = String(repeating: "0", count: 64)
        body.frontPhotoPath = "existing.jpg"
        context.insert(body)
        try context.save()

        let data = try XCTUnwrap(UIImage(systemName: "person.fill")?.pngData())
        let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-photo-\(UUID().uuidString).png")
        try data.write(to: assetURL)
        defer { try? FileManager.default.removeItem(at: assetURL) }
        let record = makePhotoRecord(
            bodyID: body.id,
            angle: .front,
            hash: String(repeating: "0", count: 64),
            assetURL: assetURL
        )

        XCTAssertThrowsError(try CloudPhotoSyncService.applyDownloadedRecords([record], in: context))
        XCTAssertEqual(body.frontPhotoPath, "existing.jpg")
    }

    func testNewerServerPhotoReplacesLosingLocalHashAndPath() throws {
        let context = try makeContext()
        let body = DailyBodyRecord(planID: UUID(), date: .now)
        body.frontPhotoHash = "old-hash"
        body.frontPhotoPath = "old.jpg"
        context.insert(body)
        context.insert(PhotoSyncMetadata(
            bodyID: body.id,
            angle: .front,
            contentHash: "old-hash",
            updatedAt: Date(timeIntervalSince1970: 100),
            deviceID: "device-a",
            isDeleted: false
        ))
        try context.save()

        let data = try XCTUnwrap(UIImage(systemName: "person.crop.circle.fill")?.pngData())
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-photo-\(UUID().uuidString).png")
        try data.write(to: assetURL)
        defer { try? FileManager.default.removeItem(at: assetURL) }

        try CloudPhotoSyncService.applyDownloadedRecords([
            makePhotoRecord(bodyID: body.id, angle: .front, hash: hash, assetURL: assetURL, updatedAt: Date(timeIntervalSince1970: 200))
        ], in: context)

        let installed = try XCTUnwrap(body.frontPhotoPath)
        defer { try? BodyPhotoStore.shared.delete(identifier: installed) }
        XCTAssertEqual(body.frontPhotoHash, hash)
        XCTAssertEqual(BodyPhotoStore.shared.contentHash(for: installed), hash)
    }

    func testMigratedVersionlessPhotoCannotBorrowNewerBodyClock() throws {
        let context = try makeContext()
        let body = DailyBodyRecord(planID: UUID(), date: .now)
        body.frontPhotoHash = "stale-v2-hash"
        body.frontPhotoPath = "stale-v2.jpg"
        body.updatedAt = Date(timeIntervalSince1970: 300) // unrelated weight/note edit
        context.insert(body)
        try context.save()

        let data = try XCTUnwrap(UIImage(systemName: "person.crop.square.fill")?.pngData())
        let cloudHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-photo-\(UUID().uuidString).png")
        try data.write(to: assetURL)
        defer { try? FileManager.default.removeItem(at: assetURL) }

        try CloudPhotoSyncService.applyDownloadedRecords([
            makePhotoRecord(
                bodyID: body.id, angle: .front, hash: cloudHash,
                assetURL: assetURL, updatedAt: Date(timeIntervalSince1970: 200)
            )
        ], in: context)

        let installed = try XCTUnwrap(body.frontPhotoPath)
        defer { try? BodyPhotoStore.shared.delete(identifier: installed) }
        XCTAssertEqual(body.frontPhotoHash, cloudHash)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PhotoSyncMetadata>()).first?.updatedAt, Date(timeIntervalSince1970: 200))
    }

    func testNewerServerDeletionClearsPathHashAndProtectedFile() throws {
        let context = try makeContext()
        let data = try XCTUnwrap(UIImage(systemName: "person.fill")?.pngData())
        let identifier = try BodyPhotoStore.shared.save(imageData: data)
        let hash = try XCTUnwrap(BodyPhotoStore.shared.contentHash(for: identifier))
        let body = DailyBodyRecord(planID: UUID(), date: .now)
        body.frontPhotoPath = identifier
        body.frontPhotoHash = hash
        context.insert(body)
        context.insert(PhotoSyncMetadata(
            bodyID: body.id,
            angle: .front,
            contentHash: hash,
            updatedAt: Date(timeIntervalSince1970: 100),
            deviceID: "device-a",
            isDeleted: false
        ))
        try context.save()

        let deletion = makePhotoRecord(
            bodyID: body.id,
            angle: .front,
            hash: nil,
            assetURL: nil,
            updatedAt: Date(timeIntervalSince1970: 200),
            isDeleted: true
        )
        try CloudPhotoSyncService.applyDownloadedRecords([deletion], in: context)

        XCTAssertNil(body.frontPhotoPath)
        XCTAssertNil(body.frontPhotoHash)
        XCTAssertNil(BodyPhotoStore.shared.contentHash(for: identifier))
    }

    func testUnrelatedBodyEditDoesNotAdvancePhotoMutationVersion() throws {
        let context = try makeContext()
        let body = DailyBodyRecord(planID: UUID(), date: .now)
        context.insert(body)
        let photoDate = Date(timeIntervalSince1970: 100)
        try CloudPhotoSyncService.stageLocalMutation(
            bodyID: body.id,
            angle: .front,
            contentHash: "photo-hash",
            at: photoDate,
            in: context
        )
        body.actualWeight = 90
        body.updatedAt = Date(timeIntervalSince1970: 200)
        try context.save()

        let metadata = try XCTUnwrap(context.fetch(FetchDescriptor<PhotoSyncMetadata>()).first)
        XCTAssertEqual(metadata.updatedAt, photoDate)
        XCTAssertEqual(metadata.contentHash, "photo-hash")
    }

    func testDeletingWholeBodyStagesAllAngleDeletionMarkers() throws {
        let context = try makeContext()
        let plan = WeightLossPlan(
            name: "删除测试", startDate: .now, durationDays: 7,
            startWeight: 90, phaseTargetWeight: 88, finalTargetWeight: 80,
            dailyCalorieTarget: 1_900, dailyProteinTarget: 140, dailyWaterTarget: 2.2
        )
        let body = DailyBodyRecord(planID: plan.id, date: .now)
        context.insert(plan)
        context.insert(body)
        try context.save()

        try SyncDeletionService.deletePlanGraph(
            plan: plan,
            bodyRecords: [body],
            mealPlans: [],
            workoutPlans: [],
            from: context
        )
        try context.save()

        let markers = try context.fetch(FetchDescriptor<PhotoSyncMetadata>())
        XCTAssertEqual(Set(markers.map(\.angleRaw)), Set(CloudPhotoAngle.allCases.map(\.rawValue)))
        XCTAssertTrue(markers.allSatisfy(\.isDeleted))
    }

    private func makePhotoRecord(
        bodyID: UUID,
        angle: CloudPhotoAngle,
        hash: String?,
        assetURL: URL?,
        updatedAt: Date = .now,
        isDeleted: Bool = false
    ) -> CKRecord {
        let id = CKRecord.ID(
            recordName: CloudPhotoSyncService.recordName(bodyID: bodyID, angle: angle),
            zoneID: CloudKitConstants.zoneID
        )
        let record = CKRecord(recordType: CloudRecordType.photo.rawValue, recordID: id)
        record["bodyID"] = bodyID.uuidString.lowercased() as CKRecordValue
        record["angle"] = angle.rawValue as CKRecordValue
        record["contentHash"] = hash as CKRecordValue?
        record["updatedAt"] = updatedAt as CKRecordValue
        record["deviceID"] = "test-device" as CKRecordValue
        record["isDeleted"] = NSNumber(value: isDeleted)
        if let assetURL { record["asset"] = CKAsset(fileURL: assetURL) }
        return record
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: WorkoutSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContext(ModelContainer(for: schema, configurations: [configuration]))
    }
}
