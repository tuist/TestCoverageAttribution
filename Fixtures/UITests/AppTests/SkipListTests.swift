import TestCoverageAttribution
import Testing
import XCTest

// Unit tests hosted in the app, run by `AttributionTests` with a skip list that names every test
// called `testSkipped…`, every test of `SkippedTests` and every test marked unskippable. The listed
// tests pass when they run, so a run with or without the list succeeds and the result bundle tells
// which ran; only a class setUp that must not run crashes.

/// Some of its tests are listed: the rest run, after the class setUp, and so does the listed one it
/// marks unskippable.
final class PartlySkippedTests: XCTestCase {
    nonisolated(unsafe) static var classSetUpRan = false

    /// Named as the skip list names it, and as its selector.
    @objc static let unskippableTests = ["testUnskippable()", "testUnskippableThrowingAndReturnError:"]

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

    func testUnskippable() {
        XCTAssertTrue(Self.classSetUpRan)
    }

    func testUnskippableThrowing() throws {}
}

/// All of its tests are listed, but the class is unskippable: they run, after the class setUp,
/// except the one it lets the list skip.
final class UnskippableTests: XCTestCase {
    nonisolated(unsafe) static var classSetUpRan = false

    @objc static let isUnskippable = true
    @objc static let skippableTests = ["testSkippable"]

    override static func setUp() {
        super.setUp()
        classSetUpRan = true
    }

    func testFirst() {
        XCTAssertTrue(Self.classSetUpRan)
    }

    func testSecond() {}

    func testSkippable() {}
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
/// they run. A listed test marked unskippable runs.
@Suite(.coverageAttribution)
struct SwiftTestingTests {
    @Test func runs() {}

    @Test func skipped() {}

    @Test(arguments: [1, 2]) func skippedWithArguments(value _: Int) {}

    @Test(.unskippable) func unskippable() {}
}

/// Every test is listed. The suite is unskippable, so they run, except the one that opts back in
/// and the tests of the nested suite that does.
@Suite(.coverageAttribution, .unskippable)
struct UnskippableSwiftTestingTests {
    @Test func runs() {}

    @Test(.skippable) func skipped() {}

    @Suite(.skippable)
    struct SkippableTests {
        @Test func skipped() {}

        @Test(.unskippable) func unskippable() {}
    }
}

/// Listed too, but without the trait nothing reads the list, so it runs.
struct UntraitedSwiftTestingTests {
    @Test func runs() {}
}
