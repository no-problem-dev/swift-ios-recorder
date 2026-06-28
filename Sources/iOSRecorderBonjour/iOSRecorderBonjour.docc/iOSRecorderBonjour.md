# ``iOSRecorderBonjour``

iOS から Mac へ記録を Bonjour 経由で自動転送する Exporter と、Mac 側で受け取る Receiver を提供するライブラリ。

## Overview

`iOSRecorderBonjour` は、`iOSRecorder` の `Exporter` プロトコルを実装する `BonjourExporter` と、
Mac 側で受信する `BonjourReceiver` の 2 本柱で構成される。

iOS 側では `BonjourExporter` を `Session` に渡すだけで、キャプチャのたびに同一 LAN の Mac 受信機を
mDNS で自動発見して TCP で送信する。一度通ったアドレスをキャッシュするため、2 回目以降はブラウズなしで
即座に送れる（テザリング環境での安定性も向上）。

```swift
import iOSRecorder
import iOSRecorderBonjour

let exporter = BonjourExporter()          // mDNS で Mac を自動検索
let session = Session(
    sources: [screenshotSource, logSource],
    store: store,
    exporters: [exporter]
)
try await session.capture(screenName: "Home")
```

Mac 側では `BonjourReceiver` を起動して `AsyncThrowingStream<Record, Error>` を消費する。
`serviceName` を指定すると Bonjour で自分を広告し、iOS 側がゼロコンフィグで発見する。

```swift
import iOSRecorderBonjour

let receiver = try BonjourReceiver(serviceName: "MyApp-Mac")
try await receiver.start()
for try await record in receiver.records() {
    print("受信:", record.id, "artifacts:", record.artifacts.count)
}
```

Mac まで物理的に届くかを UI で示したい場合は `ExportReachability` を使う。
`start()` 後は `isReachable` プロパティが `@Observable` で更新されるため、SwiftUI でそのまま監視できる。

## Topics

### iOS 側（送信）

- ``BonjourExporter``

### Mac 側（受信）

- ``BonjourReceiver``

### 到達性監視

- ``ExportReachability``
