# TestCoverageAttribution

[![TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution/actions/workflows/test-coverage-attribution.yml/badge.svg)](https://github.com/tuist/TestCoverageAttribution/actions/workflows/test-coverage-attribution.yml)

> [!WARNING]
> This package is experimental and in early development. Its API, the environment variables it reads and the format of what it records may change without notice between versions, and it hasn't been tested beyond the cases in this repository. Don't depend on it for anything critical yet.

TestCoverageAttribution records which code each test executes. Xcode's code coverage tells you what a whole test run covered. This package attributes that coverage to the individual test that executed it. It can also skip a list of tests before they run.

[Tuist](https://tuist.dev) uses it to collect per-test coverage evidence, which lets a run that skips tests reuse those tests' coverage from an earlier run, and to skip the tests a change can't affect.

Both work for XCTest tests, UI tests included. Swift Testing tests get them in suites that have the `.coverageAttribution` trait: evidence when a test doesn't run at the same time as another, and skipping with Swift 6.3 (Xcode 26.4) or later.

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

**Swift Testing** needs the `.coverageAttribution` trait on each suite, because Swift Testing has no observation center a library can join. The trait applies to the suites nested in the one that has it.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

Swift Testing runs tests in parallel within a process by default, and the counters can't tell tests that run at the same time apart: their records are marked overlapped, and a reader should give them no evidence. A test gets evidence when no other test runs at the same time, as in a run with parallelization off; `.serialized` only orders a suite's own tests. Tests in suites without the trait run as usual and get none.

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

A runner that knows which tests a change can't affect, such as Tuist's coverage-based selective testing, can have the package skip them before they run. Set `TEST_COVERAGE_ATTRIBUTION_SKIP_FILE` to the absolute path of a UTF-8 file that lists them, one per line. A relative path is read from the test process's working directory, such as the simulator app's, where the file isn't.

```text
CheckoutTests/DiscountTests/testAppliesDiscount()
CheckoutTests/DiscountTests/testRoundsDown()
CheckoutUITests/PaymentTests/testPaysWithCard()
```

```bash
TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE="$PWD/skip.txt" xcodebuild test …
```

- **Names.** Each line is `module/suite/name`, the way `-skip-testing` names a test and the records name it: the test bundle, the class without its Swift module, and the test as the result bundle names it (`testAppliesDiscount()`). The selector works too (`testAppliesDiscount`), including the bridged selectors of throwing and asynchronous Swift tests (`…AndReturnError:`, `…WithCompletionHandler:`). A Swift Testing suite nested in another is named by its whole path, `module/Outer/Inner/name`: the first component is the module, the last the test, and everything between the suite.
- **Only tests.** A line with fewer than three components, or an empty one, is ignored. Skip a whole target with `-skip-testing:CheckoutTests` instead. A suite is never skipped by naming it, because it can gain tests the list doesn't know about.
- **Forgiving.** Blank lines and tests that don't exist are ignored. An unreadable file skips nothing. Skipping doesn't depend on `TEST_COVERAGE_ATTRIBUTION_DIR`.
- **Where it applies.** `xcodebuild` passes the variable to the test process with the `TEST_RUNNER_` prefix: the app that hosts unit tests, and the runner of UI tests. It works with `test` and `test-without-building`, with `-only-testing`, and with parallel testing, where Xcode lists the tests, without the removed ones, before it hands them out to its clones. `swift test` reads it from the environment.
- **What a skipped test looks like.** It's removed from the suite XCTest builds for its class, so it doesn't run and isn't in the result bundle. A class whose tests are all removed doesn't run its class `setUp` and `tearDown`. A class with tests left runs them as usual, class `setUp` included.
- **Swift Testing.** In a suite with the `.coverageAttribution` trait, a listed test is cancelled before it starts, every argument of a parameterized test included, and reported as skipped, whether tests run in parallel or not. The line names it as the records do: the Swift module, every suite the test is nested in, outermost first (`CheckoutTests/Pricing/Discounts/appliesDiscount()`), as `-skip-testing` names it, and the test's display name when it declares one (`Applies a discount`), its function otherwise (`appliesDiscount()`). A nested test also matches a line that names it by its innermost suite alone (`CheckoutTests/Discounts/appliesDiscount()`), as Tuist did before it recorded whole paths. This needs Swift 6.3 (Xcode 26.4) or later: before, a trait can skip a test only by not running it, which reports it as passed, so the listed tests run. Listed tests in suites without the trait run too.

### Unskippable tests

Coverage only sees the code a test runs. A test whose real inputs are something else, such as fixtures, resources, the network or the environment, can break without any covered code changing. Mark it unskippable and it always runs, even when the skip list names it.

**Swift Testing.** Add `.unskippable` to a test, or to a suite to cover every test in it and its nested suites, and `.skippable` to opt a test or a nested suite back in. The most specific one wins: a test's trait overrides its suite's, and a nested suite's overrides its parent's. The suite still needs the `.coverageAttribution` trait, since it's what skips listed tests.

```swift
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }               // always runs
    @Test(.skippable) func formatsTheDate() { … }      // can be skipped
}
```

**XCTest.** Declare class methods with these names, which the package looks up at run time, so the test target needs nothing from the package. From Swift they need `@objc`.

| Class method | Type | Meaning |
| --- | --- | --- |
| `unskippableTests` | `[String]` / `NSArray<NSString *> *` | The class's tests that always run. |
| `isUnskippable` | `Bool` / `BOOL` | Every test of the class always runs. |
| `skippableTests` | `[String]` / `NSArray<NSString *> *` | The tests the list can still skip in a class that's unskippable. |

```swift
final class FixtureTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}

final class NetworkTests: XCTestCase {
    @objc static let isUnskippable = true
    @objc static let skippableTests = ["testFormatsTheDate"]
}
```

```objc
@implementation NetworkTests
+ (BOOL)isUnskippable { return YES; }
@end
```

A test is named as in the skip list: `testParsesTheFixtures`, `testParsesTheFixtures()` or its selector. The lists win over the class: a test in `unskippableTests` always runs, a test in `skippableTests` can be skipped, and any other follows `isUnskippable`. A subclass inherits these methods and can override them. A method with a different return type is ignored.

**What the runner sees.** An unskippable test runs and is reported as usual. When the package records, each unskippable test that runs is listed in [`unskippable.tsv`](#output), so a runner that writes the skip list can stop listing it. A listed unskippable test is a *forced run*.

## Output

The output is written under `$TEST_COVERAGE_ATTRIBUTION_DIR/<pid>/`, one directory per test process:

| File | Contents |
| --- | --- |
| `images.tsv` | One line per instrumented image: its index, the byte size of its counters, the addresses of its `__llvm_prf_data` and `__llvm_prf_cnts` sections, and its path. |
| `<n>.data`, `<n>.names` | Image `n`'s raw `__llvm_prf_data` and `__llvm_prf_names` sections: what maps a counter to its function. |
| `records.bin` | One record per scope. |
| `launches.tsv` | One line per app process a UI test launched, written when `XCUIApplication.launch()` or `activate()` returns: the process's pid, the test bundle, the suite and the test, separated by tabs. A launch outside a test, such as in a class `setUp`, has an empty test name. A pid is listed once, with the scope that launched it, even when later tests activate the same process. Only written by a process that launches an app. |
| `unskippable.tsv` | One line per unskippable test that ran, written when it starts: the module, the suite and the test, named as in its record (an XCTest test as XCTest names it, `testParsesTheFixtures`), then `1` if the skip list named it (a forced run) or `0` if not, separated by tabs. A test is listed once per process. A name with a tab or a line break isn't written. Only written by a process that runs an unskippable test. |

A scope is one of the following:
- an XCTest test;
- a Swift Testing test;
- a *gap*: whatever ran between two tests, such as a class `setUp`, a suite's one-time setup, or leaked background work.

Each record is laid out in the host's byte order, little-endian on every Apple platform, as follows:

- `u8` kind (`0` gap, `1` XCTest, `2` Swift Testing), `u8` flags (`1` overlapped), `u8` version (currently `1`), `u8` zero.
- The module, the suite and the test name, each a `u32` length followed by UTF-8 bytes. XCTest records name the test bundle as the module. Swift Testing records name the Swift module, and every suite the test is nested in, outermost first and separated by `/` (`Outer/Inner`), as the result bundle does.
- `u32` count of images whose counters moved. For each image: `u32` image index, `u32` count, then `count` `u32` counter indices and `count` `u64` deltas (how much each counter moved).

The deltas are what turns counters into lines. In the image's coverage mapping (`__llvm_covfun`), a region's count is an expression over counters, so knowing which counters moved isn't enough.

## Guarantees

- It never resets or writes the coverage counters: Xcode's and SwiftPM's own coverage reports are unchanged.
- It never crashes or blocks the tests. Any failure stops recording, removes what it wrote for the process so a reader never gets partial output, and lets the tests run.
- Only one copy records per process. If the package ends up linked more than once into the same process, for example into two test bundles loaded by the same host, the first copy to load does the recording and the others forward to it. The Objective-C runtime then logs `Class TestCoverageAttributionObserver is implemented in both …` once, which is harmless.

## Limitations

- **Swift Testing needs the trait.** Tests in suites without it aren't attributed or skipped, tests that run at the same time get no evidence, and skipping them needs Swift 6.3. See [Usage](#usage).
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
