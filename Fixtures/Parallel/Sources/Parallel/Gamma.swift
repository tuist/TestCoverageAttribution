public enum Gamma {
    public static func fanOut(_ count: Int) async -> Int {
        await withTaskGroup(of: Int.self) { group in
            for index in 0 ..< 4 {
                group.addTask { GammaLeaf.work(index, count) }
            }
            var sum = 0
            for await value in group {
                sum &+= value
            }
            return Shared.mix(sum)
        }
    }
}
