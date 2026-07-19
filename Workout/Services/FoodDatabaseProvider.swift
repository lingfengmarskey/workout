/Users/marcos/.rvm/scripts/rvm:29: operation not permitted: ps
import Foundation

/// A normalized product returned by a barcode database. Values are expressed
/// per the supplied basis (the Open Food Facts adapter uses 100 g).
struct BarcodeFoodProduct: Codable, Equatable, Identifiable {
    let barcode: String
    var id: String { barcode }
    var name: String
    var brand: String
    var basisAmount: Double
    var basisUnit: FoodNutritionBasisUnit
    var caloriesPerBasis: Double
    var proteinPerBasis: Double?
    var carbohydratesPerBasis: Double?
    var fatPerBasis: Double?
    var sodiumPerBasis: Double?

    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && basisAmount > 0
            && caloriesPerBasis >= 0
            && caloriesPerBasis.isFinite
    }
}

protocol FoodDatabaseProvider {
    func lookup(barcode: String) async throws -> BarcodeFoodProduct?
}

enum FoodDatabaseError: LocalizedError, Equatable {
    case invalidBarcode
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidBarcode: "条码格式不正确。"
        case .unavailable: "食品数据库暂时不可用。"
        case .invalidResponse: "食品数据库返回的数据不完整。"
        }
    }
}

struct FoodDatabaseConfiguration: Equatable {
    var endpoint: URL = URL(string: "https://world.openfoodfacts.org/api/v2/product/")!
    var timeout: TimeInterval = 8
}

/// Remote adapter kept behind a protocol so the UI and tests never depend on
/// a specific service. No result is written to SwiftData until the user
/// confirms it in the barcode confirmation view.
struct OpenFoodFactsProvider: FoodDatabaseProvider {
    var configuration = FoodDatabaseConfiguration()

    func lookup(barcode: String) async throws -> BarcodeFoodProduct? {
        guard BarcodeNormalizer.normalize(barcode) != nil else {
            throw FoodDatabaseError.invalidBarcode
        }
        let normalized = BarcodeNormalizer.normalize(barcode)!
        let url = configuration.endpoint.appendingPathComponent(normalized)
        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw FoodDatabaseError.unavailable
            }
            let decoded = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
            guard decoded.status == 1, let product = decoded.product else { return nil }
            let result = product.normalized(barcode: normalized)
            return result.isUsable ? result : nil
        } catch let error as FoodDatabaseError {
            throw error
        } catch {
            throw FoodDatabaseError.unavailable
        }
    }
}

/// A deterministic provider used by tests and previews. It also gives the
/// app an offline integration point without coupling the UI to HTTP.
struct InMemoryFoodDatabaseProvider: FoodDatabaseProvider {
    let products: [String: BarcodeFoodProduct]

    init(products: [BarcodeFoodProduct] = []) {
        self.products = Dictionary(uniqueKeysWithValues: products.compactMap { product in
            guard let barcode = BarcodeNormalizer.normalize(product.barcode) else { return nil }
            return (barcode, product)
        })
    }

    func lookup(barcode: String) async throws -> BarcodeFoodProduct? {
        guard let normalized = BarcodeNormalizer.normalize(barcode) else {
            throw FoodDatabaseError.invalidBarcode
        }
        return products[normalized]
    }
}

enum BarcodeNormalizer {
    static func normalize(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        guard digits == trimmed,
              (8...14).contains(digits.count) else { return nil }
        return digits
    }
}

private struct OpenFoodFactsResponse: Decodable {
    let status: Int
    let product: OpenFoodFactsProduct?
}

private struct OpenFoodFactsProduct: Decodable {
    let productName: String?
    let brands: String?
    let nutriments: OpenFoodFactsNutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case nutriments
    }

    func normalized(barcode: String) -> BarcodeFoodProduct {
        let values = nutriments ?? .init()
        let energy = values.energyKcal100g ?? values.energyKJ100g.map(FoodEnergyUnit.kJ.calories(from:)) ?? 0
        return BarcodeFoodProduct(
            barcode: barcode,
            name: productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            brand: brands?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            basisAmount: 100,
            basisUnit: .gram,
            caloriesPerBasis: energy,
            proteinPerBasis: values.protein100g,
            carbohydratesPerBasis: values.carbohydrates100g,
            fatPerBasis: values.fat100g,
            sodiumPerBasis: values.sodium100g.map { $0 * 1_000 }
        )
    }
}

private struct OpenFoodFactsNutriments: Decodable {
    let energyKcal100g: Double?
    let energyKJ100g: Double?
    let protein100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let sodium100g: Double?

    init(
        energyKcal100g: Double? = nil,
        energyKJ100g: Double? = nil,
        protein100g: Double? = nil,
        carbohydrates100g: Double? = nil,
        fat100g: Double? = nil,
        sodium100g: Double? = nil
    ) {
        self.energyKcal100g = energyKcal100g
        self.energyKJ100g = energyKJ100g
        self.protein100g = protein100g
        self.carbohydrates100g = carbohydrates100g
        self.fat100g = fat100g
        self.sodium100g = sodium100g
    }

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKJ100g = "energy_100g"
        case protein100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case sodium100g = "sodium_100g"
    }
}

