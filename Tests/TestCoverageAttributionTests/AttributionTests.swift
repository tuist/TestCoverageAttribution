import Foundation
import Testing

/// Runs the fixture package's tests with attribution on and reads back what the observer wrote.
@Suite(.serialized, .timeLimit(.minutes(10)))
struct AttributionTests {
    private static let packageRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// How the fixture's tests are run: SwiftPM, or Xcode, on macOS or on an iOS simulator, which
    /// links the package statically into the test bundle and passes `TEST_RUNNER_`-prefixed
    /// variables to the test process.
    enum Runner: CaseIterable {
        case swiftPM
        case xcodebuild
        case iOSSimulator
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
        // Each test ran the code it called and none it didn't (mangled `Calculator.add` and
        // `Calculator.multiply`).
        let calculatorAdd = "10CalculatorO3add"
        let calculatorMultiply = "10CalculatorO8multiply"
        #expect(add.ran(calculatorAdd) && !add.ran(calculatorMultiply))
        #expect(xcTestOnly.ran(calculatorAdd) && !xcTestOnly.ran(calculatorMultiply))
        #expect(multiply.ran(calculatorMultiply) && !multiply.ran(calculatorAdd))
        #expect(byZero.ran(calculatorMultiply) && !byZero.ran(calculatorAdd))
        // The early return runs only when multiplying by zero.
        #expect(multiply.counters != byZero.counters)
    }

    /// Without the variable the fixture's tests pass as usual, and the observer had nowhere to write.
    @Test func runsTheTestsUnchangedWithoutAnOutputDirectory() throws {
        #expect(try runFixture(.swiftPM, attributing: false).isEmpty)
    }

    /// Recording never resets or writes the counters: SwiftPM's coverage report is the same, byte for
    /// byte, with attribution on and off.
    @Test func leavesTheCoverageReportUnchanged() throws {
        _ = try runFixture(.swiftPM, attributing: false)
        let report = try swiftPMCoverageReport()
        #expect(try !runFixture(.swiftPM, attributing: true).isEmpty)
        #expect(try swiftPMCoverageReport() == report)
    }

    /// Linked from a static archive, as Tuist links packages by default, an XCTest-only target
    /// references nothing in the package, so the linker drops the observer unless the target links
    /// with `-ObjC`, which loads every archive member that defines an Objective-C class.
    @Test(arguments: [false, true])
    func needsObjCToLinkTheObserverFromAStaticArchive(objC: Bool) throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "TestCoverageAttribution-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appending(path: "output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var environment = Self.cleanEnvironment
        environment["TEST_COVERAGE_ATTRIBUTION_DIR"] = output.path()

        try Self.execute(
            Self.packageRoot.appending(path: "Fixtures/StaticArchive/run.sh"),
            [scratch.appending(path: "build").path(), objC ? "objc" : "no-objc"],
            environment: environment,
            log: scratch.appending(path: "run.log")
        )

        let test = try Record.all(in: output).first { $0.kind == .xcTest && $0.name == "testSum" }
        #expect((test != nil) == objC)
        #expect(test?.ran("3sum") ?? !objC)
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
        var environment = Self.cleanEnvironment
        let arguments: [String]
        switch runner {
        case .swiftPM:
            environment["TEST_COVERAGE_ATTRIBUTION_DIR"] = attributing ? output.path() : nil
            arguments = [
                "swift", "test", "--package-path", fixture.path(), "--scratch-path", build.appending(path: "swiftpm").path(),
                "--enable-code-coverage",
            ] + (filter.map { ["--filter", $0] } ?? [])
        case .xcodebuild, .iOSSimulator:
            environment["TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR"] = attributing ? output.path() : nil
            let destination = runner == .iOSSimulator ? "id=\(try Self.iPhoneSimulator(fixture: fixture))" : "platform=macOS"
            arguments = [
                "xcodebuild", "test", "-scheme", "\(name)-Package", "-destination", destination,
                "-derivedDataPath", build.appending(path: "xcode").path(), "-enableCodeCoverage", "YES", "-quiet",
            ]
        }
        try Self.execute(
            URL(filePath: "/usr/bin/xcrun"),
            arguments,
            environment: environment,
            directory: fixture,
            log: scratch.appending(path: "run.log")
        )
        try inspect(output)
        return try Record.all(in: output)
    }

    /// The coverage report of the last SwiftPM run of `Fixtures/Example`.
    private func swiftPMCoverageReport() throws -> Data {
        let log = FileManager.default.temporaryDirectory.appending(path: "TestCoverageAttribution-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        try Self.execute(
            URL(filePath: "/usr/bin/xcrun"),
            [
                "swift", "test", "--package-path", Self.packageRoot.appending(path: "Fixtures/Example").path(),
                "--scratch-path", Self.packageRoot.appending(path: ".build/fixtures/Example/swiftpm").path(),
                "--show-codecov-path",
            ],
            environment: Self.cleanEnvironment,
            log: log
        )
        let output = String(bytes: try Data(contentsOf: log), encoding: .utf8) ?? ""
        let path = try #require(output.split(separator: "\n").last.map(String.init))
        return try Data(contentsOf: URL(filePath: path))
    }

    /// This process's environment without the observer's variables, which the package's own test
    /// run may have set.
    private static var cleanEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TEST_COVERAGE_ATTRIBUTION_OWNER"] = nil
        environment["TEST_COVERAGE_ATTRIBUTION_DIR"] = nil
        environment["TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR"] = nil
        return environment
    }

    /// Runs `executable` and requires it to succeed, with its output in the failure.
    private static func execute(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        directory: URL? = nil,
        log: URL
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        FileManager.default.createFile(atPath: log.path(), contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        try handle.close()
        let output = String(bytes: try Data(contentsOf: log), encoding: .utf8) ?? ""
        try #require(process.terminationStatus == 0, "\(executable.lastPathComponent) failed:\n\(output)")
    }

    /// An iPhone simulator the selected Xcode can run. Xcode lists only those its iOS platform
    /// supports, which `simctl` doesn't: a runner can have runtimes installed for other Xcodes.
    private static func iPhoneSimulator(fixture: URL) throws -> String {
        let log = FileManager.default.temporaryDirectory.appending(path: "TestCoverageAttribution-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        try execute(
            URL(filePath: "/usr/bin/xcrun"),
            ["xcodebuild", "-showdestinations", "-scheme", "\(fixture.lastPathComponent)-Package"],
            environment: cleanEnvironment,
            directory: fixture,
            log: log
        )
        // `{ platform:iOS Simulator, arch:arm64, id:<UDID>, OS:26.2, name:iPhone 17 }`
        let destinations = String(bytes: try Data(contentsOf: log), encoding: .utf8) ?? ""
        let iPhone = destinations.split(separator: "\n").first {
            $0.contains("platform:iOS Simulator") && $0.contains("name:iPhone") && !$0.contains("error:")
        }
        let id = iPhone?.split(separator: ", ").first { $0.hasPrefix("id:") }?.dropFirst(3)
        return try #require(id.map(String.init), "The selected Xcode has no iPhone simulator:\n\(destinations)")
    }
}
