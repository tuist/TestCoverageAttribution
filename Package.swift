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
            dependencies: [
                // The observer reads Mach-O images, so elsewhere the package builds without it and
                // records nothing: a cross-platform test target can link it unconditionally.
                .target(
                    name: "TestCoverageAttributionObserver",
                    condition: .when(platforms: [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS])
                ),
            ]
        ),
        .testTarget(name: "TestCoverageAttributionTests"),
    ]
)
