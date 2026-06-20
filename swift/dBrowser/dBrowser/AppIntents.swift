//
//  AppIntents.swift
//  dBrowser
//
//  NARROW App Intents surface — deliberately exposes ONLY saved Copilot
//  workflows, research ledgers, and fixed foreground destinations.
//
//  Strategy guardrail: dBrowser competes with the platform on agentic browsing,
//  so we do NOT expose browsing history, bookmarks, wallet state, chain state,
//  memory IDs, or conversations to Spotlight/Siri — feeding those to the OS
//  would surrender the surface we are trying to own. Keep that restraint; do
//  not add entities here for those domains.
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

// MARK: - macOS 27 system integration gate

enum DBrowserMacOS27SystemIntegrationGate {
    static let minimumMacOSMajorVersion = 27
    static let availabilityLabel = "macOS 27+"
    static let privacyBoundary = "Fixed foreground destinations and user-supplied prompts only; no history, bookmarks, wallet state, chain state, memory IDs, or conversations."

    static var isRuntimeAvailable: Bool {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            true
        } else {
            false
        }
    }
}

enum DBrowserSystemDestination: String, AppEnum, CaseIterable, Identifiable {
    case browser
    case copilot
    case wallet
    case localLLM
    case runtime
    case hyperactiveWeb
    case mcp

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "dBrowser Destination" }
    static var caseDisplayRepresentations: [DBrowserSystemDestination: DisplayRepresentation] {
        [
            .browser: "Browser",
            .copilot: "Copilot",
            .wallet: "Wallet & Identity",
            .localLLM: "Local LLMs",
            .runtime: "Runtime",
            .hyperactiveWeb: "Hyperactive Web",
            .mcp: "MCP"
        ]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browser: "Browser"
        case .copilot: "Copilot"
        case .wallet: "Wallet & Identity"
        case .localLLM: "Local LLMs"
        case .runtime: "Runtime"
        case .hyperactiveWeb: "Hyperactive Web"
        case .mcp: "MCP"
        }
    }

    var panel: BrowserPanel? {
        switch self {
        case .browser: nil
        case .copilot: .copilot
        case .wallet: .wallet
        case .localLLM: .localLLM
        case .runtime: .runtime
        case .hyperactiveWeb: .hyperactiveWeb
        case .mcp: .mcp
        }
    }
}

enum DBrowserAppIntentHandoff: Equatable {
    case openDestination(DBrowserSystemDestination)
    case startCopilotPrompt(String)
    case runWorkflow(id: UUID, title: String)

    var queuedDialog: String {
        switch self {
        case .openDestination(let destination):
            "Opening \(destination.title) in dBrowser."
        case .startCopilotPrompt:
            "Opening dBrowser and starting Copilot."
        case .runWorkflow(_, let title):
            "Opening dBrowser to run “\(title)”."
        }
    }
}

@MainActor
enum DBrowserAppIntentHandoffCenter {
    private static var pendingHandoffs: [DBrowserAppIntentHandoff] = []

    @discardableResult
    static func routeOrEnqueue(_ handoff: DBrowserAppIntentHandoff) -> String {
        guard let viewModel = BrowserViewModel.shared else {
            pendingHandoffs.append(handoff)
            return handoff.queuedDialog
        }
        return viewModel.handleSystemHandoff(handoff)
    }

    static func drainPendingHandoffs(into viewModel: BrowserViewModel) {
        let handoffs = pendingHandoffs
        pendingHandoffs.removeAll()
        for handoff in handoffs {
            viewModel.handleSystemHandoff(handoff)
        }
    }

    static var pendingHandoffCountForTesting: Int {
        pendingHandoffs.count
    }

    static func resetForTesting() {
        pendingHandoffs.removeAll()
    }
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
        let dialog = DBrowserAppIntentHandoffCenter.routeOrEnqueue(
            .runWorkflow(id: workflow.id, title: workflow.title)
        )
        return .result(dialog: "\(dialog)")
    }
}

// MARK: - macOS 27 Siri and system foreground handoff

@available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
struct OpenDBrowserDestinationIntent: AppIntent {
    static var title: LocalizedStringResource { "Open dBrowser Destination" }
    static var description: IntentDescription {
        IntentDescription("Open a fixed dBrowser destination from Siri, Shortcuts, Spotlight, or Apple Intelligence without exposing private browser data to the system.")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Destination")
    var destination: DBrowserSystemDestination

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$destination)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = DBrowserAppIntentHandoffCenter.routeOrEnqueue(.openDestination(destination))
        return .result(dialog: "\(dialog)")
    }
}

@available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
struct AskDBrowserCopilotIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask dBrowser Copilot" }
    static var description: IntentDescription {
        IntentDescription("Open dBrowser and start a visible Copilot prompt from Siri or system intelligence surfaces.")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Prompt")
    var prompt: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Copilot \(\.$prompt)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return .result(dialog: "Open dBrowser Copilot and enter a prompt.")
        }
        let dialog = DBrowserAppIntentHandoffCenter.routeOrEnqueue(.startCopilotPrompt(trimmedPrompt))
        return .result(dialog: "\(dialog)")
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
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            AppShortcut(
                intent: OpenDBrowserDestinationIntent(),
                phrases: [
                    "Open \(.applicationName)",
                    "Open a destination in \(.applicationName)"
                ],
                shortTitle: "Open dBrowser",
                systemImageName: "rectangle.connected.to.line.below"
            )
            AppShortcut(
                intent: AskDBrowserCopilotIntent(),
                phrases: [
                    "Ask \(.applicationName) Copilot",
                    "Ask \(.applicationName) about this page"
                ],
                shortTitle: "Ask Copilot",
                systemImageName: "sparkles"
            )
        }
    }
}
