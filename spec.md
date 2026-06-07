# iOSRecorder 設計仕様

## 本質

**開発中の iOS アプリの中で、実行時の観測を「計測（measure）」し「保持（retain）」する、オンデバイスの計器。**
Mac との連携・MCP 連携は、保持された記録に対する**数ある出力能力（capability）の 1 つ**にすぎない。「ブリッジ」は本質ではない。

これにより iOS コアは単体で完結する — Mac も MCP も無くても「記録して貯めて、アプリ内で見る」だけで価値がある。

## 不変項（ドメインの核）

> セッション中に撮られた **Record** を、**保存し・検索し・取り出す**。

これ以外（どう通信するか／どこに保存するか／どう直列化するか／何を計測するか）はすべて「やり方」であり、ポート（プロトコル）として外に追い出して差し替え可能にする。

## レイヤ構造

```
Layer 1: コア＝計器（iOSRecorder, プラットフォーム非依存・依存ゼロ）
  計測: Source（何を測るか）→ Session が Record を組み立てる
  保持: RecordStore（保存・検索・取得）
  ※ Mac も MCP も知らない

Layer 2: 能力（capability）＝保持した記録に対して“何かする”
  Exporter（外へ出す）: Bonjour / iCloud / ファイル …
  Trigger（記録を起こす）: フロートボタン / シェイク（iOSRecorderUI）

Layer 3: 下流の消費者（Mac companion・別バイナリ）
  RecordReceiver（Export の対向）→ RecordStore（File 実装）→ MCP（list/get）
```

## 4 つのポート（差し替え可能な周辺）

| ポート | 抽象化する関心 | 現行実装 | 差し替え候補 |
|---|---|---|---|
| `Source` | 何を計測するか | `ScreenshotSource` / `StateSource` / `LogSource` / `NetworkSource` / `TypedStateSource<Value>` / `EventSource<Value>` | view 階層 / 動画 |
| `RecordStore` | どこに保持するか | `RingBufferStore`（オンデバイス） / `FileRecordStore`（Mac） | SQLite, GRDB |
| `Exporter` / `RecordReceiver` | どう通信するか | `BonjourExporter`（実装予定） | iCloud, gRPC, WebSocket |
| `RecordCodec` | どう直列化するか | `JSONRecordCodec` | Protobuf, MessagePack |

## ドメインモデル

- `Record` — ある瞬間に保持された観測単位（id, session, recordedAt, metadata, artifacts）
- `Artifact` — 中身の単位。`kind`（typed）+ `mediaType` + 不透明な `data` + 検索用 `attributes`
  - **拡張性の核**: data をコアにとって不透明にしたことで、通信・保存・MCP は新しい artifact 種を知らずにそのまま流せる（OCP）。新種の追加は「生産者（Source）」と「消費者」の両端だけ
  - **任意構造体の計測**: `TypedStateSource<Value: Encodable>` / `EventSource<Value>` で任意の値を差し込める。`kind` を族（`agent_response` 等）で分けると `RecordQuery.kinds` で絞り込め、Swift 型名は `attributes["type"]` に自動で刻まれて MCP 出力に `[kind <型名>]` として現れる。`.network` は core を触らず生産者ターゲット（`iOSRecorderNetwork`）側で定義する OCP の実例
- `RecordMetadata` — 検索対象（screenName, appVersion, tags, attributes）
- `RecordSummary` — 一覧用の軽量表現（artifact の data を含まない）
- `RecordQuery` — ストレージ非依存の検索条件（session / screenName / kinds / timeRange / text / limit）
- `Session` — 計器の中核 actor。トリガで Source を回し、Record を組み立て、Store に保持し、任意で Exporter に出す

## 依存グラフ（依存ルールをターゲット境界で強制）

```
iOSRecorder（コア・依存ゼロ）← 全員がここに依存
  ├─ iOSRecorderUI         （SwiftUI 統合・フロートボタン・アプリ内ビューア）
  ├─ iOSRecorderScreenshot （ScreenshotSource）
  ├─ iOSRecorderNetwork    （URLProtocol 傍受 + NetworkSource で .network artifact 化）
  ├─ iOSRecorderBonjour    （Exporter / RecordReceiver 実装）
  ├─ iOSRecorderStore      （RecordStore のファイル実装。1 record = 1 フォルダ）
  └─ iOSRecorderMCP        （RecordStore を list/get に橋渡し）

ios-recorder（exe・合成ルート）= 具体アダプタをここでだけ結線（serve / mcp）
iOSRecorderTestSupport     = ポートを差し替える共有 Fake/Fixture（テスト専用）
```

