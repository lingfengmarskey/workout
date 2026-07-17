import CloudKit
import Foundation
import SwiftData

struct CloudMergeSummary {
    var inserted = 0
    var updated = 0
    var deleted = 0
    var ignored = 0
}

@MainActor
enum CloudRecordMergeService {
    static func apply(
        changedRecords: [CKRecord],
        deletedRecords: [(recordID: CKRecord.ID, recordType: String)],
        in context: ModelContext
    ) throws -> CloudMergeSummary {
        var summary = CloudMergeSummary()

        // Tombstones are applied first so a stale changed record in the same
        // CloudKit batch cannot resurrect an object deleted on another device.
        let payloads = try changedRecords.map { try CloudRecordPayload.decode($0) }
        for payload in payloads {
            if case let .tombstone(tombstone) = payload {
                if try delete(recordName: tombstone.recordName, entityType: tombstone.entityType, in: context) {
                    summary.deleted += 1
                } else {
                    summary.ignored += 1
                }
            }
        }

        let tombstonedNames = Set(payloads.compactMap { payload -> String? in
            if case let .tombstone(tombstone) = payload { return tombstone.recordName }
            return nil
        })

        for (record, payload) in zip(changedRecords, payloads) {
            if case .tombstone = payload { continue }
            guard !tombstonedNames.contains(record.recordID.recordName) else {
                summary.ignored += 1
                continue
            }
            switch payload {
            case let .plan(value): try merge(value, in: context, summary: &summary)
            case let .body(value): try merge(value, in: context, summary: &summary)
            case let .meal(value): try merge(value, in: context, summary: &summary)
            case let .workout(value): try merge(value, in: context, summary: &summary)
            case .tombstone: break
            }
        }

        for deletion in deletedRecords {
            guard let entityType = SyncEntityType(recordType: deletion.recordType) else { continue }
            if try delete(recordName: deletion.recordID.recordName, entityType: entityType, in: context) {
                summary.deleted += 1
            }
        }

        try context.save()
        return summary
    }

    private static func merge(_ payload: CloudPlanPayload, in context: ModelContext, summary: inout CloudMergeSummary) throws {
        let models = try context.fetch(FetchDescriptor<WeightLossPlan>())
        if let model = models.first(where: { $0.id == payload.identity.id }) {
            guard prefersRemote(payload.identity, localUpdatedAt: model.updatedAt) else { summary.ignored += 1; return }
            model.name = payload.name
            model.startDate = payload.startDate
            model.durationDays = payload.durationDays
            model.startWeight = payload.startWeight
            model.phaseTargetWeight = payload.phaseTargetWeight
            model.finalTargetWeight = payload.finalTargetWeight
            model.dailyCalorieTarget = payload.dailyCalorieTarget
            model.dailyProteinTarget = payload.dailyProteinTarget
            model.dailyWaterTarget = payload.dailyWaterTarget
            model.statusRaw = payload.statusRaw
            model.createdAt = payload.createdAt
            model.updatedAt = payload.identity.updatedAt
            model.syncRevision = payload.identity.syncRevision
            summary.updated += 1
        } else {
            let model = WeightLossPlan(
                id: payload.identity.id,
                name: payload.name,
                startDate: payload.startDate,
                durationDays: payload.durationDays,
                startWeight: payload.startWeight,
                phaseTargetWeight: payload.phaseTargetWeight,
                finalTargetWeight: payload.finalTargetWeight,
                dailyCalorieTarget: payload.dailyCalorieTarget,
                dailyProteinTarget: payload.dailyProteinTarget,
                dailyWaterTarget: payload.dailyWaterTarget,
                status: PlanStatus(rawValue: payload.statusRaw) ?? .active,
                createdAt: payload.createdAt,
                updatedAt: payload.identity.updatedAt
            )
            model.syncRevision = payload.identity.syncRevision
            context.insert(model)
            summary.inserted += 1
        }
    }

    private static func merge(_ payload: CloudBodyPayload, in context: ModelContext, summary: inout CloudMergeSummary) throws {
        let models = try context.fetch(FetchDescriptor<DailyBodyRecord>())
        let model: DailyBodyRecord
        if let existing = models.first(where: { $0.id == payload.identity.id }) {
            guard prefersRemote(payload.identity, localUpdatedAt: existing.updatedAt) else { summary.ignored += 1; return }
            model = existing
            summary.updated += 1
        } else {
            model = DailyBodyRecord(id: payload.identity.id, planID: payload.planID, date: payload.date)
            context.insert(model)
            summary.inserted += 1
        }
        model.planID = payload.planID
        model.date = payload.date
        model.actualWeight = payload.actualWeight
        model.waist = payload.waist
        model.sleepHours = payload.sleepHours
        model.morningEnergy = payload.morningEnergy
        model.frontPhotoHash = payload.frontPhotoHash
        model.sidePhotoHash = payload.sidePhotoHash
        model.backPhotoHash = payload.backPhotoHash
        model.note = payload.note
        model.createdAt = payload.createdAt
        model.updatedAt = payload.identity.updatedAt
        model.syncRevision = payload.identity.syncRevision
    }

