[English](./README.md) | 日本語

# swift-ios-recorder

開発中の iOS アプリが実際に何をしているか（画面・アプリ自身の状態・通信・ログ）を Mac 上の AI コーディングエージェントに見せる。UI の変更確認を、手でタップしてスクショを撮るループから外すためのもの。

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)

## 概要

ルートの View に modifier を 1 つ付けるとフロートボタンが出る。押すか端末を振ると、その場で
キャプチャを 1 件取る。スクリーンショット、自分で選んでエンコードしたアプリの状態、直近の HTTP
通信、直近のログが、1 つのタイムスタンプの下にまとまる。

キャプチャは撮ったそばから同一ネットワークの Mac へ届く。同梱の実行ファイルを MCP サーバーとして
登録すれば、コーディングエージェントが一覧・取得・イベント検索をできる。つまり、エージェントは
自分が今変えた画面を、こちらが言葉で説明しなくても見られる。

ソースは個別に選べる。スクショだけでもよいし、状態・通信・ログを必要に応じて足せる。Mac が
いなければアプリ内でキャプチャを閲覧できる。出荷するものではないので、デバッグビルドにだけ
組み込むこと。

## 使い方

### iOS アプリ側

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
    exporters: [BonjourExporter()]   // 同一ネットワークの Mac へ送る
)
let controller = RecorderController(session: session, store: store)

// ルートに 1 行。タップ / シェイクで計測、長押しで一覧。
ContentView().recorder(controller)
```

`BonjourExporter` は Bonjour のブラウズで Mac を見つけるので、アプリにローカルネットワーク権限と
`Info.plist` の `NSLocalNetworkUsageDescription` が要る。許可が下りるまでキャプチャは撮れて保存も
されるが、端末から出て行かない。

### Mac 側

```sh
claude mcp add ios-recorder -- ios-recorder mcp
```

受信機は MCP プロセスに同居するので、エージェントの起動・終了に連動する。別に常駐させるデーモンは
無い。登録後は、端末でボタンを押せばキャプチャがエージェントの手元に届き、`list_captures` /
`get_capture` / `search_events` / `get_event` で読める。受信機だけを単体で動かしたい場合は
`ios-recorder serve`。

> バイナリを置き換えたら `codesign --force --sign - <path>` で再署名すること。上書きコピーすると
> ad-hoc 署名が無効になり、起動時にプロセスが落とされる。

## ドキュメント

[API ドキュメント](https://no-problem-dev.github.io/swift-ios-recorder/documentation/iosrecorder/)

## インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-ios-recorder.git", .upToNextMinor(from: "0.6.0"))
]
```

```swift
.target(name: "YourTarget", dependencies: [
    .product(name: "iOSRecorder", package: "swift-ios-recorder"),           // コア
    .product(name: "iOSRecorderUI", package: "swift-ios-recorder"),         // SwiftUI 統合
    .product(name: "iOSRecorderScreenshot", package: "swift-ios-recorder"), // スクリーンショット
    .product(name: "iOSRecorderBonjour", package: "swift-ios-recorder"),    // Mac への転送
])
```

Mac 側の相棒は `ios-recorder` 実行ファイル。このリポジトリを `swift build` して作る。

## コントリビュート

[CONTRIBUTING.md](./CONTRIBUTING.md) を参照。

## ライセンス

MIT。[LICENSE](./LICENSE) を参照。
