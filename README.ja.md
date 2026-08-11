[English](./README.md) | 日本語

# swift-ios-recorder

開発中の iOS アプリの実行時を**計測して保持する**オンデバイス計器。撮った記録（スクショ + state + ログ）を Mac / MCP / AI へ流して、UI 確認ループの手作業を無くす。

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)

## 本質

**計測（measure）+ 保持（retain）が核。** Mac 連携・MCP 連携はその上に載る能力の 1 つ。
詳細な設計は [spec.md](./spec.md) を参照。

## 構成

| モジュール | 役割 |
|---|---|
| `iOSRecorder` | コア。Record / Artifact / 各ポート / Session / RingBufferStore / Log・StateSource（依存ゼロ） |
| `iOSRecorderScreenshot` | `ScreenshotSource`（UIKit drawHierarchy、iOS） |
| `iOSRecorderUI` | SwiftUI 統合（フロートボタン・シェイク・アプリ内ビューア） |
| `iOSRecorderBonjour` | Exporter / Receiver（同一 LAN 即時転送、Network framework） |
| `iOSRecorderStore` | RecordStore のファイル実装（Mac、1 record = 1 フォルダ） |
| `iOSRecorderMCP` | RecordStore を `list_captures` / `get_capture` / `search_events` / `get_event` に橋渡し（MCP stdio） |
| `ios-recorder` | Mac companion exe（`serve` / `mcp`） |

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-ios-recorder.git", .upToNextMinor(from: "0.6.0"))
]
```

```swift
.target(name: "YourTarget", dependencies: [
    .product(name: "iOSRecorder", package: "swift-ios-recorder"),           // コア（計測 + 保持）
    .product(name: "iOSRecorderUI", package: "swift-ios-recorder"),         // SwiftUI 統合
    .product(name: "iOSRecorderScreenshot", package: "swift-ios-recorder"), // スクショ計測（iOS）
    .product(name: "iOSRecorderBonjour", package: "swift-ios-recorder"),    // 同一 LAN の Mac へ転送
])
```

Mac companion（`ios-recorder` 実行ファイル）はこのリポジトリを `swift build` してビルドする。

## 使い方

### iOS アプリ側（DEBUG 限定）

```swift
import iOSRecorder
import iOSRecorderUI
import iOSRecorderScreenshot
import iOSRecorderBonjour

let store = RingBufferStore()
let session = Session(
    sources: [
        ScreenshotSource(),
        StateSource(encoding: { await appState.snapshot() })
    ],
    store: store,
    exporters: [BonjourExporter()]   // 同一 LAN の Mac へ即時送信
)
let controller = RecorderController(session: session, store: store)

// ルートに 1 行。タップ/シェイクで計測、長押しで一覧。
ContentView().recorder(controller)
```

### Mac 側

```sh
# Claude Code に MCP 登録するだけ。受信機は MCP プロセスに同居し、
# Claude Code の起動/終了に連動して起動/停止する（別デーモン不要）。
claude mcp add ios-recorder -- ios-recorder mcp
```

これで iPhone でフロートボタンを押す → Mac に届く → Claude Code が
`list_captures` / `get_capture`(maxDimension で縮小) / `search_events` / `get_event` / `delete_capture` / `clear_captures`
で画面+state を取得、という UI 確認ループが閉じる。

`ios-recorder serve` は受信機のみを単体起動する headless 運用向けの代替手段。

> バイナリ更新時はコピー後に `codesign --force --sign - <path>` で再署名すること
> （ad-hoc 署名が無効化され起動時に SIGKILL されるため）。

## 開発

```sh
swift build && swift test          # 48 tests / 13 suites
# iOS 専用ターゲットのコンパイル確認:
xcodebuild build -scheme iOSRecorderUI -destination 'generic/platform=iOS'
```
