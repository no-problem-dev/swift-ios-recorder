# ``iOSRecorderNetwork``

URLSession 通信をインターセプトしてライブログを積み、キャプチャ時点のスナップショットを `iOSRecorder` の `Source` として提供するライブラリ。

## Overview

`iOSRecorderNetwork` は、アプリの HTTP 通信をゼロコード変更で記録に含める仕組みを提供します。
`NetworkMonitor` を起動すると `URLProtocol` のスウィズリングで全 `URLSession` 通信をインターセプトし、
ライブバッファ (`NetworkLogStore`) に新しい順で蓄積します。

```swift
import iOSRecorderNetwork

let monitor = await NetworkMonitor(ignoredHosts: ["metrics.example.com"])
await monitor.start()
```

キャプチャ時には `NetworkSource` を `Session` の `sources` に渡します。
`measure(_:)` が呼ばれると、バッファの最新 N 件をスナップショットして 1 つの `Artifact` にまとめます。
スナップショット前に `NetworkLogSanitizer` が機密ヘッダをマスクし、ボディをバイト上限で切り詰めるため、
意図しない認証情報の流出を防ぎます。

```swift
import iOSRecorder
import iOSRecorderNetwork

let networkSource = NetworkSource(store: monitor.store, maxEntries: 50, bodyLimit: 4096)
let session = Session(
    sources: [networkSource, screenshotSource],
    store: store
)
try await session.capture(screenName: "Checkout")
```

`NetworkLogStore` は `@Observable` で宣言されているため、SwiftUI から直接購読して通信リストをリアルタイム表示することもできます（`iOSRecorderUI` の `NetworkListView` がこれを利用します）。

## Topics

### 通信傍受

- ``NetworkMonitor``
- ``NetworkLogStore``

### データモデル

- ``NetworkLog``
- ``NetworkLogSanitizer``

### Source 統合

- ``NetworkSource``
