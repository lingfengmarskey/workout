import CloudKit
import Foundation

struct CloudZoneChangeBatch {
    let changedRecords: [CKRecord]
    let deletedRecords: [(recordID: CKRecord.ID, recordType: String)]
    let changeToken: CKServerChangeToken?
}

struct CloudRecordLookupBatch {
    let recordsByID: [CKRecord.ID: CKRecord]
    let errorsByID: [CKRecord.ID: Error]
}

struct CloudModifyBatchResult {
    let savedRecords: [CKRecord.ID: CKRecord]
    let saveErrors: [CKRecord.ID: Error]
    let deletedRecordIDs: Set<CKRecord.ID>
    let deleteErrors: [CKRecord.ID: Error]

    var firstError: Error? {
        saveErrors.values.first ?? deleteErrors.values.first
    }
}

actor CloudKitTransport {
    static let shared = CloudKitTransport()

    // CloudKit rejects a single fetch/modify operation with more than 400 items
    // ("your request contains N items which is more than the maximum ... (400)").
    // Stay well under so large syncs are split into several operations.
    static let maxBatchSize = 200

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

    func fetchRecords(withIDs recordIDs: [CKRecord.ID]) async throws -> CloudRecordLookupBatch {
        guard !recordIDs.isEmpty else {
            return CloudRecordLookupBatch(recordsByID: [:], errorsByID: [:])
        }
        var records: [CKRecord.ID: CKRecord] = [:]
        var errors: [CKRecord.ID: Error] = [:]
        for chunk in recordIDs.chunked(into: Self.maxBatchSize) {
            let results = try await database.records(for: chunk)
            for (id, result) in results {
                switch result {
                case let .success(record): records[id] = record
                case let .failure(error): errors[id] = error
                }
            }
        }
        return CloudRecordLookupBatch(recordsByID: records, errorsByID: errors)
    }

    func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID]
    ) async throws -> CloudModifyBatchResult {
        guard !records.isEmpty || !recordIDs.isEmpty else {
            return CloudModifyBatchResult(savedRecords: [:], saveErrors: [:], deletedRecordIDs: [], deleteErrors: [:])
        }

        var saved: [CKRecord.ID: CKRecord] = [:]
        var saveErrors: [CKRecord.ID: Error] = [:]
        var deleted = Set<CKRecord.ID>()
        var deleteErrors: [CKRecord.ID: Error] = [:]

        // Split into per-operation batches under CloudKit's 400-item limit.
        // atomically:false, so saves and deletes need not share an operation.
        for chunk in records.chunked(into: Self.maxBatchSize) {
            let results = try await database.modifyRecords(
                saving: chunk,
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: false
            )
            for (id, result) in results.saveResults {
                switch result {
                case let .success(record): saved[id] = record
                case let .failure(error): saveErrors[id] = error
                }
            }
        }

        for chunk in recordIDs.chunked(into: Self.maxBatchSize) {
            let results = try await database.modifyRecords(
                saving: [],
                deleting: chunk,
                savePolicy: .ifServerRecordUnchanged,
                atomically: false
            )
            for (id, result) in results.deleteResults {
                switch result {
                case .success: deleted.insert(id)
                case let .failure(error): deleteErrors[id] = error
                }
            }
        }

        return CloudModifyBatchResult(
            savedRecords: saved,
            saveErrors: saveErrors,
            deletedRecordIDs: deleted,
            deleteErrors: deleteErrors
        )
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

extension Array {
    /// Splits the array into sub-arrays of at most `size` elements, preserving
    /// order. Used to keep CloudKit operations under the 400-item limit.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
