import XCTest
@testable import Workout

final class ActualFoodEntryTests: XCTestCase {
    func testScalesEnergyAndMacrosFromTheNutritionBasis() {
        let entry = ActualFoodEntry(
            mealSlot: .lunch,
            foodName: "熟米饭",
            amount: 200,
            unit: "g",
            nutritionBasisAmount: 100,
            caloriesPerBasis: 116,
            proteinPerBasis: 2.6,
            carbohydratesPerBasis: 25.9,
            fatPerBasis: 0.3
        )

        XCTAssertEqual(entry.multiplier, 2, accuracy: 0.0001)
        XCTAssertEqual(entry.calories, 232, accuracy: 0.0001)
        XCTAssertEqual(entry.protein ?? -1, 5.2, accuracy: 0.0001)
        XCTAssertEqual(entry.carbohydrates ?? -1, 51.8, accuracy: 0.0001)
        XCTAssertEqual(entry.fat ?? -1, 0.6, accuracy: 0.0001)
    }

    func testMealPlanRoundTripsActualEntriesAndAggregatesTotals() throws {
        let meal = DailyMealPlan(
            planID: UUID(),
            date: .now,
            breakfast: "燕麦",
            lunch: "米饭和鸡胸肉",
            dinner: "鱼和蔬菜",
            snack: "酸奶",
            plannedCalories: 1_900,
            plannedProtein: 140,
            waterTarget: 2.2
        )
        let rice = ActualFoodEntry(
            mealSlot: .lunch,
            foodName: "熟米饭",
            amount: 200,
            unit: "g",
            nutritionBasisAmount: 100,
            caloriesPerBasis: 116,
            proteinPerBasis: 2.6
        )
        let chicken = ActualFoodEntry(
            mealSlot: .lunch,
            foodName: "鸡胸肉",
            amount: 100,
            unit: "g",
            nutritionBasisAmount: 100,
            caloriesPerBasis: 165,
            proteinPerBasis: 31
        )

        meal.actualFoodEntries = [rice, chicken]

        XCTAssertEqual(meal.actualFoodEntries, [rice, chicken])
        XCTAssertEqual(meal.actualCalories, 397, accuracy: 0.0001)
        XCTAssertEqual(meal.actualProtein ?? -1, 36.2, accuracy: 0.0001)
        XCTAssertNil(meal.actualCarbohydrates)
        XCTAssertNil(meal.actualFat)
    }

    func testInvalidNutritionBasisDoesNotProduceEnergy() {
        let entry = ActualFoodEntry(
            mealSlot: .snack,
            foodName: "测试",
            amount: 100,
            unit: "g",
            nutritionBasisAmount: 0,
            caloriesPerBasis: 500
        )

        XCTAssertEqual(entry.multiplier, 0)
        XCTAssertEqual(entry.calories, 0)
    }
}
