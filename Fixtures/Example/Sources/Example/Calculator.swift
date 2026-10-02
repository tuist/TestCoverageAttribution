public enum Calculator {
    public static func add(_ lhs: Int, _ rhs: Int) -> Int {
        lhs + rhs
    }

    public static func multiply(_ lhs: Int, _ rhs: Int) -> Int {
        if lhs == 0 || rhs == 0 {
            return 0
        }
        return lhs * rhs
    }
}
