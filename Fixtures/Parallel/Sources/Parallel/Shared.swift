public enum Shared {
    public static func mix(_ value: Int) -> Int {
        (value &* 0x9E37_79B9) ^ (value >> 7)
    }
}
