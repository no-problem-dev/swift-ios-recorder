import Testing
import Foundation
@testable import iOSRecorderUI
import iOSRecorder
import iOSRecorderTestSupport

@MainActor
@Suite struct RecorderControllerTests {
    @Test func captureStoresAndRefreshesSummaries() async {
        let store = RingBufferStore()
        let session = Session(sources: [FakeSource()], store: store)
        let controller = RecorderController(session: session, store: store)

        await controller.capture(screenName: "Home")

        #expect(controller.summaries.count == 1)
        #expect(controller.summaries.first?.metadata.screenName == "Home")
    }

    @Test func captureWithEnteredNameUsesAndClearsField() async {
        let store = RingBufferStore()
        let session = Session(sources: [FakeSource()], store: store)
        let controller = RecorderController(session: session, store: store)
        controller.captureScreenName = "  Checkout  "

        await controller.captureWithEnteredName()

        #expect(controller.summaries.first?.metadata.screenName == "Checkout")
        #expect(controller.captureScreenName == "")
    }

    @Test func emptyEnteredNameCapturesWithoutScreenName() async {
        let store = RingBufferStore()
        let session = Session(sources: [FakeSource()], store: store)
        let controller = RecorderController(session: session, store: store)
        controller.captureScreenName = "   "

        await controller.captureWithEnteredName()

        #expect(controller.summaries.first?.metadata.screenName == nil)
    }

    @Test func recordForIDFetchesFullRecord() async {
        let store = RingBufferStore()
        try? await store.save(RecordFixtures.make(id: RecordID(rawValue: "x"), artifacts: [.log(text: "hi")]))
        let session = Session(sources: [], store: store)
        let controller = RecorderController(session: session, store: store)

        let record = await controller.record(for: RecordID(rawValue: "x"))
        #expect(record?.artifacts.first?.data == Data("hi".utf8))
    }

    @Test func removeAllClearsRecords() async {
        let store = RingBufferStore()
        let session = Session(sources: [FakeSource()], store: store)
        let controller = RecorderController(session: session, store: store)
        await controller.capture()
        #expect(controller.summaries.count == 1)

        await controller.removeAll()
        #expect(controller.summaries.isEmpty)
    }

    @Test func customItemsAreRetained() {
        let store = RingBufferStore()
        let session = Session(sources: [], store: store)
        let controller = RecorderController(
            session: session,
            store: store,
            items: [
                .action(id: "a", title: "Reset") {},
                .toggle(id: "b", title: "Flag", get: { true }, set: { _ in }),
                .info(id: "c", title: "Env", value: { "staging" })
            ]
        )
        #expect(controller.items.count == 3)
        #expect(controller.items.map(\.id) == ["a", "b", "c"])
    }

    @Test func captureUsesCurrentScreenWhenNoExplicitName() async {
        let store = RingBufferStore()
        let session = Session(sources: [FakeSource()], store: store)
        let controller = RecorderController(session: session, store: store)
        controller.currentScreen = "Login"

        await controller.capture()

        #expect(controller.summaries.first?.metadata.screenName == "Login")
    }

    @Test func explicitNameOverridesCurrentScreen() async {
        let store = RingBufferStore()
        let session = Session(sources: [FakeSource()], store: store)
        let controller = RecorderController(session: session, store: store)
        controller.currentScreen = "Login"

        await controller.capture(screenName: "Home")

        #expect(controller.summaries.first?.metadata.screenName == "Home")
    }

    @Test func panelPresentationTogglesState() {
        let store = RingBufferStore()
        let session = Session(sources: [], store: store)
        let controller = RecorderController(session: session, store: store)

        #expect(controller.isPresentingPanel == false)
        controller.isPresentingPanel = true
        #expect(controller.isPresentingPanel == true)
    }
}

/// The re-send button is the one place a person asks for a delivery and waits to be told what
/// happened. Reporting every attempt as sent hides exactly the failure they pressed it to fix.
@MainActor
@Suite struct ReexportReportingTests {
    private func controller(exporters: [any Exporter]) -> (RecorderController, RingBufferStore) {
        let store = RingBufferStore()
        let session = Session(sources: [FakeSource()], store: store, exporters: exporters)
        return (RecorderController(session: session, store: store), store)
    }

    @Test func failedReexportIsReportedAsFailed() async {
        let (controller, _) = controller(exporters: [FakeExporter(shouldThrow: true, label: "Mac")])
        let record = RecordFixtures.make()

        let outcomes = await controller.reexport(record)

        #expect(outcomes.contains { !$0.succeeded }, "a re-send every exporter refused reported no failure")
        #expect(ReexportResult(outcomes) == .failed(reason: "transportFailed(\"fake\")"))
    }

    @Test func successfulReexportIsReportedAsSent() async {
        let (controller, _) = controller(exporters: [FakeExporter(label: "Mac")])

        let outcomes = await controller.reexport(RecordFixtures.make())
        let allSucceeded = outcomes.allSatisfy { $0.succeeded }

        #expect(allSucceeded)
        #expect(ReexportResult(outcomes) == .sent)
    }

    /// With nothing configured to send to, nothing was sent — which is not the same as sent.
    @Test func reexportWithNoExporterIsNotReportedAsSent() async {
        let (controller, _) = controller(exporters: [])

        let outcomes = await controller.reexport(RecordFixtures.make())

        #expect(outcomes.isEmpty)
        #expect(ReexportResult(outcomes) != .sent)
    }

    /// One route failing is a failure even when another worked: the capture did not reach everywhere.
    @Test func partialReexportFailureIsReportedAsFailed() async {
        let (controller, _) = controller(exporters: [
            FakeExporter(label: "Mac"),
            FakeExporter(shouldThrow: true, label: "Backup")
        ])

        let outcomes = await controller.reexport(RecordFixtures.make())

        #expect(ReexportResult(outcomes) == .failed(reason: "transportFailed(\"fake\")"))
    }
}
