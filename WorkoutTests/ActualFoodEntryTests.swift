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

    func testEnergyUnitConvertsKilojoulesToKcal() {
        XCTAssertEqual(FoodEnergyUnit.kJ.calories(from: 418.4), 100, accuracy: 0.0001)

        let entry = ActualFoodEntry(
            mealSlot: .lunch,
            foodName: "测试食品",
            amount: 100,
            unit: "g",
            nutritionBasisAmount: 100,
            caloriesPerBasis: FoodEnergyUnit.kJ.calories(from: 418.4),
            originalEnergyPerBasis: 418.4,
            originalEnergyUnit: .kJ
        )

        XCTAssertEqual(entry.calories, 100, accuracy: 0.0001)
        XCTAssertEqual(entry.originalEnergyPerBasis, 418.4, accuracy: 0.0001)
        XCTAssertEqual(entry.originalEnergyUnit, .kJ)
    }

    func testSodiumIsScaledWithTheNutritionBasis() {
        let entry = ActualFoodEntry(
            mealSlot: .dinner,
            foodName: "测试食品",
            amount: 200,
            unit: "g",
            nutritionBasisAmount: 100,
            caloriesPerBasis: 100,
            sodiumPerBasis: 180
        )

        XCTAssertEqual(entry.sodium ?? -1, 360, accuracy: 0.0001)
    }

    func testLegacySnapshotWithoutNewOptionalFieldsStillDecodes() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","mealSlot":"lunch","foodName":"熟米饭","amount":200,"unit":"g","nutritionBasisAmount":100,"caloriesPerBasis":116,"dataSource":"manual","isConfirmed":true}
        """
        let entry = try JSONDecoder().decode(ActualFoodEntry.self, from: Data(legacy.utf8))

        XCTAssertNil(entry.sodiumPerBasis)
        XCTAssertEqual(entry.originalEnergyUnit, .kcal)
        XCTAssertEqual(entry.calories, 232, accuracy: 0.0001)
    }

    func testTemplateReferenceDoesNotReplaceNutritionSnapshot() {
        let templateID = UUID()
        let entry = ActualFoodEntry(
            templateID: templateID,
            mealSlot: .lunch,
            foodName: "熟米饭",
            amount: 200,
            unit: "g",
            nutritionBasisAmount: 100,
            caloriesPerBasis: 116,
            proteinPerBasis: 2.6
        )

        XCTAssertEqual(entry.templateID, templateID)
        XCTAssertEqual(entry.calories, 232, accuracy: 0.0001)
    }
}
