import SwiftData
import SwiftUI

@main
struct WorkoutApp: App {
    @UIApplicationDelegateAdaptor(WorkoutAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema(versionedSchema: WorkoutSchemaV5.self)
        // CloudKit is used as an explicit sync transport by CloudSyncEngine.
        // Keep SwiftData's local store out of automatic CloudKit mirroring;
        // automatic mirroring rejects this schema's unique constraints and
        // non-optional fields before the app can even launch.
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

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
            BootstrapView(notificationRouter: appDelegate.notificationRouter)
        }
        .modelContainer(modelContainer)
    }
}

private struct BootstrapView: View {
    @ObservedObject var notificationRouter: NotificationNavigationRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @AppStorage(AppLockSettings.enabledKey) private var isAppLockEnabled = false
    @AppStorage(CurrentPlanSelection.storageKey) private var currentPlanID = ""
    @State private var didAttemptSeed = false
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var authenticationError: String?

    var body: some View {
        ZStack {
            RootView(notificationRouter: notificationRouter)

            if isAppLockEnabled && !isUnlocked {
                AppLockView(
                    authenticationMethod: AppLockService.authenticationMethodName(),
                    isAuthenticating: isAuthenticating,
                    errorMessage: authenticationError,
                    unlock: authenticate
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if scenePhase != .active {
                PrivacyShieldView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.15), value: scenePhase)
            .task {
                guard isAppLockEnabled else {
                    isUnlocked = true
                    return
                }
                await authenticate()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    if isAppLockEnabled && !isAuthenticating {
                        isUnlocked = false
                        authenticationError = nil
                    }
                case .active:
                    Task { try? await CloudSyncEngine.shared.synchronize(in: modelContext) }
                    if isAppLockEnabled && !isUnlocked && !isAuthenticating {
                        Task { await authenticate() }
                    }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onChange(of: isAppLockEnabled) { _, enabled in
                if !enabled {
                    isUnlocked = true
                    authenticationError = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppLockSettings.didAuthenticate)) { _ in
                isUnlocked = true
                authenticationError = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudKitRemoteChange)) { _ in
                Task { try? await CloudSyncEngine.shared.synchronize(in: modelContext) }
            }
            .task(id: activePlanID) {
                try? await LocalReminderService.reschedule(
                    ReminderSettingsStore.load(),
                    hasActivePlan: activePlanID != nil
                )
            }
            .task {
                guard !didAttemptSeed else { return }
                didAttemptSeed = true

                do {
                    try SeedData.seedIfNeeded(in: modelContext)
                    try PhotoHashBackfillService.runIfNeeded(in: modelContext)
                } catch {
                    assertionFailure("Failed to seed initial data: \(error)")
                }
            }
    }

    private var activePlanID: UUID? {
        CurrentPlanSelection.resolve(from: plans, storedID: currentPlanID)?.id
    }

    @MainActor
    private func authenticate() async {
        guard isAppLockEnabled, !isAuthenticating else { return }
        isAuthenticating = true
        authenticationError = nil
        defer { isAuthenticating = false }

        do {
            try await AppLockService.authenticate(reason: "解锁减脂计划并查看你的健康记录")
            isUnlocked = true
        } catch {
            isUnlocked = false
            authenticationError = error.localizedDescription
        }
    }
}

private struct AppLockView: View {
    let authenticationMethod: String
    let isAuthenticating: Bool
    let errorMessage: String?
    let unlock: () async -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                Text("减脂计划已锁定")
                    .font(.title2.bold())
                Text("验证身份后可查看体型照片与健康记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await unlock() }
                } label: {
                    if isAuthenticating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("使用\(authenticationMethod)解锁", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAuthenticating)
            }
            .padding(32)
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
