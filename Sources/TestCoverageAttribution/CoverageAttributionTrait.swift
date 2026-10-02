import TestCoverageAttributionObserver
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
/// is left out. Use `.serialized` on the suite or `-parallel-testing-enabled NO`. When the run
/// collects no attribution, the trait does nothing.
public struct CoverageAttributionTrait: TestTrait, SuiteTrait, TestScoping {
    public var isRecursive: Bool {
        true
    }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
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
        try await function()
    }
}

extension Trait where Self == CoverageAttributionTrait {
    /// Attributes the code each test executes to that test. See ``CoverageAttributionTrait``.
    public static var coverageAttribution: Self {
        Self()
    }
}
