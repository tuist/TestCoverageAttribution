import Foundation

/// The function at an offset of an image listed in `functions.tsv`, from the image's symbol table
/// (`nm`): what a functions record's offsets name. The same reduction Tuist's reader does.
struct FunctionSymbols {
    private var paths: [UInt32: String] = [:]
    private var tables: [String: (starts: [UInt64], names: [String])] = [:]

    init(process: URL) throws {
        let list = process.appending(path: "functions.tsv")
        guard FileManager.default.fileExists(atPath: list.path()) else { return }
        for line in try String(contentsOf: list, encoding: .utf8).split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 2)
            guard fields.count == 3, let index = UInt32(fields[0]) else { throw FunctionTableError.malformed(String(line)) }
            paths[index] = String(fields[2])
        }
        for path in Set(paths.values) {
            tables[path] = try Self.table(path)
        }
    }

    func function(image: UInt32, offset: UInt32) throws -> String {
        guard let path = paths[image], let table = tables[path] else { throw FunctionTableError.malformed("image \(image)") }
        var low = 0, high = table.starts.count
        while low < high {
            let middle = (low + high) / 2
            if table.starts[middle] <= UInt64(offset) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { throw FunctionTableError.malformed("offset \(offset) in \(path)") }
        return table.names[low - 1]
    }

    /// The image's text symbols, by offset from its base: their address less `__TEXT`'s.
    private static func table(_ path: String) throws -> (starts: [UInt64], names: [String]) {
        let loadCommands = try AttributionTests.execute(URL(filePath: "/usr/bin/otool"), ["-l", path])
        let lines = loadCommands.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var base: UInt64 = 0
        if let segment = lines.firstIndex(of: "segname __TEXT"), segment + 1 < lines.count,
           let address = lines[segment + 1].split(separator: " ").last
        {
            base = UInt64(address.dropFirst(2), radix: 16) ?? 0
        }
        var symbols: [(UInt64, String)] = []
        for line in try AttributionTests.execute(URL(filePath: "/usr/bin/xcrun"), ["nm", "-n", "--defined-only", path])
            .split(separator: "\n")
        {
            let fields = line.split(separator: " ", maxSplits: 2)
            guard fields.count == 3, fields[1] == "t" || fields[1] == "T",
                  let address = UInt64(fields[0], radix: 16) else { continue }
            let name = fields[2].hasPrefix("_") ? String(fields[2].dropFirst()) : String(fields[2])
            symbols.append((address - base, name))
        }
        return (symbols.map(\.0), symbols.map(\.1))
    }
}
