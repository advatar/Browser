import Foundation

public enum BrowserDeveloperWorkflowKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case failedCITriage
    case prEvidencePacket
    case featureFlagAudit
    case debugHistoryContext
    case stagingQAScreenshots
    case teamSkillRun
    case monitoringWatch
    case browserConsoleInvestigation
    case animationReferenceCapture
    case recurringRoutine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .failedCITriage: "Failed CI triage"
        case .prEvidencePacket: "PR evidence packet"
        case .featureFlagAudit: "Feature flag audit"
        case .debugHistoryContext: "Debug history context"
        case .stagingQAScreenshots: "Staging QA screenshots"
        case .teamSkillRun: "Team skill run"
        case .monitoringWatch: "Monitoring watch"
        case .browserConsoleInvestigation: "Browser console investigation"
        case .animationReferenceCapture: "Animation reference capture"
        case .recurringRoutine: "Recurring routine"
        }
    }

    public var defaultEvidenceKinds: [BrowserDeveloperEvidenceKind] {
        switch self {
        case .failedCITriage:
            return [.sourceURL, .logLink, .timestampedNote, .draftComment]
        case .prEvidencePacket:
            return [.sourceURL, .logLink, .screenshot, .dashboardSignal, .timestampedNote, .draftComment]
        case .featureFlagAudit:
            return [.sourceURL, .screenshot, .dashboardSignal, .timestampedNote]
        case .debugHistoryContext:
            return [.sourceURL, .pageSnapshot, .timestampedNote]
        case .stagingQAScreenshots:
            return [.sourceURL, .screenshot, .pageSnapshot, .timestampedNote]
        case .teamSkillRun:
            return [.sourceURL, .pageSnapshot, .domSnapshot, .timestampedNote]
        case .monitoringWatch:
            return [.sourceURL, .screenshot, .dashboardSignal, .logLink, .timestampedNote]
        case .browserConsoleInvestigation:
            return [.sourceURL, .screenshot, .consoleFinding, .downloadedArtifact, .timestampedNote]
        case .animationReferenceCapture:
            return [.sourceURL, .screenshot, .animationFrame, .domSnapshot, .timestampedNote]
        case .recurringRoutine:
            return [.sourceURL, .screenshot, .routineSignal, .dashboardSignal, .timestampedNote]
        }
    }

    public var protectedActions: [BrowserDeveloperProtectedAction] {
        switch self {
        case .failedCITriage:
            return [.postPRComment]
        case .prEvidencePacket:
            return [.postPRComment, .deployRollback]
        case .featureFlagAudit:
            return [.changeFeatureFlag]
        case .debugHistoryContext:
            return []
        case .stagingQAScreenshots:
            return [.postPRComment, .download]
        case .teamSkillRun:
            return [.editAdminConsole, .credentialUse]
        case .monitoringWatch:
            return [.pageIncident, .deployRollback]
        case .browserConsoleInvestigation:
            return [.editAdminConsole, .databaseChange, .billingChange, .download]
        case .animationReferenceCapture:
            return []
        case .recurringRoutine:
            return [.postPRComment, .changeFeatureFlag, .pageIncident, .deployRollback]
        }
    }
}

public enum BrowserDeveloperEvidenceKind: String, CaseIterable, Codable, Equatable {
    case screenshot
    case pageSnapshot
    case domSnapshot
    case logLink
    case downloadedArtifact
    case sourceURL
    case timestampedNote
    case draftComment
    case dashboardSignal
    case consoleFinding
    case animationFrame
    case routineSignal

    public var title: String {
        switch self {
        case .screenshot: "Screenshot"
        case .pageSnapshot: "Page snapshot"
        case .domSnapshot: "DOM snapshot"
        case .logLink: "Log link"
        case .downloadedArtifact: "Downloaded artifact"
        case .sourceURL: "Source URL"
        case .timestampedNote: "Timestamped note"
        case .draftComment: "Draft comment"
        case .dashboardSignal: "Dashboard signal"
        case .consoleFinding: "Console finding"
        case .animationFrame: "Animation frame"
        case .routineSignal: "Routine signal"
        }
    }
}

