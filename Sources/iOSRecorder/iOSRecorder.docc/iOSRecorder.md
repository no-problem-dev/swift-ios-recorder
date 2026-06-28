# ``iOSRecorder``

開発中の iOS アプリの実行時状態を**計測して保持する**コアライブラリ。スクリーンショット・状態 JSON・ログを 1 件のキャプチャとしてまとめ、Mac・MCP・AI ツールへ流すための基盤を提供する。依存ゼロで、アダプタ（UI/Bonjour/Store/MCP）の置き換えが可能なポート設計。

## Overview

`iOSRecorder` はパッケージ全体のコア。`Session` がトリガを受けて `Source` を並列実行し、
集めたデータを `Artifact` の配列として `Record` にまとめ、`RecordStore` に保存する。
必要に応じて `Exporter` へ非同期配送し、失敗を握り潰さずに `ExportOutcome` として記録する。

```swift
import iOSRecorder

// セッションを組み立てる
let store = RingBufferStore(capacity: 50)
let session = Session(
    sources: [logSource, stateSource],
    store: store
)

// キャプチャを取る
let id = try await session.capture(screenName: "Dashboard", tags: ["release"])

// 後から記録を取り出す
let record = try await store.fetch(id)
print(record.artifacts.map(\.kind.rawValue))
```

このモジュールは iOS / macOS どちらでも動作し、UIKit にも SwiftUI にも依存しない。
各拡張ライブラリは以下の役割を担う。

- UI の組み込み・デバッグパネル表示は `iOSRecorderUI`
- キャプチャにスクリーンショットを添付するには `iOSRecorderScreenshot`
- HTTP 通信ログをキャプチャに含めるには `iOSRecorderNetwork`
- 記録を Bonjour 経由で Mac へ転送するには `iOSRecorderBonjour`
- アプリ終了後も記録を残すファイル永続化は `iOSRecorderStore`
- キャプチャを MCP ツールとして AI エージェントへ公開するには `iOSRecorderMCP`

## Topics

### セッション管理

- ``Session``

### キャプチャ・データモデル

- ``Record``
- ``RecordMetadata``
- ``RecordSummary``
- ``RecordID``
- ``SessionID``
- ``Artifact``
- ``ArtifactKind``
- ``RecordContext``
- ``RecordQuery``

### ポート（差し替え可能な境界）

- ``Source``
- ``RecordStore``
- ``Exporter``
- ``RecordReceiver``
- ``RecordCodec``
- ``StorageReporting``
- ``OutboxDraining``

### 組み込み実装

- ``RingBufferStore``
- ``OutboxExporter``
- ``JSONRecordCodec``

### デバッグイベント・ログ

- ``DebugEvent``
- ``DebugLog``
- ``DebugProbe``
- ``DebugReport``
- ``DebugInterpreter``
- ``DebugMetric``
- ``MetricExtractor``
- ``CountMetricExtractor``
- ``SpanMetricExtractor``

### ソース（計測の組み立てブロック）

- ``LogBuffer``
- ``LogSource``
- ``StateSource``
- ``TypedStateSource``
- ``EventBuffer``
- ``EventSource``
- ``DebugLogSource``
- ``MetricsSource``

### 配送状態

- ``DeliveryState``
- ``ExportOutcome``
- ``StorageInfo``
- ``RecordStoreError``
- ``ExporterError``

### メトリクス UI モデル

- ``MetricsReport``
- ``MetricsScope``
- ``MetricSeries``
- ``MetricItem``
- ``MetricAxis``
- ``MetricAxisOption``
- ``MetricFormat``
- ``MetricsStore``
