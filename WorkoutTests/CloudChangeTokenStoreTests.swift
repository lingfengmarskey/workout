import CloudKit
import XCTest
@testable import Workout

final class CloudChangeTokenStoreTests: XCTestCase {
    func testNilTokenRoundTrips() throws {
        XCTAssertNil(try CloudChangeTokenStore.encode(nil))
        XCTAssertNil(try CloudChangeTokenStore.decode(nil))
    }

    func testInvalidTokenDataThrowsInsteadOfResettingSilently() {
        XCTAssertThrowsError(try CloudChangeTokenStore.decode(Data("invalid".utf8)))
    }
}
