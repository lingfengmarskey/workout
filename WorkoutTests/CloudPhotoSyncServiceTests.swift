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

    private func makePhotoRecord(bodyID: UUID, angle: CloudPhotoAngle, hash: String, assetURL: URL) -> CKRecord {
        let id = CKRecord.ID(
            recordName: CloudPhotoSyncService.recordName(bodyID: bodyID, angle: angle),
            zoneID: CloudKitConstants.zoneID
        )
        let record = CKRecord(recordType: CloudRecordType.photo.rawValue, recordID: id)
        record["bodyID"] = bodyID.uuidString.lowercased() as CKRecordValue
        record["angle"] = angle.rawValue as CKRecordValue
        record["contentHash"] = hash as CKRecordValue
        record["updatedAt"] = Date.now as CKRecordValue
        record["deviceID"] = "test-device" as CKRecordValue
        record["asset"] = CKAsset(fileURL: assetURL)
        return record
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: WorkoutSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContext(ModelContainer(for: schema, configurations: [configuration]))
    }
}