public enum BrowserDeveloperEvidenceRedactionState: String, Codable, Equatable {
    case none
    case redacted
    case sensitiveOmitted
    case traceMinimized
}

public enum BrowserDeveloperEvidencePrivacyBoundary: String, Codable, Equatable {
    case localOnly
    case privateBrowserContext
    case redactedModelContext
    case externalReferenceOnly
    case userApprovedExport

    public var title: String {
        switch self {
        case .localOnly: "Local only"
        case .privateBrowserContext: "Private browser context"
        case .redactedModelContext: "Redacted model context"
        case .externalReferenceOnly: "External reference only"
        case .userApprovedExport: "User-approved export"
        }
    }
}

public struct BrowserDeveloperEvidenceItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var kind: BrowserDeveloperEvidenceKind
    public var title: String
    public var capturedAt: Date
    public var summary: String
    public var sourceURLString: String?
    public var localFilePath: String?
    public var externalURLString: String?
    public var redactionState: BrowserDeveloperEvidenceRedactionState
    public var privacyBoundary: BrowserDeveloperEvidencePrivacyBoundary
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        kind: BrowserDeveloperEvidenceKind,
        title: String,
        capturedAt: Date = Date(),
        summary: String,
        sourceURLString: String? = nil,
        localFilePath: String? = nil,
        externalURLString: String? = nil,
        redactionState: BrowserDeveloperEvidenceRedactionState = .none,
        privacyBoundary: BrowserDeveloperEvidencePrivacyBoundary = .localOnly,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.capturedAt = capturedAt
        self.summary = summary
        self.sourceURLString = sourceURLString
        self.localFilePath = localFilePath
        self.externalURLString = externalURLString
        self.redactionState = redactionState
        self.privacyBoundary = privacyBoundary
        self.metadata = metadata
    }
}

public enum BrowserDeveloperProtectedAction: String, CaseIterable, Codable, Equatable, Hashable {
    case postPRComment
    case changeFeatureFlag
    case editAdminConsole
    case pageIncident
    case deployRollback
    case billingChange
    case databaseChange
    case download
    case credentialUse
    case walletPayment

    public var title: String {
        switch self {
        case .postPRComment: "Post PR comment"
        case .changeFeatureFlag: "Change feature flag"
        case .editAdminConsole: "Edit admin console"
        case .pageIncident: "Page incident"
        case .deployRollback: "Deploy or rollback"
        case .billingChange: "Billing change"
        case .databaseChange: "Database change"
        case .download: "Download artifact"
        case .credentialUse: "Use credentials"
        case .walletPayment: "Wallet or payment action"
        }
    }

    public var approvalGate: String {
        switch self {
        case .postPRComment: "Draft locally; require approval before posting."
        case .changeFeatureFlag: "Inspect only; require approval before saving flag changes."
        case .editAdminConsole: "Stage exact edits; require approval before changing admin state."
        case .pageIncident: "Stage incident note; require approval before paging."
        case .deployRollback: "Collect rollout evidence; require approval before deploy or rollback."
        case .billingChange: "Inspect billing state; require approval before billing changes."
        case .databaseChange: "Collect query evidence; require approval before database changes."
        case .download: "Require approval before downloading external artifacts."
        case .credentialUse: "Use platform credential boundaries; never expose secrets to prompts."
        case .walletPayment: "Route through wallet/payment policy and receipt review."
        }
    }
}

public enum BrowserDeveloperActionDisposition: String, Codable, Equatable {
    case localEvidenceOnly
    case draftOnly
    case requiresApproval
}

public struct BrowserDeveloperApprovalDecision: Codable, Equatable, Identifiable {
    public let id: String
    public var action: BrowserDeveloperProtectedAction
    public var disposition: BrowserDeveloperActionDisposition
    public var reason: String

    public init(action: BrowserDeveloperProtectedAction) {
        self.id = action.rawValue
        self.action = action
        self.disposition = .requiresApproval
        self.reason = action.approvalGate
    }
}

