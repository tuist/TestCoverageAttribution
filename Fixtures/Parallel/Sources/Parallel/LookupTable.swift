/// Built by whichever test reaches it first; the others only read it, through its accessor.
let lookupTable: [Int] = (0 ..< 1024).map { $0 &* 7 }
