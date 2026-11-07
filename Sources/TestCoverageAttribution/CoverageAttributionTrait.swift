#if canImport(TestCoverageAttributionObserver)
    import TestCoverageAttributionObserver
#endif
import Testing

/// Attributes the code each Swift Testing test executes to that test: Swift Testing has no
/// observation center a library can join, so the trait marks where each test starts and ends, and
/// binds the test to its task.
///
/// The counters tell what a test ran only when it runs alone in its process. Tests running in
/// parallel are told apart through their tasks, in code built with
/// `-sanitize-coverage=func,trace-pc-guard,pc-table`: each function entry is attributed to the test
/// whose task, child task or `Task {}` runs it.
@_documentation(visibility: private)
public struct CoverageAttributionTrait: TestTrait, SuiteTrait, TestScoping {
    /// Whether a scope is already open around the running test case: a test in a suite nested in
    /// another that has the trait gets it once from each, and two scopes would mark it overlapped.
    @TaskLocal private static var isInScope = false

    /// The running test's context, which the observer reads from the task that enters a function.
    @TaskLocal private static var context: UInt32 = 0

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
            let key = UnsafeRawPointer(Unmanaged.passUnretained(Self.$context).toOpaque())
            let context = test_coverage_attribution_context_begin(module, suite, name, key)
            defer { test_coverage_attribution_context_end(context) }
            try await Self.$isInScope.withValue(true) {
                try await Self.$context.withValue(context) {
                    try await function()
                }
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
