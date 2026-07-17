import CloudKit
import Foundation
import SwiftData

@MainActor
final class CloudSyncEngine {
    static let shared = CloudSyncEngine()

    private(set) var isSyncing = false

    private init() {}

    func enableAndSynchronize(in context: ModelContext) async throws {
        let state = try syncState(in: context)
        state.phase = .initialSync
        state.lastErrorSummary = nil
        try context.save()

        do {
            try await CloudKitInfrastructureService.shared.preparePrivateZone()
            try await synchronize(in: context)
        } catch {
            state.phase = .needsAttention
            state.lastErrorSummary = error.localizedDescription
            try? context.save()
            throw error
        }
    }

    func synchronize(in context: ModelContext) async throws {
        guard !isSyncing else { return }
        let state = try syncState(in: context)
        guard state.phase != .disabled, state.phase != .paused else { return }

        isSyncing = true
        defer { isSyncing = false }
        let syncStartedAt = Date.now
        state.lastAttemptAt = syncStartedAt
        state.lastErrorSummary = nil
        try context.save()

        do {
            let batch = try await fetchChangesRecoveringExpiredToken(state: state, context: context)
            let photoRecords = batch.changedRecords.filter { $0.recordType == CloudRecordType.photo.rawValue }
            let structuredRecords = batch.changedRecords.filter { $0.recordType != CloudRecordType.photo.rawValue }
            _ = try CloudRecordMergeService.apply(
                changedRecords: structuredRecords,
                deletedRecords: batch.deletedRecords,
                in: context
            )
            try CloudPhotoSyncService.applyDownloadedRecords(photoRecords, in: context)

            // Persist the token only after the corresponding changes have been
            // committed locally. A crash before this point safely replays them.
            state.zoneChangeTokenData = try CloudChangeTokenStore.encode(batch.changeToken)
            try context.save()

            try await uploadLocalChanges(
                changedSince: state.lastSuccessfulSyncAt,
                state: state,
                context: context
            )
            try await CloudPhotoSyncService.uploadLocalPhotos(
                changedSince: state.lastSuccessfulSyncAt,
                state: state,
                context: context
            )

            state.lastSuccessfulSyncAt = syncStartedAt
            state.lastErrorSummary = nil
            state.phase = .ready
            state.pendingRecordCount = 0
            state.pendingPhotoCount = 0
            try context.save()
        } catch {
            state.phase = .needsAttention
            state.lastErrorSummary = error.localizedDescription
            try? context.save()
            throw error
        }
    }

    func stopThisDevice(in context: ModelContext) throws {
        let state = try syncState(in: context)
        state.phase = .disabled
        state.zoneChangeTokenData = nil
        state.pendingRecordCount = 0
        state.pendingPhotoCount = 0
        state.lastErrorSummary = nil
        try context.save()
    }

    func deleteCloudDataKeepingLocal(in context: ModelContext) async throws {
        try await CloudKitInfrastructureService.shared.deletePrivateZone()
        try stopThisDevice(in: context)
    }

    func syncState(in context: ModelContext) throws -> CloudSyncState {
        if let existing = try context.fetch(FetchDescriptor<CloudSyncState>()).first(where: { $0.id == "primary" }) {
            return existing
        }
        let state = CloudSyncState()
        context.insert(state)
        try context.save()
        return state
    }

    private func uploadLocalChanges(
        changedSince lastSuccessfulSyncAt: Date?,
        state: CloudSyncState,
        context: ModelContext
    ) async throws {
        let cutoff = lastSuccessfulSyncAt ?? .distantPast
        let plans = try context.fetch(FetchDescriptor<WeightLossPlan>()).filter { $0.updatedAt > cutoff }
        let bodies = try context.fetch(FetchDescriptor<DailyBodyRecord>()).filter { $0.updatedAt > cutoff }
        let meals = try context.fetch(FetchDescriptor<DailyMealPlan>()).filter { $0.updatedAt > cutoff }
        let workouts = try context.fetch(FetchDescriptor<DailyWorkoutPlan>()).filter { $0.updatedAt > cutoff }
        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>()).filter { !$0.isUploaded }

