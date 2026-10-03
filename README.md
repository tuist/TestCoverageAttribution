# TestCoverageAttribution

> [!WARNING]
> This package is experimental and in early development. Its API, the environment variables it reads and the format of what it records may change without notice between versions, and it hasn't been tested beyond the cases in this repository. Don't depend on it for anything critical yet.

TestCoverageAttribution records which code each test executes. Xcode's code coverage tells you what a whole test run covered. This package attributes that coverage to the individual test that executed it.

[Tuist](https://tuist.dev) uses it to collect per-test coverage evidence, which lets a run that skips tests reuse those tests' coverage from an earlier run.

## Installation

Add the package and link the `TestCoverageAttribution` product to your **test targets**. Never link it to an app target.

```swift
.package(url: "https://github.com/tuist/TestCoverageAttribution", branch: "main"),
```

```swift
.testTarget(
    name: "CheckoutTests",
    dependencies: [
        "Checkout",
        .product(name: "TestCoverageAttribution", package: "TestCoverageAttribution"),
    ]
),
```

In an Xcode project, add the package and add `TestCoverageAttribution` to the test target's *Link Binary With Libraries* phase.

When the package is linked as a static library or a static framework, as Tuist's Xcode project integration of packages does by default, add `-ObjC` to the test target's `OTHER_LDFLAGS`. An XCTest-only target references nothing in the package, so the linker drops the observer without it. SwiftPM and Xcode's own package integration link the package's object files directly and need nothing.

The package records on Apple platforms only. Elsewhere, such as Linux, it builds and does nothing, so a cross-platform test target can link it unconditionally.

## Usage

**XCTest** needs nothing else. Linking the package is enough: the library registers an `XCTestObservation` observer when the test bundle loads.

**Swift Testing** has no observation center a library can join, so add the `.coverageAttribution` trait to your suites. The trait applies to every test and nested suite of the suite it is added to:

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution, .serialized)
struct CheckoutTests {
    @Test func appliesDiscount() { ... }
}
```

Attribution needs the tests of a process to run one at a time. A test that overlaps another is marked as overlapped and left out of per-test attribution. Use `.serialized` on Swift Testing suites, or `-parallel-testing-enabled NO`.

## When it records

Nothing happens unless the test process sets `TEST_COVERAGE_ATTRIBUTION_DIR`. Without it, the tests run as if the package weren't linked, so a test target can link the package unconditionally.

- **Tuist** sets the directory when a run collects coverage evidence.
- **`xcodebuild`** passes it to the test process with the `TEST_RUNNER_` prefix: `TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR=/tmp/attribution xcodebuild test -enableCodeCoverage YES …`.
- **`swift test`** reads it from the environment: `TEST_COVERAGE_ATTRIBUTION_DIR=/tmp/attribution swift test --enable-code-coverage`.

Code coverage must be enabled: without instrumentation there are no counters to observe.

Supported platforms are macOS and the iOS simulator. On a device, the process can't write to a directory on the Mac that runs the tests.

## Output

The output is written under `$TEST_COVERAGE_ATTRIBUTION_DIR/<pid>/`, one directory per test process:

| File | Contents |
| --- | --- |
| `images.tsv` | One line per instrumented image: its index, the byte size of its counters, the addresses of its `__llvm_prf_data` and `__llvm_prf_cnts` sections, and its path. |
| `<n>.data`, `<n>.names` | Image `n`'s raw `__llvm_prf_data` and `__llvm_prf_names` sections: what maps a counter to its function. |
| `records.bin` | One record per scope. |

A scope is one of the following:
- an XCTest test;
- a Swift Testing test;
- a *gap*: whatever ran between two tests, such as a class `setUp`, a suite's one-time setup, or leaked background work.

Each record is laid out in little-endian as follows:

- `u8` kind (`0` gap, `1` XCTest, `2` Swift Testing), `u8` flags (`1` overlapped), `u8` version (currently `1`), `u8` zero.
- The module, the suite and the test name, each a `u32` length followed by UTF-8 bytes. XCTest records name the test bundle as the module.
- `u32` count of images whose counters moved. For each image: `u32` image index, `u32` count, then `count` `u32` counter indices and `count` `u64` deltas (how much each counter moved).

The deltas are what turns counters into lines. In the image's coverage mapping (`__llvm_covfun`), a region's count is an expression over counters, so knowing which counters moved isn't enough.

## Guarantees

- It never resets or writes the coverage counters: Xcode's own coverage report is unchanged.
- It never crashes or blocks the tests. Any failure stops recording, removes what it wrote for the process so a reader never gets partial output, and lets the tests run.
- Only one copy records per process. If the package ends up linked more than once into the same process, for example into two test bundles loaded by the same host, the first copy to load does the recording and the others forward to it.
- Images loaded after the first test starts, such as a framework the tests `dlopen` late, are not observed.

## Development

```bash
mise run build
mise run test   # runs Fixtures/Example with SwiftPM and xcodebuild, and Fixtures/Concurrency with SwiftPM, and checks the records
mise run lint
```
