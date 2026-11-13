# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.2] - 2026-11-13
### Details
#### Bug Fixes
- Revert the whole Swift Testing suite paths of 0.5.1 by @esnunes in [#43](https://github.com/tuist/TestCoverageAttribution/pull/43)

## [0.5.1] - 2026-11-13
### Details
#### Bug Fixes
- Still skip nested Swift Testing tests listed by their innermost suite by @esnunes
- Name Swift Testing tests under their whole suite path by @esnunes

#### Documentation
- Drop the claim that a display name with a slash can't be listed by @esnunes

#### Testing
- Cover a Swift Testing suite nested ten levels deep by @esnunes in [#42](https://github.com/tuist/TestCoverageAttribution/pull/42)

## [0.5.0] - 2026-11-10
### Details
#### Features
- Keep tests marked unskippable from being skipped by @esnunes in [#40](https://github.com/tuist/TestCoverageAttribution/pull/40)

## [0.4.0] - 2026-11-09
### Details
#### Features
- Skip the Swift Testing tests a skip list names by @esnunes

#### Testing
- Run the SwiftPM Swift Testing skip test with the skip list's tests by @esnunes in [#38](https://github.com/tuist/TestCoverageAttribution/pull/38)

## [0.3.1] - 2026-11-04
### Details
#### Miscellaneous Tasks
- Remove a stray coverage profile and ignore *.profraw by @esnunes in [#34](https://github.com/tuist/TestCoverageAttribution/pull/34)

## [0.3.0] - 2026-11-03
### Details
#### Bug Fixes
- Run the shard check on this Xcode's build, and require an absolute skip list path by @esnunes in [#32](https://github.com/tuist/TestCoverageAttribution/pull/32)

#### Features
- Skip the XCTest tests a skip list names by @esnunes

#### Testing
- Assert the skip list on the result bundle alone, with an xcodebuild timeout by @esnunes

## [0.2.0] - 2026-10-27
### Details
#### Bug Fixes
- List an app process once, with the scope that launched it by @esnunes

#### Documentation
- Clarify why the UI test fixture is a Tuist project by @esnunes

#### Features
- Record the app processes each UI test launches by @esnunes

#### Styling
- Apply SwiftFormat 0.64.4 formatting to the UI test fixture by @esnunes in [#27](https://github.com/tuist/TestCoverageAttribution/pull/27)

## [0.1.2] - 2026-10-27
### Details
#### Styling
- Apply SwiftFormat 0.64.4 formatting by @esnunes in [#25](https://github.com/tuist/TestCoverageAttribution/pull/25)

## [0.1.1] - 2026-10-04
### Details
#### Documentation
- Install from 0.1.0, and title release notes with the version by @esnunes in [#21](https://github.com/tuist/TestCoverageAttribution/pull/21)

## [0.1.0] - 2026-10-04
### Details
#### Bug Fixes
- Build on Linux and record nothing there by @esnunes in [#13](https://github.com/tuist/TestCoverageAttribution/pull/13)
- Never leave partial or torn output behind by @esnunes in [#11](https://github.com/tuist/TestCoverageAttribution/pull/11)
- Mark every overlapping scope and open one scope per test by @esnunes in [#5](https://github.com/tuist/TestCoverageAttribution/pull/5)

#### Documentation
- Keep the output directory in the examples and drop .serialized by @esnunes in [#16](https://github.com/tuist/TestCoverageAttribution/pull/16)
- Say how to serialize attribution runs and list the limitations by @esnunes
- Say the package is experimental and in early development by @esnunes

#### Features
- Record which coverage counters each test moves by @esnunes

#### Miscellaneous Tasks
- Release with git-cliff and check that PR titles are conventional by @esnunes in [#20](https://github.com/tuist/TestCoverageAttribution/pull/20)
- Run the macOS jobs on Tuist Runners by @esnunes in [#18](https://github.com/tuist/TestCoverageAttribution/pull/18)
- Build the package and run a consumer's tests on Linux by @esnunes
- Run clang's static analyzer on the Objective-C observer by @esnunes in [#10](https://github.com/tuist/TestCoverageAttribution/pull/10)
- Scan the Swift sources and workflows with CodeQL by @esnunes in [#3](https://github.com/tuist/TestCoverageAttribution/pull/3)
- Add a security policy and code owners by @esnunes in [#4](https://github.com/tuist/TestCoverageAttribution/pull/4)
- Pin actions to commit SHAs and scope the token to read by @esnunes in [#2](https://github.com/tuist/TestCoverageAttribution/pull/2)

#### Testing
- Keep Xcode's destinations in the simulator failure message by @esnunes in [#19](https://github.com/tuist/TestCoverageAttribution/pull/19)
- Create an iPhone simulator when the runner has none by @esnunes
- Pick a simulator the selected Xcode can run, and pin Xcode 26.2 by @esnunes in [#15](https://github.com/tuist/TestCoverageAttribution/pull/15)
- Cover the iOS simulator, static archives and the coverage report by @esnunes

## New Contributors
* @esnunes made their first contribution
* @renovate[bot] made their first contribution in [#17](https://github.com/tuist/TestCoverageAttribution/pull/17)
[0.5.2]: https://github.com/tuist/TestCoverageAttribution/compare/0.5.1..0.5.2
[0.5.1]: https://github.com/tuist/TestCoverageAttribution/compare/0.5.0..0.5.1
[0.5.0]: https://github.com/tuist/TestCoverageAttribution/compare/0.4.0..0.5.0
[0.4.0]: https://github.com/tuist/TestCoverageAttribution/compare/0.3.1..0.4.0
[0.3.1]: https://github.com/tuist/TestCoverageAttribution/compare/0.3.0..0.3.1
[0.3.0]: https://github.com/tuist/TestCoverageAttribution/compare/0.2.0..0.3.0
[0.2.0]: https://github.com/tuist/TestCoverageAttribution/compare/0.1.2..0.2.0
[0.1.2]: https://github.com/tuist/TestCoverageAttribution/compare/0.1.1..0.1.2
[0.1.1]: https://github.com/tuist/TestCoverageAttribution/compare/0.1.0..0.1.1

<!-- generated by git-cliff -->
