English | [日本語](./README.ja.md)

# swift-ios-recorder

An on-device instrument that **captures and retains** the runtime state of iOS apps under development — screenshots, state JSON, and logs bundled as a single capture — and streams them to Mac, MCP servers, and AI tools, eliminating manual UI verification loops.

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)

## Core Idea

**Measure + retain is the foundation.** Mac integration and MCP integration are capabilities built on top.
See [spec.md](./spec.md) for the detailed design.

## Modules

| Module | Role |
|---|---|
| `iOSRecorder` | Core. `Record` / `Artifact` / ports / `Session` / `RingBufferStore` / `Log` & `StateSource` (zero dependencies) |
| `iOSRecorderScreenshot` | `ScreenshotSource` (UIKit `drawHierarchy`, iOS only) |
| `iOSRecorderUI` | SwiftUI integration (floating button, shake-to-capture, in-app viewer) |
| `iOSRecorderBonjour` | `Exporter` / `Receiver` (same-LAN instant transfer, Network framework) |
| `iOSRecorderStore` | `RecordStore` file implementation (Mac, 1 record = 1 folder) |
| `iOSRecorderMCP` | Bridges `RecordStore` to `list_captures` / `get_capture` / `search_events` / `get_event` (MCP stdio) |
| `ios-recorder` | Mac companion executable (`serve` / `mcp`) |

## Usage

### iOS app side (DEBUG builds only)

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
    exporters: [BonjourExporter()]   // stream to Mac over the same LAN
)
let controller = RecorderController(session: session, store: store)

// One line at the root. Tap/shake to capture, long-press to list.
ContentView().recorder(controller)
```

### Mac side

```sh
# Register as an MCP server in Claude Code. The receiver runs inside the MCP process,
# starting and stopping with Claude Code — no separate daemon needed.
claude mcp add ios-recorder -- ios-recorder mcp
```

Once registered, pressing the floating button on iPhone sends a capture to the Mac,
and Claude Code can retrieve it via `list_captures` / `get_capture` (images downscaled to `maxDimension`)
/ `search_events` / `get_event` / `delete_capture` / `clear_captures`.

`ios-recorder serve` is an alternative for headless operation that runs only the receiver.

> After updating the binary, re-sign it with `codesign --force --sign - <path>`.
> Without re-signing, the ad-hoc signature is invalidated and the process is killed at launch with SIGKILL.

## Development

```sh
swift build && swift test          # 48 tests / 13 suites
# Verify compile for iOS-only targets:
xcodebuild build -scheme iOSRecorderUI -destination 'generic/platform=iOS'
```
