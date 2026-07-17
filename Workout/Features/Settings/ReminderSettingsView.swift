import SwiftUI
import SwiftData
import UIKit

struct ReminderSettingsView: View {
    @AppStorage(CurrentPlanSelection.storageKey) private var currentPlanID = ""
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var configurations = ReminderSettingsStore.load()
    @State private var authorizationState: ReminderAuthorizationState = .notDetermined
    @State private var errorMessage: String?

    var body: some View {
        Form {
            permissionSection
            if activePlan == nil {
                Section {
                    Label("没有选择当前计划，提醒不会被调度。请在计划库中选择一个进行中的计划。", systemImage: "pause.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            reminderSection(title: "每日提醒", kinds: ReminderKind.allCases.filter { !$0.isWeekly })
            reminderSection(title: "每周提醒", kinds: ReminderKind.allCases.filter(\.isWeekly))

            Section {
                Text("提醒使用系统本地通知，不会上传你的计划或健康数据。工作日为周一至周五，周末为周六和周日。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("提醒设置")
        .task { authorizationState = await LocalReminderService.authorizationState() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                authorizationState = await LocalReminderService.authorizationState()
                await reschedule(configurations)
            }
        }
        .onChange(of: configurations) { _, newValue in
            ReminderSettingsStore.save(newValue)
            Task { await reschedule(newValue) }
        }
        .onDisappear {
            // Persist synchronously as a final safeguard when leaving the editor.
            ReminderSettingsStore.save(configurations)
            Task { await reschedule(configurations) }
        }
        .alert("无法更新提醒", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var activePlan: WeightLossPlan? {
        CurrentPlanSelection.resolve(from: plans, storedID: currentPlanID)
    }

    private var permissionSection: some View {
        Section("通知权限") {
            LabeledContent("状态", value: authorizationState.title)
            switch authorizationState {
            case .notDetermined:
                Button("允许通知") { Task { await requestAuthorization() } }
            case .denied:
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .allowed:
                Label("通知仅在本机调度", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func reminderSection(title: String, kinds: [ReminderKind]) -> some View {
        Section(title) {
            ForEach(kinds) { kind in
                if let index = configurations.firstIndex(where: { $0.kind == kind }) {
                    NavigationLink {
                        ReminderEditorView(configuration: $configurations[index])
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.title)
                                Text(summary(configurations[index]))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: kind.systemImage)
                        }
                    }
                }
            }
        }
    }

    private func summary(_ configuration: ReminderConfiguration) -> String {
        guard configuration.enabled else { return "已关闭" }
        if configuration.kind.isWeekly {
            return "\(weekdayName(configuration.weeklyWeekday)) \(time(configuration.weekdayHour, configuration.weekdayMinute))"
        }
        return "工作日 \(time(configuration.weekdayHour, configuration.weekdayMinute)) · 周末 \(time(configuration.weekendHour, configuration.weekendMinute))"
    }

    private func requestAuthorization() async {
        do {
            _ = try await LocalReminderService.requestAuthorization()
            authorizationState = await LocalReminderService.authorizationState()
            await reschedule(configurations)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reschedule(_ configurations: [ReminderConfiguration]) async {
        do {
            try await LocalReminderService.reschedule(configurations, hasActivePlan: activePlan != nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func time(_ hour: Int, _ minute: Int) -> String {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute))?
            .formatted(date: .omitted, time: .shortened) ?? "--:--"
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "" }
        return symbols[weekday - 1]
    }
}

private struct ReminderEditorView: View {
    @Binding var configuration: ReminderConfiguration

    var body: some View {
        Form {
            Section {
                Toggle("启用提醒", isOn: $configuration.enabled)
            }

            if configuration.kind.isWeekly {
                Section("提醒时间") {
                    Picker("星期", selection: $configuration.weeklyWeekday) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(weekdayName(weekday)).tag(weekday)
                        }
                    }
                    DatePicker(
                        "时间",
                        selection: timeBinding(hour: $configuration.weekdayHour, minute: $configuration.weekdayMinute),
                        displayedComponents: .hourAndMinute
                    )
                }
            } else {
                Section("工作日") {
                    DatePicker(
                        "时间",
                        selection: timeBinding(hour: $configuration.weekdayHour, minute: $configuration.weekdayMinute),
                        displayedComponents: .hourAndMinute
                    )
                }
                Section("周末") {
                    DatePicker(
                        "时间",
                        selection: timeBinding(hour: $configuration.weekendHour, minute: $configuration.weekendMinute),
                        displayedComponents: .hourAndMinute
                    )
                }
            }
        }
        .navigationTitle(configuration.kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: hour.wrappedValue, minute: minute.wrappedValue)) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour.wrappedValue = components.hour ?? hour.wrappedValue
                minute.wrappedValue = components.minute ?? minute.wrappedValue
            }
        )
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "" }
        return symbols[weekday - 1]
    }
}
