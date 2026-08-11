import Foundation

/// Keeps recent captures in memory only, bounded by a record count and a byte budget at the same time.
///
/// Nothing reaches disk, so everything is gone when the process ends — use a file-backed store when captures
/// have to survive a relaunch. Whichever limit is hit first evicts the oldest captures, and ``fetch(_:)`` on an
/// evicted id throws ``RecordStoreError/notFound(_:)``.
public actor RingBufferStore: RecordStore {
    private var storage: [RecordID: Record] = [:]
    private var order: [RecordID] = []
    private var totalBytes = 0
    private let capacity: Int
    private let capacityBytes: Int

    /// - Parameters:
    ///   - capacity: Most captures to keep.
    ///   - capacityBytes: Ceiling on the summed artifact bytes. Screenshots dwarf everything else, so this is
    ///     the limit that actually stops the buffer from eating memory. The newest capture is always kept,
    ///     even when it exceeds the budget on its own.
    public init(capacity: Int = 100, capacityBytes: Int = 64_000_000) {
        self.capacity = max(1, capacity)
        self.capacityBytes = max(1, capacityBytes)
    }

    public func save(_ record: Record) async throws {
        if let existing = storage[record.id] {
            totalBytes -= Self.byteSize(of: existing)
        } else {
            order.append(record.id)
        }
        storage[record.id] = record
        totalBytes += Self.byteSize(of: record)
        while order.count > 1, order.count > capacity || totalBytes > capacityBytes {
            let evicted = order.removeFirst()
            if let old = storage.removeValue(forKey: evicted) {
                totalBytes -= Self.byteSize(of: old)
            }
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
        if let removed = storage.removeValue(forKey: id) {
            totalBytes -= Self.byteSize(of: removed)
        }
        order.removeAll { $0 == id }
    }

    public func removeAll() async throws {
        storage.removeAll()
        order.removeAll()
        totalBytes = 0
    }

    private static func byteSize(of record: Record) -> Int {
        record.artifacts.reduce(0) { $0 + $1.data.count }
    }
}
