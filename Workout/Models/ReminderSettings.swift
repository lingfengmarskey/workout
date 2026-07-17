import Foundation

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case morningWeight
    case breakfast
    case lunch
    case dinner
    case workout
    case eveningLog
    case weeklyPhoto
    case weeklyReview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morningWeight: "早晨称重"
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .workout: "锻炼"
        case .eveningLog: "晚间记录"
        case .weeklyPhoto: "每周体型拍照"
        case .weeklyReview: "每周复盘"
        }
    }

    var systemImage: String {
        switch self {
        case .morningWeight: "scalemass"
        case .breakfast: "sunrise"
        case .lunch: "fork.knife"
        case .dinner: "moon.stars"
        case .workout: "figure.run"
        case .eveningLog: "checklist"
        case .weeklyPhoto: "camera"
        case .weeklyReview: "chart.line.uptrend.xyaxis"
        }
    }

    var message: String {
        switch self {
        case .morningWeight: "记录今天的体重，关注长期趋势。"
        case .breakfast: "看看今天的早餐计划，按自己的节奏开始一天。"
        case .lunch: "午餐时间到了，记得查看计划并补充水分。"
        case .dinner: "查看今晚的饮食计划，为今天好好收尾。"
        case .workout: "今天的锻炼计划正在等你，量力而行。"
        case .eveningLog: "花一分钟记录饮食、步数和身体感受。"
        case .weeklyPhoto: "在相似光线和站姿下记录本周体型。"
        case .weeklyReview: "回顾本周趋势和执行情况，再决定是否调整计划。"
        }
    }

    var isWeekly: Bool {
        self == .weeklyPhoto || self == .weeklyReview
    }
}

struct ReminderConfiguration: Codable, Equatable, Identifiable {
    var kind: ReminderKind
    var enabled: Bool
    var weekdayHour: Int
    var weekdayMinute: Int
    var weekendHour: Int
    var weekendMinute: Int
    /// Calendar weekday: Sunday = 1, Saturday = 7.
    var weeklyWeekday: Int

    var id: ReminderKind { kind }
}

enum ReminderSettingsStore {
    private static let key = "reminders.configurations.v1"

    static func load() -> [ReminderConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([ReminderConfiguration].self, from: data) else {
            return defaults
        }

        let savedByKind = Dictionary(uniqueKeysWithValues: saved.map { ($0.kind, $0) })
        return defaults.map { savedByKind[$0.kind] ?? $0 }
    }

    static func save(_ configurations: [ReminderConfiguration]) {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static let defaults: [ReminderConfiguration] = [
        configuration(.morningWeight, hour: 7, minute: 30, weekendHour: 8, weekendMinute: 30),
        configuration(.breakfast, hour: 8, minute: 0, weekendHour: 9, weekendMinute: 0),
        configuration(.lunch, hour: 12, minute: 0, weekendHour: 12, weekendMinute: 30),
        configuration(.dinner, hour: 19, minute: 0, weekendHour: 19, weekendMinute: 0),
        configuration(.workout, hour: 18, minute: 30, weekendHour: 10, weekendMinute: 0),
        configuration(.eveningLog, hour: 21, minute: 30, weekendHour: 21, weekendMinute: 30),
        configuration(.weeklyPhoto, hour: 9, minute: 0, weekendHour: 9, weekendMinute: 0, weekday: 7),
        configuration(.weeklyReview, hour: 20, minute: 0, weekendHour: 20, weekendMinute: 0, weekday: 1)
    ]

    private static func configuration(
        _ kind: ReminderKind,
        hour: Int,
        minute: Int,
        weekendHour: Int,
        weekendMinute: Int,
        weekday: Int = 2
    ) -> ReminderConfiguration {
        ReminderConfiguration(
            kind: kind,
            enabled: false,
            weekdayHour: hour,
            weekdayMinute: minute,
            weekendHour: weekendHour,
            weekendMinute: weekendMinute,
            weeklyWeekday: weekday
        )
    }
}
