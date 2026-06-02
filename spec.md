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
| `Source` | 何を計測するか | `ScreenshotSource`（予定） | state / log / network / view 階層 / 動画 |
| `RecordStore` | どこに保持するか | `RingBufferStore`（オンデバイス） / `FileRecordStore`（Mac） | SQLite, GRDB |
| `Exporter` / `RecordReceiver` | どう通信するか | `BonjourExporter`（実装予定） | iCloud, gRPC, WebSocket |
| `RecordCodec` | どう直列化するか | `JSONRecordCodec` | Protobuf, MessagePack |

## ドメインモデル

- `Record` — ある瞬間に保持された観測単位（id, session, recordedAt, metadata, artifacts）
- `Artifact` — 中身の単位。`kind`（typed）+ `mediaType` + 不透明な `data` + 検索用 `attributes`
  - **拡張性の核**: data をコアにとって不透明にしたことで、通信・保存・MCP は新しい artifact 種を知らずにそのまま流せる（OCP）。新種の追加は「生産者（Source）」と「消費者」の両端だけ
- `RecordMetadata` — 検索対象（screenName, appVersion, tags, attributes）
- `RecordSummary` — 一覧用の軽量表現（artifact の data を含まない）
- `RecordQuery` — ストレージ非依存の検索条件（session / screenName / kinds / timeRange / text / limit）
- `Session` — 計器の中核 actor。トリガで Source を回し、Record を組み立て、Store に保持し、任意で Exporter に出す

## 依存グラフ（依存ルールをターゲット境界で強制）

```
iOSRecorder（コア・依存ゼロ）← 全員がここに依存
  ├─ iOSRecorderUI         （SwiftUI 統合・フロートボタン・アプリ内ビューア）
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

検証: macOS で 48 tests / 13 suites 緑、iOS 専用ターゲットは xcodebuild（generic/iOS）でコンパイル確認済み、
MCP は実バイナリに JSON-RPC を流して動作確認済み。

### 残（実運用フェーズ）

- `BonjourExporter` の Bonjour 発見経路（現状ループバック直結はテスト済み、mDNS 発見は実機 LAN で要確認）
- ローカルネットワーク権限（`NSLocalNetworkUsageDescription`）の説明とハンドリング
- `#if DEBUG` ガードのアプリ側ベストプラクティス文書化
