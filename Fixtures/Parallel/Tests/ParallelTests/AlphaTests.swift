import Parallel
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct AlphaTests {
    @Test func first() async {
        await Barrier.arrive()
        #expect(Alpha.compute(10000) != Int.min)
    }

    @Test func second() async {
        await Barrier.arrive()
        #expect(Alpha.compute(10000) != Int.min)
    }
}
