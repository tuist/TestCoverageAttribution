import Parallel
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct BetaTests {
    @Test func first() async {
        await Barrier.arrive()
        #expect(await Beta().add(10000) != Int.min)
    }

    @Test func second() async {
        await Barrier.arrive()
        #expect(await Beta().add(10000) != Int.min)
    }
}
