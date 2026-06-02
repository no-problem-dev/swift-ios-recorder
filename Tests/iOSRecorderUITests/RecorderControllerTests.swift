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
