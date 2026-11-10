#!/bin/bash
# Builds an Objective-C XCTest bundle, its tests and the C code they call instrumented for coverage,
# with the observer linked in, and runs it: run.sh <build directory> <counters>, where <counters> is
# `word` for clang's default 8-byte counters, `byte` for single-byte counters
# (`-mllvm -enable-single-byte-coverage`), or `byte-stripped` for single-byte counters in a bundle
# stripped of its local symbols, the profile version among them. Each single-byte bundle is padded
# so that only one of the observer's checks can catch it: `byte` has a whole number of 8-byte
# counters, so only its profile version tells, and `byte-stripped` hasn't.
set -euo pipefail

BUILD=$1
COUNTERS=$2
FIXTURE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$FIXTURE/../.." && pwd)
SDK=$(xcrun --show-sdk-path)
PLATFORM=$(xcrun --show-sdk-platform-path)
FRAMEWORKS=$PLATFORM/Developer/Library/Frameworks
BUNDLE=$BUILD/ByteCoverageTests.xctest
BINARY=$BUNDLE/Contents/MacOS/ByteCoverageTests
# The coverage flags, as positional parameters: macOS's bash 3.2 treats an empty array as unbound
# under `set -u`.
set -- -fprofile-instr-generate -fcoverage-mapping
if [ "$COUNTERS" != word ]; then set -- "$@" -mllvm -enable-single-byte-coverage; fi

link() {
    xcrun clang -bundle -fobjc-arc -isysroot "$SDK" -F "$FRAMEWORKS" -fprofile-instr-generate \
        "$BUILD"/*.o -o "$BINARY" -framework Foundation -framework XCTest \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS"
}

counters_size() {
    xcrun size -m "$BINARY" | awk '/__llvm_prf_cnts/ { print $3 }'
}

rm -rf "$BUILD"
mkdir -p "$BUNDLE/Contents/MacOS"
xcrun clang -c -fobjc-arc -fmodules -isysroot "$SDK" \
    -I "$ROOT/Sources/TestCoverageAttributionObserver/include" \
    "$ROOT/Sources/TestCoverageAttributionObserver/TestCoverageAttributionObserver.m" -o "$BUILD/observer.o"
xcrun clang -c -isysroot "$SDK" "$@" "$FIXTURE/Classify.c" -o "$BUILD/Classify.o"
xcrun clang -c -fobjc-arc -fmodules -isysroot "$SDK" -F "$FRAMEWORKS" "$@" \
    "$FIXTURE/ByteCoverageTests.m" -o "$BUILD/ByteCoverageTests.o"
/usr/libexec/PlistBuddy \
    -c "Add :CFBundleIdentifier string dev.tuist.ByteCoverageTests" \
    -c "Add :CFBundleExecutable string ByteCoverageTests" \
    -c "Add :CFBundlePackageType string BNDL" \
    "$BUNDLE/Contents/Info.plist" > /dev/null
link

# A function without branches has one single-byte counter.
SIZE=$(counters_size)
case $COUNTERS in
    byte) PADDING=$(((8 - SIZE % 8) % 8)) ;;
    byte-stripped) PADDING=$((SIZE % 8 == 0 ? 1 : 0)) ;;
    *) PADDING=0 ;;
esac
if [ "$PADDING" -gt 0 ]; then
    for i in $(seq "$PADDING"); do echo "int padding$i(void) { return $i; }"; done > "$BUILD/Padding.c"
    xcrun clang -c -isysroot "$SDK" "$@" "$BUILD/Padding.c" -o "$BUILD/Padding.o"
    link
fi
SIZE=$(counters_size)
case $COUNTERS in
    byte)
        if [ $((SIZE % 8)) -ne 0 ]; then
            echo "The counters section ($SIZE bytes) isn't a multiple of 8 bytes" >&2
            exit 1
        fi
        ;;
    byte-stripped)
        xcrun strip -x "$BINARY"
        if nm "$BINARY" | grep -q ___llvm_profile_raw_version; then
            echo "strip kept the profile version" >&2
            exit 1
        fi
        if [ $((SIZE % 8)) -eq 0 ]; then
            echo "The counters section ($SIZE bytes) is a multiple of 8 bytes" >&2
            exit 1
        fi
        ;;
esac
LLVM_PROFILE_FILE="$BUILD/default.profraw" xcrun xctest "$BUNDLE"
