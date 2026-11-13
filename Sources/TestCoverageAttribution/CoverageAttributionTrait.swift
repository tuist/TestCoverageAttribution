#if canImport(TestCoverageAttributionObserver)
    import TestCoverageAttributionObserver
#endif
import Testing

/// Attributes the code each Swift Testing test executes to that test, by marking where each test
/// starts and ends: Swift Testing has no observation center a library can join. It also skips the
/// tests the skip list names, by cancelling them before they run, unless they're marked
/// `.unskippable` (``SkippabilityTrait``).
///
/// The trait has to be added to every suite, and Swift Testing runs tests in parallel within a
/// process by default, which leaves overlapping tests without evidence.
public struct CoverageAttributionTrait: TestTrait, SuiteTrait, TestScoping {
    /// Whether a scope is already open around the running test case: a test in a suite nested in
    /// another that has the trait gets it once from each, and two scopes would mark it overlapped.
    @TaskLocal private static var isInScope = false

    public var isRecursive: Bool {
        true
    }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void,
    ) async throws {
        #if canImport(TestCoverageAttributionObserver)
            guard testCase != nil, !Self.isInScope else {
                try await function()
                return
            }
            let components = test.id.nameComponents
            let module = test.id.moduleName
            let suite = components.count >= 2 ? components[components.count - 2] : ""
            // The name the result bundle reports the test under, which is the test's identity
            // everywhere else: its display name when it declares one, its function otherwise.
            let name = test.displayName ?? components.last ?? test.name
            let isListed = test_coverage_attribution_is_skipped(module, suite, name)
            if !SkippabilityTrait.isSkippable(test) {
                // It runs, listed or not, and the output says so, for the runner to stop listing it.
                test_coverage_attribution_report_unskippable(module, suite, name, isListed)
            } else if isListed {
                #if compiler(>=6.3)
                    // `Test.cancel` reports the test as skipped. Before Swift 6.3 a trait can only
                    // skip a test by not running it, which reports it as passed, so it runs instead.
                    try Test.cancel("Listed in TEST_COVERAGE_ATTRIBUTION_SKIP_FILE", sourceLocation: test.sourceLocation)
                #endif
            }
            test_coverage_attribution_scope_begin(module, suite, name)
            defer { test_coverage_attribution_scope_end(module, suite, name) }
            try await Self.$isInScope.withValue(true) {
                try await function()
            }
        #else
            try await function()
        #endif
    }
}

extension Trait where Self == CoverageAttributionTrait {
    /// See ``CoverageAttributionTrait``.
    public static var coverageAttribution: Self {
        Self()
    }
}
