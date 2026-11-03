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
    /// run its class `setUp`, which crashes. The tests left run, after their class `setUp`, and so
    /// does a listed Swift Testing test.
    @Test(arguments: SkipListRun.allCases)
    func removesTheListedXCTestTestsBeforeTheyRun(run: SkipListRun) throws {
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

        AppTests/SkippedTests/testFirst()
        AppTests/SkippedTests/testSecond()
        AppTests/SwiftTestingTests/runs()
        AppTests/UnlistedTests
        AppTests/MissingTests/testMissing()
        SkipUITests/PartlySkippedUITests/testSkipped()
        SkipUITests/SkippedUITests/testSkipped()
        """.write(to: skipList, atomically: true, encoding: .utf8)
        let resultBundle = scratch.appending(path: "Tests.xcresult")
        try runSkipListScheme(run, skipList: skipList, resultBundle: resultBundle)

        let results = try Self.testResults(in: resultBundle)
        #expect(results.allSatisfy { $0.result == "Passed" }, "\(results)")
        #expect(results.map(\.identifier).sorted() == (run == .shard ? [
            "AppTests/PartlySkippedTests/testRuns()",
            "SkipUITests/PartlySkippedUITests/testLaunch()",
        ] : [
            "AppTests/PartlySkippedTests/testRuns()",
            "AppTests/SwiftTestingTests/runs()",
            "AppTests/UnlistedTests/testRuns()",
            "SkipUITests/PartlySkippedUITests/testLaunch()",
        ]))
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
        ])
    }

    /// Generates `Fixtures/UITests` and runs its `SkipList` scheme on an iPhone simulator, the way
    /// `run` says, with the skip list.
    private func runSkipListScheme(_ run: SkipListRun, skipList: URL, resultBundle: URL) throws {
        let fixture = Self.packageRoot.appending(path: "Fixtures/UITests")
        let derivedData = Self.packageRoot.appending(path: ".build/fixtures/UITests/skip-list")
        let simulator = try Self.iPhoneSimulator(fixture: Self.packageRoot.appending(path: "Fixtures/Example"))
        try Self.execute(URL(filePath: "/usr/bin/xcrun"), ["simctl", "bootstatus", simulator, "-b"])
        try Self.execute(URL(filePath: "/usr/bin/env"), ["tuist", "generate", "--no-open"], directory: fixture)
        var environment = Self.cleanEnvironment
        environment["TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE"] = skipList.path()
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
                        "-only-testing:SkipUITests/PartlySkippedUITests",
                    ],
                environment: environment,
                directory: fixture,
                timeout: Self.xcodebuildTimeout,
            )
        }
    }

    /// How long one xcodebuild invocation may take before it is stopped and its output reported,
    /// well under the suite's time limit.
    static let xcodebuildTimeout: TimeInterval = 360

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
