public actor Beta {
    private var total = 0

    public init() {}

    public func add(_ count: Int) -> Int {
        for index in 0 ..< count {
            total &+= betaStep(index)
        }
        return total &+ lookupTable[count & 1023]
    }
}

func betaStep(_ index: Int) -> Int {
    index ^ 0x55
}
