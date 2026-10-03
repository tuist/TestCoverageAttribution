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

    /// Two tests that run at the same time are both marked overlapped, including the one that
    /// ends last, whose record would otherwise miss what it ran before the other ended.
    @Test func marksEveryOverlappingTestAsOverlapped() throws {
        let records = try runFixture(.swiftPM, attributing: true, fixture: "Concurrency", filter: "OverlapTests")
        let tests = records.filter { $0.kind == .swiftTesting && $0.suite == "OverlapTests" }

        #expect(tests.map(\.name).sorted() == ["first()", "second()"])
        #expect(tests.map(\.overlapped) == [true, true])
    }

    /// Once no scope is active the overlap is over: a scope that starts after it is clean again.
    @Test func clearsTheOverlapOnceNoScopeIsActive() throws {
        let records = try runFixture(.swiftPM, attributing: true, fixture: "Concurrency", filter: "ScopeSequenceTests")
        let scopes = records.filter { $0.kind == .swiftTesting && $0.suite == "ScopeSequenceTests" }

        #expect(scopes.map { "\($0.name): \($0.overlapped ? "overlapped" : "clean")" } == [
            "a: overlapped", "b: overlapped", "c: clean",
        ])
        #expect(scopes.last?.counters.isEmpty == false)
    }

    /// When part of an image can't be written the observer removes what it wrote for the process,
    /// so a reader finds no output instead of records whose counters it can't map to functions.
    @Test func removesTheOutputWhenAnImageCannotBeWritten() throws {
        var processes: [Set<String>] = []
        let records = try runFixture(.swiftPM, attributing: true, fixture: "Concurrency", filter: "OutputFailureTests") {
            processes = try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
                .map { try Set(FileManager.default.contentsOfDirectory(atPath: $0.path())) }
        }

        // The fixture's test ran: it left `0.names` as a directory in its process, and the observer
        // removed what it had written there.
        #expect(processes.contains { $0.contains("0.names") && !$0.contains("images.tsv") && !$0.contains("records.bin") })
        #expect(records.isEmpty)
    }

    /// The trait on a suite and on a suite nested in it opens one scope per test, not one per trait.
    @Test func recordsOneScopePerTestWhenNestedSuitesBothHaveTheTrait() throws {
        let records = try runFixture(.swiftPM, attributing: true, fixture: "Concurrency", filter: "Outer")
        let tests = records.filter { $0.kind == .swiftTesting && $0.name == "nested()" }

        try #require(tests.count == 1)
        #expect(!tests[0].overlapped)
        #expect(!tests[0].counters.isEmpty)
    }

    /// Runs one of the packages under `Fixtures`; with SwiftPM, only the tests `filter` matches.
    /// `inspect` gets the output directory before it is removed.
    /// `Concurrency` is a package of its own: Swift Testing runs suites in parallel across the
    /// process, so its tests would overlap the others.
    private func runFixture(
        _ runner: Runner,
        attributing: Bool,
        fixture name: String = "Example",
        filter: String? = nil,
        inspect: (URL) throws -> Void = { _ in }
    ) throws -> [Record] {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "TestCoverageAttribution-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appending(path: "output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let fixture = Self.packageRoot.appending(path: "Fixtures/\(name)")
        let build = Self.packageRoot.appending(path: ".build/fixtures/\(name)")
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
            ] + (filter.map { ["--filter", $0] } ?? [])
        case .xcodebuild:
            environment["TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR"] = attributing ? output.path() : nil
            process.currentDirectoryURL = fixture
            process.arguments = [
                "xcodebuild", "test", "-scheme", "\(name)-Package", "-destination", "platform=macOS",
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
        try inspect(output)
        return try Record.all(in: output)
    }
}
