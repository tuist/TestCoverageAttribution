import TestCoverageAttribution
import Testing
import XCTest

// Unit tests hosted in the app, run by `AttributionTests` with a skip list that names every test
// called `testSkipped…` and every test of `SkippedTests`. The listed tests pass when they run, so
// a run with or without the list succeeds and the result bundle tells which ran; only a class
// setUp that must not run crashes.

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

    func testSkipped() {}

    /// Listed as `testSkippedThrowing()`; its selector is `testSkippedThrowingAndReturnError:`.
    func testSkippedThrowing() throws {}

    /// Listed as `testSkippedAsync`; its selector is `testSkippedAsyncWithCompletionHandler:`.
    func testSkippedAsync() async {}
}

/// All of its tests are listed: the class doesn't run, not even its class setUp.
final class SkippedTests: XCTestCase {
    override static func setUp() {
        super.setUp()
        fatalError("A class whose tests are all listed doesn't run its class setUp")
    }

    func testFirst() {}

    func testSecond() {}
}

final class UnlistedTests: XCTestCase {
    func testRuns() {}
}

/// The trait cancels the listed tests from Swift 6.3 on, which reports them as skipped; before,
/// they run.
@Suite(.coverageAttribution)
struct SwiftTestingTests {
    @Test func runs() {}

    @Test func skipped() {}

    @Test(arguments: [1, 2]) func skippedWithArguments(value _: Int) {}
}

/// Listed too, but without the trait nothing reads the list, so it runs.
struct UntraitedSwiftTestingTests {
    @Test func runs() {}
}
