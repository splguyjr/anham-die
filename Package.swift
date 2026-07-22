// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnhamDie",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "AnhamDieApp",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/AnhamDieApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AnhamDieCoreTests",
            dependencies: ["AnhamDieApp"],
            path: "Tests/AnhamDieCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
