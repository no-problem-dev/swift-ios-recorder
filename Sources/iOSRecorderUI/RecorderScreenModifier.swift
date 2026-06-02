import SwiftUI

public extension View {
    /// 画面に名前を付ける。表示中はその名前が撮影に自動付与され、一覧・検索で識別できる。
    /// `.recorder(controller)` の内側で使うこと（controller を環境から取得する）。
    func recorderScreen(_ name: String) -> some View {
        modifier(RecorderScreenModifier(name: name))
    }
}

struct RecorderScreenModifier: ViewModifier {
    let name: String
    @Environment(RecorderController.self) private var controller: RecorderController?

    func body(content: Content) -> some View {
        content.onAppear { controller?.currentScreen = name }
    }
}
