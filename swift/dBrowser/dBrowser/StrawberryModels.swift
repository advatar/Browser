import Foundation

struct BrowserAutomationRequest: Equatable, Identifiable {
    let id: UUID
    let tabID: UUID
    var command: BrowserAutomationCommand
    var createdAt: Date
    var timeoutSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        tabID: UUID,
        command: BrowserAutomationCommand,
        createdAt: Date = Date(),
        timeoutSeconds: TimeInterval = 3
    ) {
        self.id = id
        self.tabID = tabID
        self.command = command
        self.createdAt = createdAt
        self.timeoutSeconds = timeoutSeconds
    }
}

enum BrowserAutomationCommand: Equatable {
    case domQuery(DOMQueryRequest)
    case pageSnapshot(PageSnapshotRequest)
    case action(BrowserDOMAction)
}

struct DOMQueryRequest: Codable, Equatable {
    var selector: String
    var limit: Int
    var includeHidden: Bool

    nonisolated init(selector: String = "body *", limit: Int = 40, includeHidden: Bool = false) {
        self.selector = selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "body *" : selector
        self.limit = Self.normalizedLimit(limit)
        self.includeHidden = includeHidden
    }

    nonisolated static func normalizedLimit(_ limit: Int) -> Int {
        min(max(limit, 1), 100)
    }
}

struct DOMElementRecord: Codable, Equatable, Identifiable {
    var index: Int
    var tagName: String
    var role: String?
    var ariaLabel: String?
    var text: String?
    var value: String?
    var href: String?
    var inputType: String?
    var name: String?
    var placeholder: String?
    var disabled: Bool
    var hidden: Bool

    var id: String { "\(index)-\(tagName)" }

    var searchableText: String {
        [
            tagName,
            role,
            ariaLabel,
            text,
            value,
            href,
            inputType,
            name,
            placeholder
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }
}

struct DOMQueryResult: Codable, Equatable {
    var selector: String
    var elements: [DOMElementRecord]
    var totalMatched: Int
    var truncated: Bool
}

struct PageSnapshotRequest: Codable, Equatable {
    var maxTextCharacters: Int
    var maxElements: Int
    var includeMetadata: Bool

    nonisolated init(maxTextCharacters: Int = 4_000, maxElements: Int = 30, includeMetadata: Bool = true) {
        self.maxTextCharacters = min(max(maxTextCharacters, 200), 20_000)
        self.maxElements = min(max(maxElements, 1), 100)
        self.includeMetadata = includeMetadata
    }
}

struct PageSnapshot: Codable, Equatable {
    var urlString: String
    var title: String
    var visibleText: String
    var headings: [String]
    var links: [DOMElementRecord]
    var buttons: [DOMElementRecord]
    var formControls: [DOMElementRecord]
    var metadata: [String: String]
    var truncated: Bool
    var redactionCount: Int

