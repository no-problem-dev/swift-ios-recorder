# ``iOSRecorderBonjour``

Sends a capture from the device to a Mac on the same network as it is taken, and receives it on the Mac.

## Overview

Two halves: ``BonjourExporter`` implements the core's `Exporter` on the device, and ``BonjourReceiver``
listens on the Mac. A record travels as one length-prefixed TCP frame.

On the device, pass the exporter to the session and every capture is sent as it is taken. The receiver is
found by browsing for `_iosrecorder._tcp` over mDNS; the concrete host and port that worked is remembered,
so a flaky answer or a bad IPv6 link-local pick costs one record rather than every record.

```swift
import iOSRecorder
import iOSRecorderBonjour

let exporter = BonjourExporter()          // finds the Mac by browsing
let session = Session(
    sources: [screenshotSource, logSource],
    store: store,
    exporters: [exporter]
)
try await session.capture(screenName: "Home")
```

### Local network permission

Browsing is a local network operation. On a real device the app therefore needs local network permission
and an `NSLocalNetworkUsageDescription` string in its `Info.plist`. The iOS Simulator runs as a process on
the Mac itself and never shows that prompt, so a Simulator reaches a receiver on the same Mac with no
permission step at all — the denial path only exists on hardware.

Denial does not produce an error. The browser keeps waiting rather than failing, so
``BonjourExporter/export(_:)`` returns only when its own deadline fires — 5 seconds by default — and
throws `ExporterError.transportFailed("timeout")`. `Session` records that as a failed export outcome. The
capture itself was already saved, so it stays on the device and stays browsable in the app; it just never
leaves. A Mac that is not running looks exactly the same from the device's side.

The `init(host:port:)` form of ``BonjourExporter`` skips browsing entirely and dials a known address,
which needs no permission. That is what tests and tethered setups use.

### What "delivered" means

Returning from `export(_:)` without throwing means the bytes were handed to TCP — not that the receiver
decoded them or stored them. A frame the receiver cannot decode is dropped on its side and still counts
as delivered here.

A frame carries at most 64 MB. A record that encodes larger throws
`ExporterError.payloadTooLarge(bytes:)` before any connection is attempted, and `OutboxExporter` deletes
such records rather than queueing them, since retrying can never help. On the receiving end, a length
prefix claiming more than 64 MB causes that connection to be hung up instead of the buffer being
allocated; other connections keep being served.

### Receiving

On the Mac, start a ``BonjourReceiver`` and consume its stream.

```swift
import iOSRecorderBonjour

let receiver = try BonjourReceiver(serviceName: "MyApp-Mac")
try await receiver.start()
for try await record in receiver.records() {
    print("received:", record.id, "artifacts:", record.artifacts.count)
}
```

Supplying `serviceName` advertises the listener so devices discover it with no configuration. Leave it
`nil` and nothing is published: the device has to be given the host and port directly, which is how tests
avoid the permission prompt that advertising triggers. With `port: .any` the OS picks a free port, readable
from ``BonjourReceiver/resolvedPort`` once `start()` has returned.

``BonjourReceiver/records()`` hands back one shared sequence. Two iterations split the frames between them
rather than each seeing every frame. It finishes normally when ``BonjourReceiver/stop()`` is called and
throws the underlying `NWError` when the listener fails — most often because the port is already taken.
A frame that fails to decode is dropped without a trace, so a codec mismatch between the two ends looks
exactly like a sender that went quiet. `stop()` does not disconnect peers that are already connected;
their sockets stay open until the peer closes them or the process exits.

### Showing whether the Mac is within reach

``ExportReachability`` answers that for a debug UI. It polls every 2 seconds while nothing is found and
backs off to every 4 once a receiver is there, and each poll is a fresh 1.5-second browse followed by a
real TCP connection — discovery alone is not enough, because over tethering a stale advertisement stays
visible after the receiver is gone and would show green while every export fails.

```swift
let reachability = ExportReachability()
reachability.start()
// `isReachable` is @Observable, so SwiftUI follows it directly.
```

``ExportReachability/isReachable`` is `false` until `start()` is called and stays `false` while local
network permission is denied. Call ``ExportReachability/stop()`` explicitly: the polling task is not tied
to the object's lifetime and keeps running if the object is merely released.

## Topics

### Sending from the device

- ``BonjourExporter``

### Receiving on the Mac

- ``BonjourReceiver``

### Reachability

- ``ExportReachability``
