import Foundation

/// The wire format the Bonjour transport uses unless another codec is supplied; dates travel as ISO 8601.
///
/// Artifact bytes ride along base64-encoded, so an encoded screenshot is roughly a third larger than the file.
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
