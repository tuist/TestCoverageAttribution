# TestCoverageAttribution

[![TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution/actions/workflows/test-coverage-attribution.yml/badge.svg)](https://github.com/tuist/TestCoverageAttribution/actions/workflows/test-coverage-attribution.yml)

> [!WARNING]
> This package is experimental and in early development. Its API, the environment variables it reads and the format of what it records may change without notice between versions, and it hasn't been tested beyond the cases in this repository. Don't depend on it for anything critical yet.

TestCoverageAttribution records which code each test executes. Xcode's code coverage tells you what a whole test run covered. This package attributes that coverage to the individual test that executed it. It can also skip a list of tests before they run.

[Tuist](https://tuist.dev) uses it to collect per-test coverage evidence, which lets a run that skips tests reuse those tests' coverage from an earlier run, and to skip the tests a change can't affect.

Both work for XCTest tests, UI tests included. Swift Testing tests run as usual: they get no per-test evidence and are never skipped one by one.

## Installation

Add the package and link the `TestCoverageAttribution` product to your **test targets**. Never link it to an app target.

```swift
.package(url: "https://github.com/tuist/TestCoverageAttribution", .upToNextMinor(from: "0.1.0")),
```

While the package is at 0.x, a minor version can break its API or the format of what it records, so pin to the minor version.

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

When the package is linked as a static library or a static framework, as Tuist's Xcode project integration of packages does by default, add `-ObjC` to the test target's `OTHER_LDFLAGS`. An XCTest-only target references nothing in the package, so the linker drops the observer, and with it the skip list, without it. SwiftPM and Xcode's own package integration link the package's object files directly and need nothing.

The package records on Apple platforms only. Elsewhere, such as Linux, it builds and does nothing, so a cross-platform test target can link it unconditionally.

## Usage

**XCTest** needs nothing else. Linking the package is enough: the library registers an `XCTestObservation` observer when the test bundle loads. XCTest runs the tests of a process one at a time, and parallel testing runs each clone in a process of its own, so every test gets a record of its own either way.

**UI tests** need nothing else either. The app a UI test drives runs in a process of its own, which the package can't observe, but Xcode profiles that process separately when code coverage is on. The package records which test launched which app process, so a reader such as Tuist can attribute the app's coverage to the test. See [`launches.tsv`](#output).

**Swift Testing** isn't supported. Swift Testing tests run as usual, and their coverage is in the run's report as always, but no test-scoped evidence is recorded for them and the skip list doesn't apply to them. Swift Testing has no observation center a library can join, it runs tests in parallel within a process by default, and a trait has no public way to skip a test.

## When it records

Nothing happens unless the test process sets `TEST_COVERAGE_ATTRIBUTION_DIR`. Without it, the tests run as if the package weren't linked, so a test target can link the package unconditionally.

- **Tuist** sets the directory when a run collects coverage evidence.
- **`xcodebuild`** passes it to the test process with the `TEST_RUNNER_` prefix.
- **`swift test`** reads it from the environment.

Use a fresh directory, such as one from `mktemp -d`, rather than a fixed path in a shared `/tmp`:

```bash
output=$(mktemp -d)
TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR="$output" xcodebuild test -enableCodeCoverage YES …
TEST_COVERAGE_ATTRIBUTION_DIR="$output" swift test --enable-code-coverage
ls "$output"   # one directory per test process
```

Code coverage must be enabled: without instrumentation there are no counters to observe.

Supported platforms are macOS and the iOS simulator. On a device, the process can't write to a directory on the Mac that runs the tests.

## Skipping tests

A runner that knows which tests a change can't affect, such as Tuist's coverage-based selective testing, can have the package remove them before XCTest runs them. Set `TEST_COVERAGE_ATTRIBUTION_SKIP_FILE` to the absolute path of a UTF-8 file that lists them, one per line. A relative path is read from the test process's working directory, such as the simulator app's, where the file isn't.

```text
CheckoutTests/DiscountTests/testAppliesDiscount()
CheckoutTests/DiscountTests/testRoundsDown()
CheckoutUITests/PaymentTests/testPaysWithCard()
```

```bash
TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE="$PWD/skip.txt" xcodebuild test …
```

- **Names.** Each line is `module/suite/name`, the way `-skip-testing` names a test and the records name it: the test bundle, the class without its Swift module, and the test as the result bundle names it (`testAppliesDiscount()`). The selector works too (`testAppliesDiscount`), including the bridged selectors of throwing and asynchronous Swift tests (`…AndReturnError:`, `…WithCompletionHandler:`).
- **Only tests.** A line without exactly three components is ignored. Skip a whole target with `-skip-testing:CheckoutTests` instead. A suite is never skipped by naming it, because it can gain tests the list doesn't know about.
- **Forgiving.** Blank lines and tests that don't exist are ignored. An unreadable file skips nothing. Skipping doesn't depend on `TEST_COVERAGE_ATTRIBUTION_DIR`.
- **Where it applies.** `xcodebuild` passes the variable to the test process with the `TEST_RUNNER_` prefix: the app that hosts unit tests, and the runner of UI tests. It works with `test` and `test-without-building`, with `-only-testing`, and with parallel testing, where Xcode lists the tests, without the removed ones, before it hands them out to its clones. `swift test` reads it from the environment.
- **What a skipped test looks like.** It's removed from the suite XCTest builds for its class, so it doesn't run and isn't in the result bundle. A class whose tests are all removed doesn't run its class `setUp` and `tearDown`. A class with tests left runs them as usual, class `setUp` included.
- **XCTest only.** Swift Testing tests in the same target run as usual, even when listed.

## Output

The output is written under `$TEST_COVERAGE_ATTRIBUTION_DIR/<pid>/`, one directory per test process:

| File | Contents |
| --- | --- |
| `images.tsv` | One line per instrumented image: its index, the byte size of its counters, the addresses of its `__llvm_prf_data` and `__llvm_prf_cnts` sections, and its path. |
| `<n>.data`, `<n>.names` | Image `n`'s raw `__llvm_prf_data` and `__llvm_prf_names` sections: what maps a counter to its function. |
| `records.bin` | One record per scope. |
| `launches.tsv` | One line per app process a UI test launched, written when `XCUIApplication.launch()` or `activate()` returns: the process's pid, the test bundle, the suite and the test, separated by tabs. A launch outside a test, such as in a class `setUp`, has an empty test name. A pid is listed once, with the scope that launched it, even when later tests activate the same process. Only written by a process that launches an app. |

A scope is one of the following:
- an XCTest test;
- a Swift Testing test;
- a *gap*: whatever ran between two tests, such as a class `setUp`, a suite's one-time setup, or leaked background work.

Each record is laid out in the host's byte order, little-endian on every Apple platform, as follows:

- `u8` kind (`0` gap, `1` XCTest, `2` Swift Testing), `u8` flags (`1` overlapped), `u8` version (currently `1`), `u8` zero.
- The module, the suite and the test name, each a `u32` length followed by UTF-8 bytes. XCTest records name the test bundle as the module.
- `u32` count of images whose counters moved. For each image: `u32` image index, `u32` count, then `count` `u32` counter indices and `count` `u64` deltas (how much each counter moved).

The deltas are what turns counters into lines. In the image's coverage mapping (`__llvm_covfun`), a region's count is an expression over counters, so knowing which counters moved isn't enough.

## Guarantees

- It never resets or writes the coverage counters: Xcode's and SwiftPM's own coverage reports are unchanged.
- It never crashes or blocks the tests. Any failure stops recording, removes what it wrote for the process so a reader never gets partial output, and lets the tests run.
- Only one copy records per process. If the package ends up linked more than once into the same process, for example into two test bundles loaded by the same host, the first copy to load does the recording and the others forward to it. The Objective-C runtime then logs `Class TestCoverageAttributionObserver is implemented in both …` once, which is harmless.

## Limitations

- **Swift Testing isn't attributed or skipped.** See [Usage](#usage).
- **Skipping some of a class's tests uses a private method.** XCTest has no public way to remove tests from a class's suite, so the package uses `XCTestSuite`'s private `-setTests:`, which keeps the suite and the class `setUp` it runs. If a future Xcode removes it, a class with some tests listed runs all of them; a class with all of its tests listed is still skipped. A class that overrides `defaultTestSuite` without calling `super` isn't filtered.
- **UI tests record which app process each test launched, not the app's counters.** The app's coverage comes from the profile Xcode writes for each app process (`<uuid>-<pid>.profraw` beside the run's `Coverage.profdata`). The pid is read from `XCUIApplication`'s private `processID` property; if a future Xcode removes it, nothing is written. Processes the app starts itself, such as extensions, aren't listed.
- **Images loaded late aren't observed.** An image loaded after the first test starts, such as a framework the tests `dlopen`, is missing from the records.
- **The package's own code shows up in the records.** The package is instrumented like the code under test, so its functions appear in the records, and a reader should ignore them.

## Development

```bash
mise run build
mise run test   # runs the fixtures (SwiftPM, xcodebuild on macOS and an iOS simulator), checks the records and the skip list
mise run lint
```

## License

TestCoverageAttribution is released under the MIT license. See [LICENSE](LICENSE).
