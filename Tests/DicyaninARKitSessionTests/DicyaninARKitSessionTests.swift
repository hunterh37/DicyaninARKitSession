import XCTest
@testable import DicyaninARKitSession

final class DicyaninARKitSessionTests: XCTestCase {
    /// The shared manager must be a single, reusable instance.
    func testSharedManagerIsSingleton() {
        XCTAssertTrue(ARKitSessionManager.shared === ARKitSessionManager.shared)
    }
}
