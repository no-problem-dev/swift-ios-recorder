# ``iOSRecorderStore``

Keeps captures on disk as plain files, so they survive a relaunch and can be opened in Finder without this package.

## Overview

``FileRecordStore`` implements the core's `RecordStore`. Use it in place of `RingBufferStore` when
captures have to outlive the process, and on the Mac side as the store the receiver writes into.

One capture is one folder. Artifact files are named by their position and kind, with the extension taken
from the media type:

```
<root>/<recordID>/meta.json
<root>/<recordID>/0-screenshot.jpg
<root>/<recordID>/1-network.json
```

```swift
import iOSRecorder
import iOSRecorderStore

let storeURL = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ios-recorder-captures")

let store = FileRecordStore(rootURL: storeURL, maxRecords: 100)

let session = Session(
    sources: [screenshotSource],
    store: store
)
try await session.capture(screenName: "Settings")

let info = await store.storageInfo()
print("records:", info.totalRecords, "bytes:", info.totalBytes)
```

The root directory does not have to exist; it is created on the first save.

### Interrupted saves

Artifacts are written first and `meta.json` last, and a folder without a readable `meta.json` is ignored
everywhere. A save that is cut short therefore leaves files on disk that no query, no fetch and no
retention pass will ever return or remove. They have to be deleted by hand or by wiping the root.

### Growth

`maxRecords` is the only bound. Each save deletes the oldest folders past it, ordered by recorded time
rather than by size — unlike `RingBufferStore`, there is no byte budget, so a run of screenshot-heavy
captures can be large while still being under the count. Leave `maxRecords` out and the directory grows
without limit.

``FileRecordStore`` also conforms to `StorageReporting`, so ``FileRecordStore/storageInfo()`` reports the
record count, the total bytes actually on disk, the oldest and newest recorded times, and the root path.
Without that conformance the MCP `get_storage_info` tool has nothing to answer with.

Reading the metadata of every folder is cached and reused until the root directory's modification time
changes. Adding or removing a capture creates or removes a folder, which always changes that timestamp —
including when another process does it, which is how a standalone receiver and an MCP server pointed at
the same root stay in step.

The Mac companion executable uses `~/.iosrecorder/captures` with a cap of 300 records. On the device the
same type also serves as the spool behind `OutboxExporter`, holding captures that failed to send until
the Mac is reachable again.

## Topics

### File-backed storage

- ``FileRecordStore``
