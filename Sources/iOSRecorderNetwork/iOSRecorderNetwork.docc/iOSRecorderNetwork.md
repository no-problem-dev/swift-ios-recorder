# ``iOSRecorderNetwork``

Records the HTTP the app makes without changing any calling code, and folds the recent traffic into a capture with secrets masked.

## Overview

``NetworkMonitor`` intercepts `URLSession` traffic and files each exchange in a ``NetworkLogStore``. It
runs independently of capturing: traffic accumulates whether or not a record is ever taken.

```swift
import iOSRecorderNetwork

let monitor = await NetworkMonitor(ignoredHosts: ["metrics.example.com"])
await monitor.start()
```

`start()` registers a `URLProtocol` and swizzles `URLSessionConfiguration.protocolClasses`, so sessions
the app builds from its own configuration are intercepted too. There is no counterpart that unhooks it —
interception lasts for the life of the process, so treat `start()` as a debug-build-only switch.

The interceptor holds only a weak reference to the store. Release the monitor and requests keep being
intercepted while nothing is recorded; start a second monitor and the interceptor points at the newer
store. `ignoredHosts` matches as a substring, so `"example.com"` also skips `api.example.com`.

At capture time, pass ``NetworkSource`` in the session's `sources`.

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

### What actually gets logged

Only a body the caller set as `httpBody` is recorded. A streamed or multipart upload arrives as
`httpBodyStream` and is logged with no request body at all. The whole response is buffered in memory in
order to be logged, so a large download is held twice while it is in flight.

``NetworkLogStore`` is memory only, newest first, and keeps 500 exchanges by default. A request older
than that is gone even if a capture happens a second later. It is `@Observable`, so SwiftUI can subscribe
to it directly and show traffic live — which is what the network list in `iOSRecorderUI` does.

### What is masked, and when

Header values whose names suggest a secret are masked as the interceptor writes the entry, so they are
already hidden in the live buffer. Everything else — the URL query string, the request body, the
response body — is masked only by ``NetworkLog/redacted(bodyLimit:)``, which ``NetworkSource`` applies to
every entry on the way into a capture. A ``NetworkLog`` read straight out of the live buffer still holds
the query string and both bodies exactly as they went over the wire.

``NetworkLogSanitizer`` decides what counts as a secret by substring rather than an exact list, which is
what catches `client_secret`, `oauth_signature` and `X-Auth-Token`; the bare names `key` and `sig` and
anything ending in `key` are caught as well. In a JSON body it replaces the string value of any such key
with `***`. It works on the raw text, so it also covers a body that was truncated or is not valid JSON —
but only string values are reachable that way, and a secret stored as a number survives.

Non-text bodies become a placeholder that keeps only the size, such as `<elided image/jpeg, 124534 bytes>`.
A body with no declared content type is elided too when it looks like decoded binary. Text bodies are cut
to `bodyLimit` characters — 4096 by default — with a note giving the original length, so a short body and
a shortened one can be told apart.

Captured traffic is added to a record as an artifact of kind `network`.

## Topics

### Interception

- ``NetworkMonitor``
- ``NetworkLogStore``

### Data model

- ``NetworkLog``
- ``NetworkLogSanitizer``

### Folding traffic into a capture

- ``NetworkSource``
