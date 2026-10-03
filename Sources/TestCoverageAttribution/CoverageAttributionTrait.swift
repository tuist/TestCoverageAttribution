#if canImport(TestCoverageAttributionObserver)
    import TestCoverageAttributionObserver
#endif
import Testing

/// Attributes the code each Swift Testing test executes to that test.
///
/// XCTest needs nothing beyond linking this package: the library observes it on its own. Swift
/// Testing has no observation center a library can join, so this trait marks where each test
/// starts and ends. It applies to every test and nested suite of the suite it is added to:
///
/// ```swift
/// @Suite(.coverageAttribution) struct CheckoutTests { ... }
/// ```
///
/// Attribution needs the tests of a process to run one at a time: a test that overlaps another
/// is left out. `.serialized` orders only the suite's own tests, so turn off parallel testing for
/// the run (`swift test --no-parallel`, `-parallel-testing-enabled NO`). When the run collects no
/// attribution, or off Apple platforms, the trait does nothing.
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
        performing function: @Sendable () async throws -> Void
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
    /// Attributes the code each test executes to that test. See ``CoverageAttributionTrait``.
    public static var coverageAttribution: Self {
        Self()
    }
}
