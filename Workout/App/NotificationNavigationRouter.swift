import SwiftUI
import UserNotifications

enum AppTab: Hashable {
    case today
    case plan
    case progress
    case settings
}

enum TodayNotificationDestination: String, Identifiable {
    case bodyRecord
    case mealRecord
    case workoutRecord

    var id: String { rawValue }
}

enum ProgressNotificationDestination: String, Identifiable {
    case photoHistory
    case weeklyReview

    var id: String { rawValue }
}

@MainActor
final class NotificationNavigationRouter: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var todayDestination: TodayNotificationDestination?
    @Published var progressDestination: ProgressNotificationDestination?

    func route(to kind: ReminderKind) {
        todayDestination = nil
        progressDestination = nil

        switch kind {
        case .morningWeight:
            selectedTab = .today
            todayDestination = .bodyRecord
        case .breakfast, .lunch, .dinner:
            selectedTab = .today
            todayDestination = .mealRecord
        case .workout:
            selectedTab = .today
            todayDestination = .workoutRecord
        case .eveningLog:
            selectedTab = .today
        case .weeklyPhoto:
            selectedTab = .progress
            progressDestination = .photoHistory
        case .weeklyReview:
            selectedTab = .progress
            progressDestination = .weeklyReview
        }
    }
}

final class WorkoutAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let notificationRouter = NotificationNavigationRouter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rawValue = response.notification.request.content.userInfo["reminderKind"] as? String
        if let rawValue, let kind = ReminderKind(rawValue: rawValue) {
            Task { @MainActor in
                notificationRouter.route(to: kind)
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}