        var structuredRecords = plans.map { CloudRecordCodec.record(for: $0) }
        structuredRecords += bodies.map { CloudRecordCodec.record(for: $0) }
        structuredRecords += meals.map { CloudRecordCodec.record(for: $0) }
        structuredRecords += workouts.map { CloudRecordCodec.record(for: $0) }
        let tombstoneRecords = tombstones.map { CloudRecordCodec.record(for: $0) }
        let targetIDs = tombstones.map { CKRecord.ID(recordName: $0.recordName, zoneID: CloudKitConstants.zoneID) }
        let lookupIDs = structuredRecords.map { $0.recordID } + tombstoneRecords.map { $0.recordID } + targetIDs
        state.pendingRecordCount = structuredRecords.count + tombstones.count
        try context.save()

        guard !lookupIDs.isEmpty else { return }

        let lookup = try await CloudKitTransport.shared.fetchRecords(withIDs: lookupIDs)
        let fatalLookupErrors = lookup.errorsByID.values.filter { !Self.isUnknownItem($0) }
        if let error = fatalLookupErrors.first { throw error }

        var recordsToSave: [CKRecord] = []
        var remoteRecordsToApply: [CKRecord] = []
        for local in structuredRecords {
            guard let server = lookup.recordsByID[local.recordID] else {
                recordsToSave.append(local)
                continue
            }
            let localIdentity = try CloudPayloadIdentity(record: local)
            let serverIdentity = try CloudPayloadIdentity(record: server)
            if localIdentity.updatedAt == serverIdentity.updatedAt,
               localIdentity.syncRevision == serverIdentity.syncRevision,
               localIdentity.deviceID == serverIdentity.deviceID {
                continue
            }
            if Self.prefersLocal(localIdentity, over: serverIdentity) {
                recordsToSave.append(CloudRecordCodec.rebasing(local, onto: server))
            } else {
                remoteRecordsToApply.append(server)
            }
        }

        var activeTombstones: [SyncTombstone] = []
        var tombstoneRecordAlreadyExists = Set<CKRecord.ID>()
        for (tombstone, localRecord) in zip(tombstones, tombstoneRecords) {
            let targetID = CKRecord.ID(recordName: tombstone.recordName, zoneID: CloudKitConstants.zoneID)
            if let serverTarget = lookup.recordsByID[targetID] {
                let targetIdentity = try CloudPayloadIdentity(record: serverTarget)
                if CloudDeletionConflictResolver.entity(
                    updatedAt: targetIdentity.updatedAt,
                    deviceID: targetIdentity.deviceID,
                    isNewerThanDeletionAt: tombstone.deletedAt,
                    deletionDeviceID: tombstone.deviceID
                ) {
                    remoteRecordsToApply.append(serverTarget)
                    context.delete(tombstone)
                    continue
                }
            }

            activeTombstones.append(tombstone)
            if let serverTombstone = lookup.recordsByID[localRecord.recordID] {
                tombstoneRecordAlreadyExists.insert(localRecord.recordID)
                let serverPayload: CloudTombstonePayload
                if case let .tombstone(payload) = try CloudRecordPayload.decode(serverTombstone) {
                    serverPayload = payload
                } else {
                    throw CloudRecordPayloadError.unsupportedRecordType(serverTombstone.recordType)
                }
                let localWins = tombstone.deletedAt > serverPayload.deletedAt || (
                    tombstone.deletedAt == serverPayload.deletedAt && tombstone.deviceID > serverPayload.deviceID
                )
                if localWins {
                    recordsToSave.append(CloudRecordCodec.rebasing(localRecord, onto: serverTombstone))
                } else {
                    tombstone.deletedAt = serverPayload.deletedAt
                    tombstone.deviceID = serverPayload.deviceID
                }
            } else {
                recordsToSave.append(localRecord)
            }
        }