    private static func merge(_ payload: CloudMealPayload, in context: ModelContext, summary: inout CloudMergeSummary) throws {
        let models = try context.fetch(FetchDescriptor<DailyMealPlan>())
        let model: DailyMealPlan
        if let existing = models.first(where: { $0.id == payload.identity.id }) {
            guard prefersRemote(payload.identity, localUpdatedAt: existing.updatedAt) else { summary.ignored += 1; return }
            model = existing
            summary.updated += 1
        } else {
            model = DailyMealPlan(
                id: payload.identity.id,
                planID: payload.planID,
                date: payload.date,
                breakfast: payload.breakfast,
                lunch: payload.lunch,
                dinner: payload.dinner,
                snack: payload.snack,
                plannedCalories: payload.plannedCalories,
                plannedProtein: payload.plannedProtein,
                waterTarget: payload.waterTarget
            )
            context.insert(model)
            summary.inserted += 1
        }
        model.planID = payload.planID
        model.date = payload.date
        model.breakfast = payload.breakfast
        model.lunch = payload.lunch
        model.dinner = payload.dinner
        model.snack = payload.snack
        model.plannedCalories = payload.plannedCalories
        model.plannedProtein = payload.plannedProtein
        model.waterTarget = payload.waterTarget
        model.breakfastStatusRaw = payload.breakfastStatusRaw
        model.lunchStatusRaw = payload.lunchStatusRaw
        model.dinnerStatusRaw = payload.dinnerStatusRaw
        model.snackStatusRaw = payload.snackStatusRaw
        model.hungerLevel = payload.hungerLevel
        model.actualWater = payload.actualWater
        model.note = payload.note
        model.updatedAt = payload.identity.updatedAt
        model.syncRevision = payload.identity.syncRevision
    }

    private static func merge(_ payload: CloudWorkoutPayload, in context: ModelContext, summary: inout CloudMergeSummary) throws {
        let models = try context.fetch(FetchDescriptor<DailyWorkoutPlan>())
        let model: DailyWorkoutPlan
        if let existing = models.first(where: { $0.id == payload.identity.id }) {
            guard prefersRemote(payload.identity, localUpdatedAt: existing.updatedAt) else { summary.ignored += 1; return }
            model = existing
            summary.updated += 1
        } else {
            model = DailyWorkoutPlan(
                id: payload.identity.id,
                planID: payload.planID,
                date: payload.date,
                workoutType: payload.workoutType,
                strengthDescription: payload.strengthDescription,
                cardioDescription: payload.cardioDescription,
                warmupDescription: payload.warmupDescription,
                cooldownDescription: payload.cooldownDescription,
                plannedDurationMinutes: payload.plannedDurationMinutes,
                targetSteps: payload.targetSteps,
                intensityDescription: payload.intensityDescription
            )
            context.insert(model)
            summary.inserted += 1
        }
        model.planID = payload.planID
        model.date = payload.date
        model.workoutType = payload.workoutType
        model.strengthDescription = payload.strengthDescription
        model.cardioDescription = payload.cardioDescription
        model.warmupDescription = payload.warmupDescription
        model.cooldownDescription = payload.cooldownDescription
        model.plannedDurationMinutes = payload.plannedDurationMinutes
        model.targetSteps = payload.targetSteps
        model.intensityDescription = payload.intensityDescription
        model.statusRaw = payload.statusRaw
        model.actualDurationMinutes = payload.actualDurationMinutes
        model.actualSteps = payload.actualSteps
        model.fatigueLevel = payload.fatigueLevel
        model.painDescription = payload.painDescription
        model.note = payload.note
        model.updatedAt = payload.identity.updatedAt
        model.syncRevision = payload.identity.syncRevision
    }

    private static func prefersRemote(_ identity: CloudPayloadIdentity, localUpdatedAt: Date) -> Bool {
        if identity.updatedAt != localUpdatedAt { return identity.updatedAt > localUpdatedAt }
        return identity.deviceID > SyncDeviceIdentity.current
    }

    @discardableResult
    private static func delete(recordName: String, entityType: SyncEntityType, in context: ModelContext) throws -> Bool {
        guard let id = UUID(uuidString: String(recordName.suffix(36))) else { return false }
        switch entityType {
        case .plan:
            guard let model = try context.fetch(FetchDescriptor<WeightLossPlan>()).first(where: { $0.id == id }) else { return false }
            context.delete(model)
        case .bodyRecord:
            guard let model = try context.fetch(FetchDescriptor<DailyBodyRecord>()).first(where: { $0.id == id }) else { return false }
            try BodyPhotoStore.shared.deletePhotos(for: model)
            context.delete(model)
        case .mealPlan:
            guard let model = try context.fetch(FetchDescriptor<DailyMealPlan>()).first(where: { $0.id == id }) else { return false }
            context.delete(model)
        case .workoutPlan:
            guard let model = try context.fetch(FetchDescriptor<DailyWorkoutPlan>()).first(where: { $0.id == id }) else { return false }
            context.delete(model)
        }
        return true
    }
}

private extension SyncEntityType {
    init?(recordType: String) {
        switch CloudRecordType(rawValue: recordType) {
        case .plan: self = .plan
        case .body: self = .bodyRecord
        case .meal: self = .mealPlan
        case .workout: self = .workoutPlan
        default: return nil
        }
    }
}
