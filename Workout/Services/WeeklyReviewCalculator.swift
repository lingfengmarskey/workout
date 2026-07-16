import Foundation

struct WeeklyReviewSummary: Identifiable {
    enum Recommendation {
        case maintain
        case plateau
        case tooFast
        case insufficientData
    }

    let weekIndex: Int
    let startDate: Date
    let endDate: Date
    let isComplete: Bool
    let averageWeight: Double?
    let endWeight: Double?
    let weightLoss: Double?
    let averageWaist: Double?
    let mealCompletionRate: Double
    let workoutCompletionRate: Double
    let averageSteps: Double?
    let averageSleep: Double?
    let averageHunger: Double?
    let averageEnergy: Double?
    let averageFatigue: Double?
    let painSummary: [String]
    let photoRecords: [DailyBodyRecord]
    var recommendation: Recommendation = .insufficientData

    var id: Int { weekIndex }
}

enum WeeklyReviewCalculator {
    static func summaries(
        plan: WeightLossPlan,
        bodyRecords: [DailyBodyRecord],
        mealPlans: [DailyMealPlan],
        workoutPlans: [DailyWorkoutPlan],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [WeeklyReviewSummary] {
        let today = calendar.startOfDay(for: today)
        guard today >= plan.startDate else { return [] }
        let visibleDays = min(plan.durationDays, (calendar.dateComponents([.day], from: plan.startDate, to: today).day ?? 0) + 1)
        let visibleWeeks = Int(ceil(Double(visibleDays) / 7.0))

        var results = (0..<visibleWeeks).compactMap { weekOffset -> WeeklyReviewSummary? in
            guard let start = calendar.date(byAdding: .day, value: weekOffset * 7, to: plan.startDate),
                  let plannedEnd = calendar.date(byAdding: .day, value: 6, to: start) else { return nil }
            let end = min(min(plannedEnd, today), plan.endDate)

            let bodies = records(bodyRecords, planID: plan.id, start: start, end: end)
            let meals = records(mealPlans, planID: plan.id, start: start, end: end)
            let workouts = records(workoutPlans, planID: plan.id, start: start, end: end)
            let weights = bodies.compactMap(\.actualWeight)

            let mealScores = meals.flatMap { meal in
                [meal.breakfastStatus, meal.lunchStatus, meal.dinnerStatus, meal.snackStatus]
            }.map(score)
            let workoutScores = workouts.map { score($0.status) }

            return WeeklyReviewSummary(
                weekIndex: weekOffset + 1,
                startDate: start,
                endDate: end,
                isComplete: end >= plannedEnd,
                averageWeight: average(weights),
                endWeight: bodies.last(where: { $0.actualWeight != nil })?.actualWeight,
                weightLoss: weights.count >= 2 ? weights.first! - weights.last! : nil,
                averageWaist: average(bodies.compactMap(\.waist)),
                mealCompletionRate: rate(mealScores),
                workoutCompletionRate: rate(workoutScores),
                averageSteps: average(workouts.compactMap(\.actualSteps).map(Double.init)),
                averageSleep: average(bodies.compactMap(\.sleepHours)),
                averageHunger: average(meals.compactMap(\.hungerLevel).map(Double.init)),
                averageEnergy: average(bodies.compactMap(\.morningEnergy).map(Double.init)),
                averageFatigue: average(workouts.compactMap(\.fatigueLevel).map(Double.init)),
                painSummary: workouts.map(\.painDescription).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                photoRecords: bodies.filter { $0.frontPhotoPath != nil || $0.sidePhotoPath != nil || $0.backPhotoPath != nil }
            )
        }

        for index in results.indices {
            let current = results[index]
            guard let loss = current.weightLoss else { continue }
            let strained = (current.averageHunger ?? 0) >= 4
                || (current.averageFatigue ?? 0) >= 4
                || current.painSummary.isEmpty == false
            if loss > 1.2 && strained {
                results[index].recommendation = .tooFast
            } else if index > 0,
                      loss < 0.4,
                      let previousLoss = results[index - 1].weightLoss,
                      previousLoss < 0.4 {
                results[index].recommendation = .plateau
            } else if (0.4...1.2).contains(loss) && !strained {
                results[index].recommendation = .maintain
            }
        }
        return Array(results.reversed())
    }

    private static func records<T>(_ values: [T], planID: UUID, start: Date, end: Date) -> [T] where T: WeeklyDatedRecord {
        values.filter { $0.planID == planID && $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
    }

    private static func score(_ status: CompletionStatus) -> Double {
        switch status {
        case .completed, .rest: 1
        case .partial: 0.5
        case .notRecorded, .missed: 0
        }
    }

    private static func rate(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private protocol WeeklyDatedRecord {
    var planID: UUID { get }
    var date: Date { get }
}

extension DailyBodyRecord: WeeklyDatedRecord {}
extension DailyMealPlan: WeeklyDatedRecord {}
extension DailyWorkoutPlan: WeeklyDatedRecord {}
