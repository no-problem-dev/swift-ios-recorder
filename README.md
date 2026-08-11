English | [日本語](./README.ja.md)

# swift-ios-recorder

Shows what your iOS app is actually doing — the screen, the app's own state, its network traffic and its logs — to an AI coding agent on your Mac, so checking a UI change stops being a manual tap-and-screenshot loop.

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)

## Overview

One modifier on your root view gives a build a floating button. Tap it — or shake the
device — and the app takes a capture: a screenshot, whatever application state you chose
to encode, recent HTTP traffic, and recent logs, all filed under a single timestamp.

Captures travel to a Mac on the same network as they are taken. Register the companion
executable as an MCP server and a coding agent can list them, open them, and search their
events, so it can look at the screen it just changed instead of asking you to describe it.

Every source is opt-in: take screenshots only, or add state, network and logs as you need
them. Captures can also be browsed inside the app, which is what you get when there is no
Mac listening. Nothing here is meant to ship — compile it into debug builds only.

## Usage

### In the iOS app

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
    exporters: [BonjourExporter()]   // send to a Mac on the same network
)
let controller = RecorderController(session: session, store: store)

// One line at the root. Tap or shake to capture, long-press to browse.
ContentView().recorder(controller)
```

`BonjourExporter` discovers the Mac with a Bonjour browse, so the app needs the local
network permission and an `NSLocalNetworkUsageDescription` string in its `Info.plist`.
Until that is granted the capture is still taken and stored — it just never leaves the
device.

### On the Mac

```sh
claude mcp add ios-recorder -- ios-recorder mcp
```

The receiver runs inside the MCP process, so it starts and stops with the agent and there
is no separate daemon to keep alive. Once registered, pressing the button on the phone
puts a capture where the agent can reach it through `list_captures`, `get_capture`,
`search_events` and `get_event`. For headless use, `ios-recorder serve` runs the receiver
on its own.

> After replacing the binary, re-sign it with `codesign --force --sign - <path>`. Copying
> over it invalidates the ad-hoc signature, and the process is then killed at launch.

## Documentation

[API documentation](https://no-problem-dev.github.io/swift-ios-recorder/documentation/iosrecorder/)

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-ios-recorder.git", .upToNextMinor(from: "0.8.0"))
]
```

```swift
.target(name: "YourTarget", dependencies: [
    .product(name: "iOSRecorder", package: "swift-ios-recorder"),           // core
    .product(name: "iOSRecorderUI", package: "swift-ios-recorder"),         // SwiftUI integration
    .product(name: "iOSRecorderScreenshot", package: "swift-ios-recorder"), // screenshots
    .product(name: "iOSRecorderBonjour", package: "swift-ios-recorder"),    // transfer to a Mac
])
```

The Mac companion is the `ios-recorder` executable, built from this repository with
`swift build`.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

MIT. See [LICENSE](./LICENSE).
