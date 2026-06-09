//
//  AppIntents.swift
//  dBrowser
//
//  NARROW App Intents surface — deliberately exposes ONLY saved Copilot
//  workflows and research ledgers (the two agent-trigger surfaces).
//
//  Strategy guardrail: dBrowser competes with the platform on agentic browsing,
//  so we do NOT expose browsing history, bookmarks, wallet, chain state, or
//  conversations to Spotlight/Siri — feeding those to the OS would surrender the
//  surface we are trying to own. Keep that restraint; do not add entities here
//  for those domains.
//

import AppIntents
import Foundation

// MARK: - Off-main store readers
//
// The stores' instance load() is main-actor isolated, but App Intent queries run
// off the main actor. Read the persisted JSON directly via the stores' nonisolated
// default file URLs.

nonisolated private func loadWorkflowsFromDisk() -> [SavedCopilotWorkflow] {
    guard let url = CopilotWorkflowStore.defaultFileURL(),
          let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([SavedCopilotWorkflow].self, from: data)) ?? []
}

nonisolated private func loadLedgersFromDisk() -> [BrowserResearchLedger] {
    guard let url = ResearchLedgerStore.defaultFileURL(),
          let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([BrowserResearchLedger].self, from: data)) ?? []
}

// MARK: - Saved workflow entity

struct SavedWorkflowEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Copilot Workflow" }
    static var defaultQuery: SavedWorkflowQuery { SavedWorkflowQuery() }

    var id: UUID
    @Property(title: "Title") var title: String
    var isEnabled: Bool

    init(workflow: SavedCopilotWorkflow) {
        self.id = workflow.id
        self.isEnabled = workflow.isEnabled
        self.title = workflow.title
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: isEnabled ? "Enabled" : "Disabled")
    }
}

struct SavedWorkflowQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SavedWorkflowEntity] {
        loadWorkflowsFromDisk()
            .filter { identifiers.contains($0.id) }
            .map(SavedWorkflowEntity.init(workflow:))
    }

    func suggestedEntities() async throws -> [SavedWorkflowEntity] {
        loadWorkflowsFromDisk().map(SavedWorkflowEntity.init(workflow:))
    }
}

// MARK: - Research ledger entity

struct ResearchLedgerEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Research Ledger" }
    static var defaultQuery: ResearchLedgerQuery { ResearchLedgerQuery() }

    var id: String // topic
    @Property(title: "Topic") var topic: String
    @Property(title: "Sources") var sourceCount: Int

    init(ledger: BrowserResearchLedger) {
        self.id = ledger.topic
        self.sourceCount = ledger.entries.count
        self.topic = ledger.topic
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(topic)", subtitle: "\(sourceCount) source(s)")
    }
}

struct ResearchLedgerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ResearchLedgerEntity] {
        loadLedgersFromDisk()
            .filter { identifiers.contains($0.topic) }
            .map(ResearchLedgerEntity.init(ledger:))
    }

    func suggestedEntities() async throws -> [ResearchLedgerEntity] {
        loadLedgersFromDisk().map(ResearchLedgerEntity.init(ledger:))
    }
}

// MARK: - Run a saved workflow

struct RunWorkflowIntent: AppIntent {
    static var title: LocalizedStringResource { "Run dBrowser Workflow" }
    static var description: IntentDescription {
        IntentDescription("Run a saved Copilot workflow in dBrowser. Opens the app so the agent run stays observable and human-in-the-loop.")
    }
    // Always foreground the app: the run is never executed silently from a closed
    // app — the user sees the Copilot run UI where actions can be approved.
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Workflow")
    var workflow: SavedWorkflowEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$workflow)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let viewModel = BrowserViewModel.shared else {
            return .result(dialog: "dBrowser is still starting — try again in a moment.")
        }
        guard viewModel.copilotWorkflows.contains(where: { $0.id == workflow.id && $0.isEnabled }) else {
            return .result(dialog: "“\(workflow.title)” is disabled or no longer exists.")
        }
        if viewModel.runWorkflow(workflow.id) != nil {
            return .result(dialog: "Running “\(workflow.title)” in dBrowser.")
        }
        return .result(dialog: "Could not start “\(workflow.title)”.")
    }
}

// MARK: - Export a research ledger

enum ResearchExportFormat: String, AppEnum {
    case markdown
    case csv

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Export Format" }
    static var caseDisplayRepresentations: [ResearchExportFormat: DisplayRepresentation] {
        [.markdown: "Markdown", .csv: "CSV"]
    }
}

struct ExportResearchLedgerIntent: AppIntent {
    static var title: LocalizedStringResource { "Export dBrowser Research" }
    static var description: IntentDescription {
        IntentDescription("Export a research ledger as Markdown or CSV with dated citations and evidence.")
    }

    @Parameter(title: "Research ledger")
    var ledger: ResearchLedgerEntity

    @Parameter(title: "Format", default: .markdown)
    var format: ResearchExportFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$ledger) as \(\.$format)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let model = loadLedgersFromDisk().first(where: { $0.topic == ledger.id }) else {
            return .result(value: "", dialog: "No research ledger found for “\(ledger.topic)”.")
        }
        let output = format == .markdown ? model.markdownExport : model.csvExport
        return .result(value: output, dialog: "Exported \(model.entries.count) source(s) from “\(model.topic)”.")
    }
}

// MARK: - Shortcuts

struct DBrowserShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunWorkflowIntent(),
            phrases: [
                "Run a workflow in \(.applicationName)",
                "Run my \(.applicationName) agent"
            ],
            shortTitle: "Run Workflow",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: ExportResearchLedgerIntent(),
            phrases: [
                "Export research from \(.applicationName)"
            ],
            shortTitle: "Export Research",
            systemImageName: "square.and.arrow.up"
        )
    }
}
