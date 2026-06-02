import Testing
import Foundation
@testable import iOSRecorder
import iOSRecorderTestSupport

@Suite struct SessionTests {
    @Test func captureGathersArtifactsFromAllSourcesAndStores() async throws {
        let store = RingBufferStore()
        let session = Session(
            sources: [
                FakeSource(kind: .screenshot, artifact: .screenshot(pngData: Data([0]))),
                FakeSource(kind: .log, artifact: .log(text: "l"))
            ],
            store: store
        )
        let id = try await session.capture(screenName: "Home", tags: ["t"])
        let record = try await store.fetch(id)
        #expect(record.artifacts.count == 2)
        #expect(record.metadata.screenName == "Home")
        #expect(record.metadata.tags == ["t"])
        #expect(record.session == session.id)
    }

    @Test func captureSkipsNilArtifacts() async throws {
        let store = RingBufferStore()
        let session = Session(
            sources: [FakeSource(artifact: nil), FakeSource(artifact: .log(text: "x"))],
            store: store
        )
        let id = try await session.capture()
        let record = try await store.fetch(id)
        #expect(record.artifacts.count == 1)
    }

    @Test func capturePropagatesAppVersion() async throws {
        let store = RingBufferStore()
        let session = Session(appVersion: "1.2.3", sources: [FakeSource()], store: store)
        let id = try await session.capture()
        let record = try await store.fetch(id)
        #expect(record.metadata.appVersion == "1.2.3")
    }

    @Test func captureExportsToAttachedExporters() async throws {
        let store = RingBufferStore()
        let exporter = FakeExporter()
        let session = Session(sources: [FakeSource()], store: store, exporters: [exporter])
        _ = try await session.capture()
        let count = await exporter.exportedCount()
        #expect(count == 1)
    }

    @Test func captureSucceedsEvenWhenExporterThrows() async throws {
        let store = RingBufferStore()
        let exporter = FakeExporter(shouldThrow: true)
        let session = Session(sources: [FakeSource()], store: store, exporters: [exporter])
        let id = try await session.capture()
        let record = try await store.fetch(id)
        #expect(record.artifacts.count == 1)
    }

    @Test func attachAddsExporterAfterInit() async throws {
        let store = RingBufferStore()
        let exporter = FakeExporter()
        let session = Session(sources: [FakeSource()], store: store)
        await session.attach(exporter)
        _ = try await session.capture()
        let count = await exporter.exportedCount()
        #expect(count == 1)
    }
}