public enum BrowserDeveloperApprovalPolicy {
    public static func decisions(for actions: [BrowserDeveloperProtectedAction]) -> [BrowserDeveloperApprovalDecision] {
        Array(Set(actions))
            .sorted { $0.rawValue < $1.rawValue }
            .map(BrowserDeveloperApprovalDecision.init(action:))
    }

    public static func requiresApproval(for actions: [BrowserDeveloperProtectedAction]) -> Bool {
        !decisions(for: actions).isEmpty
    }
}

public enum BrowserDeveloperWorkflowStatus: String, Codable, Equatable {
    case draft
    case running
    case waitingForApproval
    case completed
    case blocked
}

public enum BrowserDeveloperWorkflowEntryPoint: String, Codable, Equatable, CaseIterable {
    case copilot
    case mcp
    case localREPL
    case routine

    public var title: String {
        switch self {
        case .copilot: "Copilot"
        case .mcp: "MCP"
        case .localREPL: "Local REPL"
        case .routine: "Routine"
        }
    }
}

public enum BrowserDeveloperAutomationSurfaceStatus: String, Codable, Equatable {
    case ready
    case staged

    public var title: String {
        switch self {
        case .ready: "Ready"
        case .staged: "Staged"
        }
    }
}

public struct BrowserDeveloperAutomationSurface: Codable, Equatable, Identifiable {
    public let id: BrowserDeveloperWorkflowEntryPoint
    public var status: BrowserDeveloperAutomationSurfaceStatus
    public var invocation: String
    public var privacyBoundary: BrowserDeveloperEvidencePrivacyBoundary

    public init(
        id: BrowserDeveloperWorkflowEntryPoint,
        status: BrowserDeveloperAutomationSurfaceStatus,
        invocation: String,
        privacyBoundary: BrowserDeveloperEvidencePrivacyBoundary
    ) {
        self.id = id
        self.status = status
        self.invocation = invocation
        self.privacyBoundary = privacyBoundary
    }

    public static func localFirstSurfaces(browserAutomationKitPackaged: Bool = true) -> [BrowserDeveloperAutomationSurface] {
        [
            BrowserDeveloperAutomationSurface(
                id: .copilot,
                status: .ready,
                invocation: "Start from the Copilot developer workflow template list.",
                privacyBoundary: .redactedModelContext
            ),
            BrowserDeveloperAutomationSurface(
                id: .mcp,
                status: browserAutomationKitPackaged ? .ready : .staged,
                invocation: "Run `browser-automation-kit serve-mcp --stdio` for local MCP clients.",
                privacyBoundary: .privateBrowserContext
            ),
            BrowserDeveloperAutomationSurface(
                id: .localREPL,
                status: browserAutomationKitPackaged ? .ready : .staged,
                invocation: "Run `browser-automation-kit list-surfaces`, then inspect templates and runs in the local ledger.",
                privacyBoundary: .localOnly
            ),
            BrowserDeveloperAutomationSurface(
                id: .routine,
                status: .ready,
                invocation: "Schedule local evidence checks with cooldowns and wake conditions.",
                privacyBoundary: .localOnly
            )
        ]
    }
}

public struct BrowserDeveloperWorkflowTemplate: Codable, Equatable, Identifiable {
    public let id: String
    public var kind: BrowserDeveloperWorkflowKind
    public var title: String
    public var prompt: String
    public var localFirstInstructions: [String]
    public var defaultEvidenceKinds: [BrowserDeveloperEvidenceKind]
    public var protectedActions: [BrowserDeveloperProtectedAction]
    public var entryPoints: [BrowserDeveloperWorkflowEntryPoint]

