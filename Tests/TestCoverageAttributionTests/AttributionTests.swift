import Foundation
import Testing

/// Runs the fixture package's tests with attribution on and reads back what the observer wrote.
@Suite(.serialized, .timeLimit(.minutes(10)))
struct AttributionTests {
    private static let packageRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// How the fixture's tests are run: SwiftPM, or Xcode, which links the package statically
    /// into the test bundle and passes `TEST_RUNNER_`-prefixed variables to the test process.
    enum Runner: CaseIterable {
        case swiftPM
        case xcodebuild
    }

    @Test(arguments: Runner.allCases)
    func attributesEachTestToTheCountersItMoved(runner: Runner) throws {
        let records = try runFixture(runner, attributing: true)
        let tests = records.filter { $0.kind != .gap }

        let add = try #require(tests.first { $0.kind == .xcTest && $0.suite == "AdditionTests" && $0.name == "testAdd" })
        let multiply = try #require(
            tests.first { $0.kind == .swiftTesting && $0.suite == "MultiplicationTests" && $0.name == "multiply()" }
        )
        // A test that declares a display name is recorded under it, as the result bundle reports it.
        let byZero = try #require(tests.first { $0.kind == .swiftTesting && $0.name == "Multiplying by zero" })
        // A test target that links the package without importing it is observed too.
        let xcTestOnly = try #require(tests.first { $0.kind == .xcTest && $0.suite == "SubtractionTests" })

        for record in [add, multiply, byZero, xcTestOnly] {
            #expect(record.version == 1)
            #expect(!record.overlapped)
            #expect(!record.counters.isEmpty)
        }
        // XCTest names the bundle, which SwiftPM builds as one for every test target.
        #expect(add.module == (runner == .swiftPM ? "ExamplePackageTests" : "ExampleTests"))
        #expect(multiply.module == "ExampleTests")
        // Each test moved its own counters: the early return runs only when multiplying by zero.
        #expect(add.counters != multiply.counters)
        #expect(multiply.counters != byZero.counters)
    }

    /// Without the variable the fixture's tests pass as usual, and the observer had nowhere to write.
    @Test func runsTheTestsUnchangedWithoutAnOutputDirectory() throws {
        #expect(try runFixture(.swiftPM, attributing: false).isEmpty)
    }

    private func runFixture(_ runner: Runner, attributing: Bool) throws -> [Record] {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "TestCoverageAttribution-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appending(path: "output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let fixture = Self.packageRoot.appending(path: "Fixtures/Example")
        let build = Self.packageRoot.appending(path: ".build/fixtures/Example")
        var environment = ProcessInfo.processInfo.environment
        environment["TEST_COVERAGE_ATTRIBUTION_OWNER"] = nil
        environment["TEST_COVERAGE_ATTRIBUTION_DIR"] = nil

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        switch runner {
        case .swiftPM:
            environment["TEST_COVERAGE_ATTRIBUTION_DIR"] = attributing ? output.path() : nil
            process.arguments = [
                "swift", "test", "--package-path", fixture.path(), "--scratch-path", build.appending(path: "swiftpm").path(),
                "--enable-code-coverage",
            ]
        case .xcodebuild:
            environment["TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR"] = attributing ? output.path() : nil
            process.currentDirectoryURL = fixture
            process.arguments = [
                "xcodebuild", "test", "-scheme", "Example-Package", "-destination", "platform=macOS",
                "-derivedDataPath", build.appending(path: "xcode").path(), "-enableCodeCoverage", "YES", "-quiet",
            ]
        }
        process.environment = environment
        let log = scratch.appending(path: "swift-test.log")
        FileManager.default.createFile(atPath: log.path(), contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        try handle.close()
        let logContents = String(decoding: try Data(contentsOf: log), as: UTF8.self)
        try #require(process.terminationStatus == 0, "swift test failed:\n\(logContents)")
        return try Record.all(in: output)
    }
}
