# ``iOSRecorder``

開発中の iOS アプリの実行時状態を**計測して保持する**コアライブラリ。スクリーンショット・状態 JSON・ログを 1 件のキャプチャとしてまとめ、Mac・MCP・AI ツールへ流すための基盤を提供する。依存ゼロで、アダプタ（UI/Bonjour/Store/MCP）の置き換えが可能なポート設計。

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
