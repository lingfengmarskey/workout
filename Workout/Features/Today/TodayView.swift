import SwiftData
import SwiftUI

struct TodayView: View {
    @ObservedObject var notificationRouter: NotificationNavigationRouter
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]
    @Query(sort: \DailyWorkoutPlan.date) private var workoutPlans: [DailyWorkoutPlan]
    @AppStorage(CurrentPlanSelection.storageKey) private var currentPlanID = ""

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let plan = activePlan {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        planHeader(plan)

                        if let record = todayBodyRecord(for: plan) {
                            NavigationLink {
                                BodyRecordView(record: record, plan: plan)
                            } label: {
                                bodyCard(record: record, plan: plan)
                            }
                            .buttonStyle(.plain)
                        }

                        if let meal = todayMealPlan(for: plan) {
                            NavigationLink {
                                MealPlanDetailView(plan: meal, bodyWeight: plan.effectiveWeight(on: meal.date, from: bodyRecords))
                            } label: {
                                mealCard(meal)
                            }
                            .buttonStyle(.plain)
                        }

                        if let workout = todayWorkoutPlan(for: plan) {
                            NavigationLink {
                                WorkoutPlanDetailView(plan: workout)
                            } label: {
                                workoutCard(workout)
                            }
                            .buttonStyle(.plain)
                        }

                        completionCard(plan: plan)
                    }
                    .padding()
                }
                .navigationTitle("今天")
            } else {
                ContentUnavailableView(
                    plans.contains(where: { $0.status == .active }) ? "请选择当前计划" : "没有进行中的计划",
                    systemImage: "pause.circle",
                    description: Text(plans.contains(where: { $0.status == .active })
                        ? "请在“设置”的计划库中选择要使用的进行中计划。"
                        : "请在“设置”中创建新计划，或恢复一个已暂停的计划。")
                )
                .navigationTitle("今天")
            }
        }
        .navigationDestination(item: validNotificationDestination) { destination in
            notificationDestination(destination)
        }
    }

    private var validNotificationDestination: Binding<TodayNotificationDestination?> {
        Binding(
            get: { activePlan == nil ? nil : notificationRouter.todayDestination },
            set: { notificationRouter.todayDestination = $0 }
        )
    }

    @ViewBuilder
    private func notificationDestination(_ destination: TodayNotificationDestination) -> some View {
        if let plan = activePlan {
            switch destination {
            case .bodyRecord:
                if let record = todayBodyRecord(for: plan) {
                    BodyRecordView(record: record, plan: plan)
                } else {
                    missingTodayRecord("今天没有身体记录", systemImage: "scalemass")
                }
            case .mealRecord:
                if let meal = todayMealPlan(for: plan) {
                    MealPlanDetailView(plan: meal, bodyWeight: plan.effectiveWeight(on: meal.date, from: bodyRecords))
                } else {
                    missingTodayRecord("今天没有饮食计划", systemImage: "fork.knife")
                }
            case .workoutRecord:
                if let workout = todayWorkoutPlan(for: plan) {
                    WorkoutPlanDetailView(plan: workout)
                } else {
                    missingTodayRecord("今天没有锻炼计划", systemImage: "figure.run")
                }
            }
        } else {
            missingTodayRecord(
                plans.contains(where: { $0.status == .active }) ? "请选择当前计划" : "没有进行中的计划",
                systemImage: "pause.circle"
            )
        }
    }

    private func missingTodayRecord(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
    }

    private var activePlan: WeightLossPlan? {
        CurrentPlanSelection.resolve(from: plans, storedID: currentPlanID)
    }

    private func todayBodyRecord(for plan: WeightLossPlan) -> DailyBodyRecord? {
        bodyRecords.first {
            $0.planID == plan.id && calendar.isDateInToday($0.date)
        }
    }

    private func todayMealPlan(for plan: WeightLossPlan) -> DailyMealPlan? {
        mealPlans.first {
            $0.planID == plan.id && calendar.isDateInToday($0.date)
        }
    }

    private func todayWorkoutPlan(for plan: WeightLossPlan) -> DailyWorkoutPlan? {
        workoutPlans.first {
            $0.planID == plan.id && calendar.isDateInToday($0.date)
        }
    }

    private func planHeader(_ plan: WeightLossPlan) -> some View {
        let elapsed = calendar.dateComponents(
            [.day],
            from: plan.startDate,
            to: calendar.startOfDay(for: .now)
        ).day ?? 0
        let day = min(max(elapsed + 1, 1), plan.durationDays)
        let week = ((day - 1) / 7) + 1

        return VStack(alignment: .leading, spacing: 8) {
            Text(plan.name)
                .font(.title2.bold())
            Text("第 \(week) 周 · 第 \(day) 天")
                .foregroundStyle(.secondary)
            ProgressView(value: Double(day), total: Double(plan.durationDays))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func bodyCard(record: DailyBodyRecord, plan: WeightLossPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("今日体重", systemImage: "scalemass.fill")
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("计划")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plan.plannedWeight(on: .now), format: .number.precision(.fractionLength(1)))
                        .font(.title2.bold())
                    Text("kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("实际")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let weight = record.actualWeight {
                        Text(weight, format: .number.precision(.fractionLength(1)))
                            .font(.title2.bold())
                        Text("kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("点击记录")
                            .font(.headline)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func mealCard(_ meal: DailyMealPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("今日饮食", systemImage: "fork.knife")
                    .font(.headline)
                Spacer()
                Text("\(meal.completedMealCount)/4 完成")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("\(meal.plannedCalories) kcal · 蛋白质 \(meal.plannedProtein)g · 饮水 \(meal.waterTarget, specifier: "%.1f")L")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            mealRow("早餐", meal.breakfastStatus)
            mealRow("午餐", meal.lunchStatus)
            mealRow("晚餐", meal.dinnerStatus)
            mealRow("加餐", meal.snackStatus)
        }
        .cardStyle()
    }

    private func mealRow(_ title: String, _ status: CompletionStatus) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(status.displayName)
                .foregroundStyle(status == .completed ? Color.green : Color.secondary)
        }
        .font(.subheadline)
    }

    private func workoutCard(_ workout: DailyWorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("今日锻炼", systemImage: "figure.strengthtraining.traditional")
                    .font(.headline)
                Spacer()
                Text(workout.status.displayName)
                    .foregroundStyle(workout.status == .completed ? Color.green : Color.secondary)
            }

            Text(workout.workoutType)
                .font(.title3.bold())
            Text("\(workout.plannedDurationMinutes) 分钟 · 目标 \(workout.targetSteps) 步")
                .foregroundStyle(.secondary)
            Text(workout.strengthDescription)
                .font(.subheadline)
                .lineLimit(2)
        }
        .cardStyle()
    }

    private func completionCard(plan: WeightLossPlan) -> some View {
        let bodyDone = todayBodyRecord(for: plan)?.actualWeight != nil
        let mealDone = (todayMealPlan(for: plan)?.completedMealCount ?? 0) == 4
        let workoutDone = todayWorkoutPlan(for: plan)?.status == .completed
        let completed = [bodyDone, mealDone, workoutDone].filter { $0 }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("今日完成度")
                .font(.headline)
            ProgressView(value: Double(completed), total: 3)
            HStack {
                statusLabel("体重", bodyDone)
                Spacer()
                statusLabel("饮食", mealDone)
                Spacer()
                statusLabel("锻炼", workoutDone)
            }
        }
        .cardStyle()
    }

    private func statusLabel(_ title: String, _ completed: Bool) -> some View {
        Label(title, systemImage: completed ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(completed ? Color.green : Color.secondary)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
