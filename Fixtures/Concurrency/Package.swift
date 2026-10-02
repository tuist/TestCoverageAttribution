// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Concurrency",
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(name: "Concurrency"),
        .testTarget(
            name: "ConcurrencyTests",
            dependencies: [
                "Concurrency",
                .product(name: "TestCoverageAttribution", package: "TestCoverageAttribution"),
            ]
        ),
    ]
)
