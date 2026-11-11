import Foundation
import Testing

extension AttributionTests {
    /// How Xcode runs the tests: one process per target, clones that each get some classes, or a
    /// sharded run's slice of prebuilt tests (`test-without-building` with `-only-testing`).
    enum SkipListRun: CaseIterable {
        case serial
        case parallel
        case shard
    }

    /// The listed XCTest tests of a unit test target hosted in the app and of a UI test target
    /// don't run: they aren't in the result bundle, and a class whose tests are all listed doesn't
    /// run its class `setUp`, which crashes. The tests left run, after their class `setUp`. Built
    /// with Swift 6.3 or later, the listed Swift Testing tests of a suite with the trait are
    /// skipped, every argument of a parameterized one included; before, they run. A listed Swift
    /// Testing test without the trait runs.
    ///
    /// Listed tests marked unskippable run, and `unskippable.tsv` lists them as listed: XCTest
    /// tests a class names in `unskippableTests`, every test of a class with `isUnskippable` but
    /// those it names in `skippableTests`, and Swift Testing tests marked `.unskippable` or in a
    /// suite that is, unless a test or a nested suite opts back in with `.skippable`.
    @Test(arguments: SkipListRun.allCases)
    func skipsTheListedTests(run: SkipListRun) throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "TestCoverageAttribution-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let skipList = scratch.appending(path: "skip.txt")
        // Names in each form the list accepts, and a blank line, a module alone and a test that
        // doesn't exist, which are ignored.
        try """
        AppTests/PartlySkippedTests/testSkipped()
        AppTests/PartlySkippedTests/testSkippedThrowing()
        AppTests/PartlySkippedTests/testSkippedAsync
        AppTests/PartlySkippedTests/testUnskippable()
        AppTests/PartlySkippedTests/testUnskippableThrowing()

        AppTests/SkippedTests/testFirst()
        AppTests/SkippedTests/testSecond()
        AppTests/UnskippableTests/testFirst()
        AppTests/UnskippableTests/testSecond()
        AppTests/UnskippableTests/testSkippable()
        AppTests/SwiftTestingTests/skipped()
        AppTests/SwiftTestingTests/skippedWithArguments(value:)
        AppTests/SwiftTestingTests/unskippable()
        AppTests/UnskippableSwiftTestingTests/runs()
        AppTests/UnskippableSwiftTestingTests/skipped()
        AppTests/UnskippableSwiftTestingTests/SkippableTests/skipped()
        AppTests/UnskippableSwiftTestingTests/SkippableTests/unskippable()
        AppTests/UntraitedSwiftTestingTests/runs()
        AppTests/UnlistedTests
        AppTests/MissingTests/testMissing()
        SkipUITests/PartlySkippedUITests/testSkipped()
        SkipUITests/PartlySkippedUITests/testUnskippable()
        SkipUITests/SkippedUITests/testSkipped()
        """.write(to: skipList, atomically: true, encoding: .utf8)
        let resultBundle = scratch.appending(path: "Tests.xcresult")
        let output = scratch.appending(path: "output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try runSkipListScheme(run, skipList: skipList, resultBundle: resultBundle, output: output)

        let results = try Self.testResults(in: resultBundle)
        #expect(results.map(\.description).sorted() == Self.expectedResults(run))
        let unskippable = try Self.unskippableTests(in: output)
        #expect(unskippable == Self.expectedUnskippable(run))
    }

