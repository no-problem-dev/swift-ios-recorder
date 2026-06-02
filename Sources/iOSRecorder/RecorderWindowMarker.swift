/// 計器用オーバーレイウィンドウを識別するためのマーカー。
/// ScreenshotSource はこの identifier を持つウィンドウを撮影対象から除外する
/// （フロートボタン等の計器 UI がスクショに写り込まないようにするため）。
public enum RecorderWindowMarker {
    public static let overlayIdentifier = "dev.iOSRecorder.overlay"
}
