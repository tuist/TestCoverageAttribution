public enum Delta {
    /// An unstructured task: it inherits the caller's TaskLocals.
    public static func unstructured(_ count: Int) async -> Int {
        await Task { DeltaWork.run(count) }.value
    }

    /// A detached task: it inherits no TaskLocals.
    public static func detached(_ count: Int) async -> Int {
        await Task.detached { DetachedWork.run(count) }.value
    }
}
