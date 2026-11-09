# TestCoverageAttribution

A Swift package that test targets link to record which coverage counters each test moves (per-test coverage attribution). Tuist's CLI reduces the output to per-test evidence; the record layout is a contract with it (`TuistKit.CoverageObserverOutput` in tuist/tuist).

## Layout
- `Sources/TestCoverageAttributionObserver` - Objective-C, Foundation only. XCTest is looked up at run time (class, protocol and selectors by name), so nothing links XCTest. It reads each instrumented image's `__llvm_prf_cnts` directly and never calls the LLVM profile runtime. Registers its XCTest observer from a constructor when the test bundle loads, and hooks `-[XCUIApplication launch]`/`-activate` once the bundle starts, to list the app processes UI tests launch. Its constructor also reads the skip list (`TEST_COVERAGE_ATTRIBUTION_SKIP_FILE`) and hooks `+[XCTestCase defaultTestSuite]` to remove the listed tests; it lives in this file because `-ObjC` loads only archive members that define a class. A class keeps listed tests it marks unskippable with class methods looked up by name (`unskippableTests`, `isUnskippable`, `skippableTests`), and the observer lists the unskippable tests that run in `unskippable.tsv`.
- `Sources/TestCoverageAttribution` - the Swift Testing trait (`.coverageAttribution`) that calls `test_coverage_attribution_scope_begin/end` around each test, and cancels the tests `test_coverage_attribution_is_skipped` finds in the skip list, unless the most specific `.unskippable`/`.skippable` trait (`SkippabilityTrait`) says they're unskippable; it reports those through `test_coverage_attribution_report_unskippable`. Cancelling needs `Test.cancel`, so it's compiled only with Swift 6.3 or later; before, listed tests run, since a test a trait doesn't run is reported as passed.
- `Tests/TestCoverageAttributionTests` - runs the fixtures with attribution on and parses what the observer wrote: `Records.swift` mirrors the `records.bin` layout and `FunctionTable.swift` maps counters to function names as Tuist's reader does.
  - `Fixtures/Example` - with SwiftPM, xcodebuild on macOS and xcodebuild on an iOS simulator.
  - `Fixtures/Concurrency` - the overlapping, nested-trait and failure cases, in a package of their own since Swift Testing runs suites in parallel across the process.
  - `Fixtures/StaticArchive` - links the observer from a static archive, with and without `-ObjC`, into a bundle with a Swift and an Objective-C test class.
  - `Fixtures/UITests` - an app, its UI tests and its hosted unit tests. It's a Tuist project (`Project.swift`), because a UI test needs an app target and SwiftPM can't build apps; `Launches.swift` reads `launches.tsv`, and `SkipListTests.swift` runs the `SkipList` scheme serially, in parallel and as a shard and reads the result bundle.

## Rules
- Never crash or block the test process: every failure path returns and the tests run as if nothing were linked.
- Never reset or write the counters.
- Changing `records.bin`: update `write_record()`, `Records.swift`, the README and Tuist's reader together, and bump `kRecordVersion` when a record gains a field.
- Changing `launches.tsv`: update `write_launch()`, `Launches.swift`, the README and Tuist's reader (`CoverageObserverOutput.parseLaunches`) together.
- Changing the skip list format: update `load_skip_list()`, `SkipListTests.swift`, the README and Tuist's writer together.
- Changing `unskippable.tsv` or the XCTest marker names: update `write_unskippable()`/`xctest_is_unskippable()`, `SkipListTests.swift`, the README and Tuist's reader together.
- No `unsafeFlags` in `Package.swift`: they make the package unusable as a versioned dependency.

## Commands
- `mise run build`, `mise run test`, `mise run lint` (`--fix`).
