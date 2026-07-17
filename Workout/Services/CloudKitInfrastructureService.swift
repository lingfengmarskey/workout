import CloudKit
import Foundation

enum CloudKitConstants {
    static let containerIdentifier = "iCloud.com.lingfengmarskey.workout"
    static let zoneName = "WorkoutPrivateZone"
    static let subscriptionID = "WorkoutPrivateZoneChanges"

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }
}

enum CloudAccountAvailability: String, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var displayName: String {
        switch self {
        case .available: "可用"
        case .noAccount: "未登录 iCloud"
        case .restricted: "受系统限制"
        case .temporarilyUnavailable: "暂时不可用"
        case .couldNotDetermine: "无法确定"
        }
    }
}

actor CloudKitInfrastructureService {
    static let shared = CloudKitInfrastructureService()

    private let container: CKContainer
    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: CloudKitConstants.containerIdentifier)) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func accountAvailability() async throws -> CloudAccountAvailability {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let availability: CloudAccountAvailability = switch status {
                case .available: .available
                case .noAccount: .noAccount
                case .restricted: .restricted
                case .temporarilyUnavailable: .temporarilyUnavailable
                case .couldNotDetermine: .couldNotDetermine
                @unknown default: .couldNotDetermine
                }
                continuation.resume(returning: availability)
            }
        }
    }

    func preparePrivateZone() async throws {
        guard try await accountAvailability() == .available else {
            throw CloudInfrastructureError.accountUnavailable
        }

        let zone = CKRecordZone(zoneID: CloudKitConstants.zoneID)
        _ = try await save(zone: zone)

        let subscription = CKRecordZoneSubscription(
            zoneID: CloudKitConstants.zoneID,
            subscriptionID: CloudKitConstants.subscriptionID
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        _ = try await save(subscription: subscription)
    }

    func deletePrivateZone() async throws {
        guard try await accountAvailability() == .available else {
            throw CloudInfrastructureError.accountUnavailable
        }
        do {
            _ = try await database.deleteRecordZone(withID: CloudKitConstants.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // Idempotent: the requested cloud data is already absent.
        }
    }

    private func save(zone: CKRecordZone) async throws -> CKRecordZone {
        try await withCheckedThrowingContinuation { continuation in
            database.save(zone) { savedZone, error in
                if let error { continuation.resume(throwing: error) }
                else if let savedZone { continuation.resume(returning: savedZone) }
                else { continuation.resume(throwing: CloudInfrastructureError.missingResult) }
            }
        }
    }

    private func save(subscription: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            database.save(subscription) { savedSubscription, error in
                if let error { continuation.resume(throwing: error) }
                else if let savedSubscription { continuation.resume(returning: savedSubscription) }
                else { continuation.resume(throwing: CloudInfrastructureError.missingResult) }
            }
        }
    }
}

enum CloudInfrastructureError: LocalizedError {
    case accountUnavailable
    case missingResult

    var errorDescription: String? {
        switch self {
        case .accountUnavailable: "当前 iCloud 账号不可用。"
        case .missingResult: "CloudKit 没有返回有效结果，请稍后重试。"
        }
    }
}
