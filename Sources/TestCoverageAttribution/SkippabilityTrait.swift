import Testing

/// Whether the skip list (`TEST_COVERAGE_ATTRIBUTION_SKIP_FILE`) can skip a test: `.unskippable`
/// for a test whose real inputs coverage can't see, such as fixtures, resources, the network or
/// the environment, so it always runs, and `.skippable` to opt a test or suite back in under an
/// unskippable suite.
///
/// On a suite it applies to every test in it and in its nested suites. The most specific one
/// wins: a test's overrides its suite's, and a nested suite's overrides its parent's. It takes
/// effect in suites with the `.coverageAttribution` trait, which is what skips listed tests.
public struct SkippabilityTrait: TestTrait, SuiteTrait {
    /// Whether the skip list can skip the test.
    public let isSkippable: Bool

    public var isRecursive: Bool {
        true
    }

    /// Whether the skip list can skip `test`, from the most specific trait that says. Swift
    /// Testing puts a suite's recursive traits before its children's own, outermost first, so the
    /// last one in `test.traits` is the most specific.
    static func isSkippable(_ test: Test) -> Bool {
        (test.traits.last { $0 is Self } as? Self)?.isSkippable ?? true
    }
}

extension Trait where Self == SkippabilityTrait {
    /// The test, or every test in the suite, always runs, even when the skip list names it. See
    /// ``SkippabilityTrait``.
    public static var unskippable: Self {
        Self(isSkippable: false)
    }

    /// The skip list can skip the test, or the tests in the suite, under a suite marked
    /// `.unskippable`. See ``SkippabilityTrait``.
    public static var skippable: Self {
        Self(isSkippable: true)
    }
}
