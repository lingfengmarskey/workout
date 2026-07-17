import Foundation
import SwiftData

@MainActor
enum PhotoHashBackfillService {
    private static let completionKey = "cloudSync.photoHashBackfill.v2.completed"

    static func runIfNeeded(in context: ModelContext) throws {
        guard !UserDefaults.standard.bool(forKey: completionKey) else { return }

        let records = try context.fetch(FetchDescriptor<DailyBodyRecord>())
        var changed = false
        var couldReadEveryExistingPhoto = true

        for record in records {
            changed = backfill(
                identifier: record.frontPhotoPath,
                hash: &record.frontPhotoHash,
                couldReadEveryExistingPhoto: &couldReadEveryExistingPhoto
            ) || changed
            changed = backfill(
                identifier: record.sidePhotoPath,
                hash: &record.sidePhotoHash,
                couldReadEveryExistingPhoto: &couldReadEveryExistingPhoto
            ) || changed
            changed = backfill(
                identifier: record.backPhotoPath,
                hash: &record.backPhotoHash,
                couldReadEveryExistingPhoto: &couldReadEveryExistingPhoto
            ) || changed
        }

        if changed { try context.save() }
        if couldReadEveryExistingPhoto {
            UserDefaults.standard.set(true, forKey: completionKey)
        }
    }

    private static func backfill(
        identifier: String?,
        hash: inout String?,
        couldReadEveryExistingPhoto: inout Bool
    ) -> Bool {
        guard hash == nil, let identifier else { return false }
        guard let computedHash = BodyPhotoStore.shared.contentHash(for: identifier) else {
            couldReadEveryExistingPhoto = false
            return false
        }
        hash = computedHash
        return true
    }
}
