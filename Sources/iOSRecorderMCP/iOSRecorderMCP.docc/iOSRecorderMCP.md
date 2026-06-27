# ``iOSRecorderMCP``

`RecordStore` の内容を MCP（Model Context Protocol）ツール群として公開するライブラリ。`list_captures` / `get_capture` / `search_events` / `get_event` / `delete_capture` / `clear_captures` / `get_storage_info` を stdio JSON-RPC で提供する。

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
