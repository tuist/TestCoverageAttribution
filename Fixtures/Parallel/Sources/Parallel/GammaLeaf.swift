enum GammaLeaf {
    static func work(_ index: Int, _ count: Int) -> Int {
        var sum = index
        for value in 0 ..< count {
            sum &+= value &* index
        }
        return sum
    }
}
