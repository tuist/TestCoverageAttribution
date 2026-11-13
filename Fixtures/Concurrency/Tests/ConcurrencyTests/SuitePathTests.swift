import Concurrency
import TestCoverageAttribution
import Testing

/// A suite at the top level, a suite nested in it, one in an extension of it and one in an enum
/// namespace: their tests are recorded and listed under every suite they're nested in, outermost
/// first, as the result bundle names them.
@Suite(.coverageAttribution, .serialized)
struct SuitePathTests {
    @Test func topLevel() {
        #expect(Steps.first() == 1)
    }

    struct Nested {
        @Test func nested() {
            #expect(Steps.second() == 2)
        }

        @Test(.unskippable) func unskippable() {
            #expect(Steps.second() == 2)
        }
    }
}

extension SuitePathTests {
    struct InExtension {
        @Test func inExtension() {
            #expect(Steps.third() == 3)
        }

        @Test(.unskippable) func unskippable() {
            #expect(Steps.third() == 3)
        }
    }
}

enum SuitePathNamespace {
    @Suite(.coverageAttribution)
    struct Inner {
        @Test func inNamespace() {
            #expect(Steps.first() == 1)
        }

        @Test(.unskippable) func unskippable() {
            #expect(Steps.first() == 1)
        }
    }
}
