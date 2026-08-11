# ``iOSRecorderScreenshot``

Adds the screen itself to a capture: rasterizes the app's key window and attaches it as a downscaled JPEG.

## Overview

``ScreenshotSource`` is a `Source`. Add it to a session's `sources` and every capture carries an image
of whatever was on screen when the trigger fired.

```swift
import iOSRecorder
import iOSRecorderScreenshot

let screenshotSource = ScreenshotSource(
    scale: 0,            // 0 uses the device's own scale
    maxDimension: 1024,  // longest edge in pixels
    jpegQuality: 0.8
)

let session = Session(
    sources: [screenshotSource],
    store: store
)
try await session.capture(screenName: "Profile")
```

Rasterizing uses `drawHierarchy`, which — unlike `ImageRenderer` — also captures native
`UIViewRepresentable` content, so map views, web views and camera previews come out as they look.

The recorder's own overlay window is excluded by its accessibility identifier, so the floating buttons
from `iOSRecorderUI` never appear in a shot.

### What it costs and what it drops

The stored image is always a downscaled JPEG. A full-resolution PNG runs past 5 MB per frame on an
iPhone 16 Pro, which dominates memory, transfer and disk; the image handed to an AI agent by
`iOSRecorderMCP` is capped at the same 1024 px ceiling anyway, so shrinking this early costs nothing.
Pass `maxDimension: 0` to keep the rendered size.

Only `drawHierarchy` runs on the main actor. The JPEG encode runs off it, so a capture does not freeze
the UI for the length of the encode.

When no window can be found there is no artifact and no error: the record is saved without a screenshot,
and nothing anywhere reports why. The image's own attributes carry the window's `width` and `height` in
points, which is how a consumer can tell what was rendered before downscaling.

The whole target is compiled only where UIKit exists. In a macOS build ``ScreenshotSource`` is not
present at all, so a session shared between iOS and macOS has to leave it out on the Mac side.

## Topics

### Capturing the screen

- ``ScreenshotSource``
