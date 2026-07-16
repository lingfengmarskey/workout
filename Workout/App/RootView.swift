import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                TodayView()
            }
            .tabItem {
                Label("今天", systemImage: "sun.max.fill")
            }

            NavigationStack {
                PlanOverviewView()
            }
            .tabItem {
                Label("计划", systemImage: "calendar")
            }

            NavigationStack {
                ProgressDashboardView()
            }
            .tabItem {
                Label("进度", systemImage: "chart.xyaxis.line")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KeyboardDismissalView())
    }
}
