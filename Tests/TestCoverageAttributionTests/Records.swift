import Foundation

/// A scope the observer recorded, as `records.bin` lays it out (see `write_record()`).
struct Record: Equatable {
    enum Kind: UInt8 {
        case gap = 0
        case xcTest = 1
        case swiftTesting = 2
    }

    let kind: Kind
    let overlapped: Bool
    let version: UInt8
    let module: String
    let suite: String
    let name: String
    /// The counters that moved, by image index: each counter's index and by how much it moved.
    let counters: [UInt32: [UInt32: UInt64]]

    /// Every record the observer wrote under `directory`, one subdirectory per process.
    static func all(in directory: URL) throws -> [Record] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { $0.appending(path: "records.bin") }
            .filter { FileManager.default.fileExists(atPath: $0.path()) }
            .flatMap { try parse(Data(contentsOf: $0)) }
    }

    static func parse(_ data: Data) throws -> [Record] {
        var reader = Reader(bytes: [UInt8](data))
        var records: [Record] = []
        while !reader.isAtEnd {
            let header = Array(try reader.bytes(4))
            guard let kind = Kind(rawValue: header[0]) else { throw Reader.Error.malformed }
            let module = try reader.string()
            let suite = try reader.string()
            let name = try reader.string()
            var counters: [UInt32: [UInt32: UInt64]] = [:]
            for _ in 0 ..< (try reader.uint32()) {
                let image = try reader.uint32()
                let count = Int(try reader.uint32())
                let indices = try (0 ..< count).map { _ in try reader.uint32() }
                let deltas = try (0 ..< count).map { _ in try reader.uint64() }
                counters[image] = Dictionary(uniqueKeysWithValues: zip(indices, deltas))
            }
            records.append(Record(
                kind: kind,
                overlapped: header[1] & 1 == 1,
                version: header[2],
                module: module,
                suite: suite,
                name: name,
                counters: counters
            ))
        }
        return records
    }
}

private struct Reader {
    enum Error: Swift.Error {
        case malformed
    }

    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool {
        offset >= bytes.count
    }

    mutating func bytes(_ count: Int) throws -> ArraySlice<UInt8> {
        guard offset + count <= bytes.count else { throw Error.malformed }
        defer { offset += count }
        return bytes[offset ..< offset + count]
    }

    mutating func uint32() throws -> UInt32 {
        try bytes(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func uint64() throws -> UInt64 {
        try bytes(8).reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func string() throws -> String {
        let length = Int(try uint32())
        return String(decoding: try bytes(length), as: UTF8.self)
    }
}