    /// The tests `skipsTheListedTests` expects in the result bundle, and how they end. A shard runs
    /// its `-only-testing` classes alone, and no Swift Testing test.
    private static func expectedResults(_ run: SkipListRun) -> [String] {
        #if compiler(>=6.3)
            let listedSwiftTesting = "Skipped"
        #else
            let listedSwiftTesting = "Passed"
        #endif
        var results = [
            "AppTests/PartlySkippedTests/testRuns() Passed",
            "AppTests/PartlySkippedTests/testUnskippable() Passed",
            "AppTests/PartlySkippedTests/testUnskippableThrowing() Passed",
            "AppTests/UnskippableTests/testFirst() Passed",
            "AppTests/UnskippableTests/testSecond() Passed",
            "SkipUITests/PartlySkippedUITests/testLaunch() Passed",
            "SkipUITests/PartlySkippedUITests/testUnskippable() Passed",
        ]
        if run != .shard {
            results += [
                "AppTests/SwiftTestingTests/runs() Passed",
                "AppTests/SwiftTestingTests/skipped() \(listedSwiftTesting)",
                "AppTests/SwiftTestingTests/skippedWithArguments(value:) \(listedSwiftTesting)",
                "AppTests/SwiftTestingTests/unskippable() Passed",
                "AppTests/UnlistedTests/testRuns() Passed",
                "AppTests/UnskippableSwiftTestingTests/SkippableTests/skipped() \(listedSwiftTesting)",
                "AppTests/UnskippableSwiftTestingTests/SkippableTests/unskippable() Passed",
                "AppTests/UnskippableSwiftTestingTests/runs() Passed",
                "AppTests/UnskippableSwiftTestingTests/skipped() \(listedSwiftTesting)",
                "AppTests/UntraitedSwiftTestingTests/runs() Passed",
            ]
        }
        return results.sorted()
    }

    /// The lines `skipsTheListedTests` expects in `unskippable.tsv`, every test listed, named as
    /// the records name them: XCTest tests as XCTest names them, without `()` or a bridged suffix,
    /// and Swift Testing tests under every suite they're nested in.
    private static func expectedUnskippable(_ run: SkipListRun) -> [String] {
        var lines = [
            "AppTests\tPartlySkippedTests\ttestUnskippable\t1",
            "AppTests\tPartlySkippedTests\ttestUnskippableThrowing\t1",
            "AppTests\tUnskippableTests\ttestFirst\t1",
            "AppTests\tUnskippableTests\ttestSecond\t1",
            "SkipUITests\tPartlySkippedUITests\ttestUnskippable\t1",
        ]
        if run != .shard {
            lines += [
                "AppTests\tUnskippableSwiftTestingTests/SkippableTests\tunskippable()\t1",
                "AppTests\tSwiftTestingTests\tunskippable()\t1",
                "AppTests\tUnskippableSwiftTestingTests\truns()\t1",
            ]
        }
        return lines.sorted()
    }