コアが Network/SQLite を import しないことは「ターゲットがそれらに依存していない」事実で保証される。具体をコアに漏らすとコンパイルが通らない＝型システムが設計を守る。

## MCP 連携（pull 型・2 ツール）

Mac の `ios-recorder serve` が Bonjour で記録を受けて `FileRecordStore` に保存。`ios-recorder mcp`（`claude mcp add` で登録）が同じ Store を読み、Claude Code に 2 ツールを提供：

- `list_captures(filter?)` → `RecordStore.query` → `[RecordSummary]`（画像バイト無し・トークン節約）
- `get_capture(id)` → `RecordStore.fetch` → `Record`（artifact data 込み）

push やブロッキングは使わない。Claude が必要な時に取りに行く。

## 通信トランスポート

即時性が要るため v1 は **Bonjour + ローカル HTTP**（同一 LAN・即時）。iCloud は同期遅延があるため不採用だが、`Exporter` 差し替え候補として実装は残せる。やり方が増えたら `Exporter` 実装を 1 ターゲット足して合成ルートの結線を 1 行変えるだけ。

## TDD 方針

ターゲット分割は TDD のための境界。各ポートを `iOSRecorderTestSupport` の Fake に差し替えて隔離検証する。

- `iOSRecorderTests` — `RecordQuery` の絞り込み、`RingBufferStore`（保存/取得/容量退避/検索順）、`Session.capture`（Fake Source/Exporter で計測・保持・出力の振る舞い）、`JSONRecordCodec` の往復
- `iOSRecorderStoreTests` — `FileRecordStore` の round-trip・Finder フレンドリーなレイアウト・notFound・query 絞り込み/整列
- `iOSRecorderMCPTests` — `RecordMCPServer` が Store に委譲し summary/record を正しく返す・notFound 伝播
- Bonjour（ネットワーク）/ UI（オーバーレイ）のテストは各実装着手時に追加

## 実装ロードマップ（全マイルストーン完了）

