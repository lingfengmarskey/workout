import XCTest
@testable import Workout

final class CompoundMealTests: XCTestCase {
    func testNutritionAggregatesComponentsUsingTheirActualAmounts() {
        let rice = CompoundMealComponent(
            foodName: "米饭",
            amount: 200,
            unit: "g",
            basisAmount: 100,
            caloriesPerBasis: 116,
            proteinPerBasis: 2.6
        )
        let chicken = CompoundMealComponent(
            foodName: "鸡胸肉",
            amount: 100,
            unit: "g",
            basisAmount: 100,
            caloriesPerBasis: 133,
            proteinPerBasis: 23.3
        )

        let nutrition = CompoundMealCalculator.nutrition(for: [rice, chicken])

        XCTAssertEqual(nutrition.calories, 365, accuracy: 0.001)
        XCTAssertEqual(nutrition.protein ?? 0, 28.5, accuracy: 0.001)
    }

    func testServingScalingScalesAllAvailableNutrients() {
        let component = CompoundMealComponent(
            foodName: "燕麦",
            amount: 50,
            unit: "g",
            basisAmount: 100,
            caloriesPerBasis: 380,
            proteinPerBasis: 13,
            carbohydratesPerBasis: 68,
            fatPerBasis: 7
        )

        let nutrition = CompoundMealCalculator.nutrition(for: [component]).scaled(by: 1.5)

        XCTAssertEqual(nutrition.calories, 285, accuracy: 0.001)
        XCTAssertEqual(nutrition.protein ?? 0, 9.75, accuracy: 0.001)
        XCTAssertEqual(nutrition.carbohydrates ?? 0, 51, accuracy: 0.001)
        XCTAssertEqual(nutrition.fat ?? 0, 5.25, accuracy: 0.001)
    }

    func testCompoundTemplateRoundTripsComponentJSON() throws {
        let components = [
            CompoundMealComponent(
                foodName: "米饭",
                amount: 150,
                unit: "g",
                basisAmount: 100,
                caloriesPerBasis: 116
            )
        ]
        let template = CompoundMealTemplate(name: "鸡肉饭", components: components)

        XCTAssertEqual(template.components, components)
        XCTAssertEqual(template.nutrition.calories, 174, accuracy: 0.001)
    }
}
