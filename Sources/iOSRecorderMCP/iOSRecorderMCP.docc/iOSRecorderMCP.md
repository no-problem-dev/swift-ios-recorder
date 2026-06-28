# ``iOSRecorderMCP``

`RecordStore` の内容を MCP（Model Context Protocol）ツール群として公開するライブラリ。`list_captures` / `get_capture` / `search_events` / `get_event` / `delete_capture` / `clear_captures` / `get_storage_info` を stdio JSON-RPC で提供する。

## Overview

`iOSRecorderMCP` は、`iOSRecorder` が蓄積したキャプチャを AI エージェントから操作できるようにする。
`RecordMCPServer` がドメインロジックを担い、`StdioMCPServer` が stdin/stdout の JSON-RPC レイヤを提供する。

Mac 側でコマンドラインツールとして起動することを想定しており、Xcode の MCP ツール設定や Claude Code の
`mcpServers` に登録するだけで、AI からキャプチャの一覧取得・詳細参照・イベント検索が即座に行える。

```swift
import Foundation
import iOSRecorder
import iOSRecorderStore
import iOSRecorderMCP

// ストアを開く（FileRecordStore は iOSRecorderStore が提供）
let storeURL = URL(filePath: CommandLine.arguments[1])
let store = FileRecordStore(rootURL: storeURL)

// MCP サーバーを起動して stdio で待ち受ける
let mcp = StdioMCPServer(store: store)
await mcp.run()
```

`DebugEventQuery` を使うと、カテゴリ・名前・フリーテキストで複数キャプチャを横断検索できる。
検索結果の `DebugEventSearchResult` は走査した件数と打ち切り有無を明示し、
「見つからない ≠ 存在しない」を AI に正確に伝える。

受信機（`BonjourReceiver`）の起動・停止を MCP から制御するには `ReceiverStatusProviding` と
`ReceiverControlling` を実装したオブジェクトを `StdioMCPServer` に渡す。

## Topics

### MCP サーバー

- ``RecordMCPServer``
- ``StdioMCPServer``
- ``MCPRequestHandler``

### 検索・クエリ

- ``DebugEventQuery``
- ``DebugEventHit``
- ``DebugEventSearchResult``

### 受信機制御ポート

- ``ReceiverStatusSnapshot``
- ``ReceiverStatusProviding``
- ``ReceiverControlling``
