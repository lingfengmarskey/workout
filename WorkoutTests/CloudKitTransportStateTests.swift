import CloudKit
import XCTest
@testable import Workout

final class CloudKitTransportStateTests: XCTestCase {
    func testAccumulatorIsSafeForConcurrentCallbacks() {
        let accumulator = ZoneChangeAccumulator()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "cloud-transport-test", attributes: .concurrent)

        for index in 0..<200 {
            group.enter()
            queue.async {
                let id = CKRecord.ID(
                    recordName: "record-\(index)",
                    zoneID: CloudKitConstants.zoneID
                )
                accumulator.addChanged(CKRecord(recordType: "Test", recordID: id))
                group.leave()
            }
        }
        group.wait()

        XCTAssertEqual(accumulator.snapshot().changedRecords.count, 200)
    }

    func testIncompleteZoneDoesNotExposeFinalToken() {
        let accumulator = ZoneChangeAccumulator()
        accumulator.finishZone(token: nil, moreComing: true, error: nil)

        let snapshot = accumulator.snapshot()
        XCTAssertTrue(snapshot.moreComing)
        XCTAssertNil(snapshot.changeToken)
    }

    func testZoneErrorIsPreservedForRecoveryClassification() {
        let accumulator = ZoneChangeAccumulator()
        let expected = CKError(.changeTokenExpired)
        accumulator.finishZone(token: nil, moreComing: false, error: expected)

        XCTAssertEqual((accumulator.snapshot().zoneError as? CKError)?.code, .changeTokenExpired)
    }
}
