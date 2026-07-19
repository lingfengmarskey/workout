/Users/marcos/.rvm/scripts/rvm:29: operation not permitted: ps
import XCTest
@testable import Workout

final class FoodDatabaseProviderTests: XCTestCase {
    func testBarcodeNormalizerAcceptsCommonLengthsAndRejectsInvalidInput() {
        XCTAssertEqual(BarcodeNormalizer.normalize(" 4901234567894 "), "4901234567894")
        XCTAssertEqual(BarcodeNormalizer.normalize("012345678901"), "012345678901")
        XCTAssertNil(BarcodeNormalizer.normalize("1234"))
        XCTAssertNil(BarcodeNormalizer.normalize("49012A4567894"))
    }

    func testInMemoryProviderNormalizesLookupAndReturnsProduct() async throws {
        let product = BarcodeFoodProduct(
            barcode: "4901234567894",
            name: "测试食品",
            brand: "测试品牌",
            basisAmount: 100,
            basisUnit: .gram,
            caloriesPerBasis: 120,
            proteinPerBasis: 4,
            carbohydratesPerBasis: 20,
            fatPerBasis: 2,
            sodiumPerBasis: 100
        )
        let provider = InMemoryFoodDatabaseProvider(products: [product])

        let result = try await provider.lookup(barcode: "4901234567894")

        XCTAssertEqual(result, product)
    }

    func testInMemoryProviderReturnsNilForUnknownBarcode() async throws {
        let provider = InMemoryFoodDatabaseProvider()
        let result = try await provider.lookup(barcode: "4901234567894")
        XCTAssertNil(result)
    }

    func testProductRequiresNameAndValidEnergy() {
        var product = BarcodeFoodProduct(
            barcode: "4901234567894",
            name: "",
            brand: "",
            basisAmount: 100,
            basisUnit: .gram,
            caloriesPerBasis: 120,
            proteinPerBasis: nil,
            carbohydratesPerBasis: nil,
            fatPerBasis: nil,
            sodiumPerBasis: nil
        )
        XCTAssertFalse(product.isUsable)
        product.name = "测试食品"
        XCTAssertTrue(product.isUsable)
    }
}

