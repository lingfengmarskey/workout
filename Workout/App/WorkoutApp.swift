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
    @State private var didAttemptSeed = false

    var body: some View {
        RootView()
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
