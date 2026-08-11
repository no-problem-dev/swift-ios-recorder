/// The accessibility identifier that marks the recorder's own overlay window.
///
/// The screenshot source skips every window carrying it, which is what keeps the floating capture button out of
/// the picture it takes. A custom overlay window has to set this identifier or it will appear in every shot.
public enum RecorderWindowMarker {
    public static let overlayIdentifier = "dev.iOSRecorder.overlay"
}
