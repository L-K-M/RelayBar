// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RelayBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RelayBar", targets: ["RelayBar"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/gonzalezreal/swift-markdown-ui.git",
            exact: "2.4.1"
        ),
        .package(
            url: "https://github.com/smittytone/HighlighterSwift.git",
            exact: "3.1.0"
        ),
        .package(
            url: "https://github.com/mgriebling/SwiftMath.git",
            exact: "1.7.3"
        )
    ],
    targets: [
        .executableTarget(
            name: "RelayBar",
            dependencies: [
                .product(name: "Highlighter", package: "HighlighterSwift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftMath", package: "SwiftMath")
            ],
            path: "Sources/RelayBar",
            resources: [
                .copy("Resources/THIRD_PARTY_NOTICES.txt")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "RelayBarTests",
            dependencies: ["RelayBar"],
            path: "Tests/RelayBarTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