    public init(
        id: String,
        kind: BrowserDeveloperWorkflowKind,
        title: String? = nil,
        prompt: String,
        localFirstInstructions: [String] = Self.defaultLocalFirstInstructions,
        defaultEvidenceKinds: [BrowserDeveloperEvidenceKind]? = nil,
        protectedActions: [BrowserDeveloperProtectedAction]? = nil,
        entryPoints: [BrowserDeveloperWorkflowEntryPoint] = [.copilot, .mcp, .localREPL]
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.prompt = prompt
        self.localFirstInstructions = localFirstInstructions
        self.defaultEvidenceKinds = defaultEvidenceKinds ?? kind.defaultEvidenceKinds
        self.protectedActions = protectedActions ?? kind.protectedActions
        self.entryPoints = entryPoints
    }

    public func renderedPrompt(activeURLString: String? = nil, snapshotSummary: String? = nil) -> String {
        var lines = [
            title,
            "",
            prompt,
            "",
            "Local-first constraints:"
        ]
        lines.append(contentsOf: localFirstInstructions.map { "- \($0)" })
        lines.append("")
        lines.append("Expected evidence: \(defaultEvidenceKinds.map(\.title).joined(separator: ", ")).")
        if protectedActions.isEmpty {
            lines.append("External mutations: none requested.")
        } else {
            lines.append("External mutations are blocked unless explicitly approved: \(protectedActions.map(\.title).joined(separator: ", ")).")
        }
        if let activeURLString {
            lines.append("Active source: \(activeURLString)")
        }
        if let snapshotSummary {
            lines.append("Snapshot already available: \(snapshotSummary)")
        }
        lines.append("Return a reviewable local evidence packet and draft next steps. Do not post, save settings, page, deploy, roll back, spend, sign, or disclose credentials.")
        return lines.joined(separator: "\n")
    }

    public static let defaultLocalFirstInstructions = [
        "Store evidence locally; use links and local file references instead of uploading private content.",
        "Use bounded page snapshots and redaction labels for browser context.",
        "Draft comments, settings changes, incident notes, and commands without applying them.",
        "Ask for explicit approval before any external mutation or sensitive disclosure."
    ]

    public static let localFirstDefaults: [BrowserDeveloperWorkflowTemplate] = [
        BrowserDeveloperWorkflowTemplate(
            id: "failed-ci-triage",
            kind: .failedCITriage,
            prompt: "Open the failed CI run or current active page, identify the failing job, compare it with the last passing run when available, and draft a short diagnosis with log links."
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "pr-evidence-packet",
            kind: .prEvidencePacket,
            prompt: "Build a PR evidence packet with linked issue, checks, preview, rollout state, known risks, screenshots, and reviewer decisions."
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "feature-flag-audit",
            kind: .featureFlagAudit,
            prompt: "Compare the current feature-flag dashboard state with the rollout plan and stage any mismatches without changing flags."
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "debug-history-context",
            kind: .debugHistoryContext,
            prompt: "Search local browsing context for the page or docs section used during a prior debugging task, then reopen and cite the relevant section."
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "staging-qa-screenshots",
            kind: .stagingQAScreenshots,
            prompt: "Run the staging flow at desktop and mobile widths, capture screenshot references, and write a compact QA checklist."
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "team-skill-run",
            kind: .teamSkillRun,
            prompt: "Follow the selected team browser procedure, capture the required evidence, and stop before filing tickets or changing external systems."
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "monitoring-watch",
            kind: .monitoringWatch,
            prompt: "Watch the monitoring page for the stated threshold, then collect dashboard, log, trace, blast-radius, and incident-note evidence if the signal changes.",
            entryPoints: [.copilot, .mcp, .localREPL, .routine]
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "browser-console-investigation",
            kind: .browserConsoleInvestigation,
            prompt: "Inspect the private product console or admin page, compare current settings to docs, capture screenshots or exported logs, and stage exact changes only."
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "animation-reference-capture",
            kind: .animationReferenceCapture,
            prompt: "Inspect the interaction, capture before/during/after visual references, record computed motion values, and write implementation notes without copying site code."
        ),
        BrowserDeveloperWorkflowTemplate(
            id: "recurring-routine",
            kind: .recurringRoutine,
            prompt: "Turn the repeated browser check into a routine with threshold, cooldown, wake condition, local evidence packet, and approval-preserving next steps.",
            entryPoints: [.copilot, .mcp, .localREPL, .routine]
        )
    ]
}

