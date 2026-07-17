import CloudKit
import Foundation
import SwiftData

enum CloudPhotoAngle: String, CaseIterable { case front, side, back }

struct CloudPhotoPayload {
    let bodyID: UUID
    let angle: CloudPhotoAngle
    let contentHash: String?
    let updatedAt: Date
    let deviceID: String
    let isDeleted: Bool
    let assetURL: URL?

    init(record: CKRecord) throws {
        guard record.recordType == CloudRecordType.photo.rawValue,
              let bodyString = record["bodyID"] as? String,
              let bodyID = UUID(uuidString: bodyString),
              let angleString = record["angle"] as? String,
              let angle = CloudPhotoAngle(rawValue: angleString),
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudRecordPayloadError.missingField("WLPhoto metadata", record.recordID.recordName)
        }
        self.bodyID = bodyID
        self.angle = angle
        self.contentHash = record["contentHash"] as? String
        self.updatedAt = updatedAt
        self.deviceID = record["deviceID"] as? String ?? ""
        self.isDeleted = (record["isDeleted"] as? NSNumber)?.boolValue ?? false
        self.assetURL = (record["asset"] as? CKAsset)?.fileURL
        if !isDeleted && (contentHash == nil || assetURL == nil) {
            throw CloudRecordPayloadError.missingField("contentHash/asset", record.recordID.recordName)
        }
    }
}

@MainActor
enum CloudPhotoSyncService {
    private struct Candidate {
        let body: DailyBodyRecord
        let metadata: PhotoSyncMetadata
        let identifier: String?
        @MainActor var recordID: CKRecord.ID {
            CKRecord.ID(recordName: recordName(bodyID: body.id, angle: metadata.angle), zoneID: CloudKitConstants.zoneID)
        }
    }

    static func applyDownloadedRecords(_ records: [CKRecord], in context: ModelContext) throws {
        let bodies = try context.fetch(FetchDescriptor<DailyBodyRecord>())
        var metadata = try context.fetch(FetchDescriptor<PhotoSyncMetadata>())
        for record in records {
            let payload = try CloudPhotoPayload(record: record)
            guard let body = bodies.first(where: { $0.id == payload.bodyID }) else { continue }
            let id = PhotoSyncMetadata.identifier(bodyID: body.id, angle: payload.angle)
            let local = metadata.first(where: { $0.id == id }) ?? inferredMetadata(body: body, angle: payload.angle, context: context)
            if !remoteWins(payload, over: local) { continue }

            let oldIdentifier = identifier(for: payload.angle, body: body)
            let oldHash = expectedHash(for: payload.angle, body: body)
            var newIdentifier: String?
            if !payload.isDeleted {
                guard let assetURL = payload.assetURL, let hash = payload.contentHash else {
                    throw CloudPhotoSyncError.missingAsset
                }
                newIdentifier = try BodyPhotoStore.shared.installDownloadedAsset(from: assetURL, expectedHash: hash)
            }
            setPhoto(identifier: newIdentifier, hash: payload.isDeleted ? nil : payload.contentHash, angle: payload.angle, body: body)
            local.contentHash = payload.contentHash
            local.updatedAt = payload.updatedAt
            local.deviceID = payload.deviceID
            local.isDeleted = payload.isDeleted
            do {
                try context.save()
            } catch {
                setPhoto(identifier: oldIdentifier, hash: oldHash, angle: payload.angle, body: body)
                try? BodyPhotoStore.shared.delete(identifier: newIdentifier)
                throw error
            }
            if oldIdentifier != newIdentifier { try? BodyPhotoStore.shared.delete(identifier: oldIdentifier) }
            if !metadata.contains(where: { $0.id == id }) { metadata.append(local) }
        }
    }

    static func uploadLocalPhotos(changedSince lastSync: Date?, state: CloudSyncState, context: ModelContext) async throws {
        let cutoff = lastSync ?? .distantPast
        let bodies = try context.fetch(FetchDescriptor<DailyBodyRecord>()).filter { $0.updatedAt > cutoff }
        let allIDs = bodies.flatMap { body in CloudPhotoAngle.allCases.map { recordID(bodyID: body.id, angle: $0) } }
        let lookup = try await CloudKitTransport.shared.fetchRecords(withIDs: allIDs)
        if let error = lookup.errorsByID.values.first(where: { ($0 as? CKError)?.code != .unknownItem }) { throw error }

        var candidates: [Candidate] = []
        var metadata = try context.fetch(FetchDescriptor<PhotoSyncMetadata>())
        for body in bodies {
            for angle in CloudPhotoAngle.allCases {
                let id = PhotoSyncMetadata.identifier(bodyID: body.id, angle: angle)
                let hash = expectedHash(for: angle, body: body)
                let serverExists = lookup.recordsByID[recordID(bodyID: body.id, angle: angle)] != nil
                guard hash != nil || serverExists || metadata.contains(where: { $0.id == id }) else { continue }
                let item = metadata.first(where: { $0.id == id }) ?? {
                    let created = PhotoSyncMetadata(bodyID: body.id, angle: angle, contentHash: hash, updatedAt: body.updatedAt, isDeleted: hash == nil)
                    context.insert(created); metadata.append(created); return created
                }()
                if item.contentHash != hash || item.isDeleted != (hash == nil) {
                    item.contentHash = hash
                    item.isDeleted = hash == nil
                    item.updatedAt = body.updatedAt
                    item.deviceID = SyncDeviceIdentity.current
                }
                candidates.append(Candidate(body: body, metadata: item, identifier: identifier(for: angle, body: body)))
            }
        }
        state.pendingPhotoCount = candidates.count
        try context.save()

        var recordsToSave: [CKRecord] = []
        for candidate in candidates {
            if let server = lookup.recordsByID[candidate.recordID] {
                let remote = try CloudPhotoPayload(record: server)
                if sameVersion(candidate.metadata, remote) { continue }
                if remoteWins(remote, over: candidate.metadata) {
                    try applyDownloadedRecords([server], in: context)
                    continue
                }
                recordsToSave.append(try record(for: candidate, rebasing: server))
            } else {
                recordsToSave.append(try record(for: candidate, rebasing: nil))
            }
        }

        let result = try await CloudKitTransport.shared.modifyRecords(saving: recordsToSave, deleting: [])
        for error in result.saveErrors.values { throw error }
        state.pendingPhotoCount = 0
        try context.save()
    }

