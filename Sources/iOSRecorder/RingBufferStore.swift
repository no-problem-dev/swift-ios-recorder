import Foundation

/// オンデバイスの保持実装。容量を超えたら最古を退避する固定長バッファ。
public actor RingBufferStore: RecordStore {
    private var storage: [RecordID: Record] = [:]
    private var order: [RecordID] = []
    private let capacity: Int

    public init(capacity: Int = 100) {
        self.capacity = max(1, capacity)
    }

    public func save(_ record: Record) async throws {
        if storage[record.id] == nil { order.append(record.id) }
        storage[record.id] = record
        while order.count > capacity {
            let evicted = order.removeFirst()
            storage[evicted] = nil
        }
    }

    public func query(_ query: RecordQuery) async throws -> [RecordSummary] {
        let summaries = order
            .compactMap { storage[$0] }
            .map(RecordSummary.init(record:))
            .filter(query.matches)
            .sorted { $0.recordedAt > $1.recordedAt }
        return Array(summaries.prefix(query.limit))
    }

    public func fetch(_ id: RecordID) async throws -> Record {
        guard let record = storage[id] else { throw RecordStoreError.notFound(id) }
        return record
    }

    public func delete(_ id: RecordID) async throws {
        storage[id] = nil
        order.removeAll { $0 == id }
    }

    public func removeAll() async throws {
        storage.removeAll()
        order.removeAll()
    }
}
