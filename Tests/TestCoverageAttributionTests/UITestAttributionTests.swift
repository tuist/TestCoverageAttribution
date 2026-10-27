import Foundation
import Testing

extension AttributionTests {
    /// The app a UI test drives runs in a process of its own, which Xcode profiles on its own and
    /// names after its pid: the observer lists each launch's pid with the test that made it, once
    /// however often tests activate it, and a launch from a class `setUp` with its suite alone.
    @Test func listsTheAppProcessesEachUITestLaunched() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "TestCoverageAttribution-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = scratch.appending(path: "output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = Self.packageRoot.appending(path: "Fixtures/UITests")
        let derivedData = Self.packageRoot.appending(path: ".build/fixtures/UITests/xcode")
        try? FileManager.default.removeItem(at: derivedData.appending(path: "Build/ProfileData"))
        let simulator = try Self.iPhoneSimulator(fixture: Self.packageRoot.appending(path: "Fixtures/Example"))
        // SpringBoard refuses to launch the UI test runner on a simulator that is still booting.
        try Self.execute(URL(filePath: "/usr/bin/xcrun"), ["simctl", "bootstatus", simulator, "-b"])
        try Self.execute(URL(filePath: "/usr/bin/env"), ["tuist", "generate", "--no-open"], directory: fixture)
        var environment = Self.cleanEnvironment
        environment["TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR"] = output.path()

        try Self.execute(
            URL(filePath: "/usr/bin/xcrun"),
            [
                "xcodebuild", "test", "-workspace", "UITests.xcworkspace", "-scheme", "AppUITests",
                "-destination", "id=\(simulator)", "-derivedDataPath", derivedData.path(), "-enableCodeCoverage", "YES",
                "-quiet",
            ],
            environment: environment,
            directory: fixture,
        )

        let launches = try Launch.all(in: output)
        #expect(launches.map { "\($0.module) \($0.suite)/\($0.name)" }.sorted() == [
            "AppUITests LaunchTests/testLaunch",
            "AppUITests LaunchTests/testRelaunch",
            "AppUITests LaunchTests/testRelaunch",
            "AppUITests SharedLaunchTests/",
        ])
        #expect(Set(launches.map(\.pid)).count == 4)
        let profileData = derivedData.appending(path: "Build/ProfileData")
        let profiledProcesses = try FileManager.default.contentsOfDirectory(atPath: profileData.path()).flatMap { device in
            try FileManager.default.contentsOfDirectory(atPath: profileData.appending(path: device).path())
                .filter { $0.hasSuffix(".profraw") }
                .compactMap { Int32($0.dropLast(".profraw".count).split(separator: "-").last ?? "") }
        }
        #expect(Set(launches.map(\.pid)).isSubset(of: Set(profiledProcesses)))
    }
}
