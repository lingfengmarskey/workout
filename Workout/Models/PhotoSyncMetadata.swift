import Foundation
import SwiftData

extension WorkoutSchemaV3 {
@Model
final class PhotoSyncMetadata {
    @Attribute(.unique) var id: String
    var bodyID: UUID
    var angleRaw: String
    var contentHash: String?
    var updatedAt: Date
    var deviceID: String
    var isDeleted: Bool

    init(
        bodyID: UUID,
        angle: CloudPhotoAngle,
        contentHash: String?,
        updatedAt: Date,
        deviceID: String = SyncDeviceIdentity.current,
        isDeleted: Bool
    ) {
        self.id = Self.identifier(bodyID: bodyID, angle: angle)
        self.bodyID = bodyID
        self.angleRaw = angle.rawValue
        self.contentHash = contentHash
        self.updatedAt = updatedAt
        self.deviceID = deviceID
        self.isDeleted = isDeleted
    }

    var angle: CloudPhotoAngle {
        CloudPhotoAngle(rawValue: angleRaw) ?? .front
    }

    static func identifier(bodyID: UUID, angle: CloudPhotoAngle) -> String {
        "\(bodyID.uuidString.lowercased())-\(angle.rawValue)"
    }
}
}

typealias PhotoSyncMetadata = WorkoutSchemaV3.PhotoSyncMetadata
