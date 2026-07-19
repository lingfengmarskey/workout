import XCTest
import UIKit
@testable import Workout

final class FoodPhotoEstimateTests: XCTestCase {
    func testMockProviderReturnsLowConfidenceCandidate() async throws {
        let image = UIImage(systemName: "fork.knife")!
        let candidates = try await MockFoodPhotoEstimateProvider().estimate(image: image)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].foodName, "米饭（示例估算）")
        XCTAssertEqual(candidates[0].calories, 232, accuracy: 0.001)
        XCTAssertLessThan(candidates[0].confidence, 1)
    }
}