public struct BrowserDeveloperWorkflowRun: Codable, Equatable, Identifiable {
    public let id: UUID
    public var kind: BrowserDeveloperWorkflowKind
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var status: BrowserDeveloperWorkflowStatus
    public var entryPoint: BrowserDeveloperWorkflowEntryPoint
    public var prompt: String
    public var sourceURLString: String?
    public var evidenceItems: [BrowserDeveloperEvidenceItem]
    public var protectedActions: [BrowserDeveloperProtectedAction]
    public var approvalDecisions: [BrowserDeveloperApprovalDecision]
    public var localOutput: String?
    public var copilotRunID: UUID?

    public init(
        id: UUID = UUID(),
        kind: BrowserDeveloperWorkflowKind,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: BrowserDeveloperWorkflowStatus = .draft,
        entryPoint: BrowserDeveloperWorkflowEntryPoint,
        prompt: String,
        sourceURLString: String? = nil,
        evidenceItems: [BrowserDeveloperEvidenceItem] = [],
        protectedActions: [BrowserDeveloperProtectedAction],
        approvalDecisions: [BrowserDeveloperApprovalDecision]? = nil,
        localOutput: String? = nil,
        copilotRunID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.entryPoint = entryPoint
        self.prompt = prompt
        self.sourceURLString = sourceURLString
        self.evidenceItems = evidenceItems
        self.protectedActions = protectedActions
        self.approvalDecisions = approvalDecisions ?? BrowserDeveloperApprovalPolicy.decisions(for: protectedActions)
        self.localOutput = localOutput
        self.copilotRunID = copilotRunID
    }

    public var requiresApprovalBeforeMutation: Bool {
        BrowserDeveloperApprovalPolicy.requiresApproval(for: protectedActions)
    }

    public var reviewSummary: String {
        let approvalText = requiresApprovalBeforeMutation
            ? "\(approvalDecisions.count) protected action\(approvalDecisions.count == 1 ? "" : "s") gated"
            : "local evidence only"
        return "\(evidenceItems.count) evidence item\(evidenceItems.count == 1 ? "" : "s"), \(approvalText)"
    }

    public mutating func appendEvidence(_ item: BrowserDeveloperEvidenceItem, now: Date = Date()) {
        evidenceItems.append(item)
        updatedAt = now
    }

    public static func draft(
        from template: BrowserDeveloperWorkflowTemplate,
        activeURLString: String? = nil,
        snapshotSummary: String? = nil,
        entryPoint: BrowserDeveloperWorkflowEntryPoint = .mcp,
        now: Date = Date()
    ) -> BrowserDeveloperWorkflowRun {
        var evidence: [BrowserDeveloperEvidenceItem] = []
        if let activeURLString {
            evidence.append(
                BrowserDeveloperEvidenceItem(
                    kind: .sourceURL,
                    title: "Active source",
                    capturedAt: now,
                    summary: activeURLString,
                    sourceURLString: activeURLString,
                    redactionState: .none,
                    privacyBoundary: .privateBrowserContext
                )
            )
        }
        if let snapshotSummary {
            evidence.append(
                BrowserDeveloperEvidenceItem(
                    kind: .pageSnapshot,
                    title: "Bounded page snapshot",
                    capturedAt: now,
                    summary: snapshotSummary,
                    sourceURLString: activeURLString,
                    redactionState: .redacted,
                    privacyBoundary: .redactedModelContext
                )
            )
        }
        return BrowserDeveloperWorkflowRun(
            kind: template.kind,
            title: template.title,
            createdAt: now,
            updatedAt: now,
            status: .draft,
            entryPoint: entryPoint,
            prompt: template.renderedPrompt(activeURLString: activeURLString, snapshotSummary: snapshotSummary),
            sourceURLString: activeURLString,
            evidenceItems: evidence,
            protectedActions: template.protectedActions
        )
    }
}
