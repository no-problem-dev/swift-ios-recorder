# ``iOSRecorderUI``

Puts a capture button and a debug panel into a SwiftUI app with one modifier, so a build can take captures and browse them without a Mac attached.

## Overview

``RecorderController`` holds the state — the `Session`, the store, and whichever of the network log,
reachability probe, outbox, debug log and metrics store the app chose to supply. Attaching it to a view
with `.recorder(_:)` is all the wiring there is.

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
                .recorder(controller)
        }
    }
}
```

None of this is meant to ship. Compile it into debug builds only.

### The buttons

On iOS the buttons live in a separate `UIWindow` placed above the app, marked with the identifier from
`RecorderWindowMarker` so the screenshot source skips it. That window hit-tests only the
rectangle the buttons currently occupy, so every other touch falls through to the app untouched — and
while the panel is presented it hit-tests its whole area again so the panel stays usable.

They start hidden. A shake reveals them, and a second shake hides them again. The camera button takes a
capture; the ladybug button opens the panel as a sheet with a badge showing how many captures are held.
The pair can be dragged anywhere on screen. On macOS there is no shake, so the buttons are visible from
the start and `.onShake(perform:)` does nothing at all.

`.recorderScreen(_:)` names the screen currently on display, and any capture taken without an explicit
name inherits it. It reads the controller out of the environment, so used outside `.recorder(_:)` the
name is dropped with no warning.

### What the panel shows

Sections appear according to what was passed to ``RecorderController``: a network list for `network`, a
connection row for `reachability`, a pending count and automatic retries for `outbox`, an event timeline
for `debugLog`, a dashboard for `metrics`. Captures are always listed.

To fix the order and the layout instead, build a ``DebugConsole`` from ``DebugSection`` values and pass
it as `console`. ``DebugItem`` adds the app's own actions, toggles and readouts to the panel;
``DebugStat`` and ``DebugStatBuilder`` build a grid of live numbers.

### Things the state does not tell you

``RecorderController/capture(screenName:)`` swallows store failures: a store that refuses the write
leaves the list unchanged and says nothing.

``RecorderController/refresh()`` reloads at most the 100 newest captures along with their delivery states
and the pending count. Nothing else updates those, so a capture delivered in the background keeps
showing as pending until the next refresh.

Passing an `outbox` starts a retry loop immediately, attempting every 5 seconds by default. It runs until
``RecorderController/stopAutoDrain()`` is called — releasing the controller does not stop it.

A denied local network permission is indistinguishable from a Mac that is simply not running: the probe
never reports reachable and the connection row keeps saying the Mac is not connected.

## Topics

### Entry point

- ``RecorderController``

### Panel layout

- ``DebugConsole``
- ``DebugSection``
- ``DebugConsoleBuilder``
- ``DebugStatBuilder``

### Panel contents

- ``DebugItem``
- ``DebugStat``
- ``DebugPreviewElement``
- ``PreviewStat``
- ``PreviewStatus``

### Metrics dashboard

- ``MetricsDashboardView``
