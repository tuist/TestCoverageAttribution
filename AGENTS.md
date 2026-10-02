# TestCoverageAttribution

A Swift package that test targets link to record which coverage counters each test moves (per-test coverage attribution). Tuist's CLI reduces the output to per-test evidence; the record layout is a contract with it (`TuistKit.CoverageObserverOutput` in tuist/tuist).

## Layout
- `Sources/TestCoverageAttributionObserver` - Objective-C, Foundation only. XCTest is looked up at run time (class, protocol and selectors by name), so nothing links XCTest. It reads each instrumented image's `__llvm_prf_cnts` directly and never calls the LLVM profile runtime. Registers its XCTest observer from a constructor when the test bundle loads.
- `Sources/TestCoverageAttribution` - the Swift Testing trait (`.coverageAttribution`) that calls `test_coverage_attribution_scope_begin/end` around each test.
- `Tests/TestCoverageAttributionTests` - runs `Fixtures/Example` with SwiftPM and xcodebuild with attribution on, and parses `records.bin` (`Records.swift` mirrors the layout).

## Rules
- Never crash or block the test process: every failure path returns and the tests run as if nothing were linked.
- Never reset or write the counters.
- Changing `records.bin`: update `write_record()`, `Records.swift`, the README and Tuist's reader together, and bump `kRecordVersion` when a record gains a field.
- No `unsafeFlags` in `Package.swift`: they make the package unusable as a versioned dependency.

## Commands
- `mise run build`, `mise run test`, `mise run lint` (`--fix`).
