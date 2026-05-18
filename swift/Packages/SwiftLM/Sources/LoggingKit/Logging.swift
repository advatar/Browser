import Contracts
import Foundation

public actor AppLogger {
    private var entries: [RequestLogRecord] = []

    public init() {}

    public func log(level: String, category: String, message: String, metadata: [String: String] = [:]) {
        let entry = RequestLogRecord(
            id: Identifiers.prefixed("log"),
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            createdAt: Time.nowISO8601()
        )
        entries.insert(entry, at: 0)
        if entries.count > 500 {
            entries = Array(entries.prefix(500))
        }
        print(Self.consoleLine(for: entry))
    }

    public func all() -> [RequestLogRecord] {
        entries
    }

    private static func consoleLine(for entry: RequestLogRecord) -> String {
        let metadata = entry.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value))" }
            .joined(separator: " ")
        let base = "[SwiftLM][\(entry.createdAt)][\(entry.level.uppercased())][\(entry.category)] \(sanitize(entry.message))"
        guard metadata.isEmpty == false else {
            return base
        }
        return "\(base) \(metadata)"
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\\n")
    }
}
