import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]
    @Query(sort: \DailyWorkoutPlan.date) private var workoutPlans: [DailyWorkoutPlan]

    @State private var showTestDataConfirmation = false
    @State private var testDataMessage: String?
    @State private var pendingStatus: PlanStatus?
    @State private var statusFeedback: PlanStatusFeedback?
    @State private var statusErrorMessage: String?

    private var activePlan: WeightLossPlan? {
        plans.first(where: { $0.status == .active })
    }

    private var historicalPlans: [WeightLossPlan] {
        plans.filter { $0.id != activePlan?.id }
    }

    var body: some View {
        Form {
            if let plan = activePlan {
                Section("当前计划") {
                    LabeledContent("名称", value: plan.name)
                    LabeledContent("开始日期", value: plan.startDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("结束日期", value: plan.endDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("起始体重", value: formattedWeight(plan.startWeight))
                    LabeledContent("阶段目标", value: formattedWeight(plan.phaseTargetWeight))
                    LabeledContent("长期目标", value: formattedWeight(plan.finalTargetWeight))
                    NavigationLink("编辑当前计划") {
                        PlanEditView(plan: plan)
                    }
                }

                Section("每日目标") {
                    LabeledContent("热量", value: "\(plan.dailyCalorieTarget) kcal")
                    LabeledContent("蛋白质", value: "\(plan.dailyProteinTarget) g")
                    LabeledContent("饮水", value: "\(plan.dailyWaterTarget.formatted(.number.precision(.fractionLength(1)))) L")
                }

                Section("计划状态") {
                    LabeledContent("当前状态", value: plan.status.displayName)
                    Button {
                        pendingStatus = .paused
                    } label: {
                        Label("暂停计划", systemImage: "pause.circle")
                    }
                    Button {
                        pendingStatus = .completed
                    } label: {
                        Label("完成计划", systemImage: "trophy.fill")
                    }
                    Button(role: .destructive) {
                        pendingStatus = .abandoned
                    } label: {
                        Label("放弃计划…", systemImage: "heart.slash")
                    }
                }
            } else {
                Section("当前计划") {
                    ContentUnavailableView(
                        "没有进行中的计划",
                        systemImage: "flag.checkered",
                        description: Text("可以创建新计划，或从历史计划恢复一个暂停的计划。")
                    )
                }
            }

            Section {
                NavigationLink {
                    PlanCreateView()
                } label: {
                    Label("创建新计划", systemImage: "plus.circle.fill")
                }
            }

            if !historicalPlans.isEmpty {
                Section("历史计划") {
                    ForEach(historicalPlans) { plan in
                        NavigationLink {
                            PlanHistoryDetailView(plan: plan)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(plan.name)
                                    Spacer()
                                    Text(plan.status.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(plan.startDate.formatted(date: .abbreviated, time: .omitted)) – \(plan.endDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("提醒") {
                NavigationLink {
                    ReminderSettingsView()
                } label: {
                    Label("本地通知", systemImage: "bell.badge")
                }
            }

            Section("后续功能") {
                NavigationLink {
                    HealthKitSettingsView()
                } label: {
                    Label("健康与步数", systemImage: "heart.text.square")
                }
                NavigationLink {
                    CloudSyncSettingsView()
                } label: {
                    Label("iCloud 同步", systemImage: "icloud")
                }
                NavigationLink {
                    AppLockSettingsView()
                } label: {
                    Label("隐私锁", systemImage: "faceid")
                }
                NavigationLink {
                    DataExportView()
                } label: {
                    Label("CSV 导出", systemImage: "square.and.arrow.up")
                }
            }

            Section("隐私") {
                Text("当前版本的数据仅使用 SwiftData 保存在本地。体型照片功能接入后，也应默认保存在 App 私有目录，不上传第三方服务器。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

#if DEBUG
            if activePlan != nil {
                Section("开发与测试") {
                    Button("生成 4 周周报测试数据", role: .destructive) {
                        showTestDataConfirmation = true
                    }
                    Text("仅 Debug 构建显示。会把当前计划移动到 28 天前，并覆盖最近 29 天的身体、饮食和锻炼记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
#endif
        }
        .navigationTitle("设置")
        .alert(
            pendingStatus?.confirmationTitle ?? "更改计划状态？",
            isPresented: Binding(
                get: { pendingStatus != nil },
                set: { if !$0 { pendingStatus = nil } }
            )
        ) {
            if let pendingStatus {
                Button(pendingStatus.confirmationButtonTitle, role: pendingStatus == .abandoned ? .destructive : nil) {
                    applyStatus(pendingStatus)
                }
            }
            Button("取消", role: .cancel) { pendingStatus = nil }
        } message: {
            Text(pendingStatus?.confirmationMessage ?? "")
        }
        .fullScreenCover(item: $statusFeedback) { feedback in
            PlanStatusFeedbackView(feedback: feedback) {
                statusFeedback = nil
            }
        }
        .alert("无法更改计划状态", isPresented: Binding(
            get: { statusErrorMessage != nil },
            set: { if !$0 { statusErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(statusErrorMessage ?? "")
        }
#if DEBUG
        .alert("生成测试数据？", isPresented: $showTestDataConfirmation) {
            Button("确认生成", role: .destructive) { generateTestData() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会覆盖当前计划最近 29 天的测试字段，请勿用于真实记录。")
        }
        .alert("周报测试数据", isPresented: Binding(
            get: { testDataMessage != nil },
            set: { if !$0 { testDataMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(testDataMessage ?? "")
        }
#endif
    }

    private func formattedWeight(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private func applyStatus(_ status: PlanStatus) {
        guard let plan = activePlan else { return }
        let completionSummary = status == .completed ? makeCompletionSummary(for: plan) : nil
        plan.status = status
        plan.updatedAt = .now
        plan.syncRevision += 1
        do {
            try modelContext.save()
            pendingStatus = nil
            statusFeedback = PlanStatusFeedback(
                status: status,
                planName: plan.name,
                completionSummary: completionSummary
            )
        } catch {
            modelContext.rollback()
            pendingStatus = nil
            statusErrorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func makeCompletionSummary(for plan: WeightLossPlan) -> PlanCompletionSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let planBodyRecords = bodyRecords.filter { $0.planID == plan.id }
        let latestWeight = planBodyRecords.last(where: { $0.actualWeight != nil })?.actualWeight
        let planMeals = mealPlans.filter { $0.planID == plan.id && $0.date <= today }
        let mealScores = planMeals.flatMap {
            [$0.breakfastStatus, $0.lunchStatus, $0.dinnerStatus, $0.snackStatus]
        }.map(completionScore)
        let planWorkouts = workoutPlans.filter { $0.planID == plan.id && $0.date <= today }
        let workoutScores = planWorkouts.map { completionScore($0.status) }
        let bodyActivityDates = planBodyRecords.filter(hasBodyActivity).map { calendar.startOfDay(for: $0.date) }
        let mealActivityDates = planMeals.filter(hasMealActivity).map { calendar.startOfDay(for: $0.date) }
        let workoutActivityDates = planWorkouts.filter(hasWorkoutActivity).map { calendar.startOfDay(for: $0.date) }
        let executedDays = Set(bodyActivityDates + mealActivityDates + workoutActivityDates).count

        return PlanCompletionSummary(
            executedDays: executedDays,
            startWeight: plan.startWeight,
            latestWeight: latestWeight,
            mealCompletionRate: average(mealScores),
            workoutCompletionRate: average(workoutScores)
        )
    }

    private func completionScore(_ status: CompletionStatus) -> Double {
        switch status {
        case .completed, .rest: 1
        case .partial: 0.5
        case .notRecorded, .missed: 0
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func hasBodyActivity(_ record: DailyBodyRecord) -> Bool {
        record.actualWeight != nil || record.waist != nil || record.sleepHours != nil
            || record.morningEnergy != nil || !record.note.isEmpty
            || record.frontPhotoPath != nil || record.sidePhotoPath != nil || record.backPhotoPath != nil
    }

    private func hasMealActivity(_ plan: DailyMealPlan) -> Bool {
        [plan.breakfastStatus, plan.lunchStatus, plan.dinnerStatus, plan.snackStatus]
            .contains { $0 != .notRecorded }
            || plan.hungerLevel != nil || plan.actualWater != nil || !plan.note.isEmpty
    }

    private func hasWorkoutActivity(_ plan: DailyWorkoutPlan) -> Bool {
        plan.status != .notRecorded || plan.actualDurationMinutes != nil || plan.actualSteps != nil
            || plan.fatigueLevel != nil || !plan.painDescription.isEmpty || !plan.note.isEmpty
    }

#if DEBUG
    private func generateTestData() {
        guard let plan = activePlan else { return }
        do {
            try WeeklyReviewTestData.generate(
                plan: plan,
                bodyRecords: bodyRecords,
                mealPlans: mealPlans,
                workoutPlans: workoutPlans,
                in: modelContext
            )
            testDataMessage = "已生成 29 天数据。请打开“进度”查看 4 个周报和不同调整建议。"
        } catch {
            testDataMessage = "生成失败：\(error.localizedDescription)"
        }
    }
#endif
}
