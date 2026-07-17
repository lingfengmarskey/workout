import Foundation
import CryptoKit
import SwiftData
import UIKit

@MainActor
final class BodyPhotoStore {
    static let shared = BodyPhotoStore()

    enum StoreError: LocalizedError {
        case invalidImage
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                "无法读取这张照片，请选择其他照片后重试。"
            case .encodingFailed:
                "照片压缩失败，请重新拍摄或选择其他照片。"
            }
        }
    }

    private let fileManager: FileManager
    private let directoryName = "BodyProgressPhotos"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Stores a compressed JPEG in Application Support and returns only its opaque filename.
    func save(imageData: Data) throws -> String {
        guard let image = UIImage(data: imageData) else { throw StoreError.invalidImage }
        let normalized = image.normalizedForStorage(maxDimension: 2_000)
        guard let data = normalized.jpegData(compressionQuality: 0.82) else {
            throw StoreError.encodingFailed
        }

        let directory = try storageDirectory()
        let identifier = "\(UUID().uuidString).jpg"
        let destination = directory.appendingPathComponent(identifier, isDirectory: false)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])

        return identifier
    }

    func image(for identifier: String?) -> UIImage? {
        guard let identifier,
              let url = try? photoURL(for: identifier),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func contentHash(for identifier: String?) -> String? {
        guard let identifier,
              let url = try? photoURL(for: identifier),
              let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func fileURL(for identifier: String) throws -> URL {
        let url = try photoURL(for: identifier)
        guard fileManager.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        return url
    }

    /// Copies a downloaded CKAsset into protected app storage without
    /// recompressing it. The caller supplies the hash advertised by WLPhoto;
    /// mismatches are rejected before any model path is changed.
    func installDownloadedAsset(from sourceURL: URL, expectedHash: String) throws -> String {
        let data = try Data(contentsOf: sourceURL)
        guard UIImage(data: data) != nil else { throw StoreError.invalidImage }
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else { throw BodyPhotoDownloadError.hashMismatch }

        let identifier = "\(UUID().uuidString).jpg"
        let destination = try storageDirectory().appendingPathComponent(identifier, isDirectory: false)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return identifier
    }

    func delete(identifier: String?) throws {
        guard let identifier else { return }
        let url = try photoURL(for: identifier)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func deletePhotos(for record: DailyBodyRecord) throws {
        try delete(identifier: record.frontPhotoPath)
        try delete(identifier: record.sidePhotoPath)
        try delete(identifier: record.backPhotoPath)
        record.frontPhotoPath = nil
        record.sidePhotoPath = nil
        record.backPhotoPath = nil
    }

    /// Use this entry point whenever a body record is removed so its files cannot be orphaned.
    func delete(record: DailyBodyRecord, from context: ModelContext) throws {
        let identifiers = [record.frontPhotoPath, record.sidePhotoPath, record.backPhotoPath]
        let deletedAt = Date.now
        try SyncDeletionService.stageDeletion(id: record.id, entityType: .bodyRecord, in: context, deletedAt: deletedAt)
        for angle in CloudPhotoAngle.allCases {
            try CloudPhotoSyncService.stageLocalMutation(
                bodyID: record.id,
                angle: angle,
                contentHash: nil,
                at: deletedAt,
                in: context
            )
        }
        context.delete(record)
        try context.save()
        identifiers.forEach { try? delete(identifier: $0) }
    }

    private func storageDirectory() throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        return directory
    }

    private func photoURL(for identifier: String) throws -> URL {
        let safeIdentifier = URL(fileURLWithPath: identifier).lastPathComponent
        return try storageDirectory().appendingPathComponent(safeIdentifier, isDirectory: false)
    }
}

enum BodyPhotoDownloadError: LocalizedError {
    case hashMismatch

    var errorDescription: String? {
        "iCloud 照片校验失败，已保留本机原照片。"
    }
}

private extension UIImage {
    func normalizedForStorage(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
