import CloudKit
import Foundation
import SwiftData

enum CloudPhotoAngle: String, CaseIterable {
    case front
    case side
    case back
}

struct CloudPhotoPayload {
    let bodyID: UUID
    let angle: CloudPhotoAngle
    let contentHash: String
    let updatedAt: Date
    let deviceID: String
    let assetURL: URL

    init(record: CKRecord) throws {
        guard record.recordType == CloudRecordType.photo.rawValue,
              let bodyString = record["bodyID"] as? String,
              let bodyID = UUID(uuidString: bodyString),
              let angleString = record["angle"] as? String,
              let angle = CloudPhotoAngle(rawValue: angleString),
              let contentHash = record["contentHash"] as? String,
              let updatedAt = record["updatedAt"] as? Date,
              let asset = record["asset"] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw CloudRecordPayloadError.missingField("WLPhoto", record.recordID.recordName)
        }
        self.bodyID = bodyID
        self.angle = angle
        self.contentHash = contentHash
        self.updatedAt = updatedAt
        self.deviceID = record["deviceID"] as? String ?? ""
        self.assetURL = assetURL
    }
}

@MainActor
enum CloudPhotoSyncService {
    private struct Candidate {
        let body: DailyBodyRecord
        let angle: CloudPhotoAngle
        let identifier: String
        let contentHash: String

        @MainActor var recordID: CKRecord.ID {
            CKRecord.ID(recordName: recordName(bodyID: body.id, angle: angle), zoneID: CloudKitConstants.zoneID)
        }
    }

    static func applyDownloadedRecords(_ records: [CKRecord], in context: ModelContext) throws {
        guard !records.isEmpty else { return }
        let bodies = try context.fetch(FetchDescriptor<DailyBodyRecord>())
        for record in records {
            let payload = try CloudPhotoPayload(record: record)
            guard let body = bodies.first(where: { $0.id == payload.bodyID }),
                  expectedHash(for: payload.angle, body: body) == payload.contentHash else {
                continue
            }
            let oldIdentifier = identifier(for: payload.angle, body: body)
            if BodyPhotoStore.shared.contentHash(for: oldIdentifier) == payload.contentHash { continue }

            let newIdentifier = try BodyPhotoStore.shared.installDownloadedAsset(
                from: payload.assetURL,
                expectedHash: payload.contentHash
            )
            setIdentifier(newIdentifier, angle: payload.angle, body: body)
            do {
                try context.save()
            } catch {
                setIdentifier(oldIdentifier, angle: payload.angle, body: body)
                try? BodyPhotoStore.shared.delete(identifier: newIdentifier)
                throw error
            }
            if oldIdentifier != newIdentifier {
                try? BodyPhotoStore.shared.delete(identifier: oldIdentifier)
            }
        }
    }

