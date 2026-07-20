import XCTest
@testable import Workout

private struct ScriptedProvider: FoodDatabaseProvider {
    let result: Result<BarcodeFoodProduct?, Error>
    final class Counter { var calls = 0 }
    let counter = Counter()

    func lookup(barcode: String) async throws -> BarcodeFoodProduct? {
        counter.calls += 1
        return try result.get()
    }
}

final class CachingFoodDatabaseProviderTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: BarcodeCacheStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CachingFoodDatabaseProviderTests")!
        defaults.removePersistentDomain(forName: "CachingFoodDatabaseProviderTests")
        store = BarcodeCacheStore(defaults: defaults)
    }

    private func product(_ barcode: String) -> BarcodeFoodProduct {
        BarcodeFoodProduct(
            barcode: barcode,
            name: "牛奶",
            brand: "测试",
            basisAmount: 100,
            basisUnit: .gram,
            caloriesPerBasis: 42,
            proteinPerBasis: 3.4,
            carbohydratesPerBasis: 5,
            fatPerBasis: 1,
            sodiumPerBasis: 40
        )
    }

    func testFreshCacheHitSkipsTheNetwork() async throws {
        store.save(product("6901234567890"), for: "6901234567890")
        let base = ScriptedProvider(result: .success(nil))
        let caching = CachingFoodDatabaseProvider(base: base, store: store)

        let result = try await caching.lookup(barcode: "6901234567890")

        XCTAssertEqual(result?.name, "牛奶")
        XCTAssertEqual(base.counter.calls, 0, "a fresh cache hit must not call the base provider")
    }

    func testSuccessfulLookupIsCached() async throws {
        let base = ScriptedProvider(result: .success(product("6901234567890")))
        let caching = CachingFoodDatabaseProvider(base: base, store: store)

        _ = try await caching.lookup(barcode: "6901234567890")

        XCTAssertNotNil(store.load(for: "6901234567890", maxAge: .infinity))
    }

    func testFallsBackToStaleCacheWhenBaseFails() async throws {
        store.save(product("6901234567890"), for: "6901234567890")
        // maxAge 0 forces the cached entry to count as stale, so the provider must
        // query the base, which fails, and then fall back to the stale copy.
        let base = ScriptedProvider(result: .failure(FoodDatabaseError.unavailable))
        let caching = CachingFoodDatabaseProvider(base: base, store: store, maxAge: 0)

        let result = try await caching.lookup(barcode: "6901234567890")

        XCTAssertEqual(result?.name, "牛奶")
        XCTAssertEqual(base.counter.calls, 1)
    }

    func testFailureWithoutCacheStillThrows() async {
        let base = ScriptedProvider(result: .failure(FoodDatabaseError.unavailable))
        let caching = CachingFoodDatabaseProvider(base: base, store: store)

        do {
            _ = try await caching.lookup(barcode: "6901234567890")
            XCTFail("expected the error to propagate when there is no cache")
        } catch {
            XCTAssertEqual(error as? FoodDatabaseError, .unavailable)
        }
    }
}
