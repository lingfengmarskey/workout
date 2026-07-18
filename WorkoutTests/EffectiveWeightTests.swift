import XCTest
@testable import Workout

final class EffectiveWeightTests: XCTestCase {
    private let calendar = Calendar.current
    private let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    private func makePlan() -> WeightLossPlan {
        WeightLossPlan(
            name: "测试计划",
            startDate: start,
            durationDays: 56,
            startWeight: 100,
            phaseTargetWeight: 90,
            finalTargetWeight: 88.5,
            dailyCalorieTarget: 1_900,
            dailyProteinTarget: 140,
            dailyWaterTarget: 2.2
        )
    }

    private func record(for plan: WeightLossPlan, dayOffset: Int, weight: Double?) -> DailyBodyRecord {
        let record = DailyBodyRecord(planID: plan.id, date: day(dayOffset))
        record.actualWeight = weight
        return record
    }

    func testUsesMostRecentPriorWeightWhenTargetDayHasNoRecord() {
        let plan = makePlan()
        let records = [
            record(for: plan, dayOffset: 2, weight: 98.0),
            record(for: plan, dayOffset: 6, weight: 95.0)
        ]

        // Day 10 has no record; should fall back to the day-6 weight, not the projection.
        XCTAssertEqual(plan.effectiveWeight(on: day(10), from: records), 95.0, accuracy: 0.0001)
    }

    func testUsesSameDayRecordWhenPresent() {
        let plan = makePlan()
        let records = [
            record(for: plan, dayOffset: 2, weight: 98.0),
            record(for: plan, dayOffset: 6, weight: 95.0)
        ]

        XCTAssertEqual(plan.effectiveWeight(on: day(6), from: records), 95.0, accuracy: 0.0001)
    }

    func testIgnoresFutureRecordsAfterTargetDay() {
        let plan = makePlan()
        let records = [
            record(for: plan, dayOffset: 2, weight: 98.0),
            record(for: plan, dayOffset: 20, weight: 92.0)
        ]

        // At day 5 only the day-2 record is in range.
        XCTAssertEqual(plan.effectiveWeight(on: day(5), from: records), 98.0, accuracy: 0.0001)
    }

    func testIgnoresRecordsFromOtherPlans() {
        let plan = makePlan()
        let otherPlanRecord = DailyBodyRecord(planID: UUID(), date: day(3))
        otherPlanRecord.actualWeight = 80.0

        // No matching record → falls back to this plan's projected weight, not 80.
        let projected = plan.plannedWeight(on: day(10))
        XCTAssertEqual(plan.effectiveWeight(on: day(10), from: [otherPlanRecord]), projected, accuracy: 0.0001)
    }

    func testFallsBackToProjectedWeightWhenNoRecordsExist() {
        let plan = makePlan()
        XCTAssertEqual(
            plan.effectiveWeight(on: day(10), from: []),
            plan.plannedWeight(on: day(10)),
            accuracy: 0.0001
        )
    }

    func testSkipsRecordsWithoutWeight() {
        let plan = makePlan()
        let records = [
            record(for: plan, dayOffset: 2, weight: 98.0),
            record(for: plan, dayOffset: 8, weight: nil) // logged waist only, no weight
        ]

        // Day 8's record has no weight, so the day-2 weight should still be used.
        XCTAssertEqual(plan.effectiveWeight(on: day(10), from: records), 98.0, accuracy: 0.0001)
    }
}
