import Testing
import XCTest

// Unit tests hosted in the app, run by `AttributionTests` with a skip list that names every test
// called `testSkipped…` and every test of `SkippedTests`: those fail if they run.

/// Some of its tests are listed: the rest run, after the class setUp.
final class PartlySkippedTests: XCTestCase {
    nonisolated(unsafe) static var classSetUpRan = false

    override static func setUp() {
        super.setUp()
        classSetUpRan = true
    }

    func testRuns() {
        XCTAssertTrue(Self.classSetUpRan)
    }

    func testSkipped() {
        XCTFail("Listed in the skip list")
    }

    /// Listed as `testSkippedThrowing()`; its selector is `testSkippedThrowingAndReturnError:`.
    func testSkippedThrowing() throws {
        XCTFail("Listed in the skip list")
    }

    /// Listed as `testSkippedAsync`; its selector is `testSkippedAsyncWithCompletionHandler:`.
    func testSkippedAsync() async {
        XCTFail("Listed in the skip list")
    }
}

/// All of its tests are listed: the class doesn't run, not even its class setUp.
final class SkippedTests: XCTestCase {
    override static func setUp() {
        super.setUp()
        fatalError("A class whose tests are all listed doesn't run its class setUp")
    }

    func testFirst() {
        XCTFail("Listed in the skip list")
    }

    func testSecond() {
        XCTFail("Listed in the skip list")
    }
}

final class UnlistedTests: XCTestCase {
    func testRuns() {}
}

/// Listed too, but Swift Testing tests don't go through XCTest's suites, so it runs.
struct SwiftTestingTests {
    @Test func runs() {}
}
