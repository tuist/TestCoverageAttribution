import Concurrency
import TestCoverageAttributionObserver
import Testing

/// Opens scopes through the functions the trait calls, in an order no scheduler can change: `a`
/// and `b` overlap, and `c` starts once both have ended.
struct ScopeSequenceTests {
    @Test func overlapEndsWhenNoScopeIsActive() {
        begin("a")
        #expect(Steps.first() == 1)
        begin("b")
        #expect(Steps.second() == 2)
        end("a")
        end("b")
        begin("c")
        #expect(Steps.third() == 3)
        end("c")
    }

    private func begin(_ name: String) {
        test_coverage_attribution_scope_begin("ConcurrencyTests", "ScopeSequenceTests", name)
    }

    private func end(_ name: String) {
        test_coverage_attribution_scope_end("ConcurrencyTests", "ScopeSequenceTests", name)
    }
}
