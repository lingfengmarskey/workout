import XCTest
@testable import Workout

final class ArrayChunkedTests: XCTestCase {
    func testSplitsIntoBatchesUnderTheLimit() {
        let items = Array(1...676)
        let chunks = items.chunked(into: CloudKitTransport.maxBatchSize)

        XCTAssertTrue(chunks.allSatisfy { $0.count <= CloudKitTransport.maxBatchSize })
        XCTAssertEqual(chunks.flatMap { $0 }, items, "order and completeness must be preserved")
        // 676 / 200 -> 200, 200, 200, 76
        XCTAssertEqual(chunks.map(\.count), [200, 200, 200, 76])
    }

    func testExactMultipleAndEmptyAndSmall() {
        XCTAssertEqual([Int]().chunked(into: 200), [])
        XCTAssertEqual([1, 2, 3].chunked(into: 200), [[1, 2, 3]])
        XCTAssertEqual([1, 2, 3, 4].chunked(into: 2), [[1, 2], [3, 4]])
    }

    func testNonPositiveSizeIsSafe() {
        XCTAssertEqual([1, 2, 3].chunked(into: 0), [[1, 2, 3]])
    }
}
