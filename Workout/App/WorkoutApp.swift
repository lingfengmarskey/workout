import SwiftData
import SwiftUI

@main
struct WorkoutApp: App {
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema(versionedSchema: WorkoutSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)

        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: WorkoutMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Unable to initialize the local data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            BootstrapView()
        }
        .modelContainer(modelContainer)
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
