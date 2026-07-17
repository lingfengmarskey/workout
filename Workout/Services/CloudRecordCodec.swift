import CloudKit
import Foundation

enum CloudRecordType: String {
    case plan = "WLPlan"
    case body = "WLBody"
    case meal = "WLMeal"
    case workout = "WLWorkout"
    case photo = "WLPhoto"
    case tombstone = "WLTombstone"
}

enum CloudRecordCodec {
    static let schemaVersion: Int64 = 1

    static func record(for plan: WeightLossPlan, rebasing existing: CKRecord? = nil) -> CKRecord {
        let record = baseRecord(type: .plan, id: plan.id, updatedAt: plan.updatedAt, revision: plan.syncRevision, existing: existing)
        set(record, "name", plan.name)
        set(record, "startDate", plan.startDate)
        set(record, "durationDays", plan.durationDays)
        set(record, "startWeight", plan.startWeight)
        set(record, "phaseTargetWeight", plan.phaseTargetWeight)
        set(record, "finalTargetWeight", plan.finalTargetWeight)
        set(record, "dailyCalorieTarget", plan.dailyCalorieTarget)
        set(record, "dailyProteinTarget", plan.dailyProteinTarget)
        set(record, "dailyWaterTarget", plan.dailyWaterTarget)
        set(record, "statusRaw", plan.statusRaw)
        set(record, "createdAt", plan.createdAt)
        return record
    }

    static func record(for body: DailyBodyRecord, rebasing existing: CKRecord? = nil) -> CKRecord {
        let record = baseRecord(type: .body, id: body.id, updatedAt: body.updatedAt, revision: body.syncRevision, existing: existing)
        set(record, "planID", body.planID.uuidString.lowercased())
        set(record, "date", body.date)
        set(record, "actualWeight", body.actualWeight)
        set(record, "waist", body.waist)
        set(record, "sleepHours", body.sleepHours)
        set(record, "morningEnergy", body.morningEnergy)
        set(record, "frontPhotoHash", body.frontPhotoHash)
        set(record, "sidePhotoHash", body.sidePhotoHash)
        set(record, "backPhotoHash", body.backPhotoHash)
        set(record, "note", body.note)
        set(record, "createdAt", body.createdAt)
        return record
    }

    static func record(for meal: DailyMealPlan, rebasing existing: CKRecord? = nil) -> CKRecord {
        let record = baseRecord(type: .meal, id: meal.id, updatedAt: meal.updatedAt, revision: meal.syncRevision, existing: existing)
        set(record, "planID", meal.planID.uuidString.lowercased())
        set(record, "date", meal.date)
        set(record, "breakfast", meal.breakfast)
        set(record, "lunch", meal.lunch)
        set(record, "dinner", meal.dinner)
        set(record, "snack", meal.snack)
        set(record, "plannedCalories", meal.plannedCalories)
        set(record, "plannedProtein", meal.plannedProtein)
        set(record, "waterTarget", meal.waterTarget)
        set(record, "breakfastStatusRaw", meal.breakfastStatusRaw)
        set(record, "lunchStatusRaw", meal.lunchStatusRaw)
        set(record, "dinnerStatusRaw", meal.dinnerStatusRaw)
        set(record, "snackStatusRaw", meal.snackStatusRaw)
        set(record, "hungerLevel", meal.hungerLevel)
        set(record, "actualWater", meal.actualWater)
        set(record, "note", meal.note)
        return record
    }

    static func record(for workout: DailyWorkoutPlan, rebasing existing: CKRecord? = nil) -> CKRecord {
        let record = baseRecord(type: .workout, id: workout.id, updatedAt: workout.updatedAt, revision: workout.syncRevision, existing: existing)
        set(record, "planID", workout.planID.uuidString.lowercased())
        set(record, "date", workout.date)
        set(record, "workoutType", workout.workoutType)
        set(record, "strengthDescription", workout.strengthDescription)
        set(record, "cardioDescription", workout.cardioDescription)
        set(record, "warmupDescription", workout.warmupDescription)
        set(record, "cooldownDescription", workout.cooldownDescription)
        set(record, "plannedDurationMinutes", workout.plannedDurationMinutes)
        set(record, "targetSteps", workout.targetSteps)
        set(record, "intensityDescription", workout.intensityDescription)
        set(record, "statusRaw", workout.statusRaw)
        set(record, "actualDurationMinutes", workout.actualDurationMinutes)
        set(record, "actualSteps", workout.actualSteps)
        set(record, "fatigueLevel", workout.fatigueLevel)
        set(record, "painDescription", workout.painDescription)
        set(record, "note", workout.note)
        return record
    }

