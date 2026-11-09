import Foundation

/// Every test of the fixture arrives here before doing its work, so they all run at once.
/// `arrive()` returns when all have, or after 10 seconds, so tests that don't run in parallel
/// finish anyway.
enum Barrier {
    static let expected = 10
    private static let lock = NSLock()
    private nonisolated(unsafe) static var arrived = 0

    static func arrive() async {
        lock.withLock { arrived += 1 }
        let deadline = ContinuousClock.now + .seconds(10)
        while lock.withLock({ arrived < expected }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
