import Parallel
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DeltaTests {
    @Test func first() async {
        await Barrier.arrive()
        #expect(await Delta.unstructured(10000) != Int.min); #expect(await Delta.detached(100) != Int.min)
    }

    @Test func second() async {
        await Barrier.arrive()
        #expect(await Delta.unstructured(10000) != Int.min); #expect(await Delta.detached(100) != Int.min)
    }
}
