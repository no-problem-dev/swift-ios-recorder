# ``iOSRecorderScreenshot``

キーウィンドウを JPEG にラスタライズして `iOSRecorder` の `Source` として提供するライブラリ。

## Overview

`iOSRecorderScreenshot` は `ScreenshotSource` を提供する。`Session` の `sources` に追加するだけで、
`capture()` のたびにキーウィンドウを `drawHierarchy` でラスタライズし、縮小 JPEG の `Artifact` を
キャプチャに添付する。

`ImageRenderer` と異なり `drawHierarchy` はネイティブの `UIViewRepresentable` 要素も確実に写せる。
フル解像度 PNG は 1 枚あたり 5 MB を超えることがあるため、ソース段階で長辺を `maxDimension` に縮小してから
JPEG に変換する。MCP が AI に渡す画像も同じ上限で再縮小されるため、情報損失はほぼ生じない。

```swift
import iOSRecorder
import iOSRecorderScreenshot

let screenshotSource = ScreenshotSource(
    scale: 0,            // 0 = デバイスのネイティブスケール
    maxDimension: 1024,  // 長辺の上限 px
    jpegQuality: 0.8
)

let session = Session(
    sources: [screenshotSource],
    store: store
)
try await session.capture(screenName: "Profile")
```

ラスタライズは `MainActor` で同期実行し、重い JPEG エンコードはバックグラウンドで行うため、UI スレッドのブロックを最小化している。

## Topics

### スクリーンショット取得

- ``ScreenshotSource``
