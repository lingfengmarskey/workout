import CloudKit
import Foundation

struct CloudZoneChangeBatch {
    let changedRecords: [CKRecord]
    let deletedRecords: [(recordID: CKRecord.ID, recordType: String)]
    let changeToken: CKServerChangeToken?
}

actor CloudKitTransport {
    static let shared = CloudKitTransport()

    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: CloudKitConstants.containerIdentifier)) {
        database = container.privateCloudDatabase
    }

    func fetchZoneChanges(since token: CKServerChangeToken?) async throws -> CloudZoneChangeBatch {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = token
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [CloudKitConstants.zoneID],
                configurationsByRecordZoneID: [CloudKitConstants.zoneID: configuration]
            )
            operation.fetchAllChanges = true
            operation.qualityOfService = .utility

            let accumulator = ZoneChangeAccumulator()
            operation.recordChangedBlock = { record in
                accumulator.addChanged(record)
            }
            operation.recordWithIDWasDeletedBlock = { recordID, recordType in
                accumulator.addDeleted(recordID: recordID, recordType: recordType)
            }
            operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
                accumulator.updateToken(token)
            }
            operation.recordZoneFetchCompletionBlock = { _, token, _, moreComing, error in
                accumulator.finishZone(token: token, moreComing: moreComing, error: error)
            }
            operation.fetchRecordZoneChangesCompletionBlock = { error in
                let snapshot = accumulator.snapshot()
                if let zoneError = snapshot.zoneError {
                    continuation.resume(throwing: zoneError)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if snapshot.moreComing {
                    continuation.resume(throwing: CloudKitTransportError.incompleteZoneFetch)
                } else {
                    continuation.resume(returning: CloudZoneChangeBatch(
                        changedRecords: snapshot.changedRecords,
                        deletedRecords: snapshot.deletedRecords,
                        changeToken: snapshot.changeToken
                    ))
                }
            }
            database.add(operation)
        }
    }
}

final class ZoneChangeAccumulator: @unchecked Sendable {
    struct Snapshot {
        let changedRecords: [CKRecord]
        let deletedRecords: [(recordID: CKRecord.ID, recordType: String)]
        let changeToken: CKServerChangeToken?
        let zoneError: Error?
        let moreComing: Bool
    }

    private let lock = NSLock()
    private var changedRecords: [CKRecord] = []
    private var deletedRecords: [(recordID: CKRecord.ID, recordType: String)] = []
    private var changeToken: CKServerChangeToken?
    private var zoneError: Error?
    private var moreComing = false

    func addChanged(_ record: CKRecord) {
        withLock { changedRecords.append(record) }
    }

    func addDeleted(recordID: CKRecord.ID, recordType: String) {
        withLock { deletedRecords.append((recordID, recordType)) }
    }

    func updateToken(_ token: CKServerChangeToken?) {
        withLock { if let token { changeToken = token } }
    }

    func finishZone(token: CKServerChangeToken?, moreComing: Bool, error: Error?) {
        withLock {
            if let token { changeToken = token }
            self.moreComing = moreComing
            if let error { zoneError = error }
        }
    }

    func snapshot() -> Snapshot {
        withLock {
            Snapshot(
                changedRecords: changedRecords,
                deletedRecords: deletedRecords,
                changeToken: moreComing ? nil : changeToken,
                zoneError: zoneError,
                moreComing: moreComing
            )
        }
    }

    private func withLock<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }
}

enum CloudKitTransportError: LocalizedError {
    case incompleteZoneFetch

    var errorDescription: String? {
        "CloudKit 尚未返回完整变更，已保留上一次同步位置，请稍后重试。"
    }
}

enum CloudChangeTokenStore {
    static func encode(_ token: CKServerChangeToken?) throws -> Data? {
        guard let token else { return nil }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func decode(_ data: Data?) throws -> CKServerChangeToken? {
        guard let data else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
}
