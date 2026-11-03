import ProjectDescription

/// An app, its UI tests and its hosted unit tests, which link the package from the repository:
/// `AttributionTests` generates it with Tuist and runs it on an iOS simulator. `AppUITests` checks
/// the launches the observer lists; `AppTests` and `SkipUITests` check the skip list.
let project = Project(
    name: "UITests",
    packages: [.local(path: "../..")],
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.TestCoverageAttribution.App",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": ["UIColorName": ""]]),
            sources: ["App/**"],
        ),
        .target(
            name: "AppUITests",
            destinations: [.iPhone],
            product: .uiTests,
            bundleId: "dev.tuist.TestCoverageAttribution.AppUITests",
            deploymentTargets: .iOS("17.0"),
            sources: ["UITests/**"],
            dependencies: [
                .target(name: "App"),
                .package(product: "TestCoverageAttribution"),
            ],
        ),
        .target(
            name: "AppTests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "dev.tuist.TestCoverageAttribution.AppTests",
            deploymentTargets: .iOS("17.0"),
            sources: ["AppTests/**"],
            dependencies: [
                .target(name: "App"),
                .package(product: "TestCoverageAttribution"),
            ],
        ),
        .target(
            name: "SkipUITests",
            destinations: [.iPhone],
            product: .uiTests,
            bundleId: "dev.tuist.TestCoverageAttribution.SkipUITests",
            deploymentTargets: .iOS("17.0"),
            sources: ["SkipUITests/**"],
            dependencies: [
                .target(name: "App"),
                .package(product: "TestCoverageAttribution"),
            ],
        ),
    ],
    schemes: [
        .scheme(
            name: "AppUITests",
            buildAction: .buildAction(targets: ["App"]),
            testAction: .targets(["AppUITests"], options: .options(coverage: true, codeCoverageTargets: ["App"])),
        ),
        .scheme(
            name: "SkipList",
            buildAction: .buildAction(targets: ["App"]),
            testAction: .targets(["AppTests", "SkipUITests"]),
        ),
    ],
)
