import SwiftUI

struct RootView: View {
    @ObservedObject var notificationRouter: NotificationNavigationRouter

    var body: some View {
        TabView(selection: $notificationRouter.selectedTab) {
            NavigationStack {
                TodayView(notificationRouter: notificationRouter)
            }
            .tabItem {
                Label("今天", systemImage: "sun.max.fill")
            }
            .tag(AppTab.today)

            NavigationStack {
                PlanOverviewView()
            }
            .tag(AppTab.plan)
            .tabItem {
                Label("计划", systemImage: "calendar")
            }

            NavigationStack {
                ProgressDashboardView(notificationRouter: notificationRouter)
            }
            .tag(AppTab.progress)
            .tabItem {
                Label("进度", systemImage: "chart.xyaxis.line")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KeyboardDismissalView())
    }
}
