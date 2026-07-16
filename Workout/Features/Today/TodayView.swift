import SwiftData
import SwiftUI

struct TodayView: View {
    @Query(sort: \WeightLossPlan.startDate, order: .reverse) private var plans: [WeightLossPlan]
    @Query(sort: \DailyBodyRecord.date) private var bodyRecords: [DailyBodyRecord]
    @Query(sort: \DailyMealPlan.date) private var mealPlans: [DailyMealPlan]
    @Query(sort: \DailyWorkoutPlan.date) private var workoutPlans: [DailyWorkoutPlan]

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
                                MealPlanDetailView(plan: meal)
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
                    "还没有减脂计划",
                    systemImage: "figure.walk",
                    description: Text("首次启动后会自动创建默认 8 周计划。")
                )
                .navigationTitle("今天")
            }
        }
    }

    private var activePlan: WeightLossPlan? {
        plans.first(where: { $0.status == .active }) ?? plans.first
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
                .foregroundStyle(status == .completed ? .green : .secondary)
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
                    .foregroundStyle(workout.status == .completed ? .green : .secondary)
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
            .foregroundStyle(completed ? .green : .secondary)
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