    static func uploadLocalPhotos(
        changedSince lastSuccessfulSyncAt: Date?,
        state: CloudSyncState,
        context: ModelContext
    ) async throws {
        let cutoff = lastSuccessfulSyncAt ?? .distantPast
        let bodies = try context.fetch(FetchDescriptor<DailyBodyRecord>()).filter { $0.updatedAt > cutoff }
        let candidates = bodies.flatMap(candidates(for:))
        state.pendingPhotoCount = candidates.count
        try context.save()
        guard !candidates.isEmpty else { return }

        let lookup = try await CloudKitTransport.shared.fetchRecords(withIDs: candidates.map(\.recordID))
        let fatalErrors = lookup.errorsByID.values.filter { ($0 as? CKError)?.code != .unknownItem }
        if let error = fatalErrors.first { throw error }

        var recordsToSave: [CKRecord] = []
        for candidate in candidates {
            let server = lookup.recordsByID[candidate.recordID]
            if let server {
                let payload = try CloudPhotoPayload(record: server)
                if payload.contentHash == candidate.contentHash { continue }
                let localWins = candidate.body.updatedAt > payload.updatedAt || (
                    candidate.body.updatedAt == payload.updatedAt && SyncDeviceIdentity.current > payload.deviceID
                )
                if !localWins {
                    try applyDownloadedRecords([server], in: context)
                    continue
                }
            }
            recordsToSave.append(try record(for: candidate, rebasing: server))
        }

        let result = try await CloudKitTransport.shared.modifyRecords(saving: recordsToSave, deleting: [])
        var retry: [CKRecord] = []
        for (id, error) in result.saveErrors {
            guard let ckError = error as? CKError,
                  ckError.code == .serverRecordChanged,
                  let local = recordsToSave.first(where: { $0.recordID == id }),
                  let server = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                throw error
            }
            let serverPayload = try CloudPhotoPayload(record: server)
            let localDate = local["updatedAt"] as? Date ?? .distantPast
            let localDevice = local["deviceID"] as? String ?? ""
            if localDate > serverPayload.updatedAt || (localDate == serverPayload.updatedAt && localDevice > serverPayload.deviceID) {
                retry.append(CloudRecordCodec.rebasing(local, onto: server))
            } else {
                try applyDownloadedRecords([server], in: context)
            }
        }
        if !retry.isEmpty {
            let retryResult = try await CloudKitTransport.shared.modifyRecords(saving: retry, deleting: [])
            if let error = retryResult.firstError { throw error }
        }
        state.pendingPhotoCount = 0
        try context.save()
    }

    static func recordName(bodyID: UUID, angle: CloudPhotoAngle) -> String {
        "wlphoto-\(bodyID.uuidString.lowercased())-\(angle.rawValue)"
    }

    private static func record(for candidate: Candidate, rebasing existing: CKRecord?) throws -> CKRecord {
        guard BodyPhotoStore.shared.contentHash(for: candidate.identifier) == candidate.contentHash else {
            throw CloudPhotoSyncError.localHashMismatch
        }
        let record: CKRecord
        if let existing { record = existing }
        else { record = CKRecord(recordType: CloudRecordType.photo.rawValue, recordID: candidate.recordID) }
        record["schemaVersion"] = NSNumber(value: CloudRecordCodec.schemaVersion)
        record["bodyID"] = candidate.body.id.uuidString.lowercased() as CKRecordValue
        record["angle"] = candidate.angle.rawValue as CKRecordValue
        record["contentHash"] = candidate.contentHash as CKRecordValue
        record["updatedAt"] = candidate.body.updatedAt as CKRecordValue
        record["deviceID"] = SyncDeviceIdentity.current as CKRecordValue
        record["asset"] = CKAsset(fileURL: try BodyPhotoStore.shared.fileURL(for: candidate.identifier))
        return record
    }

    private static func candidates(for body: DailyBodyRecord) -> [Candidate] {
        CloudPhotoAngle.allCases.compactMap { angle in
            guard let identifier = identifier(for: angle, body: body),
                  let hash = expectedHash(for: angle, body: body) else { return nil }
            return Candidate(body: body, angle: angle, identifier: identifier, contentHash: hash)
        }
    }

    private static func identifier(for angle: CloudPhotoAngle, body: DailyBodyRecord) -> String? {
        switch angle {
        case .front: body.frontPhotoPath
        case .side: body.sidePhotoPath
        case .back: body.backPhotoPath
        }
    }

    private static func expectedHash(for angle: CloudPhotoAngle, body: DailyBodyRecord) -> String? {
        switch angle {
        case .front: body.frontPhotoHash
        case .side: body.sidePhotoHash
        case .back: body.backPhotoHash
        }
    }

    private static func setIdentifier(_ identifier: String?, angle: CloudPhotoAngle, body: DailyBodyRecord) {
        switch angle {
        case .front: body.frontPhotoPath = identifier
        case .side: body.sidePhotoPath = identifier
        case .back: body.backPhotoPath = identifier
        }
    }
}

enum CloudPhotoSyncError: LocalizedError {
    case localHashMismatch

    var errorDescription: String? {
        "本机照片内容已变化，已暂停上传并等待重新校验。"
    }
}
