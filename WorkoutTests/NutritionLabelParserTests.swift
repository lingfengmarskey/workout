import XCTest
@testable import Workout

final class NutritionLabelParserTests: XCTestCase {
    func testParsesChineseLabelBasisAndNutrients() {
        let result = NutritionLabelParser.parse("每100克\n能量 418 千焦\n蛋白质 10.5克\n脂肪 2克\n碳水化合物 20克\n钠 120毫克")

        XCTAssertEqual(result.basisAmount ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(result.basisUnit, .gram)
        XCTAssertEqual(result.energyUnit, .kJ)
        XCTAssertEqual(result.calories ?? -1, 418, accuracy: 0.001)
        XCTAssertEqual(result.protein ?? -1, 10.5, accuracy: 0.001)
        XCTAssertEqual(result.carbohydrates ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(result.sodium ?? -1, 120, accuracy: 0.001)
    }

    func testParsesEnglishLabelAliasesAndServingBasis() {
        let result = NutritionLabelParser.parse("Nutrition Facts\nPer serving 30 g\nCalories 120 kcal\nProtein 4 g\nTotal Fat 3 g\nTotal Carbohydrate 15 g\nDietary Fiber 2 g\nSodium 80 mg")

        XCTAssertEqual(result.basisAmount ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(result.basisUnit, .gram)
        XCTAssertEqual(result.calories ?? -1, 120, accuracy: 0.001)
        XCTAssertEqual(result.protein ?? -1, 4, accuracy: 0.001)
        XCTAssertEqual(result.fat ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(result.fiber ?? -1, 2, accuracy: 0.001)
        XCTAssertTrue(result.overallConfidence > 0)
    }

    func testMissingEnergyOrBasisRequiresManualConfirmation() {
        let result = NutritionLabelParser.parse("Protein 5 g\nFat 2 g")

        XCTAssertNil(result.calories)
        XCTAssertFalse(result.hasRequiredNutrition)
    }

    func testParsesFullWidthDecimalPoint() {
        let result = NutritionLabelParser.parse("每100克\n能量 116 千卡\n蛋白质 10．5克")

        XCTAssertEqual(result.protein ?? -1, 10.5, accuracy: 0.001)
    }

    func testEnergyConfidenceNotBoostedWhenEnergyMissing() {
        let result = NutritionLabelParser.parse("每100克\n蛋白质 10克")

        // Energy was never parsed, so it must not appear in the confidence map.
        XCTAssertNil(result.fieldConfidences[.energy])
    }

    func testCarbohydrateLineDoesNotLeakIntoSugar() {
        let result = NutritionLabelParser.parse("每100克\n能量 116 千卡\n碳水化合物（含糖）20克")

        XCTAssertEqual(result.carbohydrates ?? -1, 20, accuracy: 0.001)
        XCTAssertNil(result.sugar)
    }

    func testStandaloneSugarRowStillParses() {
        let result = NutritionLabelParser.parse("每100克\n能量 116 千卡\n碳水化合物 20克\n糖 5克")

        XCTAssertEqual(result.carbohydrates ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(result.sugar ?? -1, 5, accuracy: 0.001)
    }
}

