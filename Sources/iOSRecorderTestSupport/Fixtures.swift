import Foundation
import iOSRecorder

public enum RecordFixtures {
    public static func make(
        id: RecordID = .generate(),
        session: SessionID = SessionID(rawValue: "test-session"),
        screenName: String? = "TestScreen",
        recordedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        tags: [String] = [],
        attributes: [String: String] = [:],
        artifacts: [Artifact] = [.log(text: "hello")]
    ) -> Record {
        Record(
            id: id,
            session: session,
            recordedAt: recordedAt,
            metadata: RecordMetadata(
                screenName: screenName,
                appVersion: nil,
                tags: tags,
                attributes: attributes
            ),
            artifacts: artifacts
        )
    }
}
