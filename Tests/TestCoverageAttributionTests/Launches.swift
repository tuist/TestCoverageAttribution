import Foundation

/// A line of `launches.tsv`: an app process a UI test launched, and the test that launched it.
struct Launch: Equatable {
    let pid: Int32
    let module: String
    let suite: String
    let name: String

    /// Every launch the observer listed under `directory`, one subdirectory per process.
    static func all(in directory: URL) throws -> [Launch] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { $0.appending(path: "launches.tsv") }
            .filter { FileManager.default.fileExists(atPath: $0.path()) }
            .flatMap { file in
                try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { line in
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    return Launch(pid: Int32(fields[0]) ?? 0, module: fields[1], suite: fields[2], name: fields[3])
                }
            }
    }
}
