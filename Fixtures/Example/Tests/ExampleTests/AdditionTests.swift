import Example
import XCTest

final class AdditionTests: XCTestCase {
    func testAdd() {
        XCTAssertEqual(Calculator.add(2, 3), 5)
    }
}
