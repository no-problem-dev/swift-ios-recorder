# ``iOSRecorderStore``

キャプチャをファイルシステム上に永続化する `RecordStore` 実装ライブラリ。

## Overview

`iOSRecorderStore` は `iOSRecorder` の `RecordStore` プロトコルを実装する `FileRecordStore` を提供する。
`RingBufferStore`（インメモリ）と置き換えることで、アプリ終了後も記録を保持できる。

1 キャプチャ = 1 フォルダとして保存するため、Finder から中身を直接確認できる。

```
<root>/<recordID>/meta.json
<root>/<recordID>/0-screenshot.jpg
<root>/<recordID>/1-network.json
```

`maxRecords` を指定すると、`save()` のたびに古い記録を自動削除してディスク使用量を上限以内に保つ。
`StorageReporting` プロトコルも実装しているため、総件数やディスク消費量を `storageInfo()` で取得できる。

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
print("保存件数:", info.totalRecords, "バイト:", info.totalBytes)
```

## Topics

### ファイル永続化

- ``FileRecordStore``
