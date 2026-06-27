import Foundation

/// `RecordCodec` の JSON 実装。日付は ISO 8601 形式で直列化する。Bonjour 転送のデフォルト codec。
public struct JSONRecordCodec: RecordCodec {
    public init() {}

    public func encode(_ record: Record) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(record)
    }

    public func decode(_ data: Data) throws -> Record {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Record.self, from: data)
    }
}
