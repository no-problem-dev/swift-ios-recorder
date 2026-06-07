import Testing
import Foundation
@testable import iOSRecorder
import iOSRecorderTestSupport

@Suite struct JSONRecordCodecTests {
    @Test func roundTripsRecord() throws {
        let codec = JSONRecordCodec()
        let original = RecordFixtures.make(artifacts: [
            .screenshot(pngData: Data([1, 2, 3])),
            .state(json: Data("{\"a\":1}".utf8))
        ])
        let decoded = try codec.decode(codec.encode(original))
        #expect(decoded.id == original.id)
        #expect(decoded.recordedAt == original.recordedAt)
        #expect(decoded.artifacts.count == 2)
        #expect(decoded.artifacts[0].data == Data([1, 2, 3]))
        #expect(decoded.artifacts[0].kind == .screenshot)
    }

    @Test func identifiersEncodeAsBareStrings() throws {
        let data = try JSONRecordCodec().encode(RecordFixtures.make(id: RecordID(rawValue: "abc")))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"id\":\"abc\""))
    }
}

@Suite struct ArtifactTests {
    @Test func screenshotConvenience() {
        let artifact = Artifact.screenshot(pngData: Data([1]))
        #expect(artifact.kind == .screenshot)
        #expect(artifact.mediaType == "image/png")
    }

    @Test func logConvenienceEncodesUTF8() {
        let artifact = Artifact.log(text: "hello")
        #expect(artifact.kind == .log)
        #expect(String(decoding: artifact.data, as: UTF8.self) == "hello")
    }

    @Test func summaryDropsArtifactData() {
        let summary = RecordSummary(record: RecordFixtures.make(
            artifacts: [.screenshot(pngData: Data([9])), .log(text: "x")]
        ))
        #expect(summary.artifactKinds == [.screenshot, .log])
    }
}

@Suite struct JPEGArtifactTests {
    @Test func jpegScreenshotFactorySetsMediaType() {
        let artifact = Artifact.screenshot(jpegData: Data([0xFF, 0xD8]), attributes: ["width": "100"])
        #expect(artifact.kind == .screenshot)
        #expect(artifact.mediaType == "image/jpeg")
        #expect(artifact.attributes["width"] == "100")
    }
}
