import XCTest

// UI tests run by `AttributionTests` with a skip list that names every test called `testSkipped`
// and every test of `SkippedUITests`. The listed tests pass when they run, so the result bundle
// tells which ran; only a class setUp that must not run crashes.

final class PartlySkippedUITests: XCTestCase {
    func testLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["launched"].waitForExistence(timeout: 30))
        app.terminate()
    }

    func testSkipped() {}
}

/// All of its tests are listed: the class doesn't run, not even its class setUp.
final class SkippedUITests: XCTestCase {
    override static func setUp() {
        super.setUp()
        fatalError("A class whose tests are all listed doesn't run its class setUp")
    }

    func testSkipped() {}
}