    var modelContextSummary: String {
        let pieces = [
            title,
            urlString,
            visibleText,
            headings.joined(separator: " ")
        ]
        return pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct BrowserDOMAction: Codable, Equatable {
    enum Kind: String, Codable, Equatable, CaseIterable {
        case click
        case typeText
        case submit
        case scroll
        case focus
        case navigate
        case waitForSelector
        case stop
    }

    var kind: Kind
    var selector: String?
    var elementIndex: Int?
    var text: String?
    var clearExistingText: Bool
    var x: Double?
    var y: Double?
    var urlString: String?

    init(
        kind: Kind,
        selector: String? = nil,
        elementIndex: Int? = nil,
        text: String? = nil,
        clearExistingText: Bool = true,
        x: Double? = nil,
        y: Double? = nil,
        urlString: String? = nil
    ) {
        self.kind = kind
        self.selector = selector
        self.elementIndex = elementIndex
        self.text = text
        self.clearExistingText = clearExistingText
        self.x = x
        self.y = y
        self.urlString = urlString
    }
}

struct BrowserActionResult: Codable, Equatable {
    var actionKind: BrowserDOMAction.Kind
    var success: Bool
    var message: String
    var urlString: String?
    var title: String?
    var affectedElement: DOMElementRecord?
}

enum BrowserAutomationStatus: String, Codable, Equatable {
    case success
    case needsApproval
    case failed
    case timedOut
    case ignored
}

enum BrowserAutomationApprovalReason: String, Codable, Equatable, Hashable, CaseIterable {
    case formSubmit
    case credentialField
    case crossOriginNavigation
    case destructiveClick
    case download
    case walletOrSigning
    case externalNavigation
}

struct BrowserAutomationApproval: Codable, Equatable {
    var reasons: [BrowserAutomationApprovalReason]
    var summary: String
}

struct BrowserAutomationResult: Equatable, Identifiable {
    let id: UUID
    var requestID: UUID
    var tabID: UUID
    var status: BrowserAutomationStatus
    var message: String
    var domQuery: DOMQueryResult?
    var pageSnapshot: PageSnapshot?
    var actionResult: BrowserActionResult?
    var approval: BrowserAutomationApproval?

    init(
        id: UUID = UUID(),
        requestID: UUID,
        tabID: UUID,
        status: BrowserAutomationStatus,
        message: String,
        domQuery: DOMQueryResult? = nil,
        pageSnapshot: PageSnapshot? = nil,
        actionResult: BrowserActionResult? = nil,
        approval: BrowserAutomationApproval? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.tabID = tabID
        self.status = status
        self.message = message
        self.domQuery = domQuery
        self.pageSnapshot = pageSnapshot
        self.actionResult = actionResult
        self.approval = approval
    }
}

enum BrowserAutomationApprovalPolicy {
    static func evaluate(
        action: BrowserDOMAction,
        currentURLString: String?,
        target: DOMElementRecord? = nil
    ) -> BrowserAutomationApproval? {
        var reasons: [BrowserAutomationApprovalReason] = []

        switch action.kind {
        case .submit:
            reasons.append(.formSubmit)
        case .navigate:
            appendNavigationReasons(action.urlString, currentURLString: currentURLString, to: &reasons)
        case .click:
            appendClickReasons(action: action, target: target, to: &reasons)
        case .typeText:
            appendCredentialReasons(action: action, target: target, to: &reasons)
        case .focus, .scroll, .waitForSelector, .stop:
            break
        }

        let uniqueReasons = Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
        guard !uniqueReasons.isEmpty else { return nil }
        return BrowserAutomationApproval(
            reasons: uniqueReasons,
            summary: "Automation requires approval for \(uniqueReasons.map(\.rawValue).joined(separator: ", "))."
        )
    }

    private static func appendNavigationReasons(
        _ urlString: String?,
        currentURLString: String?,
        to reasons: inout [BrowserAutomationApprovalReason]
    ) {
        guard let urlString, let nextURL = URL(string: urlString) else {
            reasons.append(.externalNavigation)
            return
        }

        let scheme = nextURL.scheme?.lowercased()
        if scheme != "http" && scheme != "https" {
            reasons.append(.externalNavigation)
        }

        guard
            let currentURLString,
            let currentURL = URL(string: currentURLString),
            let nextHost = nextURL.host?.lowercased(),
            let currentHost = currentURL.host?.lowercased()
        else {
            return
        }

        if nextHost != currentHost {
            reasons.append(.crossOriginNavigation)
        }
    }

    private static func appendClickReasons(
        action: BrowserDOMAction,
        target: DOMElementRecord?,
        to reasons: inout [BrowserAutomationApprovalReason]
    ) {
        let searchable = [
            action.selector?.lowercased(),
            target?.searchableText
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        for destructiveTerm in ["delete", "remove", "destroy", "reset", "confirm", "purchase", "buy", "pay"] where searchable.contains(destructiveTerm) {
            reasons.append(.destructiveClick)
            break
        }

        for signerTerm in ["wallet", "sign", "signature", "seed", "private key", "approve spend"] where searchable.contains(signerTerm) {
            reasons.append(.walletOrSigning)
            break
        }

        if searchable.contains("download") {
            reasons.append(.download)
        }
    }

    private static func appendCredentialReasons(
        action: BrowserDOMAction,
        target: DOMElementRecord?,
        to reasons: inout [BrowserAutomationApprovalReason]
    ) {
        let searchable = [
            action.selector?.lowercased(),
            target?.searchableText
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        for credentialTerm in ["password", "passcode", "secret", "token", "seed", "private", "credential"] where searchable.contains(credentialTerm) {
            reasons.append(.credentialField)
            return
        }
    }
}

enum CopilotRunStatus: String, Codable, Equatable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

enum CopilotRunEventKind: String, Codable, Equatable {
    case queued
    case pageSnapshotRequested
    case memoryAccessStarted
    case memoryAccessCompleted
    case memoryAccessDenied
    case memoryStepUpRequired
    case memoryUnavailable
    case afMarketInstallCompleted
    case afMarketDispatchCompleted
    case afMarketAttestationRecorded
    case afMarketSettlementRecorded
    case modelStarted
    case modelCompleted
    case actionRequested
    case approvalRequired
    case cancelled
    case failed
}

struct CopilotRunEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: CopilotRunEventKind
    var message: String
    var timestamp: Date

    init(id: UUID = UUID(), kind: CopilotRunEventKind, message: String, timestamp: Date = Date()) {
        self.id = id
        self.kind = kind
        self.message = message
        self.timestamp = timestamp
    }
}

struct CopilotCreditUsage: Codable, Equatable {
    var provider: String
    var promptTokens: Int
    var outputTokens: Int
    var isEstimated: Bool
    var creditsSpent: Decimal
    var billingSource: String

    static let zeroBrowserOperation = CopilotCreditUsage(
        provider: "browser",
        promptTokens: 0,
        outputTokens: 0,
        isEstimated: false,
        creditsSpent: Decimal.zero,
        billingSource: "native browsing is free"
    )

    static func estimate(prompt: String, snapshot: PageSnapshot?, provider: String = "local") -> CopilotCreditUsage {
        let promptCharacters = prompt.count + (snapshot?.modelContextSummary.count ?? 0)
        let promptTokens = max(1, promptCharacters / 4)
        let outputTokens = max(64, min(512, promptTokens / 3))
        let tokenCost = Decimal(promptTokens + outputTokens) / Decimal(1_000)
        return CopilotCreditUsage(
            provider: provider,
            promptTokens: promptTokens,
            outputTokens: outputTokens,
            isEstimated: true,
            creditsSpent: tokenCost,
            billingSource: provider == "afm" ? "AFM pipelines estimate" : "local estimator"
        )
    }
}

struct CopilotRun: Identifiable, Equatable {
    let id: UUID
    var prompt: String
    var activeTabID: UUID
    var targetURLString: String?
    var status: CopilotRunStatus
    var startedAt: Date
    var finishedAt: Date?
    var events: [CopilotRunEvent]
    var approvals: [BrowserAutomationApproval]
    var result: CopilotRunResult?
    var usage: CopilotCreditUsage?

    init(
        id: UUID = UUID(),
        prompt: String,
        activeTabID: UUID,
        targetURLString: String?,
        status: CopilotRunStatus = .queued,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        events: [CopilotRunEvent] = [],
        approvals: [BrowserAutomationApproval] = [],
        result: CopilotRunResult? = nil,
        usage: CopilotCreditUsage? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.activeTabID = activeTabID
        self.targetURLString = targetURLString
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.events = events
        self.approvals = approvals
        self.result = result
        self.usage = usage
    }
}

struct CopilotWorkflowSchedule: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case manual
        case everyLaunch
        case intervalHours
    }

    var kind: Kind
    var intervalHours: Int?

    nonisolated static let manual = CopilotWorkflowSchedule(kind: .manual)
    nonisolated static let everyLaunch = CopilotWorkflowSchedule(kind: .everyLaunch)

    nonisolated static func interval(hours: Int) -> CopilotWorkflowSchedule {
        CopilotWorkflowSchedule(kind: .intervalHours, intervalHours: max(1, hours))
    }
}

struct SavedCopilotWorkflow: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var promptTemplate: String
    var targetURLPattern: String?
    var allowedActions: [BrowserDOMAction.Kind]
    var schedule: CopilotWorkflowSchedule
    var lastRunAt: Date?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        promptTemplate: String,
        targetURLPattern: String? = nil,
        allowedActions: [BrowserDOMAction.Kind] = [],
        schedule: CopilotWorkflowSchedule = .manual,
        lastRunAt: Date? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.promptTemplate = promptTemplate
        self.targetURLPattern = targetURLPattern
        self.allowedActions = allowedActions
        self.schedule = schedule
        self.lastRunAt = lastRunAt
        self.isEnabled = isEnabled
    }
}

