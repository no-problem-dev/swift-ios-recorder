import Foundation

/// One timestamped entry in the live debug log — an agent step, a generated surface, a request, any value at all.
///
/// Everything is normalized into this one envelope so the timeline stays a single list. `payload` is opaque to
/// this package, exactly like artifact data, so a new kind of event needs no change here.
public struct DebugEvent: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let at: Date
    /// Groups events for filtering and for the timeline's section list. Open set; `agent`, `a2ui`, `network`, `metric` are conventional.
    public let category: String
    /// Distinguishes events inside a category, such as `tool_call` or `decode_failed`.
    ///
    /// Counts are grouped by `category.name`, so this is the granularity of every derived number.
    public let name: String
    /// The single line a person or an agent reads without opening the payload.
    public let summary: String
    /// Structured detail beside the summary (toolName, surfaceId, tokens). Truncation leaves its own record here too.
    public let attributes: [String: String]
    /// The raw data behind the summary. May have been cut down at capture time — check `payloadTruncated` in the attributes before trusting its length.
    public let payload: Data?

    public init(
        id: UUID = UUID(),
        at: Date = Date(),
        category: String,
        name: String,
        summary: String,
        attributes: [String: String] = [:],
        payload: Data? = nil
    ) {
        self.id = id
        self.at = at
        self.category = category
        self.name = name
        self.summary = summary
        self.attributes = attributes
        self.payload = payload
    }
}

public extension DebugEvent {
    /// A copy with the payload and its type hint stripped, leaving the summary and the remaining attributes.
    ///
    /// For folding a timeline into a message where base64 payloads would drown out everything else.
    func withoutPayload() -> DebugEvent {
        var attrs = attributes
        attrs.removeValue(forKey: "payloadType")
        return DebugEvent(
            id: id, at: at, category: category, name: name,
            summary: summary, attributes: attrs, payload: nil
        )
    }

    /// A copy whose payload is cut down to fit, keeping UTF-8 characters whole and recording what was lost.
    ///
    /// Events already inside the limit come back untouched, so only outliers such as a full prompt pay anything.
    /// The truncated copy carries `payloadTruncated` and `payloadOriginalBytes` in its attributes.
    /// - Parameter maxBytes: Ceiling for the payload after cutting.
    func withPayloadLimited(to maxBytes: Int) -> DebugEvent {
        guard let payload, payload.count > maxBytes else { return self }
        // Step back up to 3 bytes to land on a UTF-8 boundary; binary payloads keep the blunt cut.
        var truncated = payload.prefix(maxBytes)
        for back in 0..<4 where maxBytes - back >= 0 {
            let candidate = payload.prefix(maxBytes - back)
            if String(data: candidate, encoding: .utf8) != nil {
                truncated = candidate
                break
            }
        }
        var attrs = attributes
        attrs["payloadTruncated"] = "true"
        attrs["payloadOriginalBytes"] = "\(payload.count)"
        return DebugEvent(
            id: id, at: at, category: category, name: name,
            summary: summary, attributes: attrs, payload: Data(truncated)
        )
    }

    /// Puts any encodable value into the payload as JSON, so the detail view can show its structure.
    ///
    /// The value's Swift type name is recorded in `payloadType`. If encoding fails the event is still emitted,
    /// with that type name but no payload at all.
    init(
        category: String,
        name: String,
        summary: String,
        attributes: [String: String] = [:],
        at: Date = Date(),
        encoding value: some Encodable & Sendable
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var attrs = attributes
        attrs["payloadType"] = String(describing: type(of: value))
        self.init(
            at: at,
            category: category,
            name: name,
            summary: summary,
            attributes: attrs,
            payload: try? encoder.encode(value)
        )
    }

    /// Puts plain text into the payload, for output that is not JSON — log lines, model completions.
    init(
        category: String,
        name: String,
        summary: String,
        attributes: [String: String] = [:],
        at: Date = Date(),
        text: String
    ) {
        self.init(
            at: at,
            category: category,
            name: name,
            summary: summary,
            attributes: attributes,
            payload: Data(text.utf8)
        )
    }
}
