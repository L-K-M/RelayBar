// swift-tools-version: 5.9

import PackageDescription

let strictConcurrency: SwiftSetting = .enableExperimentalFeature("StrictConcurrency")

var products: [Product] = [
    .executable(name: "RelayBar", targets: ["RelayBar"]),
    .library(name: "RelayBarCore", targets: ["RelayBarCore"])
]

var targets: [Target] = [
    // Platform-neutral engine shared by the macOS app and the Linux tray.
    .target(
        name: "RelayBarCore",
        swiftSettings: [strictConcurrency]
    )
]

// The Linux-only front end is gated at the manifest level: `swift test` on
// macOS builds every target, and its runner has no GTK headers.
#if os(Linux)
targets += [
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
        swiftSettings: [strictConcurrency]
    )
]
products += [
    .executable(name: "RelayBarTray", targets: ["RelayBarTray"])
]
#endif

targets += [
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
        swiftSettings: [strictConcurrency]
    ),
    .testTarget(
        name: "RelayBarTests",
        dependencies: [
            "RelayBar",
            "RelayBarCore"
        ],
        path: "Tests/RelayBarTests",
        swiftSettings: [strictConcurrency]
    ),
    .testTarget(
        name: "RelayBarCoreTests",
        dependencies: [
            "RelayBarCore"
        ],
        path: "Tests/RelayBarCoreTests",
        swiftSettings: [strictConcurrency]
    )
]

let package = Package(
    name: "RelayBar",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
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
    targets: targets
)