1. **M1 ✅** コア（計測+保持）+ テスト緑
2. **M5 ✅** `LogSource`/`StateSource`（コア）+ `ScreenshotSource`（`drawHierarchy`、iOS）
3. **M3 ✅** `BonjourExporter`/`BonjourReceiver`（Network framework、ループバック往復テスト済み）
4. **M4 ✅** `iOSRecorderMCP` を依存ゼロの JSON-RPC over stdio で実装（`list_captures`/`get_capture`、image は base64 content）
5. **M2 ✅** `iOSRecorderUI` のフロートボタン/シェイク/アプリ内ビューア（`RecorderController` はテスト済み）
6. **結線 ✅** `ios-recorder serve`（Bonjour 受信→FileRecordStore）/ `ios-recorder mcp`（stdio）
7. **M6 ✅** `NetworkSource`（`iOSRecorderNetwork` に `iOSRecorder` 依存を足し、`NetworkLog: Codable` 化 + サニタイズ済みスナップショットを `.network` artifact に畳む）→ 通信が MCP の `get_capture` で見える
8. **M7 ✅** `TypedStateSource<Value>` / `EventBuffer<Value>`+`EventSource<Value>`（任意 Encodable を型名付きで計測。push（capture 時点）と pull の両モデル）
9. **M8 ✅** MCP `get_capture` が非画像 artifact に `[kind <型名>]` を付与、非テキストは base64 でフォールバック
10. **M9 ✅** 配送の観測性：`Session` が export 結果を握り潰さず記録（`ExportOutcome`/`DeliveryState`）、`Exporter.label`、iPhone パネルに delivered/pending バッジと未送件数。`ExportReachability` を「発見」から「実 TCP 接続」判定に変更
11. **M10 ✅** 配送の堅牢化（テザリング耐性）：`OutboxExporter`（送信失敗を永続退避→到達回復で自動再送、合成 Exporter）、`BonjourExporter` の解決済み host:port キャッシュ + 失敗時再発見。MCP に `connection_status`（受信機健全性・最終受信時刻）/ `restart_receiver`（listener 貼り直し）、exe に `ReceiverHub`
14. **M13 ✅** 任意データの構造表示＋メトリクス可視化：詳細ビューが payload を `swift-structured-data` の `StructuredValue` に解析して再帰的に折り畳み表示（型別色分け・選択コピー）。`DebugEvent` に `encoding:`/`text:` イニシャライザ追加で「全データ」を保持。汎用メトリクス可視化フレームワーク（`MetricUnit`/`MetricItem`/`MetricSeries`/`MetricsReport`/`MetricsStore` + `MetricsDashboardView`）= Swift Charts・通貨切替(USD/JPY)・倍率(×1/10/100/1000)・色分け。ドメイン（LLM コスト/トークン）は利用側が `MetricsReport` を組んで差し込む（recorder は非依存）
13. **M12 ✅** デバッグ計測システム：`DebugEvent`（時刻付き正規化封筒）/ `DebugLog`(@Observable ライブバッファ) / `DebugProbe`(生産者) / `DebugInterpreter`+`DebugReport`(オンデバイス解釈) / `MetricExtractor`+`DebugMetric`（`CountMetricExtractor`/`SpanMetricExtractor`）。`DebugLogSource`/`MetricsSource` で capture 時に `debug_timeline`/`metrics` artifact へ畳む。`iOSRecorderUI` に汎用 `DebugTimelineView`（カテゴリ別ライブ表示）。ドメイン知識は core に入れず、消費者（デモ StudioFeature）が probe を実装して AI 動作・A2UI 生成イベントを emit する
12. **M11 ✅** 自動回復：(1) URL クエリの機密キー（`?key=` 等）マスク、(2) `ReceiverHub` の listener 自己修復（世代カウンタで失敗検知→自動 re-spin）、(3) MCP `tools/call` 直前の条件付き自動回復（`listening==false` 時のみ無言で貼り直し）、(4) iPhone outbox の定期自動ドレイン（pending あり＋到達可能で数秒間隔・接続回復で自動再送）。通常運用で `restart_receiver` の手動実行は不要
15. **M14 ✅** 書き込み側のサイズ根治＋防御強化（2026-06 監査の包括対応）：
    - **ScreenshotSource を縮小 JPEG 化**（maxDimension 1024 / quality 0.8、`Artifact.screenshot(jpegData:)`）。フル解像度 PNG（1 枚 5MB 超）がディスク・転送・メモリの支配的コストだった。MCP が AI に渡す画像は元々同上限なので情報損失ゼロ。drawHierarchy のみ MainActor、エンコードは外（撮影時の UI フリーズ解消）
    - **DebugLogSource が capture 時に payload を 8KB/event で truncate**（`DebugEvent.withPayloadLimited`、UTF-8 境界保持、元サイズは `payloadOriginalBytes` に残る）。「読み出し側の責務」だけでは保存側が肥大したままだった（53KB prompt → base64 71KB がディスク残留）
    - **Framing にフレーム長上限 64MB**。受信側は上限超の長さプレフィックスで即切断（悪意/破損ピアによる巨大メモリ確保の防止）、送信側は `ExporterError.payloadTooLarge` を投げ、outbox はそれを退避せず／drain で破棄（先頭詰まり防止）
    - **RingBufferStore に capacityBytes（既定 64MB）**。件数だけでなくバイト数でも退避（最新 1 件は予算超過でも保持）
    - **Sanitizer 強化**: 機密キー判定を完全一致 Set から部分一致（`client_secret`/`oauth_signature`/`X-Auth-Token` 等を捕捉）へ、テキスト JSON body 内の機密キー文字列値をマスク（request/response 両方）、Content-Type 不明でも U+FFFD 痕跡があればバイナリとして省略
    - **MCP**: `get_storage_info`（件数/総バイト/時間範囲/保存先）追加、`search_events` が `{hits, scannedCaptures, scanTruncated}` を返し走査打ち切りを黙らせない、`RecordMCPServer.maxScannedCaptures` 設定化、`FileRecordStore` に root mtime キーの meta キャッシュ + `StorageReporting` 準拠
16. **M15 ✅** デバッグ UI のコンパクト表示（`CompactDisplay` ポリシー）：既定はコンパクト・展開はオンデマンド。構造ツリーはトップレベルのみ展開＋大量の子はバッチ開示（30 件→+100）、長い文字列リーフ/生テキストはプレビュー + 全文展開（`ExpandableText`）、タイムライン行とデータ見出しに payload サイズバッジ、capture 時 truncate の注記（`payloadOriginalBytes` 表示）、スクショは maxHeight 360

検証: macOS で 153 tests / 38 suites 緑、iOS 専用ターゲットは xcodebuild（generic/iOS）でコンパイル確認済み、
MCP は実バイナリに JSON-RPC を流して動作確認済み。

### 残（実運用フェーズ）

- `BonjourExporter` の Bonjour 発見経路（現状ループバック直結はテスト済み、mDNS 発見は実機 LAN で要確認）
- ローカルネットワーク権限（`NSLocalNetworkUsageDescription`）の説明とハンドリング
- `#if DEBUG` ガードのアプリ側ベストプラクティス文書化
