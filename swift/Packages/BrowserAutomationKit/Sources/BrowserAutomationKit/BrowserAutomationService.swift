import Foundation

public struct BrowserDeveloperMutationProposal: Codable, Equatable {
    public var action: BrowserDeveloperProtectedAction
    public var summary: String
    public var blockedEvidence: BrowserDeveloperEvidenceItem

    public init(
        action: BrowserDeveloperProtectedAction,
        summary: String,
        blockedEvidence: BrowserDeveloperEvidenceItem
    ) {
        self.action = action
        self.summary = summary
        self.blockedEvidence = blockedEvidence
    }
}

public final class BrowserAutomationService {
    public let store: DeveloperWorkflowLedgerStore
    public let templates: [BrowserDeveloperWorkflowTemplate]

    public init(
        store: DeveloperWorkflowLedgerStore = DeveloperWorkflowLedgerStore(),
        templates: [BrowserDeveloperWorkflowTemplate] = BrowserDeveloperWorkflowTemplate.localFirstDefaults
    ) {
        self.store = store
        self.templates = templates
    }

    public var automationSurfaces: [BrowserDeveloperAutomationSurface] {
        BrowserDeveloperAutomationSurface.localFirstSurfaces(browserAutomationKitPackaged: true)
    }

    public func listTemplates() -> [BrowserDeveloperWorkflowTemplate] {
        templates
    }

    public func listRuns() throws -> [BrowserDeveloperWorkflowRun] {
        try store.load()
    }

    @discardableResult
    public func startRun(
        templateID: String,
        entryPoint: BrowserDeveloperWorkflowEntryPoint = .mcp,
        sourceURLString: String? = nil,
        snapshotSummary: String? = nil,
        now: Date = Date()
    ) throws -> BrowserDeveloperWorkflowRun {
        guard let template = templates.first(where: { $0.id == templateID }) else {
            throw BrowserAutomationKitError.templateNotFound(templateID)
        }
        guard template.entryPoints.contains(entryPoint) else {
            throw BrowserAutomationKitError.unsupportedEntryPoint(entryPoint.rawValue)
        }

        var run = BrowserDeveloperWorkflowRun.draft(
            from: template,
            activeURLString: sourceURLString,
            snapshotSummary: snapshotSummary,
            entryPoint: entryPoint,
            now: now
        )
        run.status = .running

        var runs = try store.load()
        runs.insert(run, at: 0)
        try store.save(runs)
        return run
    }

    @discardableResult
    public func appendEvidence(
        _ evidence: BrowserDeveloperEvidenceItem,
        to runID: UUID,
        now: Date = Date()
    ) throws -> BrowserDeveloperWorkflowRun {
        var runs = try store.load()
        guard let index = runs.firstIndex(where: { $0.id == runID }) else {
            throw BrowserAutomationKitError.runNotFound(runID)
        }
        runs[index].appendEvidence(evidence, now: now)
        try store.save(runs)
        return runs[index]
    }

    @discardableResult
    public func proposeProtectedMutation(
        runID: UUID,
        action: BrowserDeveloperProtectedAction,
        summary: String,
        now: Date = Date()
    ) throws -> BrowserDeveloperWorkflowRun {
        var runs = try store.load()
        guard let index = runs.firstIndex(where: { $0.id == runID }) else {
            throw BrowserAutomationKitError.runNotFound(runID)
        }

        if !runs[index].protectedActions.contains(action) {
            runs[index].protectedActions.append(action)
        }
        if !runs[index].approvalDecisions.contains(where: { $0.action == action }) {
            runs[index].approvalDecisions.append(BrowserDeveloperApprovalDecision(action: action))
            runs[index].approvalDecisions.sort { $0.id < $1.id }
        }

        let blockedEvidence = BrowserDeveloperEvidenceItem(
            kind: .timestampedNote,
            title: "Blocked protected action: \(action.title)",
            capturedAt: now,
            summary: "\(summary) \(action.approvalGate)",
            redactionState: .sensitiveOmitted,
            privacyBoundary: .localOnly,
            metadata: [
                "blockedAction": action.rawValue,
                "approvalRequired": "true"
            ]
        )

        runs[index].status = .waitingForApproval
        runs[index].appendEvidence(blockedEvidence, now: now)
        try store.save(runs)
        return runs[index]
    }
}