    static func recordName(bodyID: UUID, angle: CloudPhotoAngle) -> String {
        "wlphoto-\(bodyID.uuidString.lowercased())-\(angle.rawValue)"
    }

    private static func recordID(bodyID: UUID, angle: CloudPhotoAngle) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName(bodyID: bodyID, angle: angle), zoneID: CloudKitConstants.zoneID)
    }

    private static func record(for candidate: Candidate, rebasing existing: CKRecord?) throws -> CKRecord {
        let record = existing ?? CKRecord(recordType: CloudRecordType.photo.rawValue, recordID: candidate.recordID)
        record["schemaVersion"] = NSNumber(value: CloudRecordCodec.schemaVersion)
        record["bodyID"] = candidate.body.id.uuidString.lowercased() as CKRecordValue
        record["angle"] = candidate.metadata.angle.rawValue as CKRecordValue
        record["contentHash"] = candidate.metadata.contentHash as CKRecordValue?
        record["updatedAt"] = candidate.metadata.updatedAt as CKRecordValue
        record["deviceID"] = candidate.metadata.deviceID as CKRecordValue
        record["isDeleted"] = NSNumber(value: candidate.metadata.isDeleted)
        if candidate.metadata.isDeleted {
            record["asset"] = nil
        } else {
            guard let identifier = candidate.identifier,
                  BodyPhotoStore.shared.contentHash(for: identifier) == candidate.metadata.contentHash else {
                throw CloudPhotoSyncError.localHashMismatch
            }
            record["asset"] = CKAsset(fileURL: try BodyPhotoStore.shared.fileURL(for: identifier))
        }
        return record
    }

    private static func inferredMetadata(body: DailyBodyRecord, angle: CloudPhotoAngle, context: ModelContext) -> PhotoSyncMetadata {
        let hash = expectedHash(for: angle, body: body)
        // With no local photo there is no local deletion intent to compete
        // with an authoritative WLPhoto arriving during first sync.
        let inferredDate = hash == nil ? Date.distantPast : body.updatedAt
        let item = PhotoSyncMetadata(bodyID: body.id, angle: angle, contentHash: hash, updatedAt: inferredDate, isDeleted: hash == nil)
        context.insert(item)
        return item
    }

    private static func remoteWins(_ remote: CloudPhotoPayload, over local: PhotoSyncMetadata) -> Bool {
        remote.updatedAt > local.updatedAt || (remote.updatedAt == local.updatedAt && remote.deviceID > local.deviceID)
    }

    private static func sameVersion(_ local: PhotoSyncMetadata, _ remote: CloudPhotoPayload) -> Bool {
        local.updatedAt == remote.updatedAt && local.deviceID == remote.deviceID && local.contentHash == remote.contentHash && local.isDeleted == remote.isDeleted
    }

    private static func identifier(for angle: CloudPhotoAngle, body: DailyBodyRecord) -> String? {
        switch angle { case .front: body.frontPhotoPath; case .side: body.sidePhotoPath; case .back: body.backPhotoPath }
    }
    private static func expectedHash(for angle: CloudPhotoAngle, body: DailyBodyRecord) -> String? {
        switch angle { case .front: body.frontPhotoHash; case .side: body.sidePhotoHash; case .back: body.backPhotoHash }
    }
    private static func setPhoto(identifier: String?, hash: String?, angle: CloudPhotoAngle, body: DailyBodyRecord) {
        switch angle {
        case .front: body.frontPhotoPath = identifier; body.frontPhotoHash = hash
        case .side: body.sidePhotoPath = identifier; body.sidePhotoHash = hash
        case .back: body.backPhotoPath = identifier; body.backPhotoHash = hash
        }
    }
}

enum CloudPhotoSyncError: LocalizedError {
    case localHashMismatch
    case missingAsset
    var errorDescription: String? {
        switch self {
        case .localHashMismatch: "本机照片内容已变化，已暂停上传并等待重新校验。"
        case .missingAsset: "iCloud 照片文件暂不可用，已保留本机照片。"
        }
    }
}
