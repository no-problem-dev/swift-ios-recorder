# ``iOSRecorderMCP``

Exposes the captures a device has sent as MCP tools, so an AI coding agent on the Mac can list them, open them and search their events.

## Overview

``RecordMCPServer`` holds the domain logic over a `RecordStore`; ``StdioMCPServer`` wraps it in the
newline-delimited JSON-RPC that MCP clients speak over stdin and stdout. ``MCPRequestHandler`` sits
between them and is transport-free, so a request can be tested by handing it JSON.

```swift
import Foundation
import iOSRecorder
import iOSRecorderStore
import iOSRecorderMCP

// Open the store (FileRecordStore comes from iOSRecorderStore).
let storeURL = URL(filePath: CommandLine.arguments[1])
let store = FileRecordStore(rootURL: storeURL)

// Serve MCP over stdio.
let mcp = StdioMCPServer(store: store)
await mcp.run()
```

`run()` does not return until stdin reaches EOF, which is what makes it work as a child process an MCP
client spawns and keeps alive. Errors are written to stderr, never to stdout, so they cannot corrupt the
protocol stream. The package's `ios-recorder` executable is this plus a receiver, registered with
`claude mcp add ios-recorder -- ios-recorder mcp`.

### The tools

Six are always offered:

- `list_captures` — summaries only, no image bytes; filter by `screenName`, `text`, `session`, `kinds`, `sinceMinutes`, `limit`
- `get_capture` — one capture with its artifacts
- `search_events` — debug events across captures, newest first
- `get_event` — one event including its full payload
- `delete_capture`, `clear_captures` — remove one or all

Three more depend on what was passed to the initializer, and are not listed at all when the corresponding
argument is omitted: `connection_status` needs `status`, `restart_receiver` needs `control`, and
`get_storage_info` needs `storage`. When both `status` and `control` are supplied, every tool call first
checks the receiver and silently restarts it if it has stopped listening; a healthy receiver is left
alone, because churning the port would break transfers in flight.

### Keeping responses small

`get_capture` downscales images to a 1024 px longest edge by default — pass `maxDimension: 0` for the
original. Non-image artifacts come back as text tagged with their kind. Network entries whose response
body is not text are elided down to a size placeholder, and `debug_timeline` payloads are stripped out
entirely, since the base64 would otherwise dominate the response. `maxBytes` caps each artifact's text,
counted in UTF-8 bytes, and says in the text how much was cut.

Full event bodies are reached in two steps instead: ``DebugEventQuery`` narrows by capture, category,
name, free text and age, and each ``DebugEventHit`` carries the event's identifier and the size of its
payload but not the payload itself; ``RecordMCPServer/getEvent(capture:eventID:)`` then returns one
event in full.

``DebugEventSearchResult`` reports how many captures were actually scanned and whether the scan was cut
short at the limit — 50 captures by default. That is deliberate: without it an agent would read an empty
result as proof that nothing matched, when it may only mean the search stopped early. A capture with no
`debug_timeline` artifact is never searched, so events only exist here for apps that record them.

### Controlling the receiver

``ReceiverStatusProviding`` and ``ReceiverControlling`` are implemented by whatever owns the receiver —
in this package, the `ios-recorder` executable. Pass those objects to ``StdioMCPServer`` and an agent can
ask whether the Mac is listening, how many captures have arrived and when the last one did, and can
reattach the listener when it is not getting anything.

## Topics

### Servers

- ``RecordMCPServer``
- ``StdioMCPServer``
- ``MCPRequestHandler``

### Searching events

- ``DebugEventQuery``
- ``DebugEventHit``
- ``DebugEventSearchResult``

### Receiver control

- ``ReceiverStatusSnapshot``
- ``ReceiverStatusProviding``
- ``ReceiverControlling``
