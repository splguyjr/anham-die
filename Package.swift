// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnhamDie",
    platforms: [.macOS(.v15)],
    dependencies: [
        // CLT 툴체인엔 PreviewsMacros 플러그인이 없어 #Preview가 포함된 1.16.0+ 태그는 빌드 불가.
        // 1.15.0이 #Preview 없는 마지막 태그 — Xcode 도입 전까지 exact 고정 유지할 것.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0"),
        // 테스트 전용: CLT 툴체인엔 XCTest도 Testing 모듈도 없어 swift-testing을 소스로 빌드.
        // 앱 타깃 의존성 아님 — 배포 바이너리엔 포함되지 않는다.
        // 6.3.x 태그는 CLT 링커 검색 경로에 없는 lib_TestingInterop을 요구하므로 6.2.4 고정.
        .package(url: "https://github.com/swiftlang/swift-testing", exact: "6.2.4")
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
            dependencies: [
                "AnhamDieApp",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/AnhamDieCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
