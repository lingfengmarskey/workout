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
    func save(imageData: Data, replacing oldIdentifier: String?) throws -> String {
        guard let image = UIImage(data: imageData) else { throw StoreError.invalidImage }
        let normalized = image.normalizedForStorage(maxDimension: 2_000)
        guard let data = normalized.jpegData(compressionQuality: 0.82) else {
            throw StoreError.encodingFailed
        }

        let directory = try storageDirectory()
        let identifier = "\(UUID().uuidString).jpg"
        let destination = directory.appendingPathComponent(identifier, isDirectory: false)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])

        if let oldIdentifier {
            try? delete(identifier: oldIdentifier)
        }
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
        try deletePhotos(for: record)
        try SyncDeletionService.stageDeletion(id: record.id, entityType: .bodyRecord, in: context)
        context.delete(record)
        try context.save()
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
