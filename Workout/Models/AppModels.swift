import Foundation
import SwiftData

enum PlanStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case active
    case paused
    case completed
    case abandoned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStarted: "未开始"
        case .active: "进行中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .abandoned: "已放弃"
        }
    }
}

enum CompletionStatus: String, Codable, CaseIterable, Identifiable {
    case notRecorded
    case completed
    case partial
    case missed
    case rest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notRecorded: "未记录"
        case .completed: "完成"
        case .partial: "部分完成"
        case .missed: "未完成"
        case .rest: "休息"
        }
    }
}

@Model
final class WeightLossPlan {
    @Attribute(.unique) var id: UUID
    var name: String
    var startDate: Date
    var durationDays: Int
    var startWeight: Double
    var phaseTargetWeight: Double
    var finalTargetWeight: Double
    var dailyCalorieTarget: Int
    var dailyProteinTarget: Int
    var dailyWaterTarget: Double
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        durationDays: Int,
        startWeight: Double,
        phaseTargetWeight: Double,
        finalTargetWeight: Double,
        dailyCalorieTarget: Int,
        dailyProteinTarget: Int,
        dailyWaterTarget: Double,
        status: PlanStatus = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.durationDays = durationDays
        self.startWeight = startWeight
        self.phaseTargetWeight = phaseTargetWeight
        self.finalTargetWeight = finalTargetWeight
        self.dailyCalorieTarget = dailyCalorieTarget
        self.dailyProteinTarget = dailyProteinTarget
        self.dailyWaterTarget = dailyWaterTarget
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: PlanStatus {
        get { PlanStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: max(durationDays - 1, 0), to: startDate) ?? startDate
    }

    func plannedWeight(on date: Date) -> Double {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        let elapsedDays = calendar.dateComponents([.day], from: startDate, to: normalizedDate).day ?? 0
        let clampedDay = min(max(elapsedDays, 0), max(durationDays - 1, 0))
        guard durationDays > 1 else { return phaseTargetWeight }

        let progress = Double(clampedDay) / Double(durationDays - 1)
        return startWeight - ((startWeight - phaseTargetWeight) * progress)
    }
}

@Model
final class DailyBodyRecord {
    @Attribute(.unique) var id: UUID
    var planID: UUID
    var date: Date
    var actualWeight: Double?
    var waist: Double?
    var sleepHours: Double?
    var morningEnergy: Int?
    var frontPhotoPath: String?
    var sidePhotoPath: String?
    var backPhotoPath: String?
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), planID: UUID, date: Date) {
        self.id = id
        self.planID = planID
        self.date = Calendar.current.startOfDay(for: date)
        self.note = ""
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
final class DailyMealPlan {
    @Attribute(.unique) var id: UUID
    var planID: UUID
    var date: Date
    var breakfast: String
    var lunch: String
    var dinner: String
    var snack: String
    var plannedCalories: Int
    var plannedProtein: Int
    var waterTarget: Double
    var breakfastStatusRaw: String
    var lunchStatusRaw: String
    var dinnerStatusRaw: String
    var snackStatusRaw: String
    var hungerLevel: Int?
    var actualWater: Double?
    var note: String

    init(
        id: UUID = UUID(),
        planID: UUID,
        date: Date,
        breakfast: String,
        lunch: String,
        dinner: String,
        snack: String,
        plannedCalories: Int,
        plannedProtein: Int,
        waterTarget: Double
    ) {
        self.id = id
        self.planID = planID
        self.date = Calendar.current.startOfDay(for: date)
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.snack = snack
        self.plannedCalories = plannedCalories
        self.plannedProtein = plannedProtein
        self.waterTarget = waterTarget
        self.breakfastStatusRaw = CompletionStatus.notRecorded.rawValue
        self.lunchStatusRaw = CompletionStatus.notRecorded.rawValue
        self.dinnerStatusRaw = CompletionStatus.notRecorded.rawValue
        self.snackStatusRaw = CompletionStatus.notRecorded.rawValue
        self.note = ""
    }

    var breakfastStatus: CompletionStatus {
        get { CompletionStatus(rawValue: breakfastStatusRaw) ?? .notRecorded }
        set { breakfastStatusRaw = newValue.rawValue }
    }

    var lunchStatus: CompletionStatus {
        get { CompletionStatus(rawValue: lunchStatusRaw) ?? .notRecorded }
        set { lunchStatusRaw = newValue.rawValue }
    }

    var dinnerStatus: CompletionStatus {
        get { CompletionStatus(rawValue: dinnerStatusRaw) ?? .notRecorded }
        set { dinnerStatusRaw = newValue.rawValue }
    }

    var snackStatus: CompletionStatus {
        get { CompletionStatus(rawValue: snackStatusRaw) ?? .notRecorded }
        set { snackStatusRaw = newValue.rawValue }
    }

    var completedMealCount: Int {
        [breakfastStatus, lunchStatus, dinnerStatus, snackStatus]
            .filter { $0 == .completed }
            .count
    }
}

@Model
final class DailyWorkoutPlan {
    @Attribute(.unique) var id: UUID
    var planID: UUID
    var date: Date
    var workoutType: String
    var strengthDescription: String
    var cardioDescription: String
    var warmupDescription: String
    var cooldownDescription: String
    var plannedDurationMinutes: Int
    var targetSteps: Int
    var intensityDescription: String
    var statusRaw: String
    var actualDurationMinutes: Int?
    var actualSteps: Int?
    var fatigueLevel: Int?
    var painDescription: String
    var note: String

    init(
        id: UUID = UUID(),
        planID: UUID,
        date: Date,
        workoutType: String,
        strengthDescription: String,
        cardioDescription: String,
        warmupDescription: String,
        cooldownDescription: String,
        plannedDurationMinutes: Int,
        targetSteps: Int,
        intensityDescription: String
    ) {
        self.id = id
        self.planID = planID
        self.date = Calendar.current.startOfDay(for: date)
        self.workoutType = workoutType
        self.strengthDescription = strengthDescription
        self.cardioDescription = cardioDescription
        self.warmupDescription = warmupDescription
        self.cooldownDescription = cooldownDescription
        self.plannedDurationMinutes = plannedDurationMinutes
        self.targetSteps = targetSteps
        self.intensityDescription = intensityDescription
        self.statusRaw = CompletionStatus.notRecorded.rawValue
        self.painDescription = ""
        self.note = ""
    }

    var status: CompletionStatus {
        get { CompletionStatus(rawValue: statusRaw) ?? .notRecorded }
        set { statusRaw = newValue.rawValue }
    }
}
