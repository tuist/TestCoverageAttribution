import Concurrency
import TestCoverageAttribution
import Testing

/// The trait on a suite and on a suite nested in it: `nested()` gets it from both.
@Suite(.coverageAttribution, .serialized)
enum Outer {
    @Suite(.coverageAttribution)
    struct Inner {
        @Test func nested() {
            #expect(Steps.first() == 1)
        }
    }
}
