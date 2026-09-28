import XCTest
@testable import SiliconPulse

final class BatteryHealthTests: XCTestCase {
    func testNominalCapacityHealthIsBetweenZeroAndOne() {
        let health = BatteryCollector.health(nominal: 8200, design: 9000)
        XCTAssertNotNil(health)
        XCTAssertGreaterThan(health!, 0)
        XCTAssertLessThan(health!, 1)
    }
}
