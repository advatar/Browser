import Foundation

public enum BrowserAutomationKitError: Error, Equatable, LocalizedError {
    case defaultLedgerUnavailable
    case templateNotFound(String)
    case runNotFound(UUID)
    case unsupportedEntryPoint(String)
    case invalidLocalHost(String)
    case missingArgument(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .defaultLedgerUnavailable:
            return "The local developer workflow ledger path is unavailable."
        case .templateNotFound(let id):
            return "No developer workflow template exists for id '\(id)'."
        case .runNotFound(let id):
            return "No developer workflow run exists for id '\(id.uuidString)'."
        case .unsupportedEntryPoint(let entryPoint):
            return "The selected template does not support entry point '\(entryPoint)'."
        case .invalidLocalHost(let host):
            return "MCP server host '\(host)' is not local. Use localhost, 127.0.0.1, ::1, or stdio."
        case .missingArgument(let name):
            return "Missing required argument: \(name)."
        case .invalidArgument(let value):
            return "Invalid argument: \(value)."
        }
    }
}

public final class DeveloperWorkflowLedgerStore {
    private let fileURL: URL?
    private var memoryRuns: [BrowserDeveloperWorkflowRun]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = DeveloperWorkflowLedgerStore.defaultFileURL(), seed: [BrowserDeveloperWorkflowRun] = []) {
        self.fileURL = fileURL
        self.memoryRuns = seed
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public static func ephemeral(seed: [BrowserDeveloperWorkflowRun] = []) -> DeveloperWorkflowLedgerStore {
        DeveloperWorkflowLedgerStore(fileURL: nil, seed: seed)
    }

    public func load() throws -> [BrowserDeveloperWorkflowRun] {
        guard let fileURL else { return memoryRuns }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([BrowserDeveloperWorkflowRun].self, from: data)
    }

    public func save(_ runs: [BrowserDeveloperWorkflowRun]) throws {
        guard let fileURL else {
            memoryRuns = runs
            return
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(runs)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dBrowser", isDirectory: true)
            .appendingPathComponent("developer-workflow-runs.json")
    }
}
