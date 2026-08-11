import Foundation

/// A titled set of sections produced on device, turning domain data into something a person or an agent can read.
///
/// ``markdown()`` renders it as the text that goes into an artifact or an MCP response.
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

/// Turns data this package knows nothing about — a message list, a run of events — into a readable report.
///
/// Conformances belong in the app, where the Swift domain types actually exist.
public protocol DebugInterpreter: Sendable {
    associatedtype Input
    func interpret(_ input: Input) -> DebugReport
}

/// One number derived from a run of events, carrying the unit and grouping needed to display it.
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

/// Derives numbers from a timeline; ``MetricsSource`` runs every extractor at capture time and folds the results together.
public protocol MetricExtractor: Sendable {
    func metrics(from events: [DebugEvent]) -> [DebugMetric]
}
