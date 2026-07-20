import CloudKit
import Foundation

enum CloudRecordPayload {
    case plan(CloudPlanPayload)
    case body(CloudBodyPayload)
    case meal(CloudMealPayload)
    case workout(CloudWorkoutPayload)
    case tombstone(CloudTombstonePayload)

    static func decode(_ record: CKRecord) throws -> CloudRecordPayload {
        switch CloudRecordType(rawValue: record.recordType) {
        case .plan:
            return .plan(try CloudPlanPayload(record: record))
        case .body:
            return .body(try CloudBodyPayload(record: record))
        case .meal:
            return .meal(try CloudMealPayload(record: record))
        case .workout:
            return .workout(try CloudWorkoutPayload(record: record))
        case .tombstone:
            return .tombstone(try CloudTombstonePayload(record: record))
        case .photo:
            throw CloudRecordPayloadError.unsupportedRecordType(record.recordType)
        case nil:
            throw CloudRecordPayloadError.unsupportedRecordType(record.recordType)
        }
    }
}

struct CloudPayloadIdentity {
    let id: UUID
    let updatedAt: Date
    let syncRevision: Int
    let deviceID: String

    init(record: CKRecord) throws {
        let identity = try CloudRecordCodec.identity(from: record)
        id = identity.id
        updatedAt = identity.updatedAt
        syncRevision = identity.syncRevision
        deviceID = record.string("deviceID") ?? ""
    }
}

struct CloudPlanPayload {
    let identity: CloudPayloadIdentity
    let name: String
    let startDate: Date
    let durationDays: Int
    let startWeight: Double
    let phaseTargetWeight: Double
    let finalTargetWeight: Double
    let dailyCalorieTarget: Int
    let dailyProteinTarget: Int
    let dailyWaterTarget: Double
    let statusRaw: String
    let createdAt: Date

    init(record: CKRecord) throws {
        identity = try CloudPayloadIdentity(record: record)
        name = try record.requiredString("name")
        startDate = try record.requiredDate("startDate")
        durationDays = try record.requiredInt("durationDays")
        startWeight = try record.requiredDouble("startWeight")
        phaseTargetWeight = try record.requiredDouble("phaseTargetWeight")
        finalTargetWeight = try record.requiredDouble("finalTargetWeight")
        dailyCalorieTarget = try record.requiredInt("dailyCalorieTarget")
        dailyProteinTarget = try record.requiredInt("dailyProteinTarget")
        dailyWaterTarget = try record.requiredDouble("dailyWaterTarget")
        statusRaw = try record.requiredString("statusRaw")
        createdAt = try record.requiredDate("createdAt")
    }
}

struct CloudBodyPayload {
    let identity: CloudPayloadIdentity
    let planID: UUID
    let date: Date
    let actualWeight: Double?
    let waist: Double?
    let sleepHours: Double?
    let morningEnergy: Int?
    let frontPhotoHash: String?
    let sidePhotoHash: String?
    let backPhotoHash: String?
    let note: String
    let createdAt: Date

    init(record: CKRecord) throws {
        identity = try CloudPayloadIdentity(record: record)
        planID = try record.requiredUUID("planID")
        date = try record.requiredDate("date")
        actualWeight = record.double("actualWeight")
        waist = record.double("waist")
        sleepHours = record.double("sleepHours")
        morningEnergy = record.int("morningEnergy")
        frontPhotoHash = record.string("frontPhotoHash")
        sidePhotoHash = record.string("sidePhotoHash")
        backPhotoHash = record.string("backPhotoHash")
        note = record.string("note") ?? ""
        createdAt = try record.requiredDate("createdAt")
    }
}

struct CloudMealPayload {
    let identity: CloudPayloadIdentity
    let planID: UUID
    let date: Date
    let breakfast: String
    let lunch: String
    let dinner: String
    let snack: String
    let plannedCalories: Int
    let plannedProtein: Int
    let waterTarget: Double
    let breakfastStatusRaw: String
    let lunchStatusRaw: String
    let dinnerStatusRaw: String
    let snackStatusRaw: String
    let hungerLevel: Int?
    let actualWater: Double?
    let note: String
    let actualFoodEntriesJSON: String

