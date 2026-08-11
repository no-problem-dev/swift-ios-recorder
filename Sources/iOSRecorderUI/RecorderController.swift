import Foundation
import Observation
import DesignSystem
import iOSRecorder
import iOSRecorderNetwork
import iOSRecorderBonjour

/// Main-actor state behind the floating buttons and the debug panel, holding no UIKit so tests can drive it directly.
@MainActor
@Observable
public final class RecorderController {
    public let session: Session
    private let store: any RecordStore
    public let items: [DebugItem]
    /// Live network monitor; when non-nil the panel gains a Network section.
    public let network: NetworkLogStore?
    /// Probe for the Mac receiver; when non-nil the panel shows a connection row.
    ///
    /// A denied Local Network permission is indistinguishable from a Mac that is simply not running:
    /// the probe never reports reachable and the row keeps saying the Mac is not connected.
    public let reachability: ExportReachability?
    /// Spool for captures that failed to send; when non-nil the panel shows the pending count and a
    /// background loop retries them as soon as the Mac is reachable again.
    public let outbox: (any OutboxDraining)?
    /// Live debug event log; when non-nil the panel gains a timeline section.
    public let debugLog: DebugLog?
    /// Metrics supplied by the app; when non-nil the panel gains a dashboard section.
    public let metrics: MetricsStore?
    /// Panel layout; when nil a default layout is composed from whichever stores were supplied.
    public let console: DebugConsole?
    /// Design system theme for the recorder UI, so the panel can follow the host app's brand.
    public let theme: ThemeProvider
    public private(set) var summaries: [RecordSummary] = []
    /// Delivery state per capture as of the last refresh; it does not follow later deliveries on its own.
    public private(set) var deliveryStates: [RecordID: DeliveryState] = [:]
    /// Captures still held by the outbox, recounted on every refresh and on every auto-drain tick.
    public private(set) var pendingCount = 0
    public var isPresentingPanel = false
    /// Hidden on iOS until a shake toggles the 📷 / 🐞 buttons, and always true on macOS, which has no shake.
    #if canImport(UIKit)
    public var isOverlayVisible = false
    #else
    public var isOverlayVisible = true
    #endif
    public var captureScreenName = ""
    /// Name of the screen on display, set by `.recorderScreen(_:)` and attached to any capture that
    /// does not carry a name of its own.
    public var currentScreen: String?
    @ObservationIgnored private var autoDrainTask: Task<Void, Never>?

    /// Creates the state for one capture session and its store.
    ///
    /// Every optional argument may be `nil`; each one supplied adds a section to the panel:
    /// `network` a network list, `reachability` the connection row,
    /// `outbox` the pending count plus automatic retries, `debugLog` the event timeline,
    /// `metrics` the dashboard.
    ///
    /// - Important: passing `outbox` starts the retry loop immediately, and it keeps running until
    ///   `stopAutoDrain()` is called — deallocating this object does not stop it.
    public init(
        session: Session,
        store: any RecordStore,
        network: NetworkLogStore? = nil,
        reachability: ExportReachability? = nil,
        outbox: (any OutboxDraining)? = nil,
        debugLog: DebugLog? = nil,
        metrics: MetricsStore? = nil,
        items: [DebugItem] = [],
        console: DebugConsole? = nil,
        theme: ThemeProvider? = nil
    ) {
        self.session = session
        self.store = store
        self.network = network
        self.reachability = reachability
        self.outbox = outbox
        self.debugLog = debugLog
        self.metrics = metrics
        self.items = items
        self.console = console
        self.theme = theme ?? ThemeProvider()
        if outbox != nil { startAutoDrain() }
    }

    /// Starts the loop that retries spooled captures whenever the Mac is reachable, so they arrive
    /// within seconds of the connection coming back and nobody has to open the panel.
    ///
    /// Does nothing without an outbox, and does nothing if the loop is already running.
    /// - Parameter interval: Wait between attempts.
    public func startAutoDrain(interval: Duration = .seconds(5)) {
        guard outbox != nil, autoDrainTask == nil else { return }
        autoDrainTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.drainIfPossible()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Cancels the retry loop, which nothing else does — not even deallocating this object.
    public func stopAutoDrain() {
        autoDrainTask?.cancel()
        autoDrainTask = nil
    }

    private func drainIfPossible() async {
        guard let outbox else { return }
        let pending = await outbox.pendingCount()
        pendingCount = pending
        guard pending > 0, reachability?.isReachable ?? true else { return }
        if await outbox.drain() > 0 { await refresh() }
    }

    /// Measures the current screen, stores the result and reloads the list.
    ///
    /// Failures are swallowed: a store that refuses the write leaves the list unchanged and tells the
    /// caller nothing.
    /// - Parameter screenName: Name to record; when nil the name set by `.recorderScreen(_:)` is used.
    public func capture(screenName: String? = nil) async {
        _ = try? await session.capture(screenName: screenName ?? currentScreen)
        await refresh()
    }

    /// Delivery state seen by the last refresh; an ID that was never refreshed reads as pending, not as an error.
    public func deliveryState(for id: RecordID) -> DeliveryState {
        deliveryStates[id] ?? .pending(reason: nil)
    }

    /// Sends one capture again and drains the spool, then reloads the list.
    ///
    /// A capture the store can no longer produce is skipped without a word, and the spool is drained anyway.
    public func resend(_ id: RecordID) async {
        if let record = try? await store.fetch(id) {
            await session.reexport(record)
        }
        await outbox?.drain()
        await refresh()
    }

    /// Captures under the name typed into the panel, trimming whitespace and clearing the field afterwards.
    ///
    /// A field holding only spaces counts as empty and falls back to the screen name in effect.
    public func captureWithEnteredName() async {
        let trimmed = captureScreenName.trimmingCharacters(in: .whitespacesAndNewlines)
        await capture(screenName: trimmed.isEmpty ? nil : trimmed)
        captureScreenName = ""
    }

    /// Reloads at most 100 of the newest captures, their delivery states and the pending count.
    ///
    /// Nothing else updates these properties, so a capture delivered in the background stays shown as
    /// pending until the next call.
    public func refresh() async {
        // Push the spool out first while the Mac is within reach, so a capture that just left shows as delivered.
        if let outbox, reachability?.isReachable ?? true {
            await outbox.drain()
        }
        summaries = (try? await store.query(RecordQuery(limit: 100))) ?? []
        var states: [RecordID: DeliveryState] = [:]
        for summary in summaries {
            states[summary.id] = await session.deliveryState(for: summary.id)
        }
        deliveryStates = states
        pendingCount = await outbox?.pendingCount() ?? 0
    }

    /// Loads a whole record with every artifact attached, which the list summaries deliberately leave out.
    /// - Returns: `nil` for an unknown ID and for a store that failed to read it — the two are not distinguished.
    public func record(for id: RecordID) async -> Record? {
        try? await store.fetch(id)
    }

    /// Hands a record to the exporters again, for pushing an already delivered capture by hand.
    public func reexport(_ record: Record) async {
        await session.reexport(record)
    }

    /// Deletes every stored capture and reloads the list; there is no undo, and whatever already reached
    /// the Mac stays there.
    public func removeAll() async {
        try? await store.removeAll()
        await refresh()
    }
}
