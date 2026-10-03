import Concurrency
import Foundation
import TestCoverageAttributionObserver
import Testing

/// Makes writing the first image's names fail, before anything has had the observer discover the
/// images, then opens a scope through the functions the trait calls.
struct OutputFailureTests {
    @Test func opensAScopeWhenAnImageCannotBeWritten() throws {
        guard let output = ProcessInfo.processInfo.environment["TEST_COVERAGE_ATTRIBUTION_DIR"] else { return }
        // A directory where the observer would create the file.
        let names = URL(filePath: output).appending(path: "\(getpid())/0.names")
        try FileManager.default.createDirectory(at: names, withIntermediateDirectories: true)

        test_coverage_attribution_scope_begin("ConcurrencyTests", "OutputFailureTests", "scope")
        #expect(Steps.first() == 1)
        test_coverage_attribution_scope_end("ConcurrencyTests", "OutputFailureTests", "scope")
    }
}
