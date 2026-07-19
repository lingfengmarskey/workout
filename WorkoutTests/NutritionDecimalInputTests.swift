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

    func testInitialTextRoundsToTwoDecimalsWithoutTrailingZeros() {
        XCTAssertEqual(NutritionDecimalInput.text(from: 3.33333), "3.33")
        XCTAssertEqual(NutritionDecimalInput.text(from: 116.0), "116")
        XCTAssertEqual(NutritionDecimalInput.text(from: 0.5), "0.5")
        XCTAssertEqual(NutritionDecimalInput.text(from: 1234.0), "1234") // no grouping separators
        XCTAssertEqual(NutritionDecimalInput.text(from: Double?.none), "")
    }
}
