import XCTest

func sum(_ lhs: Int, _ rhs: Int) -> Int {
    lhs + rhs
}

/// Links the observer from a static archive and references nothing in it.
final class ArchiveTests: XCTestCase {
    func testSum() {
        XCTAssertEqual(sum(2, 3), 5)
    }
}
