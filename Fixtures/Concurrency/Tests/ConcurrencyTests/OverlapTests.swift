import Concurrency
import Foundation
import TestCoverageAttribution
import Testing

/// Not serialized: the gates make its two tests run at the same time, with `second()` starting
/// first and ending last.
@Suite(.coverageAttribution)
struct OverlapTests {
    private static let secondStarted = Gate()
    private static let firstFinished = Gate()

    @Test func first() async {
        await Self.secondStarted.wait()
        #expect(Steps.first() == 1)
        Self.firstFinished.open()
    }

    @Test func second() async throws {
        #expect(Steps.second() == 2)
        Self.secondStarted.open()
        await Self.firstFinished.wait()
        // Lets first()'s scope end before this one does.
        try await Task.sleep(for: .milliseconds(200))
        #expect(Steps.third() == 3)
    }
}

/// Opens once. `wait()` returns when it has, or after 10 seconds, so tests that don't run in
/// parallel finish anyway.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false

    func open() {
        lock.withLock { isOpen = true }
    }

    func wait() async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !lock.withLock({ isOpen }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