    /// Built with Swift 6.3 or later, the trait cancels a listed Swift Testing test before it
    /// starts, so it leaves no record; before, it runs. The list names it by its display name. A
    /// test marked `.unskippable`, or in a suite that is, runs, unless it opts back in with
    /// `.skippable`, and `unskippable.tsv` lists it, listed or not.
    @Test func skipsTheListedSwiftTestingTests() throws {
        var unskippable: [String] = []
        let records = try runFixture(
            .swiftPM,
            attributing: true,
            skipList: """
            ExampleTests/MultiplicationTests/Multiplying by zero
            ExampleTests/MultiplicationTests/multiplyByOne()
            ExampleTests/MultiplicationTests/UnskippableMultiplicationTests/multiplyNegatives()
            ExampleTests/MultiplicationTests/UnskippableMultiplicationTests/square()
            """,
        ) { unskippable = try Self.unskippableTests(in: $0) }
        let names = records.filter { $0.kind == .swiftTesting }.map(\.name)

        #expect(names.contains("multiply()"))
        // Unskippable, the test or its suite: it runs.
        #expect(names.contains("multiplyByOne()"))
        #expect(names.contains("multiplyNegatives()"))
        #expect(names.contains("multiplyByMinusOne()"))
        #if compiler(>=6.3)
            #expect(!names.contains("Multiplying by zero"))
            // Opts back in under the unskippable suite.
            #expect(!names.contains("square()"))
        #else
            #expect(names.contains("Multiplying by zero"))
            #expect(names.contains("square()"))
        #endif
        #expect(unskippable == [
            "ExampleTests\tMultiplicationTests\tmultiplyByOne()\t1",
            "ExampleTests\tMultiplicationTests/UnskippableMultiplicationTests\tmultiplyByMinusOne()\t0",
            "ExampleTests\tMultiplicationTests/UnskippableMultiplicationTests\tmultiplyNegatives()\t1",
        ])
    }

    /// Without a skip list, every test runs, those the list would name included.
    @Test func runsEveryTestWithoutASkipList() throws {
        let fixture = Self.packageRoot.appending(path: "Fixtures/UITests")
        let simulator = try Self.iPhoneSimulator(fixture: Self.packageRoot.appending(path: "Fixtures/Example"))
        try Self.execute(URL(filePath: "/usr/bin/xcrun"), ["simctl", "bootstatus", simulator, "-b"])
        try Self.execute(URL(filePath: "/usr/bin/env"), ["tuist", "generate", "--no-open"], directory: fixture)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "TestCoverageAttribution-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let resultBundle = scratch.appending(path: "Tests.xcresult")

        // Only a class whose class setUp doesn't crash.
        try Self.execute(
            URL(filePath: "/usr/bin/xcrun"),
            [
                "xcodebuild", "test", "-workspace", "UITests.xcworkspace", "-scheme", "SkipList",
                "-destination", "id=\(simulator)", "-derivedDataPath",
                Self.packageRoot.appending(path: ".build/fixtures/UITests/skip-list").path(),
                "-resultBundlePath", resultBundle.path(), "-quiet", "-parallel-testing-enabled", "NO",
                "-only-testing:AppTests/PartlySkippedTests",
            ],
            directory: fixture,
            timeout: Self.xcodebuildTimeout,
        )
        let results = try Self.testResults(in: resultBundle)
        #expect(results.map(\.description).sorted() == [
            "AppTests/PartlySkippedTests/testRuns() Passed",
            "AppTests/PartlySkippedTests/testSkipped() Passed",
            "AppTests/PartlySkippedTests/testSkippedAsync() Passed",
            "AppTests/PartlySkippedTests/testSkippedThrowing() Passed",
            "AppTests/PartlySkippedTests/testUnskippable() Passed",
            "AppTests/PartlySkippedTests/testUnskippableThrowing() Passed",
        ])
    }

    /// Generates `Fixtures/UITests` and runs its `SkipList` scheme on an iPhone simulator, the way
    /// `run` says, with the skip list, writing its output to `output`.
    private func runSkipListScheme(_ run: SkipListRun, skipList: URL, resultBundle: URL, output: URL) throws {
        let fixture = Self.packageRoot.appending(path: "Fixtures/UITests")
        let derivedData = Self.packageRoot.appending(path: ".build/fixtures/UITests/skip-list")
        let simulator = try Self.iPhoneSimulator(fixture: Self.packageRoot.appending(path: "Fixtures/Example"))
        try Self.execute(URL(filePath: "/usr/bin/xcrun"), ["simctl", "bootstatus", simulator, "-b"])
        try Self.execute(URL(filePath: "/usr/bin/env"), ["tuist", "generate", "--no-open"], directory: fixture)
        let environment = Self.skipListEnvironment(skipList: skipList, output: output)
        let destination = ["-destination", "id=\(simulator)"]
        let parallel = ["-parallel-testing-enabled", "YES", "-parallel-testing-worker-count", "2"]

        switch run {
        case .serial, .parallel:
            try Self.execute(
                URL(filePath: "/usr/bin/xcrun"),
                ["xcodebuild", "test", "-workspace", "UITests.xcworkspace", "-scheme", "SkipList"] + destination + [
                    "-derivedDataPath", derivedData.path(), "-resultBundlePath", resultBundle.path(), "-quiet",
                ] + (run == .parallel ? parallel : ["-parallel-testing-enabled", "NO"]),
                environment: environment,
                directory: fixture,
                timeout: Self.xcodebuildTimeout,
            )
        case .shard:
            // A run with another Xcode leaves its own `.xctestrun` beside the one built here.
            let products = derivedData.appending(path: "Build/Products")
            for file in (try? FileManager.default.contentsOfDirectory(atPath: products.path())) ?? []
                where file.hasSuffix(".xctestrun")
            {
                try FileManager.default.removeItem(at: products.appending(path: file))
            }
            try Self.execute(
                URL(filePath: "/usr/bin/xcrun"),
                ["xcodebuild", "build-for-testing", "-workspace", "UITests.xcworkspace", "-scheme", "SkipList"]
                    + destination + ["-derivedDataPath", derivedData.path(), "-quiet"],
                directory: fixture,
                timeout: Self.xcodebuildTimeout,
            )
            let testRun = try #require(
                try FileManager.default.contentsOfDirectory(atPath: products.path())
                    .first { $0.hasPrefix("SkipList_") && $0.hasSuffix(".xctestrun") },
            )
            try Self.execute(
                URL(filePath: "/usr/bin/xcrun"),
                ["xcodebuild", "test-without-building", "-xctestrun", products.appending(path: testRun).path()]
                    + destination + ["-resultBundlePath", resultBundle.path(), "-quiet"] + parallel + [
                        "-only-testing:AppTests/PartlySkippedTests", "-only-testing:AppTests/SkippedTests",
                        "-only-testing:AppTests/UnskippableTests", "-only-testing:SkipUITests/PartlySkippedUITests",
                    ],
                environment: environment,
                directory: fixture,
                timeout: Self.xcodebuildTimeout,
            )
        }
    }

    /// The environment xcodebuild passes the skip list and the output directory to the test processes in.
    private static func skipListEnvironment(skipList: URL, output: URL) -> [String: String] {
        cleanEnvironment.merging([
            "TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE": skipList.path(),
            "TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR": output.path(),
        ]) { $1 }
    }

    /// How long one xcodebuild invocation may take before it is stopped and its output reported,
    /// well under the suite's time limit.
    static let xcodebuildTimeout: TimeInterval = 360

    /// The lines of every process's `unskippable.tsv` under `output`, sorted.
    static func unskippableTests(in output: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil).flatMap { process in
            let file = process.appending(path: "unskippable.tsv")
            guard FileManager.default.fileExists(atPath: file.path()) else { return [String]() }
            return try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
        }.sorted()
    }

    /// A test case in a result bundle: `module/suite/name`, and how it ended.
    struct TestResult: CustomStringConvertible {
        let identifier: String
        let result: String

        var description: String {
            "\(identifier) \(result)"
        }
    }

    /// The test cases `xcresulttool` lists in the result bundle, under their bundle and suite.
    static func testResults(in resultBundle: URL) throws -> [TestResult] {
        struct Node: Decodable {
            let name: String
            let nodeType: String
            let result: String?
            let children: [Node]?
        }
        struct Tests: Decodable {
            let testNodes: [Node]
        }
        let output = try execute(
            URL(filePath: "/usr/bin/xcrun"),
            ["xcresulttool", "get", "test-results", "tests", "--path", resultBundle.path()],
        )
        func cases(_ node: Node, _ path: [String]) -> [TestResult] {
            let path = ["Unit test bundle", "UI test bundle", "Test Suite"].contains(node.nodeType) ? path + [node.name] : path
            if node.nodeType == "Test Case" {
                return [TestResult(identifier: (path + [node.name]).joined(separator: "/"), result: node.result ?? "")]
            }
            return (node.children ?? []).flatMap { cases($0, path) }
        }
        return try JSONDecoder().decode(Tests.self, from: Data(output.utf8)).testNodes.flatMap { cases($0, []) }
    }
}
