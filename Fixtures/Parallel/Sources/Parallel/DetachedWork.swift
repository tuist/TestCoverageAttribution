enum DetachedWork {
    static func run(_ count: Int) -> Int {
        (0 ..< count).reduce(1) { $0 &* ($1 | 1) }
    }
}
