import Foundation

/// 解釈結果の構造化レポート。オンデバイスでドメインデータを「読める形」に変換した成果物。
/// markdown() でアーティファクト/MCP 向けテキストに落とせる。
public struct DebugReport: Sendable, Codable, Equatable {
    public struct Section: Sendable, Codable, Equatable {
        public let title: String
        public let lines: [String]
        public init(title: String, lines: [String]) {
            self.title = title
            self.lines = lines
        }
    }

    public let title: String
    public let sections: [Section]

    public init(title: String, sections: [Section]) {
        self.title = title
        self.sections = sections
    }

    public func markdown() -> String {
        var out = "# \(title)\n"
        for section in sections {
            out += "\n## \(section.title)\n"
            for line in section.lines { out += "- \(line)\n" }
        }
        return out
    }
}

/// ドメインデータ（ServerMessage[] / イベント列 等）を構造化レポートに変換する解釈器。
/// Swift のドメイン型が在るオンデバイス側に実装を置く。
public protocol DebugInterpreter: Sendable {
    associatedtype Input
    func interpret(_ input: Input) -> DebugReport
}

/// イベント列から導出する定量メトリクス。
public struct DebugMetric: Sendable, Codable, Equatable {
    public let name: String
    public let value: Double
    public let unit: String?
    public let category: String

    public init(name: String, value: Double, unit: String? = nil, category: String) {
        self.name = name
        self.value = value
        self.unit = unit
        self.category = category
    }
}

/// `DebugEvent` 列からメトリクスを抽出する計測器。
public protocol MetricExtractor: Sendable {
    func metrics(from events: [DebugEvent]) -> [DebugMetric]
}
