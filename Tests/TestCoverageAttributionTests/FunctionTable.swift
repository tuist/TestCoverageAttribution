import CryptoKit
import Foundation

/// Which function each counter of an instrumented image belongs to, from what the observer wrote
/// for it: `images.tsv` locates the image's sections, `<n>.data` the counters each function owns,
/// and `<n>.names` the functions' names. The same reduction Tuist's reader does.
enum FunctionTable {
    /// The function of each counter, by image index and counter index.
    static func all(in process: URL) throws -> [UInt32: [Int: String]] {
        let table = try String(contentsOf: process.appending(path: "images.tsv"), encoding: .utf8)
        var images: [UInt32: [Int: String]] = [:]
        for line in table.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 4)
            guard fields.count == 5, let index = UInt32(fields[0]), let countersSize = Int(fields[1]),
                  let dataAddress = Int64(fields[2]), let countersAddress = Int64(fields[3])
            else { throw FunctionTableError.malformed(String(line)) }
            let data = try [UInt8](Data(contentsOf: process.appending(path: "\(index).data")))
            let functionNames = try names(Data(contentsOf: process.appending(path: "\(index).names")))
            let byReference = Dictionary(functionNames.map { (reference($0), $0) }, uniquingKeysWith: { first, _ in first })
            var functions: [Int: String] = [:]
            for function in counterRanges(
                data,
                dataAddress: dataAddress,
                countersAddress: countersAddress,
                countersSize: countersSize
            ) {
                guard let name = byReference[function.reference] else { continue }
                for counter in function.counters {
                    functions[counter] = name
                }
            }
            images[index] = functions
        }
        return images
    }

    /// `__llvm_prf_names`: repeated `[uleb128 size][uleb128 compressed size][bytes]`, the bytes
    /// zlib-compressed unless the compressed size is 0, holding names separated by `0x01`.
    private static func names(_ data: Data) throws -> [String] {
        let bytes = [UInt8](data)
        var offset = 0
        var names: [String] = []
        func uleb128() throws -> Int {
            var value = 0
            var shift = 0
            while offset < bytes.count {
                let byte = bytes[offset]
                offset += 1
                value |= Int(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            throw FunctionTableError.malformed("names")
        }
        while offset < bytes.count {
            let size = try uleb128()
            let compressedSize = try uleb128()
            let length = compressedSize > 0 ? compressedSize : size
            guard offset + length <= bytes.count else { throw FunctionTableError.malformed("names") }
            var chunk = Data(bytes[offset ..< offset + length])
            offset += length
            if compressedSize > 0 {
                // A zlib stream: two header bytes, then the raw DEFLATE that Foundation inflates.
                chunk = try (Data(chunk.dropFirst(2)) as NSData).decompressed(using: .zlib) as Data
            }
            names += chunk.split(separator: 0x01).compactMap { String(bytes: $0, encoding: .utf8) }
        }
        return names
    }

    /// How `__llvm_prf_data` refers to a name: the low 64 bits of its MD5, little endian.
    private static func reference(_ name: String) -> UInt64 {
        Insecure.MD5.hash(data: Data(name.utf8)).prefix(8).enumerated()
            .reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    /// `__llvm_prf_data` is an array of fixed-size records, `u64 NameRef, u64 FuncHash, iptr
    /// CounterPtr, …, u32 NumCounters`, whose layout changed across LLVM versions. Each known
    /// layout is tried; the one whose records land inside the counters section wins.
    private static func counterRanges(
        _ data: [UInt8],
        dataAddress: Int64,
        countersAddress: Int64,
        countersSize: Int
    ) -> [(reference: UInt64, counters: Range<Int>)] {
        let total = countersSize / 8
        for (recordSize, countOffset) in [(64, 48), (56, 40), (48, 40)] where !data.isEmpty && data.count % recordSize == 0 {
            for relative in [true, false] {
                var ranges: [(reference: UInt64, counters: Range<Int>)] = []
                var claimed = 0
                var valid = true
                for offset in stride(from: 0, to: data.count, by: recordSize) {
                    let pointer = Int64(bitPattern: load(data, offset + 16, size: 8))
                    let count = Int(load(data, offset + countOffset, size: 4))
                    if count == 0, pointer == 0 { continue }
                    let distance = (relative ? dataAddress + Int64(offset) + pointer : pointer) - countersAddress
                    guard distance >= 0, distance % 8 == 0, Int(distance / 8) + count <= total else {
                        valid = false
                        break
                    }
                    let first = Int(distance / 8)
                    ranges.append((load(data, offset, size: 8), first ..< first + count))
                    claimed += count
                }
                // A wrong layout rarely lands every record in range; claiming most counters settles it.
                if valid, claimed > 0, claimed * 2 >= total { return ranges }
            }
        }
        return []
    }

    private static func load(_ bytes: [UInt8], _ offset: Int, size: Int) -> UInt64 {
        bytes[offset ..< offset + size].reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }
}

enum FunctionTableError: Error {
    case malformed(String)
}