        try context.save()

        if !remoteRecordsToApply.isEmpty {
            _ = try CloudRecordMergeService.apply(changedRecords: remoteRecordsToApply, deletedRecords: [], in: context)
        }

        let result = try await CloudKitTransport.shared.modifyRecords(
            saving: recordsToSave,
            deleting: []
        )

        let conflictResolution = try await resolveSaveConflicts(
            result.saveErrors,
            localRecords: Dictionary(uniqueKeysWithValues: recordsToSave.map { ($0.recordID, $0) }),
            context: context
        )
        if let error = conflictResolution.unhandledError { throw error }

        let savedOrResolvedIDs = Set(result.savedRecords.keys).union(conflictResolution.resolvedRecordIDs)
        for tombstone in activeTombstones {
            let tombstoneID = CloudRecordCodec.record(for: tombstone).recordID
            if savedOrResolvedIDs.contains(tombstoneID) || tombstoneRecordAlreadyExists.contains(tombstoneID) {
                tombstone.isUploaded = true
            }
        }
        try context.save()
    }

    private func resolveSaveConflicts(
        _ errors: [CKRecord.ID: Error],
        localRecords: [CKRecord.ID: CKRecord],
        context: ModelContext
    ) async throws -> (resolvedRecordIDs: Set<CKRecord.ID>, unhandledError: Error?) {
        var resolved = Set<CKRecord.ID>()
        var recordsToRetry: [CKRecord] = []
        var serverWins: [CKRecord] = []
        var firstUnhandled: Error?

        for (id, error) in errors {
            guard let ckError = error as? CKError,
                  ckError.code == .serverRecordChanged,
                  let local = localRecords[id],
                  let server = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                firstUnhandled = firstUnhandled ?? error
                continue
            }

            if local.recordType == CloudRecordType.tombstone.rawValue {
                let localDate = local["deletedAt"] as? Date ?? .distantPast
                let serverDate = server["deletedAt"] as? Date ?? .distantPast
                if localDate > serverDate {
                    recordsToRetry.append(CloudRecordCodec.rebasing(local, onto: server))
                } else {
                    resolved.insert(id)
                }
                continue
            }

            let localIdentity = try CloudPayloadIdentity(record: local)
            let serverIdentity = try CloudPayloadIdentity(record: server)
            if Self.prefersLocal(localIdentity, over: serverIdentity) {
                recordsToRetry.append(CloudRecordCodec.rebasing(local, onto: server))
            } else {
                serverWins.append(server)
                resolved.insert(id)
            }
        }

        if !serverWins.isEmpty {
            _ = try CloudRecordMergeService.apply(changedRecords: serverWins, deletedRecords: [], in: context)
        }
        if !recordsToRetry.isEmpty {
            let retry = try await CloudKitTransport.shared.modifyRecords(saving: recordsToRetry, deleting: [])
            if let error = retry.firstError { return (resolved, error) }
            resolved.formUnion(retry.savedRecords.keys)
        }
        return (resolved, firstUnhandled)
    }

    private static func prefersLocal(_ local: CloudPayloadIdentity, over server: CloudPayloadIdentity) -> Bool {
        if local.updatedAt != server.updatedAt { return local.updatedAt > server.updatedAt }
        return local.deviceID > server.deviceID
    }

    private static func isUnknownItem(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    private func fetchChangesRecoveringExpiredToken(
        state: CloudSyncState,
        context: ModelContext
    ) async throws -> CloudZoneChangeBatch {
        let token = try CloudChangeTokenStore.decode(state.zoneChangeTokenData)
        do {
            return try await CloudKitTransport.shared.fetchZoneChanges(since: token)
        } catch let error as CKError where error.code == .changeTokenExpired {
            state.zoneChangeTokenData = nil
            try context.save()
            return try await CloudKitTransport.shared.fetchZoneChanges(since: nil)
        }
    }
}
