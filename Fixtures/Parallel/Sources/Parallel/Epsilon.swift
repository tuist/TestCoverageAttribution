import Dispatch

public enum Epsilon {
    /// Work on a GCD queue, where no task runs.
    public static func onQueue(_ count: Int) async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: QueueWork.run(count))
            }
        }
    }
}
