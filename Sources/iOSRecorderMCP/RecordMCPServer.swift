import Foundation
import iOSRecorder

/// RecordStore を MCP の 2 ツール（list_captures / get_capture）に橋渡しする。
/// 現状は Store への委譲ロジックのみ。MCP トランスポート接続は M4 で。
public actor RecordMCPServer {
    private let store: any RecordStore

    public init(store: any RecordStore) {
        self.store = store
    }

    /// `list_captures(filter?)` の本体。
    public func listCaptures(_ query: RecordQuery = RecordQuery()) async throws -> [RecordSummary] {
        try await store.query(query)
    }

    /// `get_capture(id)` の本体。
    public func getCapture(_ id: RecordID) async throws -> Record {
        try await store.fetch(id)
    }

    /// `delete_capture(id)` の本体。
    public func deleteCapture(_ id: RecordID) async throws {
        try await store.delete(id)
    }

    /// `clear_captures` の本体。
    public func clearCaptures() async throws {
        try await store.removeAll()
    }

    // TODO(M4): MCP Swift SDK（stdio）に接続し、上記を list_captures / get_capture
    // ツールとして公開する。
}
