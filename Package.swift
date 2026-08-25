// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RelayBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RelayBar", targets: ["RelayBar"]),
        .executable(name: "RelayBarTray", targets: ["RelayBarTray"]),
        .library(name: "RelayBarCore", targets: ["RelayBarCore"])
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
        // Platform-neutral engine shared by the macOS app and the Linux tray.
        .target(
            name: "RelayBarCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        // libayatana-appindicator3 + GTK3 headers, resolved via pkg-config on
        // Linux only; never built on macOS because nothing there imports it.
        .systemLibrary(
            name: "CAppIndicator",
            pkgConfig: "ayatana-appindicator3-0.1",
            providers: [
                .apt(["libayatana-appindicator3-dev"])
            ]
        ),
        .executableTarget(
            name: "RelayBarTray",
            dependencies: [
                "RelayBarCore",
                "CAppIndicator"
            ],
            path: "Sources/RelayBarTray",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "RelayBar",
            dependencies: [
                "RelayBarCore",
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
            dependencies: [
                "RelayBar",
                "RelayBarCore"
            ],
            path: "Tests/RelayBarTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "RelayBarCoreTests",
            dependencies: [
                "RelayBarCore"
            ],
            path: "Tests/RelayBarCoreTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
