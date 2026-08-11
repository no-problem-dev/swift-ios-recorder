import Foundation

/// How the receiver is doing at one instant, as reported by the `connection_status` tool.
///
/// `totalReceived` and `lastReceivedAt` are what answer the question this exists for: take a
/// capture on the device, ask again, and see whether the count moved.
public struct ReceiverStatusSnapshot: Sendable, Codable, Equatable {
    public var listening: Bool
    public var port: UInt16?
    public var serviceName: String?
    public var totalReceived: Int
    public var lastReceivedAt: Date?
    public var startedAt: Date

    public init(
        listening: Bool,
        port: UInt16? = nil,
        serviceName: String? = nil,
        totalReceived: Int = 0,
        lastReceivedAt: Date? = nil,
        startedAt: Date
    ) {
        self.listening = listening
        self.port = port
        self.serviceName = serviceName
        self.totalReceived = totalReceived
        self.lastReceivedAt = lastReceivedAt
        self.startedAt = startedAt
    }
}

/// Lets the MCP layer ask about a receiver it does not own. Implemented by the executable that
/// actually holds the listener; supplying one is what makes the `connection_status` tool appear.
public protocol ReceiverStatusProviding: Sendable {
    func status() async -> ReceiverStatusSnapshot
}

/// Lets the MCP layer rebuild the listener from scratch. Supplying one makes the
/// `restart_receiver` tool appear, and also enables automatic recovery before every tool call.
public protocol ReceiverControlling: Sendable {
    func restart() async -> ReceiverStatusSnapshot
}