    init(record: CKRecord) throws {
        identity = try CloudPayloadIdentity(record: record)
        planID = try record.requiredUUID("planID")
        date = try record.requiredDate("date")
        breakfast = try record.requiredString("breakfast")
        lunch = try record.requiredString("lunch")
        dinner = try record.requiredString("dinner")
        snack = try record.requiredString("snack")
        plannedCalories = try record.requiredInt("plannedCalories")
        plannedProtein = try record.requiredInt("plannedProtein")
        waterTarget = try record.requiredDouble("waterTarget")
        breakfastStatusRaw = try record.requiredString("breakfastStatusRaw")
        lunchStatusRaw = try record.requiredString("lunchStatusRaw")
        dinnerStatusRaw = try record.requiredString("dinnerStatusRaw")
        snackStatusRaw = try record.requiredString("snackStatusRaw")
        hungerLevel = record.int("hungerLevel")
        actualWater = record.double("actualWater")
        note = record.string("note") ?? ""
        actualFoodEntriesJSON = record.string("actualFoodEntriesJSON") ?? "[]"
    }
}

struct CloudWorkoutPayload {
    let identity: CloudPayloadIdentity
    let planID: UUID
    let date: Date
    let workoutType: String
    let strengthDescription: String
    let cardioDescription: String
    let warmupDescription: String
    let cooldownDescription: String
    let plannedDurationMinutes: Int
    let targetSteps: Int
    let intensityDescription: String
    let statusRaw: String
    let actualDurationMinutes: Int?
    let actualSteps: Int?
    let fatigueLevel: Int?
    let painDescription: String
    let note: String
    let addedActivitiesJSON: String

    init(record: CKRecord) throws {
        identity = try CloudPayloadIdentity(record: record)
        planID = try record.requiredUUID("planID")
        date = try record.requiredDate("date")
        workoutType = try record.requiredString("workoutType")
        strengthDescription = record.string("strengthDescription") ?? ""
        cardioDescription = record.string("cardioDescription") ?? ""
        warmupDescription = record.string("warmupDescription") ?? ""
        cooldownDescription = record.string("cooldownDescription") ?? ""
        plannedDurationMinutes = try record.requiredInt("plannedDurationMinutes")
        targetSteps = try record.requiredInt("targetSteps")
        intensityDescription = record.string("intensityDescription") ?? ""
        statusRaw = try record.requiredString("statusRaw")
        actualDurationMinutes = record.int("actualDurationMinutes")
        actualSteps = record.int("actualSteps")
        fatigueLevel = record.int("fatigueLevel")
        painDescription = record.string("painDescription") ?? ""
        note = record.string("note") ?? ""
        addedActivitiesJSON = record.string("addedActivitiesJSON") ?? "[]"
    }
}

struct CloudTombstonePayload {
    let recordName: String
    let entityType: SyncEntityType
    let deletedAt: Date
    let deviceID: String

    init(record: CKRecord) throws {
        recordName = try record.requiredString("recordName")
        guard let entityType = SyncEntityType(rawValue: try record.requiredString("entityTypeRaw")) else {
            throw CloudRecordPayloadError.invalidField("entityTypeRaw", record.recordID.recordName)
        }
        self.entityType = entityType
        deletedAt = try record.requiredDate("deletedAt")
        deviceID = record.string("deviceID") ?? ""
    }
}

enum CloudRecordPayloadError: LocalizedError {
    case missingField(String, String)
    case invalidField(String, String)
    case unsupportedRecordType(String)

    var errorDescription: String? {
        switch self {
        case let .missingField(field, record): "云端记录 \(record) 缺少字段 \(field)。"
        case let .invalidField(field, record): "云端记录 \(record) 的字段 \(field) 无效。"
        case let .unsupportedRecordType(type): "暂不支持云端记录类型 \(type)。"
        }
    }
}

private extension CKRecord {
    func string(_ key: String) -> String? { self[key] as? String }
    func date(_ key: String) -> Date? { self[key] as? Date }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }

    func requiredString(_ key: String) throws -> String {
        guard let value = string(key) else { throw CloudRecordPayloadError.missingField(key, recordID.recordName) }
        return value
    }

    func requiredDate(_ key: String) throws -> Date {
        guard let value = date(key) else { throw CloudRecordPayloadError.missingField(key, recordID.recordName) }
        return value
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let value = int(key) else { throw CloudRecordPayloadError.missingField(key, recordID.recordName) }
        return value
    }

    func requiredDouble(_ key: String) throws -> Double {
        guard let value = double(key) else { throw CloudRecordPayloadError.missingField(key, recordID.recordName) }
        return value
    }

    func requiredUUID(_ key: String) throws -> UUID {
        guard let string = string(key), let value = UUID(uuidString: string) else {
            throw CloudRecordPayloadError.invalidField(key, recordID.recordName)
        }
        return value
    }
}
