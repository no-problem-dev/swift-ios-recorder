# ``iOSRecorderUI``

`iOSRecorder` コアと SwiftUI を繋ぐ UI 統合ライブラリ。フロートボタン・シェイク起動・アプリ内ビューア・デバッグパネルを 1 行の View modifier で組み込める。

## Overview

`iOSRecorderUI` は、デバッグ UI をアプリ本体のコードを汚さずに組み込む手段を提供します。
`RecorderController` が `Session`・`NetworkLogStore`・`ExportReachability` などをまとめて状態を管理し、
SwiftUI の `View` に `.recorder(controller:)` modifier を付けるだけで有効になります。

```swift
import SwiftUI
import iOSRecorder
import iOSRecorderUI

@main
struct MyApp: App {
    let controller: RecorderController

    init() {
        let store = RingBufferStore(capacity: 50)
        let session = Session(sources: [screenshotSource], store: store)
        controller = RecorderController(session: session, store: store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .recorder(controller: controller)
        }
    }
}
```

`.recorder(controller:)` はフローティングボタンをオーバーレイウィンドウに描画し、
タップまたはシェイクでデバッグパネルを開きます。パネルにはキャプチャ一覧・通信ログ・
デバッグタイムライン・メトリクスダッシュボードが自動的に組み込まれます（オプションで渡した
ストアに応じてセクションが出現します）。

デバッグコンソールの構成をカスタマイズしたい場合は `DebugConsole` と `DebugSection` で
任意のセクションを定義できます。`DebugItem` でチェックボックス・トグル・ボタン等の UI 要素を宣言し、
`DebugStatBuilder` でリアルタイム統計を表示するセクションを構築します。

## Topics

### エントリポイント

- ``RecorderController``

### デバッグパネル設定

- ``DebugConsole``
- ``DebugSection``
- ``DebugConsoleBuilder``
- ``DebugStatBuilder``

### パネル要素

- ``DebugItem``
- ``DebugStat``
- ``DebugPreviewElement``
- ``PreviewStat``
- ``PreviewStatus``

### メトリクス・ダッシュボード

- ``MetricsDashboardView``