struct SmartHistoryRecallResult: Identifiable, Equatable {
    var entry: BrowserHistoryEntry
    var score: Int
    var matchedText: String

    var id: UUID { entry.id }
}

enum SmartHistoryIndexer {
    static func summary(title: String, urlString: String, snapshot: PageSnapshot? = nil) -> String {
        if let snapshot {
            return boundedText(snapshot.modelContextSummary, limit: 500)
        }

        let host = URL(string: urlString)?.host ?? urlString
        let path = URL(string: urlString)?.path
            .split(separator: "/")
            .joined(separator: " ") ?? ""
        return boundedText([title, host, path].filter { !$0.isEmpty }.joined(separator: " "), limit: 500)
    }

    static func boundedText(_ text: String, limit: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit))
    }
}

final class CopilotWorkflowStore {
    private let fileURL: URL?
    private var memoryWorkflows: [SavedCopilotWorkflow]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    nonisolated init(fileURL: URL? = CopilotWorkflowStore.defaultFileURL(), seed: [SavedCopilotWorkflow] = []) {
        self.fileURL = fileURL
        self.memoryWorkflows = seed
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    nonisolated static func ephemeral(seed: [SavedCopilotWorkflow] = []) -> CopilotWorkflowStore {
        CopilotWorkflowStore(fileURL: nil, seed: seed)
    }

    func load() -> [SavedCopilotWorkflow] {
        guard let fileURL else { return memoryWorkflows }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([SavedCopilotWorkflow].self, from: data)) ?? []
    }

