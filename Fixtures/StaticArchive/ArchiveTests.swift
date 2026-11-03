import XCTest

func sum(_ lhs: Int, _ rhs: Int) -> Int {
    lhs + rhs
}

/// Links the observer from a static archive and references nothing in it.
final class ArchiveTests: XCTestCase {
    func testSum() {
        XCTAssertEqual(sum(2, 3), 5)
    }

    /// Listed in the skip list when the bundle links with `-ObjC`, so it runs only without it.
    func testSkipped() {
        XCTAssertNil(ProcessInfo.processInfo.environment["TEST_COVERAGE_ATTRIBUTION_SKIP_FILE"])
    }
}
