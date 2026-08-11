# ``iOSRecorder``

Takes one capture of a running app — the screen, the app's own state, its logs, its recent HTTP traffic — keeps it, and hands it to whatever carries it off the device. This is the core every other library in the package plugs into.

## Overview

``Session`` is the whole of it. It runs every ``Source`` concurrently, collects what they return into a
single ``Record``, saves that to a ``RecordStore``, and passes it to any ``Exporter`` that was attached.

The module has no dependencies and touches neither UIKit nor SwiftUI, so it builds the same on iOS and
macOS.

```swift
import iOSRecorder

// Assemble a session.
let store = RingBufferStore(capacity: 50)
let session = Session(
    sources: [logSource, stateSource],
    store: store
)

// Take a capture.
let id = try await session.capture(screenName: "Dashboard", tags: ["release"])

// Read it back later.
let record = try await store.fetch(id)
print(record.artifacts.map(\.kind.rawValue))
```

### What one capture does and does not promise

Sources run concurrently, so artifacts land in completion order rather than the order the sources were
listed. A source that returns `nil` is simply absent from the record — there is no way for a source to
report a failure, so "could not measure" and "nothing to say" look identical.

Saving is the only step that can throw back to the caller. An exporter that throws produces an
``ExportOutcome`` instead, read back through ``Session/deliveryState(for:)``, so a capture is never lost
because the receiving machine was unreachable. Those outcomes are kept for the last 200 captures only;
an older capture reads back as pending even if it was delivered.

### Where captures are kept

``RingBufferStore`` keeps them in memory and nowhere else, so everything is gone when the process ends.
It is bounded by a record count (100 by default) and by a byte budget (64 MB by default) at the same
time: whichever limit is reached first evicts the oldest captures, except that the newest capture is
always kept even when it exceeds the budget on its own. ``RecordStore/fetch(_:)`` on an evicted id throws
``RecordStoreError/notFound(_:)``. For captures that have to survive a relaunch, use the file-backed
store in `iOSRecorderStore`.

``RecordQuery`` matches metadata only — screen name, tags, attributes. A string that appears solely
inside a log or a state dump is not findable, so anything worth searching for later belongs in `tags`
or `attributes`.

### Sending captures on

``OutboxExporter`` wraps another exporter and spools whatever fails into a ``RecordStore``, so a stopped
receiver or a dropped connection costs nothing; `drain()` retries the spool oldest first. A record the
transport will never accept — ``ExporterError/payloadTooLarge(bytes:)`` — is deleted rather than queued,
because one oversized record at the head of the spool would block everything behind it.

``JSONRecordCodec`` is the default wire format. Artifact bytes ride along base64-encoded, so an encoded
screenshot is roughly a third larger than the file it came from.

### The rest of the package

- `iOSRecorderUI` — floating buttons, shake to reveal them, and an in-app browser, added with one SwiftUI modifier
- `iOSRecorderScreenshot` — attaches the screen to a capture
- `iOSRecorderNetwork` — records the app's HTTP traffic and folds it into a capture
- `iOSRecorderBonjour` — sends captures to a Mac on the same network, and receives them there
- `iOSRecorderStore` — keeps captures on disk, one folder per capture
- `iOSRecorderMCP` — exposes stored captures to an AI coding agent as MCP tools

## Topics

### Sessions

- ``Session``

### Captures

- ``Record``
- ``RecordMetadata``
- ``RecordSummary``
- ``RecordID``
- ``SessionID``
- ``Artifact``
- ``ArtifactKind``
- ``RecordContext``
- ``RecordQuery``

### Replaceable boundaries

- ``Source``
- ``RecordStore``
- ``Exporter``
- ``RecordReceiver``
- ``RecordCodec``
- ``StorageReporting``
- ``OutboxDraining``

### Built-in implementations

- ``RingBufferStore``
- ``OutboxExporter``
- ``JSONRecordCodec``

### Debug events and logs

- ``DebugEvent``
- ``DebugLog``
- ``DebugProbe``
- ``DebugReport``
- ``DebugInterpreter``
- ``DebugMetric``
- ``MetricExtractor``
- ``CountMetricExtractor``
- ``SpanMetricExtractor``

### Sources to build a capture from

- ``LogBuffer``
- ``LogSource``
- ``StateSource``
- ``TypedStateSource``
- ``EventBuffer``
- ``EventSource``
- ``DebugLogSource``
- ``MetricsSource``

### Delivery

- ``DeliveryState``
- ``ExportOutcome``
- ``StorageInfo``
- ``RecordStoreError``
- ``ExporterError``

### Metrics dashboard model

- ``MetricsReport``
- ``MetricsScope``
- ``MetricSeries``
- ``MetricItem``
- ``MetricAxis``
- ``MetricAxisOption``
- ``MetricFormat``
- ``MetricsStore``

### The recorder's own window

- ``RecorderWindowMarker``
