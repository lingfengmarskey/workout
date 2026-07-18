import XCTest
@testable import Workout

final class FoodTemplateTests: XCTestCase {
    func testValidTemplateExposesPersistedEnumsAndCanBeMarkedUsed() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let template = FoodTemplate(
            name: "熟米饭",
            brand: "家庭食谱",
            locale: "zh-CN",
            basisAmount: 100,
            basisUnit: .gram,
            caloriesPerBasis: 116,
            proteinPerBasis: 2.6,
            fatPerBasis: 0.3,
            carbohydratesPerBasis: 25.9,
            sodiumPerBasis: 0,
            source: .manual,
            confidence: .high,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        XCTAssertEqual(template.basisUnit, .gram)
        XCTAssertEqual(template.source, .manual)
        XCTAssertEqual(template.confidence, .high)
        XCTAssertTrue(template.isValidForSave)
        try template.validateForSave()

        let usedAt = createdAt.addingTimeInterval(60)
        template.markUsed(at: usedAt)
        XCTAssertEqual(template.lastUsedAt, usedAt)
        XCTAssertEqual(template.updatedAt, usedAt)
    }

    func testRejectsEmptyNameAndNonPositiveBasis() {
        let emptyName = FoodTemplate(
            name: "  ", basisAmount: 100, basisUnit: .gram, caloriesPerBasis: 100
        )
        XCTAssertThrowsError(try emptyName.validateForSave()) { error in
            XCTAssertEqual(error as? FoodTemplateValidationError, .emptyName)
        }

        let zeroBasis = FoodTemplate(
            name: "测试", basisAmount: 0, basisUnit: .gram, caloriesPerBasis: 100
        )
        XCTAssertThrowsError(try zeroBasis.validateForSave()) { error in
            XCTAssertEqual(error as? FoodTemplateValidationError, .invalidBasisAmount)
        }
    }

    func testRejectsNegativeOrNonFiniteNutritionValues() {
        let negativeCalories = FoodTemplate(
            name: "测试", basisAmount: 100, basisUnit: .gram, caloriesPerBasis: -1
        )
        XCTAssertThrowsError(try negativeCalories.validateForSave())
        XCTAssertEqual(negativeCalories.isValidForSave, false)

        let negativeProtein = FoodTemplate(
            name: "测试", basisAmount: 100, basisUnit: .gram, caloriesPerBasis: 100,
            proteinPerBasis: -0.1
        )
        XCTAssertThrowsError(try negativeProtein.validateForSave()) { error in
            XCTAssertEqual(error as? FoodTemplateValidationError, .invalidNutrient("蛋白质"))
        }

        let infiniteSodium = FoodTemplate(
            name: "测试", basisAmount: 100, basisUnit: .gram, caloriesPerBasis: 100,
            sodiumPerBasis: .infinity
        )
        XCTAssertThrowsError(try infiniteSodium.validateForSave()) { error in
            XCTAssertEqual(error as? FoodTemplateValidationError, .invalidNutrient("钠"))
        }
    }

    func testRejectsUnknownPersistedUnitSourceAndConfidence() {
        let template = FoodTemplate(
            name: "测试", basisAmount: 100, basisUnit: .gram, caloriesPerBasis: 100
        )
        template.basisUnitRaw = "cup"
        XCTAssertThrowsError(try template.validateForSave()) { error in
            XCTAssertEqual(error as? FoodTemplateValidationError, .unsupportedBasisUnit)
        }

        template.basisUnitRaw = FoodNutritionBasisUnit.gram.rawValue
        template.sourceRaw = "unknown"
        XCTAssertThrowsError(try template.validateForSave()) { error in
            XCTAssertEqual(error as? FoodTemplateValidationError, .unsupportedSource)
        }

        template.sourceRaw = FoodTemplateSource.manual.rawValue
        template.confidenceRaw = "unknown"
        XCTAssertThrowsError(try template.validateForSave()) { error in
            XCTAssertEqual(error as? FoodTemplateValidationError, .unsupportedConfidence)
        }
    }
}
