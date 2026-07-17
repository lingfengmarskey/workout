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
                accumulator.changedRecords.append(record)
            }
            operation.recordWithIDWasDeletedBlock = { recordID, recordType in
                accumulator.deletedRecords.append((recordID, recordType))
            }
            operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
                accumulator.changeToken = token
            }
            operation.recordZoneFetchCompletionBlock = { _, token, _, _, error in
                if let token { accumulator.changeToken = token }
                if let error { accumulator.zoneError = error }
            }
            operation.fetchRecordZoneChangesCompletionBlock = { error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let zoneError = accumulator.zoneError {
                    continuation.resume(throwing: zoneError)
                } else {
                    continuation.resume(returning: CloudZoneChangeBatch(
                        changedRecords: accumulator.changedRecords,
                        deletedRecords: accumulator.deletedRecords,
                        changeToken: accumulator.changeToken
                    ))
                }
            }
            database.add(operation)
        }
    }
}

private final class ZoneChangeAccumulator: @unchecked Sendable {
    var changedRecords: [CKRecord] = []
    var deletedRecords: [(recordID: CKRecord.ID, recordType: String)] = []
    var changeToken: CKServerChangeToken?
    var zoneError: Error?
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
