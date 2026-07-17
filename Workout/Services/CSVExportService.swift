import Foundation

enum CSVExportKind: String, CaseIterable, Identifiable {
    case body
    case meals
    case workouts
    case weeklyReviews

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: "身体记录"
        case .meals: "饮食记录"
        case .workouts: "锻炼记录"
        case .weeklyReviews: "每周复盘"
        }
    }

    var fileStem: String {
        switch self {
        case .body: "body-records"
        case .meals: "meal-records"
        case .workouts: "workout-records"
        case .weeklyReviews: "weekly-reviews"
        }
    }
}

enum CSVExportService {
    static func export(
        kinds: [CSVExportKind],
        plan: WeightLossPlan,
        bodyRecords: [DailyBodyRecord],
        mealPlans: [DailyMealPlan],
        workoutPlans: [DailyWorkoutPlan]
    ) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try kinds.map { kind in
            let url = directory.appendingPathComponent("\(kind.fileStem)-\(date(plan.startDate)).csv")
            let content = csv(
                rows: rows(
                    for: kind,
                    plan: plan,
                    bodyRecords: bodyRecords,
                    mealPlans: mealPlans,
                    workoutPlans: workoutPlans
                )
            )
            // UTF-8 BOM keeps Chinese text readable in common spreadsheet apps.
            try Data(([0xEF, 0xBB, 0xBF] as [UInt8]) + Array(content.utf8)).write(to: url, options: .atomic)
            return url
        }
    }

    static func cleanTemporaryExports() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutExports", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
    }

    private static func rows(
        for kind: CSVExportKind,
        plan: WeightLossPlan,
        bodyRecords: [DailyBodyRecord],
        mealPlans: [DailyMealPlan],
        workoutPlans: [DailyWorkoutPlan]
    ) -> [[String]] {
        switch kind {
        case .body:
            return [["日期", "计划体重_kg", "实际体重_kg", "腰围_cm", "睡眠_小时", "晨起精神", "正面照片", "侧面照片", "背面照片", "备注"]]
                + bodyRecords.filter { $0.planID == plan.id }.sorted { $0.date < $1.date }.map {
                    [date($0.date), number(plan.plannedWeight(on: $0.date)), number($0.actualWeight), number($0.waist), number($0.sleepHours), integer($0.morningEnergy), yesNo($0.frontPhotoPath != nil), yesNo($0.sidePhotoPath != nil), yesNo($0.backPhotoPath != nil), $0.note]
                }
        case .meals:
            return [["日期", "早餐计划", "早餐状态", "午餐计划", "午餐状态", "晚餐计划", "晚餐状态", "加餐计划", "加餐状态", "计划热量_kcal", "计划蛋白质_g", "饮水目标_L", "实际饮水_L", "饥饿感", "备注"]]
                + mealPlans.filter { $0.planID == plan.id }.sorted { $0.date < $1.date }.map {
                    [date($0.date), $0.breakfast, $0.breakfastStatus.displayName, $0.lunch, $0.lunchStatus.displayName, $0.dinner, $0.dinnerStatus.displayName, $0.snack, $0.snackStatus.displayName, String($0.plannedCalories), String($0.plannedProtein), number($0.waterTarget), number($0.actualWater), integer($0.hungerLevel), $0.note]
                }
        case .workouts:
            return [["日期", "训练类型", "热身", "力量训练", "有氧", "放松", "计划时长_分钟", "目标步数", "强度", "完成状态", "实际时长_分钟", "实际步数", "疲劳程度", "疼痛描述", "备注"]]
                + workoutPlans.filter { $0.planID == plan.id }.sorted { $0.date < $1.date }.map {
                    [date($0.date), $0.workoutType, $0.warmupDescription, $0.strengthDescription, $0.cardioDescription, $0.cooldownDescription, String($0.plannedDurationMinutes), String($0.targetSteps), $0.intensityDescription, $0.status.displayName, integer($0.actualDurationMinutes), integer($0.actualSteps), integer($0.fatigueLevel), $0.painDescription, $0.note]
                }
        case .weeklyReviews:
            let summaries = WeeklyReviewCalculator.summaries(
                plan: plan,
                bodyRecords: bodyRecords,
                mealPlans: mealPlans,
                workoutPlans: workoutPlans
            ).sorted { $0.weekIndex < $1.weekIndex }
            return [["周次", "开始日期", "结束日期", "完整周", "平均体重_kg", "周末体重_kg", "本周下降_kg", "平均腰围_cm", "饮食执行率", "锻炼执行率", "平均步数", "平均睡眠_小时", "平均饥饿感", "平均晨起精神", "平均疲劳", "疼痛摘要", "照片记录天数", "建议"]]
                + summaries.map {
                    [String($0.weekIndex), date($0.startDate), date($0.endDate), yesNo($0.isComplete), number($0.averageWeight), number($0.endWeight), number($0.weightLoss), number($0.averageWaist), number($0.mealCompletionRate), number($0.workoutCompletionRate), number($0.averageSteps), number($0.averageSleep), number($0.averageHunger), number($0.averageEnergy), number($0.averageFatigue), $0.painSummary.joined(separator: "；"), String($0.photoRecords.count), recommendation($0.recommendation)]
                }
        }
    }

    private static func csv(rows: [[String]]) -> String {
        rows.map { $0.map(escaped).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func escaped(_ original: String) -> String {
        let trimmed = original.drop(while: \.isWhitespace)
        let dangerous = trimmed.first.map { "=+-@".contains($0) } == true && Double(original) == nil
        let safe = dangerous ? "'" + original : original
        return "\"\(safe.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    private static func number(_ value: Double?) -> String {
        value.map { $0.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
    }

    private static func number(_ value: Double) -> String { number(Optional(value)) }
    private static func integer(_ value: Int?) -> String { value.map(String.init) ?? "" }
    private static func yesNo(_ value: Bool) -> String { value ? "是" : "否" }

    private static func recommendation(_ value: WeeklyReviewSummary.Recommendation) -> String {
        switch value {
        case .maintain: "维持计划"
        case .plateau: "检查平台期并选择调整"
        case .tooFast: "增加摄入或降低训练量"
        case .insufficientData: "数据不足"
        }
    }
}
