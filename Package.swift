// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "iOSRecorder",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // コア: 計測 + 保持（プラットフォーム非依存・依存ゼロ）
        .library(name: "iOSRecorder", targets: ["iOSRecorder"]),
        // 能力（capability）: 周辺。差し替え可能なアダプタ群
        .library(name: "iOSRecorderUI", targets: ["iOSRecorderUI"]),
        .library(name: "iOSRecorderScreenshot", targets: ["iOSRecorderScreenshot"]),
        .library(name: "iOSRecorderNetwork", targets: ["iOSRecorderNetwork"]),
        .library(name: "iOSRecorderBonjour", targets: ["iOSRecorderBonjour"]),
        .library(name: "iOSRecorderStore", targets: ["iOSRecorderStore"]),
        .library(name: "iOSRecorderMCP", targets: ["iOSRecorderMCP"]),
        // 下流の消費者（Mac companion）
        .executable(name: "ios-recorder", targets: ["ios-recorder"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
        // 任意データの構造表示（DebugTimeline 詳細）に使う。モノレポ各所と同じ URL identity。
        .package(url: "https://github.com/no-problem-dev/swift-structured-data.git", from: "1.3.0"),
        // デバッグ UI のデザイントークン/コンポーネント。UI 層（iOSRecorderUI）でのみ使う。
        .package(url: "https://github.com/no-problem-dev/swift-design-system.git", from: "1.2.0"),
    ],
    targets: [
        // ── コア ──────────────────────────────────────────────
        .target(name: "iOSRecorder"),

        // ── 能力アダプタ ───────────────────────────────────────
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

        // ── 合成ルート（Mac exe） ──────────────────────────────
        .executableTarget(
            name: "ios-recorder",
            dependencies: ["iOSRecorder", "iOSRecorderStore", "iOSRecorderBonjour", "iOSRecorderMCP"]
        ),

        // ── テスト基盤: ポートを差し替えるための共有 Fake/Fixture ──
        .target(name: "iOSRecorderTestSupport", dependencies: ["iOSRecorder"]),

        // ── テストターゲット（ターゲット境界ごとに独立検証） ──────
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