    func save(_ workflows: [SavedCopilotWorkflow]) {
        guard let fileURL else {
            memoryWorkflows = workflows
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(workflows)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save Copilot workflows: \(error.localizedDescription)")
        }
    }

    nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dBrowser", isDirectory: true)
            .appendingPathComponent("copilot-workflows.json")
    }
}

struct SmartHistoryStorePayload: Codable, Equatable {
    var history: [BrowserHistoryEntry]
    var excludedDomains: [String]
}

final class SmartHistoryStore {
    private let fileURL: URL?
    private var memoryPayload: SmartHistoryStorePayload
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    nonisolated init(fileURL: URL? = SmartHistoryStore.defaultFileURL(), seed: SmartHistoryStorePayload = SmartHistoryStorePayload(history: [], excludedDomains: [])) {
        self.fileURL = fileURL
        self.memoryPayload = seed
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    nonisolated static func ephemeral(seed: SmartHistoryStorePayload = SmartHistoryStorePayload(history: [], excludedDomains: [])) -> SmartHistoryStore {
        SmartHistoryStore(fileURL: nil, seed: seed)
    }

    func load() -> SmartHistoryStorePayload {
        guard let fileURL else { return memoryPayload }
        guard let data = try? Data(contentsOf: fileURL) else {
            return SmartHistoryStorePayload(history: [], excludedDomains: [])
        }
        return (try? decoder.decode(SmartHistoryStorePayload.self, from: data)) ?? SmartHistoryStorePayload(history: [], excludedDomains: [])
    }

    func save(_ payload: SmartHistoryStorePayload) {
        guard let fileURL else {
            memoryPayload = payload
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save Smart History: \(error.localizedDescription)")
        }
    }

    nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dBrowser", isDirectory: true)
            .appendingPathComponent("smart-history.json")
    }
}
