#if canImport(TestCoverageAttributionObserver)
    import TestCoverageAttributionObserver
#endif
import Testing

/// Attributes the code each Swift Testing test executes to that test, by marking where each test
/// starts and ends: Swift Testing has no observation center a library can join.
///
/// Kept, but hidden from the documentation and the README: test-scoped evidence and skipping are
/// supported for XCTest and XCUITest only. The trait has to be added to every suite, Swift Testing
/// runs tests in parallel within a process by default, which leaves overlapping tests without
/// evidence, and a trait has no public way to skip a test. Projects that use it anyway get records
/// as before.
@_documentation(visibility: private)
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
    @_documentation(visibility: private)
    public static var coverageAttribution: Self {
        Self()
    }
}
