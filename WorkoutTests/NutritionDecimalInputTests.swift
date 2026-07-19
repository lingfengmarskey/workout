import XCTest
@testable import Workout

final class NutritionDecimalInputTests: XCTestCase {
    func testKeepsUpToTwoFractionDigits() {
        XCTAssertEqual(NutritionDecimalInput.clamp("12.345"), "12.34")
        XCTAssertEqual(NutritionDecimalInput.clamp("0.5"), "0.5")
        XCTAssertEqual(NutritionDecimalInput.clamp("100"), "100")
    }

    func testAllowsAtMostOneSeparatorAndKeepsCommaChoice() {
        XCTAssertEqual(NutritionDecimalInput.clamp("1.2.3"), "1.23")
        XCTAssertEqual(NutritionDecimalInput.clamp("3,145"), "3,14")
    }

    func testDropsNonNumericCharacters() {
        XCTAssertEqual(NutritionDecimalInput.clamp("1a2b.3g"), "12.3")
        XCTAssertEqual(NutritionDecimalInput.clamp("12."), "12.")
    }
}
