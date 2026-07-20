import XCTest
@testable import Workout

final class EquivalentActivityTests: XCTestCase {
    func testMinutesUsesStandardMETFormula() {
        // kcal/min = MET × 3.5 × weightKg / 200 = 10 × 3.5 × 100 / 200 = 17.5
        let minutes = EquivalentActivityCalculator.minutes(forCalories: 100, met: 10, weightKg: 100)
        XCTAssertEqual(minutes, 100.0 / 17.5, accuracy: 0.0001)
    }

    func testMinutesReturnsZeroForInvalidInput() {
        XCTAssertEqual(EquivalentActivityCalculator.minutes(forCalories: 0, met: 8, weightKg: 80), 0)
        XCTAssertEqual(EquivalentActivityCalculator.minutes(forCalories: 300, met: 0, weightKg: 80), 0)
        XCTAssertEqual(EquivalentActivityCalculator.minutes(forCalories: 300, met: 8, weightKg: 0), 0)
    }

    func testSuggestionsProduceRoundedIntervalFromMETRange() {
        // Single activity, weight 100 kg, energy 100 kcal.
        // gentle MET 3.5 → 16.33 min; brisk MET 5.0 → 11.43 min.
        // Floor low to 10, ceil high to 20 → "10～20 分钟".
        let walk = ReferenceActivity(name: "快走", systemImage: "figure.walk", impact: .low, minMET: 3.5, maxMET: 5.0)
        let suggestions = EquivalentActivityCalculator.suggestions(
            forCalories: 100,
            weightKg: 100,
            activities: [walk]
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].name, "快走")
        XCTAssertEqual(suggestions[0].minMinutes, 10)
        XCTAssertEqual(suggestions[0].maxMinutes, 20)
    }

    func testSuggestionLowerBoundNeverExceedsUpperBound() {
        let suggestions = EquivalentActivityCalculator.suggestions(forCalories: 232, weightKg: 88.5)
        XCTAssertFalse(suggestions.isEmpty)
        for suggestion in suggestions {
            XCTAssertLessThanOrEqual(suggestion.minMinutes, suggestion.maxMinutes)
            XCTAssertGreaterThanOrEqual(suggestion.minMinutes, 5)
        }
    }

    func testDefaultSuggestionsCoverAtLeastThreeImpactLevels() {
        let suggestions = EquivalentActivityCalculator.suggestions(forCalories: 500, weightKg: 80)
        let impacts = Set(suggestions.map(\.impact))
        XCTAssertGreaterThanOrEqual(impacts.count, 3)
        XCTAssertTrue(impacts.contains(.low))
        XCTAssertTrue(impacts.contains(.moderate))
        XCTAssertTrue(impacts.contains(.high))
    }

    func testNoSuggestionsWhenEnergyOrWeightIsMissing() {
        XCTAssertTrue(EquivalentActivityCalculator.suggestions(forCalories: 0, weightKg: 80).isEmpty)
        XCTAssertTrue(EquivalentActivityCalculator.suggestions(forCalories: 400, weightKg: 0).isEmpty)
    }
    func testPlannedActivityAdditionRoundTripsSourceLinks() throws {
        let mealID = UUID()
        let foodID = UUID()
        let addition = PlannedActivityAddition(
            sourceMealPlanID: mealID,
            sourceFoodEntryIDs: [foodID],
            activityName: "快走",
            systemImage: "figure.walk",
            impact: .low,
            durationMinutes: 25,
            estimatedCalories: 320
        )

        let data = try JSONEncoder().encode(addition)
        let decoded = try JSONDecoder().decode(PlannedActivityAddition.self, from: data)

        XCTAssertEqual(decoded, addition)
        XCTAssertEqual(decoded.sourceMealPlanID, mealID)
        XCTAssertEqual(decoded.sourceFoodEntryIDs, [foodID])
        XCTAssertEqual(decoded.durationMinutes, 25)
    }

}
