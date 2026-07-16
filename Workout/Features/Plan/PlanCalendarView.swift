import SwiftUI

struct PlanCalendarView: View {
    let plan: WeightLossPlan
    let bodyRecords: [DailyBodyRecord]
    let mealPlans: [DailyMealPlan]
    let workoutPlans: [DailyWorkoutPlan]
    let showsCurrentWeek: Bool

    @State private var visiblePeriod: Date
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    init(plan: WeightLossPlan, bodyRecords: [DailyBodyRecord], mealPlans: [DailyMealPlan], workoutPlans: [DailyWorkoutPlan], showsCurrentWeek: Bool) {
        self.plan = plan
        self.bodyRecords = bodyRecords
        self.mealPlans = mealPlans
        self.workoutPlans = workoutPlans
        self.showsCurrentWeek = showsCurrentWeek
        let today = Calendar.current.startOfDay(for: .now)
        let initial = min(max(today, plan.startDate), plan.endDate)
        _visiblePeriod = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                periodHeader
                weekdayHeader
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(calendarCells) { cell in
                        if let date = cell.date {
                            dayCell(date)
                        } else {
                            Color.clear.frame(height: 58)
                        }
                    }
                }
                legend
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var periodHeader: some View {
        HStack {
            Button { movePeriod(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(!canMovePeriod(-1))
            Spacer()
            Text(periodTitle).font(.title3.bold())
            Spacer()
            Button { movePeriod(1) } label: { Image(systemName: "chevron.right") }
                .disabled(!canMovePeriod(1))
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns) {
            ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let inPlan = date >= plan.startDate && date <= plan.endDate
        return Group {
            if inPlan {
                NavigationLink {
                    DayPlanSummaryView(
                        plan: plan,
                        date: date,
                        bodyRecord: bodyRecord(on: date),
                        mealPlan: mealPlan(on: date),
                        workoutPlan: workoutPlan(on: date)
                    )
                } label: { dayCellContent(date, enabled: true) }
                .buttonStyle(.plain)
            } else {
                dayCellContent(date, enabled: false)
            }
        }
    }

    private func dayCellContent(_ date: Date, enabled: Bool) -> some View {
        VStack(spacing: 7) {
            Text(date.formatted(.dateTime.day()))
                .font(.subheadline.weight(calendar.isDateInToday(date) ? .bold : .regular))
            HStack(spacing: 4) {
                Circle().fill(bodyColor(date)).frame(width: 7, height: 7)
                Circle().fill(mealColor(date)).frame(width: 7, height: 7)
                Circle().fill(workoutColor(date)).frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.45))
        .background(calendar.isDateInToday(date) ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("圆点顺序：体重 · 饮食 · 锻炼").foregroundStyle(.secondary)
            HStack { legendItem("完成", .green); legendItem("部分", .yellow); legendItem("未完成", .red); legendItem("未记录", .gray); legendItem("未来", .blue.opacity(0.45)) }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(text) }
    }

    private func bodyColor(_ date: Date) -> Color {
        guard date <= calendar.startOfDay(for: .now) else { return .blue.opacity(0.45) }
        return bodyRecord(on: date)?.actualWeight == nil ? .gray : .green
    }

    private func mealColor(_ date: Date) -> Color {
        guard date <= calendar.startOfDay(for: .now) else { return .blue.opacity(0.45) }
        guard let meal = mealPlan(on: date) else { return .gray }
        let statuses = [meal.breakfastStatus, meal.lunchStatus, meal.dinnerStatus, meal.snackStatus]
        if statuses.allSatisfy({ $0 == .completed }) { return .green }
        if statuses.contains(.missed) { return .red }
        if statuses.contains(.partial) || statuses.contains(.completed) { return .yellow }
        return .gray
    }

    private func workoutColor(_ date: Date) -> Color {
        guard date <= calendar.startOfDay(for: .now) else { return .blue.opacity(0.45) }
        guard let status = workoutPlan(on: date)?.status else { return .gray }
        switch status { case .completed, .rest: return .green; case .partial: return .yellow; case .missed: return .red; case .notRecorded: return .gray }
    }

    private func bodyRecord(on date: Date) -> DailyBodyRecord? { bodyRecords.first { $0.planID == plan.id && calendar.isDate($0.date, inSameDayAs: date) } }
    private func mealPlan(on date: Date) -> DailyMealPlan? { mealPlans.first { $0.planID == plan.id && calendar.isDate($0.date, inSameDayAs: date) } }
    private func workoutPlan(on date: Date) -> DailyWorkoutPlan? { workoutPlans.first { $0.planID == plan.id && calendar.isDate($0.date, inSameDayAs: date) } }

    private var calendarCells: [CalendarCell] {
        if showsCurrentWeek {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: visiblePeriod)?.start else { return [] }
            return (0..<7).map { CalendarCell(date: calendar.date(byAdding: .day, value: $0, to: start)) }
        }
        guard let interval = calendar.dateInterval(of: .month, for: visiblePeriod),
              let days = calendar.range(of: .day, in: .month, for: visiblePeriod) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: CalendarCell(date: nil), count: leading) + days.compactMap {
            CalendarCell(date: calendar.date(byAdding: .day, value: $0 - 1, to: interval.start))
        }
    }

    private var periodTitle: String {
        if showsCurrentWeek, let interval = calendar.dateInterval(of: .weekOfYear, for: visiblePeriod), let end = calendar.date(byAdding: .day, value: 6, to: interval.start) {
            return interval.start.formatted(.dateTime.month().day()) + " – " + end.formatted(.dateTime.month().day())
        }
        return visiblePeriod.formatted(.dateTime.year().month(.wide))
    }

    private func movePeriod(_ offset: Int) {
        let component: Calendar.Component = showsCurrentWeek ? .weekOfYear : .month
        visiblePeriod = calendar.date(byAdding: component, value: offset, to: visiblePeriod) ?? visiblePeriod
    }

    private func canMovePeriod(_ offset: Int) -> Bool {
        let component: Calendar.Component = showsCurrentWeek ? .weekOfYear : .month
        guard let target = calendar.date(byAdding: component, value: offset, to: visiblePeriod),
              let interval = calendar.dateInterval(of: component, for: target) else { return false }
        return interval.end > plan.startDate && interval.start <= plan.endDate
    }
}

private struct CalendarCell: Identifiable {
    let id = UUID()
    let date: Date?
}

struct DayPlanSummaryView: View {
    let plan: WeightLossPlan
    let date: Date
    let bodyRecord: DailyBodyRecord?
    let mealPlan: DailyMealPlan?
    let workoutPlan: DailyWorkoutPlan?

    var body: some View {
        List {
            if let bodyRecord { NavigationLink("身体记录") { BodyRecordView(record: bodyRecord, plan: plan) } }
            if let mealPlan { NavigationLink("饮食计划") { MealPlanDetailView(plan: mealPlan) } }
            if let workoutPlan { NavigationLink("锻炼计划") { WorkoutPlanDetailView(plan: workoutPlan) } }
        }
        .navigationTitle(date.formatted(date: .complete, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}
