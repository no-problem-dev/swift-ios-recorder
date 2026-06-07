import SwiftUI
import DesignSystem
import iOSRecorder

public extension View {
    /// 計器 UI（フロートボタン + デバッグパネル + シェイク）を載せる。DEBUG 限定で呼ぶ。
    /// ボタンは普段隠れていて、シェイクで表示/非表示をトグル。📷 タップで撮影、🐞 タップでデバッグパネル。
    func recorder(_ controller: RecorderController) -> some View {
        modifier(RecorderModifier(controller: controller))
    }
}

struct RecorderModifier: ViewModifier {
    @Bindable var controller: RecorderController

    func body(content: Content) -> some View {
        placement(content)
            .onShake {
                withAnimation(.snappy) { controller.isOverlayVisible.toggle() }
            }
    }

    @ViewBuilder
    private func placement(_ content: Content) -> some View {
        #if canImport(UIKit)
        // ボタンは別ウィンドウに載せる（スクショに写り込まない & 本体タッチを妨げない）
        // controller を環境に流して .recorderScreen(_:) から参照できるようにする
        content
            .environment(controller)
            .background(OverlayInstaller(controller: controller))
        #else
        content
            .environment(controller)
            .overlay { FloatingButtons(controller: controller).theme(controller.theme) }
        #endif
    }
}
