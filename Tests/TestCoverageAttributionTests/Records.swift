import Foundation

/// A scope the observer recorded, as `records.bin` lays it out (see `write_record()`), or a function
/// record from `functions.bin` (see `write_functions_record()`).
struct Record: Equatable {
    enum Kind: UInt8 {
        case gap = 0
        case xcTest = 1
        case swiftTesting = 2
        case functions = 3
    }

    let kind: Kind
    let overlapped: Bool
    /// A functions record of what no test's task ran.
    var floor = false
    let version: UInt8
    let module: String
    let suite: String
    let name: String
    /// The counters that moved, by image index: each counter's index and by how much it moved.
    let counters: [UInt32: [UInt32: UInt64]]
    /// A functions record's functions, by `functions.tsv` image index: each one's offset from the
    /// image's base.
    var functionOffsets: [UInt32: [UInt32]] = [:]
    /// The functions those counters belong to, as `__llvm_prf_names` names them, or a functions
    /// record's functions, as the image's symbol table names them: mangled for Swift. Filled in by
    /// `all(in:)`, which has the images.
    var functions: Set<String> = []

    /// Whether a function whose name contains `fragment` ran in this scope.
    func ran(_ fragment: String) -> Bool {
        functions.contains { $0.contains(fragment) }
    }

    /// Every record the observer wrote under `directory`, one subdirectory per process, with the
    /// functions its counters belong to.
    static func all(in directory: URL) throws -> [Record] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "records.bin").path()) }
            .flatMap { process in
                var records = try parse(Data(contentsOf: process.appending(path: "records.bin")))
                let functionRecords = process.appending(path: "functions.bin")
                if FileManager.default.fileExists(atPath: functionRecords.path()) {
                    records += try parse(Data(contentsOf: functionRecords))
                }
                guard !records.isEmpty else { return records }
                let functions = try FunctionTable.all(in: process)
                let symbols = try FunctionSymbols(process: process)
                return try records.map { record in
                    var record = record
                    for (image, counters) in record.counters {
                        record.functions.formUnion(counters.keys.compactMap { functions[image]?[Int($0)] })
                    }
                    for (image, offsets) in record.functionOffsets {
                        record.functions.formUnion(try offsets.map { try symbols.function(image: image, offset: $0) })
                    }
                    return record
                }
            }
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
            var functionOffsets: [UInt32: [UInt32]] = [:]
            for _ in 0 ..< (try reader.uint32()) {
                let image = try reader.uint32()
                let count = Int(try reader.uint32())
                let indices = try (0 ..< count).map { _ in try reader.uint32() }
                if kind == .functions {
                    functionOffsets[image] = indices
                } else {
                    let deltas = try (0 ..< count).map { _ in try reader.uint64() }
                    counters[image] = Dictionary(uniqueKeysWithValues: zip(indices, deltas))
                }
            }
            var record = Record(
                kind: kind,
                overlapped: header[1] & 1 == 1,
                version: header[2],
                module: module,
                suite: suite,
                name: name,
                counters: counters,
            )
            record.floor = header[1] & 2 == 2
            record.functionOffsets = functionOffsets
            records.append(record)
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
        guard let string = String(bytes: try bytes(length), encoding: .utf8) else { throw Error.malformed }
        return string
    }
}
