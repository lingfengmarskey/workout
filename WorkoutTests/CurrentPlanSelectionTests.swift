import XCTest
@testable import Workout

final class CurrentPlanSelectionTests: XCTestCase {
    func testMultipleActivePlansRequireExplicitSelection() {
        let plans = [makePlan(name: "A"), makePlan(name: "B")]

        XCTAssertNil(CurrentPlanSelection.resolve(from: plans, storedID: ""))
    }

    func testStoredSelectionResolvesOnlyToAnActivePlan() {
        let active = makePlan(name: "Active")
        let paused = makePlan(name: "Paused", status: .paused)

        XCTAssertEqual(
            CurrentPlanSelection.resolve(from: [active, paused], storedID: active.id.uuidString)?.id,
            active.id
        )
        XCTAssertNil(CurrentPlanSelection.resolve(from: [active, paused], storedID: paused.id.uuidString))
    }

    func testMissingSelectionRequiresExplicitChoice() {
        let plan = makePlan(name: "Only plan")

        XCTAssertNil(CurrentPlanSelection.resolve(from: [plan], storedID: ""))
    }

    private func makePlan(name: String, status: PlanStatus = .active) -> WeightLossPlan {
        WeightLossPlan(
            name: name,
            startDate: .now,
            durationDays: 56,
            startWeight: 97,
            phaseTargetWeight: 88.5,
            finalTargetWeight: 80,
            dailyCalorieTarget: 1900,
            dailyProteinTarget: 140,
            dailyWaterTarget: 2.3,
            status: status
        )
    }
}
