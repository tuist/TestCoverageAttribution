// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "TestCoverageAttribution",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "TestCoverageAttribution",
            targets: ["TestCoverageAttribution"]
        ),
    ],
    targets: [
        .target(name: "TestCoverageAttributionObserver"),
        .target(
            name: "TestCoverageAttribution",
            dependencies: ["TestCoverageAttributionObserver"]
        ),
        .testTarget(name: "TestCoverageAttributionTests"),
    ]
)
