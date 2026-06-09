//
//  ResearchLedgerStore.swift
//  dBrowser
//
//  Persistence for research ledgers. The BrowserResearchLedger type already
//  existed but was never persisted; this store gives App Intents a stable,
//  on-disk source to read and export from. Mirrors CopilotWorkflowStore.
//

import Foundation

final class ResearchLedgerStore {
    private let fileURL: URL?
    private var memoryLedgers: [BrowserResearchLedger]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    nonisolated init(fileURL: URL? = ResearchLedgerStore.defaultFileURL(), seed: [BrowserResearchLedger] = []) {
        self.fileURL = fileURL
        self.memoryLedgers = seed
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    nonisolated static func ephemeral(seed: [BrowserResearchLedger] = []) -> ResearchLedgerStore {
        ResearchLedgerStore(fileURL: nil, seed: seed)
    }

    func load() -> [BrowserResearchLedger] {
        guard let fileURL else { return memoryLedgers }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([BrowserResearchLedger].self, from: data)) ?? []
    }

    func save(_ ledgers: [BrowserResearchLedger]) {
        guard let fileURL else {
            memoryLedgers = ledgers
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(ledgers)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save research ledgers: \(error.localizedDescription)")
        }
    }

    nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dBrowser", isDirectory: true)
            .appendingPathComponent("research-ledgers.json")
    }
}
