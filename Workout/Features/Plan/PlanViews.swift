import SwiftData
import SwiftUI

struct PlanOverviewView: View {
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]
    @Query(sort: \DailyWorkoutPlan.date) private var workoutPlans: [DailyWorkoutPlan]
    @AppStorage("plan.overview.displayMode") private var displayMode: PlanDisplayMode = .month

    private var activePlan: WeightLossPlan? {
        plans.first(where: { $0.status == .active })
    }

    var body: some View {
        Group {
            if let plan = activePlan {
                VStack(spacing: 0) {
                    if displayMode != .list {
                        PlanCalendarView(
                            plan: plan,
                            bodyRecords: bodyRecords,
                            mealPlans: mealPlans,
                            workoutPlans: workoutPlans,
                            showsCurrentWeek: displayMode == .week
                        )
                        .id(displayMode)
                    } else {
                        dailyList(plan: plan)
                    }
                }
                .navigationTitle("计划")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(PlanDisplayMode.allCases) { mode in
                                Button {
                                    displayMode = mode
                                } label: {
                                    Label(mode.title, systemImage: displayMode == mode ? "checkmark" : mode.icon)
                                }
                            }
                        } label: {
                            Image(systemName: displayMode.icon)
                        }
                        .accessibilityLabel("切换计划显示方式，当前为\(displayMode.title)")
                    }
                }
            } else {
                ContentUnavailableView(
                    "没有进行中的计划",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("请在“设置”中创建新计划，或恢复一个已暂停的计划。")
                )
                    .navigationTitle("计划")
            }
        }
    }

    private func dailyList(plan: WeightLossPlan) -> some View {
        List {
                    Section {
                        LabeledContent("开始", value: plan.startDate.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("阶段目标", value: formattedWeight(plan.phaseTargetWeight))
                        LabeledContent("周期", value: "\(plan.durationDays) 天")
                    } header: {
                        Text(plan.name)
                    }

                    Section("每日计划") {
                        ForEach(mealPlans.filter { $0.planID == plan.id }) { meal in
                            let workout = workoutPlans.first {
                                $0.planID == plan.id && Calendar.current.isDate($0.date, inSameDayAs: meal.date)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(meal.date.formatted(date: .complete, time: .omitted))
                                    .font(.headline)

                                NavigationLink {
                                    MealPlanDetailView(plan: meal)
                                } label: {
                                    Label(
                                        "饮食 · \(meal.plannedCalories) kcal · \(meal.completedMealCount)/4",
                                        systemImage: "fork.knife"
                                    )
                                }

                                if let workout {
                                    NavigationLink {
                                        WorkoutPlanDetailView(plan: workout)
                                    } label: {
                                        Label(
                                            "\(workout.workoutType) · \(workout.plannedDurationMinutes) 分钟",
                                            systemImage: "figure.strengthtraining.traditional"
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
        }

    private func formattedWeight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }
}

private enum PlanDisplayMode: String, CaseIterable, Identifiable {
    case month, week, list
    var id: String { rawValue }
    var title: String {
        switch self { case .month: "月历"; case .week: "当前周"; case .list: "列表" }
    }
    var icon: String {
        switch self { case .month: "calendar"; case .week: "calendar.day.timeline.left"; case .list: "list.bullet" }
    }
}

struct MealPlanDetailView: View {
    @Bindable var plan: DailyMealPlan
    @State private var initialSyncFingerprint: String?

    var body: some View {
        Form {
            mealSection(
                title: "早餐",
                description: plan.breakfast,
                status: statusBinding(
                    get: { plan.breakfastStatus },
                    set: { plan.breakfastStatus = $0 }
                )
            )
            mealSection(
                title: "午餐",
                description: plan.lunch,
                status: statusBinding(
                    get: { plan.lunchStatus },
                    set: { plan.lunchStatus = $0 }
                )
            )
            mealSection(
                title: "晚餐",
                description: plan.dinner,
                status: statusBinding(
                    get: { plan.dinnerStatus },
                    set: { plan.dinnerStatus = $0 }
                )
            )
            mealSection(
                title: "加餐",
                description: plan.snack,
                status: statusBinding(
                    get: { plan.snackStatus },
                    set: { plan.snackStatus = $0 }
                )
            )

            Section("全天目标") {
                LabeledContent("热量", value: "\(plan.plannedCalories) kcal")
                LabeledContent("蛋白质", value: "\(plan.plannedProtein) g")
                LabeledContent(
                    "饮水",
                    value: "\(plan.waterTarget.formatted(.number.precision(.fractionLength(1)))) L"
                )
            }

            Section("感受与备注") {
                Picker(
                    "饥饿感",
                    selection: Binding(
                        get: { plan.hungerLevel ?? 3 },
                        set: { plan.hungerLevel = $0 }
                    )
                ) {
                    ForEach(1...5, id: \.self) { score in
                        Text("\(score) 分").tag(score)
                    }
                }

                TextField("实际饮水（L）", text: doubleBinding(\DailyMealPlan.actualWater))
                    .keyboardType(.decimalPad)

                TextEditor(text: $plan.note)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle("饮食计划")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initialSyncFingerprint = syncFingerprint }
        .onDisappear {
            if initialSyncFingerprint != syncFingerprint {
                plan.updatedAt = .now
                plan.syncRevision += 1
            }
        }
    }

    private func mealSection(
        title: String,
        description: String,
        status: Binding<CompletionStatus>
    ) -> some View {
        Section(title) {
            Text(description)
            Picker("完成情况", selection: status) {
                ForEach(CompletionStatus.allCases.filter { $0 != .rest }) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
    }

    private func statusBinding(
        get: @escaping () -> CompletionStatus,
        set: @escaping (CompletionStatus) -> Void
    ) -> Binding<CompletionStatus> {
        Binding(get: get, set: set)
    }

    private func doubleBinding(
        _ keyPath: ReferenceWritableKeyPath<DailyMealPlan, Double?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = plan[keyPath: keyPath] else { return "" }
                return value.formatted(.number.precision(.fractionLength(0...1)))
            },
            set: { text in
                plan[keyPath: keyPath] = Double(text.replacingOccurrences(of: ",", with: "."))
            }
        )
    }

    private var syncFingerprint: String {
        [
            plan.breakfastStatusRaw,
            plan.lunchStatusRaw,
            plan.dinnerStatusRaw,
            plan.snackStatusRaw,
            plan.hungerLevel.map { String($0) } ?? "",
            plan.actualWater.map { String($0) } ?? "",
            plan.note
        ].joined(separator: "|")
    }
}

struct WorkoutPlanDetailView: View {
    @Bindable var plan: DailyWorkoutPlan
    @AppStorage("healthkit.steps.authorizationRequested") private var healthAuthorizationRequested = false
    @State private var isReadingHealthSteps = false
    @State private var importedSteps: Int?
    @State private var showOverwriteStepsConfirmation = false
    @State private var healthStepError: String?
    @State private var initialSyncFingerprint: String?

    var body: some View {
        Form {
            Section("今日目标") {
                LabeledContent("训练类型", value: plan.workoutType)
                LabeledContent("计划时长", value: "\(plan.plannedDurationMinutes) 分钟")
                LabeledContent("目标步数", value: "\(plan.targetSteps) 步")
                Text(plan.intensityDescription)
                    .foregroundStyle(.secondary)
            }

            Section("热身") {
                Text(plan.warmupDescription)
            }

            Section("力量训练") {
                Text(plan.strengthDescription)
            }

            Section("有氧") {
                Text(plan.cardioDescription)
            }

            Section("拉伸与放松") {
                Text(plan.cooldownDescription)
            }

            Section("执行记录") {
                Picker(
                    "完成情况",
                    selection: Binding(
                        get: { plan.status },
                        set: { plan.status = $0 }
                    )
                ) {
                    ForEach(CompletionStatus.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }

                TextField("实际步数", text: intBinding(\DailyWorkoutPlan.actualSteps))
                    .keyboardType(.numberPad)

                if Calendar.current.isDateInToday(plan.date) {
                    Button {
                        Task { await importTodaySteps() }
                    } label: {
                        if isReadingHealthSteps {
                            HStack {
                                ProgressView()
                                Text("正在读取健康步数…")
                            }
                        } else {
                            Label("从健康 App 同步今日步数", systemImage: "heart.fill")
                        }
                    }
                    .disabled(isReadingHealthSteps || !HealthKitStepService.isAvailable)
                }
                TextField("实际训练时长（分钟）", text: intBinding(\DailyWorkoutPlan.actualDurationMinutes))
                    .keyboardType(.numberPad)

                Picker(
                    "疲劳程度",
                    selection: Binding(
                        get: { plan.fatigueLevel ?? 3 },
                        set: { plan.fatigueLevel = $0 }
                    )
                ) {
                    ForEach(1...5, id: \.self) { score in
                        Text("\(score) 分").tag(score)
                    }
                }

                TextField("疼痛或不适", text: $plan.painDescription, axis: .vertical)
                TextField("备注", text: $plan.note, axis: .vertical)
            }

            if !plan.painDescription.isEmpty {
                Section {
                    Label(
                        "出现胸痛、明显头晕、异常气短或严重关节疼痛时，应停止训练并就医。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("锻炼计划")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initialSyncFingerprint = syncFingerprint }
        .onDisappear {
            if initialSyncFingerprint != syncFingerprint {
                plan.updatedAt = .now
                plan.syncRevision += 1
            }
        }
        .alert("覆盖当前步数？", isPresented: $showOverwriteStepsConfirmation) {
            Button("使用健康步数") {
                if let importedSteps { plan.actualSteps = importedSteps }
                importedSteps = nil
            }
            Button("取消", role: .cancel) { importedSteps = nil }
        } message: {
            Text("当前已记录 \(plan.actualSteps ?? 0) 步，健康 App 读取到 \(importedSteps ?? 0) 步。")
        }
        .alert("无法同步步数", isPresented: Binding(
            get: { healthStepError != nil },
            set: { if !$0 { healthStepError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(healthStepError ?? "")
        }
    }

    private func importTodaySteps() async {
        isReadingHealthSteps = true
        defer { isReadingHealthSteps = false }
        do {
            if !healthAuthorizationRequested {
                try await HealthKitStepService.requestReadAuthorization()
                healthAuthorizationRequested = true
            }
            let steps = try await HealthKitStepService.todaySteps()
            if let current = plan.actualSteps, current != steps {
                importedSteps = steps
                showOverwriteStepsConfirmation = true
            } else {
                plan.actualSteps = steps
            }
        } catch {
            healthStepError = error.localizedDescription
        }
    }

    private func intBinding(
        _ keyPath: ReferenceWritableKeyPath<DailyWorkoutPlan, Int?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let value = plan[keyPath: keyPath] else { return "" }
                return String(value)
            },
            set: { text in
                plan[keyPath: keyPath] = Int(text)
            }
        )
    }

    private var syncFingerprint: String {
        [
            plan.statusRaw,
            plan.actualDurationMinutes.map { String($0) } ?? "",
            plan.actualSteps.map { String($0) } ?? "",
            plan.fatigueLevel.map { String($0) } ?? "",
            plan.painDescription,
            plan.note
        ].joined(separator: "|")
    }
}
