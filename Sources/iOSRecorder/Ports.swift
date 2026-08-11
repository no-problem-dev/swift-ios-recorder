import Foundation

/// What a source is told about the capture in flight: which session, which screen, which caller attributes.
///
/// Every source in one capture receives the same value, so it is also the way two sources agree on what they
/// were looking at.
public struct RecordContext: Sendable {
    public let session: SessionID
    public let screenName: String?
    public let attributes: [String: String]

    public init(session: SessionID, screenName: String? = nil, attributes: [String: String] = [:]) {
        self.session = session
        self.screenName = screenName
        self.attributes = attributes
    }
}

/// One thing worth measuring when a capture happens; adding a kind of evidence means adding a conformance.
///
/// ``Session`` runs every source concurrently and drops the `nil` results, so returning `nil` means "nothing to
/// record this time". There is no way to report a failure — a source that cannot measure is indistinguishable
/// from one with nothing to say.
public protocol Source: Sendable {
    var kind: ArtifactKind { get }
    func measure(_ context: RecordContext) async -> Artifact?
}

/// Where captures live once taken, and the only part of the core an app has to choose an implementation for.
///
/// Implementations set their own eviction policy, so a capture can disappear without anyone deleting it:
/// ``fetch(_:)`` on an evicted id throws ``RecordStoreError/notFound(_:)``.
public protocol RecordStore: Sendable {
    func save(_ record: Record) async throws
    func query(_ query: RecordQuery) async throws -> [RecordSummary]
    func fetch(_ id: RecordID) async throws -> Record
    func delete(_ id: RecordID) async throws
    func removeAll() async throws
}

/// Sends a saved capture somewhere off the device — a Bonjour receiver, iCloud, a file.
///
/// ``Session`` treats exporting as best effort: a thrown error becomes an ``ExportOutcome`` and never reaches
/// the code that asked for the capture. Wrap in ``OutboxExporter`` when a failed send must be retried.
public protocol Exporter: Sendable {
    /// Names this route in every ``ExportOutcome``, so a failure can be traced to one exporter. Defaults to the type name.
    var label: String { get }
    func export(_ record: Record) async throws
}

public extension Exporter {
    var label: String { String(describing: type(of: self)) }
}

/// The receiving end of an ``Exporter``, implemented on the machine collecting captures rather than the device.
///
/// Records arrive as a throwing stream, so a transport failure ends the stream rather than arriving as an element.
public protocol RecordReceiver: Sendable {
    func records() -> AsyncThrowingStream<Record, any Error>
}

/// Turns a capture into bytes for the wire and back; both ends of a transport must agree on one.
public protocol RecordCodec: Sendable {
    func encode(_ record: Record) throws -> Data
    func decode(_ data: Data) throws -> Record
}

public enum RecordStoreError: Error, Sendable, Equatable {
    case notFound(RecordID)
}

public enum ExporterError: Error, Sendable, Equatable {
    case notImplemented(String)
    case transportFailed(String)
    /// The record is bigger than the transport will ever accept, so retrying cannot help.
    ///
    /// ``OutboxExporter`` deletes these rather than queueing them; one oversized record would
    /// otherwise sit at the head of the queue and block everything behind it.
    case payloadTooLarge(bytes: Int)
}

/// How much a device has accumulated and where it sits; this is what the MCP `get_storage_info` tool answers with.
public struct StorageInfo: Sendable, Codable, Equatable {
    public let totalRecords: Int
    public let totalBytes: Int
    public let oldestRecordedAt: Date?
    public let newestRecordedAt: Date?
    public let location: String?

    public init(
        totalRecords: Int,
        totalBytes: Int,
        oldestRecordedAt: Date? = nil,
        newestRecordedAt: Date? = nil,
        location: String? = nil
    ) {
        self.totalRecords = totalRecords
        self.totalBytes = totalBytes
        self.oldestRecordedAt = oldestRecordedAt
        self.newestRecordedAt = newestRecordedAt
        self.location = location
    }
}

/// Optional for a ``RecordStore``: without a conformance the MCP `get_storage_info` tool has nothing to answer with.
public protocol StorageReporting: Sendable {
    func storageInfo() async -> StorageInfo
}
