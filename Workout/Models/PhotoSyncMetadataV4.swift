import Foundation
import SwiftData

extension WorkoutSchemaV4 {
@Model
final class PhotoSyncMetadata {
    @Attribute(.unique) var id: String
    var bodyID: UUID
    var angleRaw: String
    var contentHash: String?
    var updatedAt: Date
    var deviceID: String
    // `isDeleted` collides with Core Data's internal deletion state on some
    // Xcode/iOS combinations and is read back as false after a save. Keep the
    // external API stable while persisting the flag under a neutral property
    // name; originalName preserves existing V3/V4 stores during migration.
    @Attribute(originalName: "isDeleted") var deletedFlag: Bool

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
        self.deletedFlag = isDeleted
    }

    var isDeleted: Bool {
        get { deletedFlag }
        set { deletedFlag = newValue }
    }

    var angle: CloudPhotoAngle {
        CloudPhotoAngle(rawValue: angleRaw) ?? .front
    }

    static func identifier(bodyID: UUID, angle: CloudPhotoAngle) -> String {
        "\(bodyID.uuidString.lowercased())-\(angle.rawValue)"
    }
}
}

typealias PhotoSyncMetadata = WorkoutSchemaV4.PhotoSyncMetadata
