import SwiftData
import SwiftUI

@main
struct WorkoutApp: App {
    var body: some Scene {
        WindowGroup {
            BootstrapView()
        }
        .modelContainer(
            for: [
                WeightLossPlan.self,
                DailyBodyRecord.self,
                DailyMealPlan.self,
                DailyWorkoutPlan.self
            ]
        )
    }
}

private struct BootstrapView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var didAttemptSeed = false

    var body: some View {
        ZStack {
            RootView()

            if scenePhase != .active {
                PrivacyShieldView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: scenePhase)
            .task {
                guard !didAttemptSeed else { return }
                didAttemptSeed = true

                do {
                    try SeedData.seedIfNeeded(in: modelContext)
                } catch {
                    assertionFailure("Failed to seed initial data: \(error)")
                }
            }
    }
}

private struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("减脂计划")
                    .font(.headline)
                Text("体型与健康记录已隐藏")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
