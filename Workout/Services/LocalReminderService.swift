import Foundation
import UserNotifications

enum ReminderAuthorizationState: Equatable {
    case notDetermined
    case allowed
    case denied

    var title: String {
        switch self {
        case .notDetermined: "尚未授权"
        case .allowed: "已允许"
        case .denied: "已关闭"
        }
    }
}

enum LocalReminderService {
    private static let identifierPrefix = "workout.reminder."

    static func authorizationState() async -> ReminderAuthorizationState {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func reschedule(_ configurations: [ReminderConfiguration], hasActivePlan: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let managedIdentifiers = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: managedIdentifiers)

        guard hasActivePlan, await authorizationState() == .allowed else { return }

        for configuration in configurations where configuration.enabled {
            if configuration.kind.isWeekly {
                try await add(
                    configuration,
                    weekday: configuration.weeklyWeekday,
                    hour: configuration.weekdayHour,
                    minute: configuration.weekdayMinute
                )
            } else {
                for weekday in 1...7 {
                    let isWeekend = weekday == 1 || weekday == 7
                    try await add(
                        configuration,
                        weekday: weekday,
                        hour: isWeekend ? configuration.weekendHour : configuration.weekdayHour,
                        minute: isWeekend ? configuration.weekendMinute : configuration.weekdayMinute
                    )
                }
            }
        }
    }

    private static func add(
        _ configuration: ReminderConfiguration,
        weekday: Int,
        hour: Int,
        minute: Int
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = configuration.kind.title
        content.body = configuration.kind.message
        content.sound = .default
        content.userInfo = ["reminderKind": configuration.kind.rawValue]

        var components = DateComponents()
        components.calendar = .current
        components.timeZone = .current
        components.weekday = weekday
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)\(configuration.kind.rawValue).\(weekday)",
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}
