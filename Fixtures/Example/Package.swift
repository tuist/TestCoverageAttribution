// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Example",
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(name: "Example"),
        .testTarget(
            name: "ExampleTests",
            dependencies: [
                "Example",
                .product(name: "TestCoverageAttribution", package: "TestCoverageAttribution"),
            ]
        ),
        .testTarget(
            name: "ExampleXCTestOnlyTests",
            dependencies: [
                "Example",
                .product(name: "TestCoverageAttribution", package: "TestCoverageAttribution"),
            ]
        ),
    ]
)
