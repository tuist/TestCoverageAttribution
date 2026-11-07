import Parallel
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct GammaTests {
    @Test func first() async {
        await Barrier.arrive()
        #expect(await Gamma.fanOut(1000) != Int.min)
    }

    @Test func second() async {
        await Barrier.arrive()
        #expect(await Gamma.fanOut(1000) != Int.min)
    }
}
