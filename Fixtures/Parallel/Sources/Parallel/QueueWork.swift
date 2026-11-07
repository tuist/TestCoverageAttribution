enum QueueWork {
    static func run(_ count: Int) -> Int {
        (0 ..< count).reduce(0) { $0 ^ $1 }
    }
}