    static func record(for tombstone: SyncTombstone, rebasing existing: CKRecord? = nil) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "tombstone-\(tombstone.recordName)", zoneID: CloudKitConstants.zoneID)
        let record: CKRecord
        if let existing,
           existing.recordType == CloudRecordType.tombstone.rawValue,
           existing.recordID == recordID {
            record = existing
        } else {
            record = CKRecord(recordType: CloudRecordType.tombstone.rawValue, recordID: recordID)
        }
        set(record, "schemaVersion", schemaVersion)
        set(record, "recordName", tombstone.recordName)
        set(record, "entityTypeRaw", tombstone.entityTypeRaw)
        set(record, "deletedAt", tombstone.deletedAt)
        set(record, "deviceID", tombstone.deviceID)
        return record
    }

    static func identity(from record: CKRecord) throws -> CloudRecordIdentity {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudRecordCodecError.missingRequiredField(record.recordID.recordName)
        }
        let revision = (record["syncRevision"] as? NSNumber)?.intValue ?? 0
        return CloudRecordIdentity(id: id, updatedAt: updatedAt, syncRevision: revision)
    }

    private static func baseRecord(
        type: CloudRecordType,
        id: UUID,
        updatedAt: Date,
        revision: Int,
        existing: CKRecord?
    ) -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: recordName(type: type, id: id),
            zoneID: CloudKitConstants.zoneID
        )
        let record: CKRecord
        if let existing,
           existing.recordType == type.rawValue,
           existing.recordID == recordID {
            record = existing
        } else {
            record = CKRecord(recordType: type.rawValue, recordID: recordID)
        }
        set(record, "schemaVersion", schemaVersion)
        set(record, "id", id.uuidString.lowercased())
        set(record, "updatedAt", updatedAt)
        set(record, "syncRevision", revision)
        set(record, "deviceID", SyncDeviceIdentity.current)
        return record
    }

    static func recordName(type: CloudRecordType, id: UUID) -> String {
        "\(type.rawValue.lowercased())-\(id.uuidString.lowercased())"
    }

    static func rebasing(_ localRecord: CKRecord, onto serverRecord: CKRecord) -> CKRecord {
        guard localRecord.recordID == serverRecord.recordID,
              localRecord.recordType == serverRecord.recordType else {
            return localRecord
        }
        for key in Set(localRecord.allKeys()).union(serverRecord.allKeys()) {
            serverRecord[key] = localRecord[key]
        }
        return serverRecord
    }

    private static func set(_ record: CKRecord, _ key: String, _ value: String?) {
        record[key] = value as CKRecordValue?
    }
    private static func set(_ record: CKRecord, _ key: String, _ value: Date?) {
        record[key] = value as CKRecordValue?
    }
    private static func set(_ record: CKRecord, _ key: String, _ value: Double?) {
        record[key] = value.map(NSNumber.init(value:))
    }
    private static func set(_ record: CKRecord, _ key: String, _ value: Int?) {
        record[key] = value.map(NSNumber.init(value:))
    }
    private static func set(_ record: CKRecord, _ key: String, _ value: Int64) {
        record[key] = NSNumber(value: value)
    }
}

struct CloudRecordIdentity: Equatable {
    let id: UUID
    let updatedAt: Date
    let syncRevision: Int
}

enum CloudRecordCodecError: LocalizedError {
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case let .missingRequiredField(recordName):
            "云端记录 \(recordName) 缺少必要字段。"
        }
    }
}
