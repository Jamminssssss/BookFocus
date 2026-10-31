// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BookFocusCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BookFocusCore", targets: ["BookFocusCore"])
    ],
    targets: [
        .target(
            name: "BookFocusCore",
            path: "Shared",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "BookFocusCoreChecks",
            dependencies: ["BookFocusCore"],
            path: "Tests/BookFocusCoreChecks"
        )
    ]
)
