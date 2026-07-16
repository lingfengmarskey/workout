#if DEBUG
import Foundation
import SwiftData

@MainActor
enum WeeklyReviewTestData {
    static func generate(
        plan: WeightLossPlan,
        bodyRecords: [DailyBodyRecord],
        mealPlans: [DailyMealPlan],
        workoutPlans: [DailyWorkoutPlan],
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws {
        let today = calendar.startOfDay(for: .now)
        let testStart = calendar.date(byAdding: .day, value: -28, to: today)!
        let shift = calendar.dateComponents([.day], from: plan.startDate, to: testStart).day ?? 0

        plan.startDate = testStart
        plan.startWeight = 97
        plan.updatedAt = .now

        bodyRecords.filter { $0.planID == plan.id }.forEach {
            $0.date = calendar.date(byAdding: .day, value: shift, to: $0.date) ?? $0.date
        }
        mealPlans.filter { $0.planID == plan.id }.forEach {
            $0.date = calendar.date(byAdding: .day, value: shift, to: $0.date) ?? $0.date
        }
        workoutPlans.filter { $0.planID == plan.id }.forEach {
            $0.date = calendar.date(byAdding: .day, value: shift, to: $0.date) ?? $0.date
        }

        let bodies = bodyRecords.filter { $0.planID == plan.id }.sorted { $0.date < $1.date }
        let meals = mealPlans.filter { $0.planID == plan.id }.sorted { $0.date < $1.date }
        let workouts = workoutPlans.filter { $0.planID == plan.id }.sorted { $0.date < $1.date }

        let testDayCount = [29, bodies.count, meals.count, workouts.count].min() ?? 0
        for day in 0..<testDayCount {
            let weight = testWeight(day: day)
            let body = bodies[day]
            body.actualWeight = day == 9 ? nil : weight // One missing value verifies that averages do not use zero.
            body.waist = day % 4 == 0 ? 105 - Double(day) * 0.12 : nil
            body.sleepHours = 6.6 + Double(day % 5) * 0.2
            body.morningEnergy = day >= 21 ? 2 + (day % 2) : 3 + (day % 3 == 0 ? 1 : 0)
            body.note = "Debug 周报测试数据 · 第 \(day + 1) 天"
            body.updatedAt = .now

            let meal = meals[day]
            meal.breakfastStatus = .completed
            meal.lunchStatus = day % 6 == 0 ? .partial : .completed
            meal.dinnerStatus = day % 9 == 0 ? .missed : .completed
            meal.snackStatus = day % 4 == 0 ? .partial : .completed
            meal.hungerLevel = day >= 21 ? 4 : 2 + day % 2
            meal.actualWater = 2.0 + Double(day % 4) * 0.15
            meal.note = "Debug 自动生成"

            let workout = workouts[day]
            workout.status = day % 7 == 3 ? .rest : (day % 5 == 0 ? .partial : .completed)
            workout.actualSteps = 7_500 + day * 110 + (day % 3) * 350
            workout.actualDurationMinutes = max(20, workout.plannedDurationMinutes - (day % 5 == 0 ? 10 : 0))
            workout.fatigueLevel = day >= 21 ? 4 + day % 2 : 2 + day % 2
            workout.painDescription = day == 25 ? "右膝轻微不适" : ""
            workout.note = "Debug 自动生成"
        }

        try context.save()
    }

    private static func testWeight(day: Int) -> Double {
        switch day {
        case 0...6: 97.0 - Double(day) * (0.8 / 6.0)       // Normal week: -0.8 kg
        case 7...13: 96.15 - Double(day - 7) * (0.2 / 6.0) // Slow week 1
        case 14...20: 95.9 - Double(day - 14) * (0.15 / 6.0) // Slow week 2: plateau advice
        default: 95.7 - Double(day - 21) * (1.35 / 7.0)     // Fast loss + fatigue advice
        }
    }
}
#endif
