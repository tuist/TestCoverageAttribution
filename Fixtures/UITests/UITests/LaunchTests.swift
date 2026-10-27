import XCTest

final class LaunchTests: XCTestCase {
    /// Activating the app it launched returns the same process, which is listed once.
    func testLaunch() {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        XCTAssertTrue(app.staticTexts["launched"].waitForExistence(timeout: 30))
        app.terminate()
    }

    /// Two launches, two processes.
    func testRelaunch() {
        let app = XCUIApplication()
        app.launch()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["launched"].waitForExistence(timeout: 30))
        app.terminate()
    }
}

/// Launched once for the class, outside any test.
final class SharedLaunchTests: XCTestCase {
    private static let app = XCUIApplication()

    override static func setUp() {
        super.setUp()
        app.launch()
    }

    override static func tearDown() {
        app.terminate()
        super.tearDown()
    }

    /// Activating the shared process leaves it listed with the class that launched it.
    func testUsesTheSharedLaunch() {
        Self.app.activate()
        XCTAssertTrue(Self.app.staticTexts["launched"].waitForExistence(timeout: 30))
    }
}
