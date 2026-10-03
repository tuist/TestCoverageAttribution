#!/bin/bash
# Links the observer into an XCTest bundle from a static archive, as Tuist links packages by
# default, and runs the bundle: run.sh <build directory> <objc|no-objc>.
set -euo pipefail

BUILD=$1
MODE=$2
FIXTURE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$FIXTURE/../.." && pwd)
SDK=$(xcrun --show-sdk-path)
PLATFORM=$(xcrun --show-sdk-platform-path)
FRAMEWORKS=$PLATFORM/Developer/Library/Frameworks
LIBRARIES=$PLATFORM/Developer/usr/lib
# The extra linker flags, as positional parameters: macOS's bash 3.2 treats an empty array as
# unbound under `set -u`.
set --
if [ "$MODE" = objc ]; then set -- -Xlinker -ObjC; fi

rm -rf "$BUILD"
mkdir -p "$BUILD/ArchiveTests.xctest/Contents/MacOS"
xcrun clang -c -fobjc-arc -fmodules -isysroot "$SDK" \
    -I "$ROOT/Sources/TestCoverageAttributionObserver/include" \
    "$ROOT/Sources/TestCoverageAttributionObserver/TestCoverageAttributionObserver.m" -o "$BUILD/observer.o"
ar rcs "$BUILD/libTestCoverageAttributionObserver.a" "$BUILD/observer.o"
/usr/libexec/PlistBuddy \
    -c "Add :CFBundleIdentifier string dev.tuist.ArchiveTests" \
    -c "Add :CFBundleExecutable string ArchiveTests" \
    -c "Add :CFBundlePackageType string BNDL" \
    "$BUILD/ArchiveTests.xctest/Contents/Info.plist" > /dev/null
xcrun swiftc -sdk "$SDK" -F "$FRAMEWORKS" -I "$LIBRARIES" -L "$LIBRARIES" \
    -profile-generate -profile-coverage-mapping -emit-library -Xlinker -bundle \
    "$FIXTURE/ArchiveTests.swift" -o "$BUILD/ArchiveTests.xctest/Contents/MacOS/ArchiveTests" \
    -framework XCTest -L "$BUILD" -lTestCoverageAttributionObserver "$@" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$LIBRARIES"
xcrun xctest "$BUILD/ArchiveTests.xctest"
