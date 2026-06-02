import Foundation

/// Mac 側受信機の健全性スナップショット。MCP の connection_status が返す。
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

/// 受信機の状態を MCP に渡すポート（exe 側が実装）。
public protocol ReceiverStatusProviding: Sendable {
    func status() async -> ReceiverStatusSnapshot
}

/// 受信機を貼り直すポート（restart_receiver 用、exe 側が実装）。
public protocol ReceiverControlling: Sendable {
    func restart() async -> ReceiverStatusSnapshot
}
