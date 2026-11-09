public enum Alpha {
    public static func compute(_ count: Int) -> Int {
        var sum = 0
        for index in 0 ..< count {
            sum &+= step(index)
        }
        return Shared.mix(sum &+ lookupTable[count & 1023])
    }

    static func step(_ index: Int) -> Int {
        index &* 31
    }
}
