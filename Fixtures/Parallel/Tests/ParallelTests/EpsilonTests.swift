import Parallel
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct EpsilonTests {
    @Test func first() async {
        await Barrier.arrive()
        #expect(await Epsilon.onQueue(10000) != Int.min)
    }

    @Test func second() async {
        await Barrier.arrive()
        #expect(await Epsilon.onQueue(10000) != Int.min)
    }
}
