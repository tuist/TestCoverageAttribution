import Foundation

/// A line of `skipped.tsv`: a test the skip list had removed (XCTest) or cancelled (Swift Testing).
struct Skip: Hashable, CustomStringConvertible {
    let framework: String
    let module: String
    let suite: String
    let name: String

    var description: String {
        "\(framework) \(module)/\(suite)/\(name)"
    }

    /// What each process under `directory` reported skipping, keyed by its pid; a process without
    /// `skipped.tsv` is left out.
    static func reports(in directory: URL) throws -> [String: [Skip]] {
        var reports: [String: [Skip]] = [:]
        for process in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let file = process.appending(path: "skipped.tsv")
            guard FileManager.default.fileExists(atPath: file.path()) else { continue }
            reports[process.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n").map { line in
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    return Skip(framework: fields[0], module: fields[1], suite: fields[2], name: fields[3])
                }
        }
        return reports
    }

    /// The tests any process under `directory` reported skipping, as sorted descriptions.
    static func all(in directory: URL) throws -> [String] {
        Set(try reports(in: directory).values.joined()).map(\.description).sorted()
    }
}
