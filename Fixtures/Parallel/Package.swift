// swift-tools-version: 6.1

import PackageDescription

/// Function-entry tracking, as Tuist turns it on for the code a test target links statically.
/// swiftc's driver takes `-sanitize-coverage` only with a sanitizer; `undefined` adds no checks to
/// Swift code.
let functionTracking: [SwiftSetting] = [
    .unsafeFlags(["-sanitize=undefined", "-sanitize-coverage=func,trace-pc-guard,pc-table"]),
]

let package = Package(
    name: "Parallel",
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(name: "Parallel", swiftSettings: functionTracking),
        .testTarget(
            name: "ParallelTests",
            dependencies: [
                "Parallel",
                .product(name: "TestCoverageAttribution", package: "TestCoverageAttribution"),
            ],
            swiftSettings: functionTracking,
        ),
    ],
)
