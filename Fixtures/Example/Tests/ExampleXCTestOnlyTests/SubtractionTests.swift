import Example
import XCTest

/// Links the package without importing it: XCTest needs nothing but the link.
final class SubtractionTests: XCTestCase {
    func testAddNegative() {
        XCTAssertEqual(Calculator.add(5, -3), 2)
    }
}
