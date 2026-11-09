enum DeltaWork {
    static func run(_ count: Int) -> Int {
        (0 ..< count).reduce(0, &+)
    }
}
