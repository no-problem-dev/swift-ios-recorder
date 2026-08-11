// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "iOSRecorder",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Core: measuring and keeping. Platform independent, no dependencies.
        .library(name: "iOSRecorder", targets: ["iOSRecorder"]),
        // Capabilities: replaceable adapters around the core.
        .library(name: "iOSRecorderUI", targets: ["iOSRecorderUI"]),
        .library(name: "iOSRecorderScreenshot", targets: ["iOSRecorderScreenshot"]),
        .library(name: "iOSRecorderNetwork", targets: ["iOSRecorderNetwork"]),
        .library(name: "iOSRecorderBonjour", targets: ["iOSRecorderBonjour"]),
        .library(name: "iOSRecorderStore", targets: ["iOSRecorderStore"]),
        .library(name: "iOSRecorderMCP", targets: ["iOSRecorderMCP"]),
        // The downstream consumer: the Mac companion.
        .executable(name: "ios-recorder", targets: ["ios-recorder"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
        // Structured display of arbitrary payloads in the debug timeline detail view.
        // Same URL identity as everywhere else in the monorepo.
        .package(url: "https://github.com/no-problem-dev/swift-structured-data.git", from: "3.0.0"),
        // Design tokens and components for the debug UI. Used by iOSRecorderUI only.
        .package(url: "https://github.com/no-problem-dev/swift-design-system.git", from: "3.0.0"),
    ],
    targets: [
        // ── Core ──────────────────────────────────────────────
        .target(name: "iOSRecorder"),

        // ── Capability adapters ───────────────────────────────
        .target(
            name: "iOSRecorderUI",
            dependencies: [
                "iOSRecorder", "iOSRecorderNetwork", "iOSRecorderBonjour",
                .product(name: "StructuredDataCore", package: "swift-structured-data"),
                .product(name: "JSONParsing", package: "swift-structured-data"),
                .product(name: "DesignSystem", package: "swift-design-system"),
            ]
        ),
        .target(name: "iOSRecorderScreenshot", dependencies: ["iOSRecorder"]),
        .target(name: "iOSRecorderNetwork", dependencies: ["iOSRecorder"]),
        .target(name: "iOSRecorderBonjour", dependencies: ["iOSRecorder"]),
        .target(name: "iOSRecorderStore", dependencies: ["iOSRecorder"]),
        .target(name: "iOSRecorderMCP", dependencies: ["iOSRecorder"]),

        // ── Composition root (Mac executable) ─────────────────
        .executableTarget(
            name: "ios-recorder",
            dependencies: ["iOSRecorder", "iOSRecorderStore", "iOSRecorderBonjour", "iOSRecorderMCP"]
        ),

        // ── Test support: shared fakes and fixtures for the ports ──
        .target(name: "iOSRecorderTestSupport", dependencies: ["iOSRecorder"]),

        // ── Test targets: one per target boundary, verified alone ──
        .testTarget(
            name: "iOSRecorderTests",
            dependencies: ["iOSRecorder", "iOSRecorderTestSupport"]
        ),
        .testTarget(
            name: "iOSRecorderStoreTests",
            dependencies: ["iOSRecorderStore", "iOSRecorder", "iOSRecorderTestSupport"]
        ),
        .testTarget(
            name: "iOSRecorderMCPTests",
            dependencies: ["iOSRecorderMCP", "iOSRecorder", "iOSRecorderTestSupport"]
        ),
        .testTarget(
            name: "iOSRecorderBonjourTests",
            dependencies: ["iOSRecorderBonjour", "iOSRecorder", "iOSRecorderTestSupport"]
        ),
        .testTarget(
            name: "iOSRecorderUITests",
            dependencies: ["iOSRecorderUI", "iOSRecorder", "iOSRecorderTestSupport"]
        ),
        .testTarget(
            name: "iOSRecorderNetworkTests",
            dependencies: ["iOSRecorderNetwork", "iOSRecorder"]
        ),
        .testTarget(
            name: "iOSRecorderScreenshotTests",
            dependencies: ["iOSRecorderScreenshot"]
        )
    ]
)
