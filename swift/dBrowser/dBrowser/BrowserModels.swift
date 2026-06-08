import Foundation

enum BrowserPanelTier: String, Equatable {
    case primary
    case advanced
}

enum BrowserPanel: String, CaseIterable, Hashable, Identifiable {
    case history
    case bookmarks
    case wallet
    case mcp
    case a2ui
    case copilot
    case advantage
    case localLLM
    case runtime

    var id: String { rawValue }

    /// The primary product surfaces shown alongside the web Browser (which is represented by a
    /// nil panel selection): the agent Copilot and the unified Wallet & Identity control plane.
    static let primaryPanels: [BrowserPanel] = [
        .copilot,
        .wallet
    ]

    /// Secondary dashboards and developer tools, demoted beneath the primary surfaces so the
    /// browser does not present nine peer control planes at the same altitude.
    static let advancedPanels: [BrowserPanel] = [
        .history,
        .bookmarks,
        .mcp,
        .a2ui,
        .advantage,
        .localLLM,
        .runtime
    ]

    var tier: BrowserPanelTier {
        BrowserPanel.primaryPanels.contains(self) ? .primary : .advanced
    }

    var title: String {
        switch self {
        case .history: "History"
        case .bookmarks: "Bookmarks"
        case .wallet: "Wallet & Identity"
        case .mcp: "MCP"
        case .a2ui: "A2UI"
        case .copilot: "Copilot"
        case .advantage: "Advantage"
        case .localLLM: "Local LLMs"
        case .runtime: "Runtime"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .bookmarks: "bookmark"
        case .wallet: "wallet.pass"
        case .mcp: "network"
        case .a2ui: "square.grid.2x2"
        case .copilot: "sparkles"
        case .advantage: "chart.line.uptrend.xyaxis"
        case .localLLM: "cpu"
        case .runtime: "server.rack"
        }
    }
}

enum BrowserAdvantageStatus: String, CaseIterable, Identifiable, Equatable {
    case exceeds
    case matches
    case gap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exceeds: "dBrowser leads"
        case .matches: "Parity covered"
        case .gap: "Close next"
        }
    }

    var systemImage: String {
        switch self {
        case .exceeds: "arrow.up.right.circle"
        case .matches: "checkmark.circle"
        case .gap: "wrench.and.screwdriver"
        }
    }
}

enum BrowserAdvantageCategory: String, CaseIterable, Identifiable, Equatable {
    case distribution
    case browserSwitching
    case companionOnboarding
    case pageContext
    case research
    case pageActions
    case workflows
    case integrations
    case safety
    case privacy
    case credits
    case benchmarks
    case localModels
    case governedMemory
    case afMarket
    case a2uiApps
    case decentralizedTrust
    case walletTrust
    case identityPayments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distribution: "Distribution"
        case .browserSwitching: "Browser switching"
        case .companionOnboarding: "Companion onboarding"
        case .pageContext: "Page context"
        case .research: "Research"
        case .pageActions: "Page actions"
        case .workflows: "Workflows"
        case .integrations: "Integrations"
        case .safety: "Safety"
        case .privacy: "Privacy"
        case .credits: "Credits"
        case .benchmarks: "Benchmarks"
        case .localModels: "Local models"
        case .governedMemory: "Governed memory"
        case .afMarket: "AFMarket"
        case .a2uiApps: "A2UI apps"
        case .decentralizedTrust: "DWeb trust"
        case .walletTrust: "Wallet trust"
        case .identityPayments: "Identity payments"
        }
    }

    static let strawberryBaseline: [BrowserAdvantageCategory] = [
        .distribution,
        .browserSwitching,
        .companionOnboarding,
        .pageContext,
        .research,
        .pageActions,
        .workflows,
        .integrations,
        .safety,
        .privacy,
        .credits,
        .benchmarks
    ]
}

struct BrowserAdvantageAction: Equatable, Identifiable {
    let id: String
    var title: String
    var detail: String
    var targetPanel: BrowserPanel?

    init(id: String, title: String, detail: String, targetPanel: BrowserPanel?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.targetPanel = targetPanel
    }
}

struct BrowserAdvantageCapability: Equatable, Identifiable {
    let id: String
    var category: BrowserAdvantageCategory
    var title: String
    var strawberryBaseline: String
    var dBrowserPosition: String
    var status: BrowserAdvantageStatus
    var evidence: [String]
    var action: BrowserAdvantageAction?

    var tracksStrawberryBaseline: Bool {
        BrowserAdvantageCategory.strawberryBaseline.contains(category)
    }
}

struct BrowserAdvantageScorecard: Equatable {
    var capabilities: [BrowserAdvantageCapability]

    var exceededCount: Int {
        count(.exceeds)
    }

    var matchedCount: Int {
        count(.matches)
    }

    var gapCount: Int {
        count(.gap)
    }

    var trackedStrawberryBaselineCategories: Set<BrowserAdvantageCategory> {
        Set(capabilities.filter(\.tracksStrawberryBaseline).map(\.category))
    }

    var baselineCoverageText: String {
        "\(trackedStrawberryBaselineCategories.count)/\(BrowserAdvantageCategory.strawberryBaseline.count) Strawberry areas tracked"
    }

    var leadText: String {
        "\(exceededCount) lead, \(matchedCount) parity, \(gapCount) next"
    }

    func capabilities(with status: BrowserAdvantageStatus) -> [BrowserAdvantageCapability] {
        capabilities.filter { $0.status == status }
    }

    private func count(_ status: BrowserAdvantageStatus) -> Int {
        capabilities.filter { $0.status == status }.count
    }

    static let current = BrowserAdvantageScorecard(
        capabilities: [
            BrowserAdvantageCapability(
                id: "distribution-apple-native",
                category: .distribution,
                title: "Apple-native browser runtime",
                strawberryBaseline: "Strawberry publicly offers macOS and Windows beta builds.",
                dBrowserPosition: "dBrowser is native Swift for Apple platforms with WKWebView, SwiftUI, Keychain-compatible policy surfaces, and iOS/macOS build lanes.",
                status: .matches,
                evidence: ["Native Swift app", "macOS and iOS simulator build targets"],
                action: BrowserAdvantageAction(
                    id: "distribution-windows-decision",
                    title: "Decide Windows shell",
                    detail: "Document whether Windows parity is required or intentionally traded for Apple-native depth.",
                    targetPanel: .runtime
                )
            ),
            BrowserAdvantageCapability(
                id: "browser-switch-import",
                category: .browserSwitching,
                title: "Switcher and import setup",
                strawberryBaseline: "Strawberry advertises import of passwords, bookmarks, and history from major browsers.",
                dBrowserPosition: "dBrowser now has a switcher plan that separates safe bookmark/history import from explicit Keychain-backed password and cookie approval flows.",
                status: .matches,
                evidence: ["BrowserImportPlanner", "BrowserImportPlan", "Native history store", "Native bookmark model"],
                action: BrowserAdvantageAction(
                    id: "browser-import-review",
                    title: "Review import plan",
                    detail: "Use safe bookmark/history import by default and require explicit approval for secrets.",
                    targetPanel: .bookmarks
                )
            ),
            BrowserAdvantageCapability(
                id: "companion-onboarding",
                category: .companionOnboarding,
                title: "Companion setup",
                strawberryBaseline: "Strawberry asks role, connected apps, and recurring work to personalize companions.",
                dBrowserPosition: "dBrowser now maps role, connected tools, recurring work, privacy posture, and model preference into A2UI apps, workflows, memory, MCP, and model choices.",
                status: .exceeds,
                evidence: ["BrowserCompanionOnboardingEngine", "A2UI app catalog", "MCP profiles", "OpenMind memory state", "AFMarket packs"],
                action: BrowserAdvantageAction(
                    id: "advantage-onboarding",
                    title: "Tune companion",
                    detail: "Generate local recommendations for apps, models, memory posture, connectors, and workflows.",
                    targetPanel: .advantage
                )
            ),
            BrowserAdvantageCapability(
                id: "page-context-active-page",
                category: .pageContext,
                title: "Audited page context",
                strawberryBaseline: "Strawberry companions understand page content, page structure, conversation memory, and related tabs.",
                dBrowserPosition: "dBrowser already captures bounded active-page snapshots and DOM records, with redaction and provider-neutral conversation attachments.",
                status: .matches,
                evidence: ["PageSnapshot", "DOMQueryResult", "LLMPageSnapshotAttachment", "OpenMind memory citations"],
                action: BrowserAdvantageAction(
                    id: "multi-tab-context",
                    title: "Add multi-tab ranking",
                    detail: "Rank other open tabs before including them in model context.",
                    targetPanel: .copilot
                )
            ),
            BrowserAdvantageCapability(
                id: "research-source-ledger",
                category: .research,
                title: "Research source ledger",
                strawberryBaseline: "Strawberry claims parallel research, source-linked synthesis, and structured comparisons.",
                dBrowserPosition: "dBrowser now has a dated research source ledger with confidence labels, citation strings, markdown export, and CSV export.",
                status: .matches,
                evidence: ["BrowserResearchLedger", "BrowserResearchSourceEntry", "Copilot runs", "Smart History summaries"],
                action: BrowserAdvantageAction(
                    id: "research-ledger",
                    title: "Open research flow",
                    detail: "Record source URLs, retrieval dates, evidence snippets, confidence, and export artifacts.",
                    targetPanel: .copilot
                )
            ),
            BrowserAdvantageCapability(
                id: "page-actions-typed-bridge",
                category: .pageActions,
                title: "Typed real-page actions",
                strawberryBaseline: "Strawberry advertises clicking, filling, scrolling, navigating, selecting, submitting, and downloading.",
                dBrowserPosition: "dBrowser executes typed click, type, focus, submit, scroll, navigate, wait, and stop commands through audited WKWebView scripts.",
                status: .matches,
                evidence: ["BrowserAutomationCommand", "BrowserDOMAction", "BrowserAutomationApprovalPolicy"],
                action: BrowserAdvantageAction(
                    id: "page-action-coverage",
                    title: "Expand action coverage",
                    detail: "Add select/menu, download, new-tab, upload metadata, and fixture-backed UI tests.",
                    targetPanel: .copilot
                )
            ),
            BrowserAdvantageCapability(
                id: "workflow-recurring-automation",
                category: .workflows,
                title: "Recurring workflow engine",
                strawberryBaseline: "Strawberry saves workflows, reruns them, schedules them, monitors page changes, and notifies users.",
                dBrowserPosition: "dBrowser now has recurring automation plans with schedules, site/page/content triggers, cooldowns, notifications, and approval-preserving policy.",
                status: .matches,
                evidence: ["BrowserRecurringWorkflowAutomation", "BrowserWorkflowAutomationScheduler", "SavedCopilotWorkflow", "CopilotWorkflowStore"],
                action: BrowserAdvantageAction(
                    id: "workflow-scheduler",
                    title: "Review automations",
                    detail: "Run due workflows with cooldowns, notifications, and approval-preserving policies.",
                    targetPanel: .copilot
                )
            ),
            BrowserAdvantageCapability(
                id: "integrations-mcp-a2ui",
                category: .integrations,
                title: "Extensible app and MCP surface",
                strawberryBaseline: "Strawberry integrates apps and MCP servers.",
                dBrowserPosition: "dBrowser supports MCP over HTTP, WebSocket, and stdio, plus installable A2UI apps, AFMarket runner packs, wallet capability contracts, and OpenMind memory.",
                status: .exceeds,
                evidence: ["MCPServerConfiguration", "A2UIAppStoreListing", "AFMPackSummary", "BlockchainCapabilityGrant"],
                action: BrowserAdvantageAction(
                    id: "production-connectors",
                    title: "Harden connectors",
                    detail: "Add built-in OAuth connector profiles, Keychain persistence, revocation, and last-used audit.",
                    targetPanel: .mcp
                )
            ),
            BrowserAdvantageCapability(
                id: "safety-approval-trust",
                category: .safety,
                title: "Approval and trust gates",
                strawberryBaseline: "Strawberry asks approval for protected/permanent actions and lets users stop or take over.",
                dBrowserPosition: "dBrowser gates form submit, credentials, cross-origin navigation, destructive clicks, downloads, and wallet/signing, then cancels runs on tab takeover.",
                status: .exceeds,
                evidence: ["BrowserAutomationApprovalReason", "CopilotRunEvent", "cancelCopilotRuns", "WalletTransactionPolicyReceipt"],
                action: BrowserAdvantageAction(
                    id: "approval-presets",
                    title: "Add presets",
                    detail: "Add scoped allow/ask/deny presets with explanations for recurring workflows.",
                    targetPanel: .copilot
                )
            ),
            BrowserAdvantageCapability(
                id: "privacy-governed-context",
                category: .privacy,
                title: "Governed local context",
                strawberryBaseline: "Strawberry stores chats/passwords/history/cookies locally and Smart History summaries locally when enabled.",
                dBrowserPosition: "dBrowser keeps local stores, redacts page snapshots, attaches only approved OpenMind citations, and records context commitments.",
                status: .exceeds,
                evidence: ["SmartHistoryStore", "OpenMindAccessDecision", "LLMRenderedConversationContext", "snapshotCommitment"],
                action: BrowserAdvantageAction(
                    id: "smart-history-opt-in",
                    title: "Make opt-in explicit",
                    detail: "Expose Smart History modes and run-level data-egress receipts.",
                    targetPanel: .history
                )
            ),
            BrowserAdvantageCapability(
                id: "credits-run-receipts",
                category: .credits,
                title: "Run-level credit visibility",
                strawberryBaseline: "Strawberry regular browsing is free; credits are consumed by companion work.",
                dBrowserPosition: "dBrowser already treats browser operations as zero-cost and records estimated provider/model usage per run.",
                status: .matches,
                evidence: ["CopilotCreditUsage.zeroBrowserOperation", "CopilotCreditUsage.estimate", "LLMConversationMessage.usage"],
                action: BrowserAdvantageAction(
                    id: "exact-usage",
                    title: "Use exact tokens",
                    detail: "Pass through exact provider usage when available and show plan or balance receipts.",
                    targetPanel: .copilot
                )
            ),
            BrowserAdvantageCapability(
                id: "benchmarks-public-runner",
                category: .benchmarks,
                title: "Public benchmark proof",
                strawberryBaseline: "Strawberry publishes a 12-workflow benchmark specification and score claims.",
                dBrowserPosition: "dBrowser now models the 12-workflow benchmark suite, supports credential-constrained 9-task mode, and records score/duration/blocker artifacts.",
                status: .matches,
                evidence: ["StrawberryBenchmarkSuite", "StrawberryBenchmarkReport", "Swift test lane"],
                action: BrowserAdvantageAction(
                    id: "benchmark-runner",
                    title: "Run benchmark lane",
                    detail: "Mirror B1-B12 tasks, score artifacts, blocker metadata, and 9/12 benchmark modes.",
                    targetPanel: .advantage
                )
            ),
            BrowserAdvantageCapability(
                id: "local-first-model-switching",
                category: .localModels,
                title: "Local-first model switching",
                strawberryBaseline: "Strawberry exposes companions; public docs do not describe context-preserving local model switching.",
                dBrowserPosition: "dBrowser preserves a provider-neutral conversation ledger while switching local MLX, LLM Router, AFMarket, and gateway models.",
                status: .exceeds,
                evidence: ["LLMConversation.switchModel", "LLMModelRegistry", "LLMConversationContextRenderer"],
                action: BrowserAdvantageAction(
                    id: "model-mode-ux",
                    title: "Promote run modes",
                    detail: "Add keep-local, fastest-available, and proof-backed mode controls.",
                    targetPanel: .localLLM
                )
            ),
            BrowserAdvantageCapability(
                id: "openmind-governed-memory",
                category: .governedMemory,
                title: "Policy-gated personal memory",
                strawberryBaseline: "Strawberry describes conversation memory and Smart History.",
                dBrowserPosition: "dBrowser uses OpenMind access intents, evidence bundles, step-up grants, writeback approvals, and correction workflows.",
                status: .exceeds,
                evidence: ["OpenMindAccessIntent", "OpenMindEvidenceBundle", "OpenMindStepUpRequest", "OpenMindCorrectionOutcome"],
                action: BrowserAdvantageAction(
                    id: "memory-review-ux",
                    title: "Review memory posture",
                    detail: "Use the runtime memory panel to inspect posture, step-up, review tasks, and correction state.",
                    targetPanel: .runtime
                )
            ),
            BrowserAdvantageCapability(
                id: "afmarket-attested-runs",
                category: .afMarket,
                title: "Attested market execution",
                strawberryBaseline: "Strawberry public docs do not claim proof-backed runner marketplaces or settlement.",
                dBrowserPosition: "dBrowser models runner packs, routing, leases, node install, attested runs, proof state, settlement state, and A2A experts.",
                status: .exceeds,
                evidence: ["AFMRunnerPack", "AFMRouteResult", "AFMAttestedRun", "AFMSettlementState", "AFMA2APeerExpert"],
                action: BrowserAdvantageAction(
                    id: "afmarket-use",
                    title: "Use AFMarket",
                    detail: "Pick a runner pack for Copilot and inspect attestation, proof, and settlement events.",
                    targetPanel: .runtime
                )
            ),
            BrowserAdvantageCapability(
                id: "a2ui-companion-apps",
                category: .a2uiApps,
                title: "Installable native AI app surfaces",
                strawberryBaseline: "Strawberry companions operate inside the browser; public docs do not claim A2UI-native app rendering.",
                dBrowserPosition: "dBrowser installs A2UI apps and renders token streams as native SwiftUI widgets with runtime profiles.",
                status: .exceeds,
                evidence: ["A2UIAppStore", "A2UIRuntimeProfile", "A2UISurfaceView"],
                action: BrowserAdvantageAction(
                    id: "a2ui-templates",
                    title: "Add templates",
                    detail: "Promote sales, recruiting, operations, extraction, research, travel, and shopping templates.",
                    targetPanel: .a2ui
                )
            ),
            BrowserAdvantageCapability(
                id: "dweb-chain-trust",
                category: .decentralizedTrust,
                title: "DWeb and chain verification",
                strawberryBaseline: "Strawberry focuses on web and app work; public docs do not claim decentralized protocol loading or chain trust.",
                dBrowserPosition: "dBrowser tracks decentralized storage adapters and chain-trust states for Bitcoin, EVM, Solana, Cosmos, Substrate, Avalanche, TRON, XRPL, Sui, and Aptos.",
                status: .exceeds,
                evidence: ["DecentralizedStorageNetwork", "ChainTrustRegistry", "BitcoinLightClientSnapshot", "MoveChainServiceSnapshot"],
                action: BrowserAdvantageAction(
                    id: "native-protocol-engines",
                    title: "Bundle engines",
                    detail: "Finish native decentralized protocol engine bundling under #133.",
                    targetPanel: .runtime
                )
            ),
            BrowserAdvantageCapability(
                id: "wallet-policy-trust",
                category: .walletTrust,
                title: "Wallet policies and receipts",
                strawberryBaseline: "Strawberry docs do not claim wallet policy receipts or proof-aware signing flows.",
                dBrowserPosition: "dBrowser exposes embedded wallet creation, chain trust labels, permission receipts, transfer previews, and approval-gated signing.",
                status: .exceeds,
                evidence: ["WalletPortfolioSnapshot", "BlockchainCapabilityGrant", "WalletTransactionPolicyReceipt"],
                action: BrowserAdvantageAction(
                    id: "wallet-advantage",
                    title: "Open wallet",
                    detail: "Inspect chain trust, embedded wallet state, policy receipts, and transfer previews.",
                    targetPanel: .wallet
                )
            ),
            BrowserAdvantageCapability(
                id: "eudi-agentic-payments",
                category: .identityPayments,
                title: "EUDI identity and agentic payments",
                strawberryBaseline: "Strawberry public docs do not claim EUDI Wallet compatibility or agentic payment protocol receipts.",
                dBrowserPosition: "dBrowser now models EUDI credential presentation, verified email import, delegated agent identity issuance, Visa Trusted Agent Protocol verification, ACP checkout, AP2 mandates, x402 requirements, Notabene TAP transfer authorization, recurring policy, and local payment receipts.",
                status: .exceeds,
                evidence: ["EUDIWalletProfile", "EUDIEmailCredentialImporter", "EUDIWalletIdentityIssuer", "VisaTrustedAgentVerifier", "ACPCheckoutSession", "AP2Mandate", "X402PaymentRequirement", "NotabeneTransferRequest", "AgenticPaymentReceipt"],
                action: BrowserAdvantageAction(
                    id: "identity-payment-policy",
                    title: "Review payments",
                    detail: "Inspect identity disclosure, agent trust, cart binding, wallet policy, and payment receipts.",
                    targetPanel: .wallet
                )
            )
        ]
    )
}

enum BrowserImportDataKind: String, CaseIterable, Identifiable, Equatable {
    case bookmarks
    case history
    case passwords
    case cookies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bookmarks: "Bookmarks"
        case .history: "History"
        case .passwords: "Passwords"
        case .cookies: "Cookies"
        }
    }

    var isSecret: Bool {
        self == .passwords || self == .cookies
    }
}

enum BrowserImportSource: String, CaseIterable, Identifiable, Equatable {
    case chrome
    case safari
    case firefox
    case edge
    case arc
    case brave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chrome: "Chrome"
        case .safari: "Safari"
        case .firefox: "Firefox"
        case .edge: "Edge"
        case .arc: "Arc"
        case .brave: "Brave"
        }
    }

    var supportedKinds: [BrowserImportDataKind] {
        switch self {
        case .safari:
            return [.bookmarks, .history, .passwords]
        case .arc:
            return [.bookmarks, .history, .cookies]
        case .chrome, .firefox, .edge, .brave:
            return BrowserImportDataKind.allCases
        }
    }
}

enum BrowserImportDisposition: String, Equatable {
    case ready
    case requiresApproval
    case unavailable
}

struct BrowserImportPlanItem: Equatable, Identifiable {
    let id: String
    var kind: BrowserImportDataKind
    var disposition: BrowserImportDisposition
    var message: String

    init(kind: BrowserImportDataKind, disposition: BrowserImportDisposition, message: String) {
        self.id = kind.rawValue
        self.kind = kind
        self.disposition = disposition
        self.message = message
    }
}

struct BrowserImportPlan: Equatable, Identifiable {
    let id: String
    var source: BrowserImportSource
    var items: [BrowserImportPlanItem]

    var readyItems: [BrowserImportPlanItem] {
        items.filter { $0.disposition == .ready }
    }

    var approvalItems: [BrowserImportPlanItem] {
        items.filter { $0.disposition == .requiresApproval }
    }

    var unavailableItems: [BrowserImportPlanItem] {
        items.filter { $0.disposition == .unavailable }
    }

    var canCompleteWithoutSecrets: Bool {
        readyItems.contains { $0.kind == .bookmarks } || readyItems.contains { $0.kind == .history }
    }

    var summary: String {
        "\(source.title): \(readyItems.count) ready, \(approvalItems.count) approval, \(unavailableItems.count) unavailable"
    }
}

enum BrowserImportPlanner {
    static func plan(
        source: BrowserImportSource,
        requestedKinds: [BrowserImportDataKind] = BrowserImportDataKind.allCases
    ) -> BrowserImportPlan {
        let items = requestedKinds.map { kind -> BrowserImportPlanItem in
            guard source.supportedKinds.contains(kind) else {
                return BrowserImportPlanItem(
                    kind: kind,
                    disposition: .unavailable,
                    message: "\(source.title) does not expose \(kind.title.lowercased()) through the current safe import path."
                )
            }

            if kind.isSecret {
                return BrowserImportPlanItem(
                    kind: kind,
                    disposition: .requiresApproval,
                    message: "\(kind.title) require explicit user approval and platform keychain or browser-export handoff."
                )
            }

            return BrowserImportPlanItem(
                kind: kind,
                disposition: .ready,
                message: "\(kind.title) can be imported, deduplicated, and logged without secret material."
            )
        }

        return BrowserImportPlan(id: source.id, source: source, items: items)
    }
}

enum BrowserCompanionRole: String, CaseIterable, Identifiable, Equatable {
    case sales
    case recruiting
    case operations
    case marketing
    case research
    case travel
    case shopping
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sales: "Sales"
        case .recruiting: "Recruiting"
        case .operations: "Operations"
        case .marketing: "Marketing"
        case .research: "Research"
        case .travel: "Travel"
        case .shopping: "Shopping"
        case .custom: "Custom"
        }
    }
}

enum BrowserCompanionRiskTolerance: String, Equatable {
    case askEveryTime
    case lowRiskOnly
    case scopedAutomation
}

struct BrowserCompanionOnboardingProfile: Equatable {
    var role: BrowserCompanionRole
    var connectedTools: [String]
    var recurringWork: [String]
    var prefersLocalModels: Bool
    var allowsGovernedMemory: Bool
    var riskTolerance: BrowserCompanionRiskTolerance

    static let localResearcher = BrowserCompanionOnboardingProfile(
        role: .research,
        connectedTools: ["MCP", "A2UI"],
        recurringWork: ["summarize sources", "export comparisons"],
        prefersLocalModels: true,
        allowsGovernedMemory: true,
        riskTolerance: .lowRiskOnly
    )
}

enum BrowserCompanionRecommendationKind: String, Equatable {
    case a2uiApp
    case workflow
    case connector
    case modelMode
    case memoryPosture
    case approvalPolicy
}

struct BrowserCompanionRecommendation: Equatable, Identifiable {
    let id: String
    var kind: BrowserCompanionRecommendationKind
    var title: String
    var detail: String
    var targetPanel: BrowserPanel
}

enum BrowserCompanionOnboardingEngine {
    static func recommendations(for profile: BrowserCompanionOnboardingProfile) -> [BrowserCompanionRecommendation] {
        var recommendations: [BrowserCompanionRecommendation] = [
            BrowserCompanionRecommendation(
                id: "model-mode",
                kind: .modelMode,
                title: profile.prefersLocalModels ? "Keep default runs local" : "Use fastest available model",
                detail: profile.prefersLocalModels
                    ? "Start with local MLX/SwiftLM and escalate only when the task needs a service-backed model."
                    : "Use the model registry to pick the fastest available provider while preserving context.",
                targetPanel: .localLLM
            ),
            BrowserCompanionRecommendation(
                id: "approval-policy",
                kind: .approvalPolicy,
                title: "Use \(profile.riskTolerance.rawValue) approvals",
                detail: "Page actions keep submit, credentials, wallet, downloads, destructive clicks, and cross-origin navigation gated.",
                targetPanel: .copilot
            )
        ]

        if profile.allowsGovernedMemory {
            recommendations.append(
                BrowserCompanionRecommendation(
                    id: "governed-memory",
                    kind: .memoryPosture,
                    title: "Enable governed OpenMind memory",
                    detail: "Attach only approved citations and require explicit writeback or correction flows.",
                    targetPanel: .runtime
                )
            )
        }

        recommendations.append(
            BrowserCompanionRecommendation(
                id: "a2ui-\(profile.role.rawValue)",
                kind: .a2uiApp,
                title: "\(profile.role.title) companion app",
                detail: "Install an A2UI app template for \(profile.role.title.lowercased()) work and route actions through native approval surfaces.",
                targetPanel: .a2ui
            )
        )

        for tool in profile.connectedTools.sorted() {
            recommendations.append(
                BrowserCompanionRecommendation(
                    id: "connector-\(tool.lowercased())",
                    kind: .connector,
                    title: "Connect \(tool)",
                    detail: "Keep scopes visible, store secrets outside prompts, and expose last-used audit state.",
                    targetPanel: .mcp
                )
            )
        }

        for (index, work) in profile.recurringWork.enumerated() {
            recommendations.append(
                BrowserCompanionRecommendation(
                    id: "workflow-\(index)",
                    kind: .workflow,
                    title: "Automate \(work)",
                    detail: "Create a saved workflow with schedule, trigger, cooldown, notification, and approval policy.",
                    targetPanel: .copilot
                )
            )
        }

        return recommendations
    }
}

enum BrowserResearchSourceConfidence: String, Equatable {
    case high
    case medium
    case low
}

struct BrowserResearchSourceEntry: Equatable, Identifiable {
    let id: UUID
    var title: String
    var urlString: String
    var retrievedAt: Date
    var evidence: String
    var confidence: BrowserResearchSourceConfidence

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        retrievedAt: Date = Date(),
        evidence: String,
        confidence: BrowserResearchSourceConfidence
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.retrievedAt = retrievedAt
        self.evidence = evidence
        self.confidence = confidence
    }

    var citation: String {
        "\(title) (\(Self.dateFormatter.string(from: retrievedAt))) - \(urlString)"
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

struct BrowserResearchLedger: Equatable {
    var topic: String
    var entries: [BrowserResearchSourceEntry]

    var datedCitations: [String] {
        entries.map(\.citation)
    }

    var markdownExport: String {
        var lines = ["# \(topic)", ""]
        for entry in entries {
            lines.append("- \(entry.citation)")
            lines.append("  - Confidence: \(entry.confidence.rawValue)")
            lines.append("  - Evidence: \(entry.evidence)")
        }
        return lines.joined(separator: "\n")
    }

    var csvExport: String {
        let rows = entries.map { entry in
            [
                escapeCSV(entry.title),
                escapeCSV(entry.urlString),
                escapeCSV(entry.citation),
                entry.confidence.rawValue,
                escapeCSV(entry.evidence)
            ]
            .joined(separator: ",")
        }
        return (["title,url,citation,confidence,evidence"] + rows).joined(separator: "\n")
    }

    private func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

enum BrowserWorkflowAutomationTriggerKind: String, Equatable {
    case schedule
    case siteVisit
    case pageChanged
    case contentAppeared
    case contentDisappeared
}

struct BrowserWorkflowAutomationTrigger: Equatable, Identifiable {
    let id: String
    var kind: BrowserWorkflowAutomationTriggerKind
    var pattern: String?

    init(kind: BrowserWorkflowAutomationTriggerKind, pattern: String? = nil) {
        self.id = [kind.rawValue, pattern].compactMap { $0 }.joined(separator: ":")
        self.kind = kind
        self.pattern = pattern
    }

    func matches(pageURLString: String?, pageEvent: String?) -> Bool {
        switch kind {
        case .schedule:
            return true
        case .siteVisit:
            guard let pattern, let pageURLString else { return false }
            return pageURLString.lowercased().contains(pattern.lowercased())
        case .pageChanged, .contentAppeared, .contentDisappeared:
            guard let pattern, let pageEvent else { return false }
            return pageEvent.lowercased().contains(pattern.lowercased())
        }
    }
}

enum BrowserWorkflowApprovalMode: String, Equatable {
    case askEveryRun
    case allowLowRisk
    case denySensitive
}

struct BrowserRecurringWorkflowAutomation: Equatable, Identifiable {
    let id: UUID
    var title: String
    var promptTemplate: String
    var schedule: CopilotWorkflowSchedule
    var triggers: [BrowserWorkflowAutomationTrigger]
    var cooldownHours: Int
    var notificationsEnabled: Bool
    var approvalMode: BrowserWorkflowApprovalMode
    var lastRunAt: Date?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        promptTemplate: String,
        schedule: CopilotWorkflowSchedule,
        triggers: [BrowserWorkflowAutomationTrigger],
        cooldownHours: Int = 1,
        notificationsEnabled: Bool = true,
        approvalMode: BrowserWorkflowApprovalMode = .askEveryRun,
        lastRunAt: Date? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.promptTemplate = promptTemplate
        self.schedule = schedule
        self.triggers = triggers
        self.cooldownHours = max(0, cooldownHours)
        self.notificationsEnabled = notificationsEnabled
        self.approvalMode = approvalMode
        self.lastRunAt = lastRunAt
        self.isEnabled = isEnabled
    }

    func isDue(now: Date = Date(), pageURLString: String? = nil, pageEvent: String? = nil) -> Bool {
        guard isEnabled else { return false }
        guard isOutsideCooldown(now: now) else { return false }
        if triggers.contains(where: { $0.matches(pageURLString: pageURLString, pageEvent: pageEvent) }) {
            return true
        }

        switch schedule.kind {
        case .manual:
            return false
        case .everyLaunch:
            return lastRunAt == nil
        case .intervalHours:
            guard let intervalHours = schedule.intervalHours else { return false }
            guard let lastRunAt else { return true }
            return now.timeIntervalSince(lastRunAt) >= TimeInterval(intervalHours * 3_600)
        }
    }

    private func isOutsideCooldown(now: Date) -> Bool {
        guard let lastRunAt else { return true }
        return now.timeIntervalSince(lastRunAt) >= TimeInterval(cooldownHours * 3_600)
    }
}

enum BrowserWorkflowAutomationScheduler {
    static func dueAutomations(
        _ automations: [BrowserRecurringWorkflowAutomation],
        now: Date = Date(),
        pageURLString: String? = nil,
        pageEvent: String? = nil
    ) -> [BrowserRecurringWorkflowAutomation] {
        automations.filter {
            $0.isDue(now: now, pageURLString: pageURLString, pageEvent: pageEvent)
        }
    }
}

enum StrawberryBenchmarkCredentialRequirement: String, Equatable {
    case none
    case salesNavigator
    case crm
    case ats
}

struct StrawberryBenchmarkTask: Equatable, Identifiable {
    let id: String
    var title: String
    var category: BrowserAdvantageCategory
    var credentialRequirement: StrawberryBenchmarkCredentialRequirement
    var expectedArtifact: String
}

enum StrawberryBenchmarkSuite {
    static let publicSpec: [StrawberryBenchmarkTask] = [
        StrawberryBenchmarkTask(id: "B1", title: "Compare product research", category: .research, credentialRequirement: .none, expectedArtifact: "sourced comparison table"),
        StrawberryBenchmarkTask(id: "B2", title: "Extract data from multiple pages", category: .research, credentialRequirement: .none, expectedArtifact: "CSV export"),
        StrawberryBenchmarkTask(id: "B3", title: "Fill a low-risk form", category: .pageActions, credentialRequirement: .none, expectedArtifact: "approval receipt"),
        StrawberryBenchmarkTask(id: "B4", title: "Monitor page change", category: .workflows, credentialRequirement: .none, expectedArtifact: "triggered workflow run"),
        StrawberryBenchmarkTask(id: "B5", title: "Summarize active page with citations", category: .pageContext, credentialRequirement: .none, expectedArtifact: "source-linked summary"),
        StrawberryBenchmarkTask(id: "B6", title: "Create recurring workflow", category: .workflows, credentialRequirement: .none, expectedArtifact: "scheduled workflow plan"),
        StrawberryBenchmarkTask(id: "B7", title: "Connect MCP tool", category: .integrations, credentialRequirement: .none, expectedArtifact: "tool inventory"),
        StrawberryBenchmarkTask(id: "B8", title: "Import browser data", category: .browserSwitching, credentialRequirement: .none, expectedArtifact: "safe import plan"),
        StrawberryBenchmarkTask(id: "B9", title: "Generate companion setup", category: .companionOnboarding, credentialRequirement: .none, expectedArtifact: "recommendation set"),
        StrawberryBenchmarkTask(id: "B10", title: "Find sales prospects", category: .research, credentialRequirement: .salesNavigator, expectedArtifact: "prospect list"),
        StrawberryBenchmarkTask(id: "B11", title: "Update CRM record", category: .integrations, credentialRequirement: .crm, expectedArtifact: "approval-gated CRM update"),
        StrawberryBenchmarkTask(id: "B12", title: "Review candidate profile", category: .research, credentialRequirement: .ats, expectedArtifact: "candidate evidence memo")
    ]

    static func tasks(includeCredentialRequired: Bool) -> [StrawberryBenchmarkTask] {
        publicSpec.filter { includeCredentialRequired || $0.credentialRequirement == .none }
    }
}

enum StrawberryBenchmarkRunStatus: String, Equatable {
    case completed
    case blocked
}

struct StrawberryBenchmarkTaskResult: Equatable, Identifiable {
    let id: String
    var task: StrawberryBenchmarkTask
    var status: StrawberryBenchmarkRunStatus
    var score: Double
    var durationSeconds: TimeInterval
    var artifactSummary: String
    var blocker: String?

    init(
        task: StrawberryBenchmarkTask,
        status: StrawberryBenchmarkRunStatus,
        score: Double,
        durationSeconds: TimeInterval,
        artifactSummary: String,
        blocker: String? = nil
    ) {
        self.id = task.id
        self.task = task
        self.status = status
        self.score = min(max(score, 0), 100)
        self.durationSeconds = durationSeconds
        self.artifactSummary = artifactSummary
        self.blocker = blocker
    }
}

struct StrawberryBenchmarkReport: Equatable {
    var results: [StrawberryBenchmarkTaskResult]

    var completedCount: Int {
        results.filter { $0.status == .completed }.count
    }

    var blockedCount: Int {
        results.filter { $0.status == .blocked }.count
    }

    var averageScore: Double {
        let completed = results.filter { $0.status == .completed }
        guard !completed.isEmpty else { return 0 }
        return completed.map(\.score).reduce(0, +) / Double(completed.count)
    }

    var totalDurationSeconds: TimeInterval {
        results.map(\.durationSeconds).reduce(0, +)
    }

    var publicSummary: String {
        "\(completedCount)/\(results.count) complete, \(blockedCount) blocked, avg \(String(format: "%.1f", averageScore))"
    }
}

enum BrowserWebCommand: Equatable {
    case back
    case forward
    case reload
    case stop
}

struct BrowserWebCommandRequest: Equatable, Identifiable {
    let id = UUID()
    let tabID: UUID
    let command: BrowserWebCommand
}

struct BrowserNavigationUpdate: Equatable {
    let tabID: UUID
    let urlString: String?
    let title: String?
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
}

struct BrowserTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var isLoading: Bool
    var canGoBack: Bool
    var canGoForward: Bool
    var mobileNotice: String?

    init(
        id: UUID = UUID(),
        title: String = "Home",
        urlString: String = "about:home",
        isLoading: Bool = false,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        mobileNotice: String? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.mobileNotice = mobileNotice
    }

    var loadableURL: URL? {
        guard mobileNotice == nil else { return nil }
        guard urlString != BrowserURLResolver.homeURLString else { return nil }
        return URL(string: urlString)
    }

    var displayURL: String {
        if urlString == BrowserURLResolver.homeURLString {
            return "Home"
        }
        return urlString
    }
}

struct BrowserHistoryEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let title: String
    let urlString: String
    let visitedAt: Date
    var summary: String?
    var isSmartHistoryIndexed: Bool

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        visitedAt: Date,
        summary: String? = nil,
        isSmartHistoryIndexed: Bool = true
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.visitedAt = visitedAt
        self.summary = summary
        self.isSmartHistoryIndexed = isSmartHistoryIndexed
    }
}

struct BrowserAddressSuggestion: Identifiable, Equatable {
    let title: String
    let urlString: String

    var id: String { urlString }
}

struct BrowserBookmark: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let urlString: String

    static let defaults: [BrowserBookmark] = [
        BrowserBookmark(title: "Zero Knowledge Gateway", urlString: RuntimeGatewayStartingPoint.zeroKnowledgeGateway.urlString),
        BrowserBookmark(title: "LLM OS Show and Tell", urlString: RuntimeGatewayStartingPoint.llmOS.urlString),
        BrowserBookmark(title: "Advatar Browser", urlString: "https://github.com/advatar/browser"),
        BrowserBookmark(title: "DuckDuckGo", urlString: "https://duckduckgo.com")
    ]
}

struct RuntimeGatewayStartingPoint: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let urlString: String
    let systemImage: String
    let isZeroKnowledgeGateway: Bool

    init(
        title: String,
        description: String,
        urlString: String,
        systemImage: String,
        isZeroKnowledgeGateway: Bool = false
    ) {
        self.id = urlString
        self.title = title
        self.description = description
        self.urlString = urlString
        self.systemImage = systemImage
        self.isZeroKnowledgeGateway = isZeroKnowledgeGateway
    }

    static let zeroKnowledgeGateway = RuntimeGatewayStartingPoint(
        title: "Zero Knowledge Gateway",
        description: "Primary gateway for zero-knowledge browser capabilities and proofs.",
        urlString: "https://zerok.cloud",
        systemImage: "shield.lefthalf.filled",
        isZeroKnowledgeGateway: true
    )

    static let llmOS = RuntimeGatewayStartingPoint(
        title: "LLM OS",
        description: "Show-and-tell runtime surface for LLM OS integration.",
        urlString: "https://llmos.showntell.dev",
        systemImage: "sparkles"
    )

    static let featured: [RuntimeGatewayStartingPoint] = [
        zeroKnowledgeGateway,
        llmOS
    ]
}

struct DecentralizedStartingPoint: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let address: String
    let systemImage: String

    init(title: String, description: String, address: String, systemImage: String) {
        self.id = address
        self.title = title
        self.description = description
        self.address = address
        self.systemImage = systemImage
    }

    static let featured: [DecentralizedStartingPoint] = [
        DecentralizedStartingPoint(
            title: "IPFS Docs",
            description: "Protocol guides, concepts, and examples published through IPNS.",
            address: "ipns://docs.ipfs.tech",
            systemImage: "book.closed"
        ),
        DecentralizedStartingPoint(
            title: "IPFS Home",
            description: "The public IPFS project site served through a mutable IPNS name.",
            address: "ipns://ipfs.tech",
            systemImage: "network"
        ),
        DecentralizedStartingPoint(
            title: "Wikipedia on IPFS",
            description: "A decentralized mirror that demonstrates large public knowledge content.",
            address: "ipns://en.wikipedia-on-ipfs.org",
            systemImage: "text.book.closed"
        ),
        DecentralizedStartingPoint(
            title: "Sample CID",
            description: "A content-addressed IPFS object for checking gateway and CID resolution.",
            address: "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi",
            systemImage: "cube.box"
        )
    ]
}

enum DecentralizedStorageGatewayStrategy: Equatable {
    case pathGateway(host: String, namespace: String)
    case rootGateway(host: String)
    case remoteRuntime(path: String)
    case none
}

enum DecentralizedStorageAdapterStage: String, Equatable {
    case directGateway = "direct-gateway"
    case remoteRuntimeHandoff = "remote-runtime-handoff"
    case nativeLocalAdapter = "native-local-adapter"
    case nativePlanned = "native-planned"
}

enum DecentralizedStorageContentAccessState: String, Equatable {
    case loadableGateway = "loadable-gateway"
    case nativeAdapter = "native-adapter"
    case remoteRuntime = "remote-runtime"
    case localResolverRequired = "local-resolver-required"
    case unsupportedLocator = "unsupported-locator"
}

struct DecentralizedStorageResolverRequirement: Equatable {
    let resolverName: String
    let reason: String
    let configurationHint: String
    let issueNumber: Int?

    var issueReference: String? {
        issueNumber.map { "#\($0)" }
    }
}

struct DecentralizedStorageContentResolution: Equatable {
    let state: DecentralizedStorageContentAccessState
    let url: URL?
    let locator: String
    let message: String
    let requirement: DecentralizedStorageResolverRequirement?

    var isLoadable: Bool {
        url != nil && (state == .loadableGateway || state == .nativeAdapter || state == .remoteRuntime)
    }
}

struct DecentralizedStorageNativeAdapterEndpoint: Equatable {
    let baseURL: URL
    let routePath: String
    let displayName: String
    let trustBoundary: String
    let requiresCredentialScope: Bool
}

struct DecentralizedStorageNativeAdapterConfiguration: Equatable {
    var endpoints: [String: DecentralizedStorageNativeAdapterEndpoint]

    nonisolated static let disabled = DecentralizedStorageNativeAdapterConfiguration(endpoints: [:])

    nonisolated static let localDefaults = DecentralizedStorageNativeAdapterConfiguration(
        endpoints: [
            "filecoin": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4881")!,
                routePath: "/dweb/filecoin/native",
                displayName: "Local Filecoin retrieval adapter",
                trustBoundary: "Local Filecoin retrieval service supplies CAR or payload bytes; the app keeps CID, deal, and piece verification metadata visible.",
                requiresCredentialScope: false
            ),
            "walrus": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4882")!,
                routePath: "/dweb/walrus/native",
                displayName: "Local Walrus Sites/quilt adapter",
                trustBoundary: "Local Walrus adapter resolves site, quilt, and blob metadata while the app preserves blob IDs and Sui/Walrus verification inputs.",
                requiresCredentialScope: false
            ),
            "iroh": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4883")!,
                routePath: "/dweb/iroh/native",
                displayName: "Local Iroh blobs adapter",
                trustBoundary: "Local Iroh blobs runtime handles peer dialing and streaming while the app preserves BLAKE3 hash or ticket verification metadata.",
                requiresCredentialScope: false
            ),
            "hypercore": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4884")!,
                routePath: "/dweb/hypercore/native",
                displayName: "Local Hypercore/Hyperdrive adapter",
                trustBoundary: "Local Hypercore runtime handles discovery and replication while the app preserves signed feed, version, and path metadata.",
                requiresCredentialScope: false
            ),
            "sia": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4885")!,
                routePath: "/dweb/sia/native",
                displayName: "Local Sia renterd adapter",
                trustBoundary: "Local renterd bridge owns host retrieval and credentials while the app keeps object path, checksum, and encryption metadata separate.",
                requiresCredentialScope: true
            ),
            "storj": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4886")!,
                routePath: "/dweb/storj/native",
                displayName: "Local Storj uplink adapter",
                trustBoundary: "Local Storj adapter owns grants and passphrases while the app preserves bucket, object, version, and credential-scope metadata.",
                requiresCredentialScope: true
            ),
            "tahoe-lafs": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4887")!,
                routePath: "/dweb/tahoe-lafs/native",
                displayName: "Local Tahoe-LAFS WebAPI adapter",
                trustBoundary: "Local Tahoe adapter dereferences capabilities inside the user-selected grid boundary while the app treats capabilities as secrets.",
                requiresCredentialScope: true
            ),
            "autonomi": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4888")!,
                routePath: "/dweb/autonomi/native",
                displayName: "Local Autonomi client adapter",
                trustBoundary: "Local Autonomi client resolves data maps and private chunks while the app preserves content-address and decryption metadata.",
                requiresCredentialScope: true
            ),
            "bittorrent": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4889")!,
                routePath: "/dweb/bittorrent/native",
                displayName: "Local BitTorrent/WebTorrent adapter",
                trustBoundary: "Local torrent engine owns tracker, DHT, or WebRTC peer discovery while the app preserves infohash and signed manifest metadata.",
                requiresCredentialScope: false
            ),
            "ceramic": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4890")!,
                routePath: "/dweb/ceramic/native",
                displayName: "Local Ceramic node adapter",
                trustBoundary: "Local Ceramic node loads stream events while the app preserves DID, commit, and anchor proof verification metadata.",
                requiresCredentialScope: false
            ),
            "orbitdb": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4891")!,
                routePath: "/dweb/orbitdb/native",
                displayName: "Local OrbitDB replication adapter",
                trustBoundary: "Local OrbitDB/IPFS runtime owns replication while the app preserves database address, access-controller, and signed log metadata.",
                requiresCredentialScope: false
            ),
            "radicle": DecentralizedStorageNativeAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4892")!,
                routePath: "/dweb/radicle/native",
                displayName: "Local Radicle node adapter",
                trustBoundary: "Local Radicle node/httpd owns seed discovery and Git object retrieval while the app preserves repository identity and signed refs metadata.",
                requiresCredentialScope: false
            )
        ]
    )

    var enabledNetworkIDs: Set<String> {
        Set(endpoints.keys)
    }

    func endpoint(for networkID: String) -> DecentralizedStorageNativeAdapterEndpoint? {
        endpoints[networkID]
    }

    func disabling(_ networkIDs: Set<String>) -> DecentralizedStorageNativeAdapterConfiguration {
        var copy = self
        for networkID in networkIDs {
            copy.endpoints.removeValue(forKey: networkID)
        }
        return copy
    }
}

struct DecentralizedStorageAdapterSpec: Equatable {
    let issueNumber: Int?
    let handlerID: String
    let stage: DecentralizedStorageAdapterStage
    let locatorKind: String
    let trustBoundary: String
    let verificationRequirements: [String]

    var issueReference: String? {
        issueNumber.map { "#\($0)" }
    }

    var verificationSummary: String {
        verificationRequirements.joined(separator: " ")
    }

    static func gateway(networkID: String, locatorKind: String = "content identifier") -> DecentralizedStorageAdapterSpec {
        DecentralizedStorageAdapterSpec(
            issueNumber: nil,
            handlerID: "\(networkID).gateway",
            stage: .directGateway,
            locatorKind: locatorKind,
            trustBoundary: "HTTPS gateway fetch with the decentralized URI preserved as source metadata.",
            verificationRequirements: [
                "Preserve the original URI and content identifier.",
                "Treat the gateway as transport, not the content trust root."
            ]
        )
    }

    static func remote(
        issueNumber: Int,
        handlerID: String,
        locatorKind: String,
        trustBoundary: String,
        verificationRequirements: [String]
    ) -> DecentralizedStorageAdapterSpec {
        DecentralizedStorageAdapterSpec(
            issueNumber: issueNumber,
            handlerID: handlerID,
            stage: .remoteRuntimeHandoff,
            locatorKind: locatorKind,
            trustBoundary: trustBoundary,
            verificationRequirements: verificationRequirements
        )
    }
}

struct DecentralizedStorageNetwork: Identifiable, Equatable {
    let id: String
    let title: String
    let schemes: [String]
    let distributionRole: String
    let gatewayStrategy: DecentralizedStorageGatewayStrategy
    let adapter: DecentralizedStorageAdapterSpec

    init(
        id: String,
        title: String,
        schemes: [String],
        distributionRole: String,
        gatewayStrategy: DecentralizedStorageGatewayStrategy,
        adapter: DecentralizedStorageAdapterSpec? = nil
    ) {
        self.id = id
        self.title = title
        self.schemes = schemes
        self.distributionRole = distributionRole
        self.gatewayStrategy = gatewayStrategy
        self.adapter = adapter ?? .gateway(networkID: id)
    }

    var primaryScheme: String {
        schemes.first ?? id
    }

    static let supported: [DecentralizedStorageNetwork] = [
        DecentralizedStorageNetwork(
            id: "ipfs",
            title: "IPFS",
            schemes: ["ipfs"],
            distributionRole: "Content-addressed app bundles, decentralized websites, and immutable asset trees.",
            gatewayStrategy: .none,
            adapter: .gateway(networkID: "ipfs", locatorKind: "CID or IPFS path")
        ),
        DecentralizedStorageNetwork(
            id: "ipns",
            title: "IPNS",
            schemes: ["ipns"],
            distributionRole: "Mutable names for IPFS app catalogs, release channels, and live decentralized web pages.",
            gatewayStrategy: .none,
            adapter: .gateway(networkID: "ipns", locatorKind: "IPNS name or peer ID")
        ),
        DecentralizedStorageNetwork(
            id: "swarm",
            title: "Swarm",
            schemes: ["bzz", "bzzr", "swarm"],
            distributionRole: "Ethereum-native decentralized storage for dapp assets, manifests, and distribution.",
            gatewayStrategy: .pathGateway(host: "gateway.ethswarm.org", namespace: "bzz")
        ),
        DecentralizedStorageNetwork(
            id: "arweave",
            title: "Arweave",
            schemes: ["ar", "arweave"],
            distributionRole: "Permanent app release manifests, audit snapshots, and public assets.",
            gatewayStrategy: .rootGateway(host: "arweave.net")
        ),
        DecentralizedStorageNetwork(
            id: "filecoin",
            title: "Filecoin",
            schemes: ["filecoin", "piececid", "fil"],
            distributionRole: "Large app bundles, model weights, data archives, and storage-deal receipts.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/filecoin/resolve"),
            adapter: .remote(
                issueNumber: 119,
                handlerID: "filecoin.piece-car",
                locatorKind: "Filecoin CID, piece CID, or storage deal reference",
                trustBoundary: "A native/local adapter retrieves CAR or payload data while the app keeps CID and deal verification as the local trust target.",
                verificationRequirements: [
                    "Preserve payload CID, piece CID, path, query, and fragment.",
                    "Verify CAR block roots and piece inclusion before treating retrieved content as trusted."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "walrus",
            title: "Walrus",
            schemes: ["walrus"],
            distributionRole: "Programmable blob availability for Sui and Walrus app deployments.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/walrus/resolve"),
            adapter: .remote(
                issueNumber: 120,
                handlerID: "walrus.blob",
                locatorKind: "Walrus blob ID",
                trustBoundary: "A native/local adapter locates the blob while the app keeps Sui/Walrus blob metadata and checksum validation explicit.",
                verificationRequirements: [
                    "Preserve blob ID and any epoch or object metadata.",
                    "Validate blob digest and Sui/Walrus metadata before install or render."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "iroh",
            title: "Iroh blobs",
            schemes: ["iroh", "iroh-blob"],
            distributionRole: "BLAKE3-addressed peer distribution and local-first install sync.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/iroh/resolve"),
            adapter: .remote(
                issueNumber: 121,
                handlerID: "iroh.blake3-blob",
                locatorKind: "Iroh blob hash or ticket",
                trustBoundary: "A native/local adapter or Iroh peer fetches bytes while the app keeps BLAKE3 hash verification local.",
                verificationRequirements: [
                    "Preserve blob hash, ticket, peer hints, and path.",
                    "Verify BLAKE3 content hash before exposing fetched bytes."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "hypercore",
            title: "Hypercore",
            schemes: ["hyper", "hypercore", "hyperdrive", "pear", "dat"],
            distributionRole: "Signed mutable catalogs, append-only update feeds, and peer-synced app data.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/hypercore/resolve"),
            adapter: .remote(
                issueNumber: 122,
                handlerID: "hypercore.feed",
                locatorKind: "Hypercore public key, Hyperdrive key, or Pear app key",
                trustBoundary: "A native/local adapter resolves feed data while append-only signature verification remains the local trust target.",
                verificationRequirements: [
                    "Preserve feed key, drive path, version, and discovery key hints.",
                    "Verify signed tree or feed blocks before trusting mutable catalog state."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "sia",
            title: "Sia",
            schemes: ["sia"],
            distributionRole: "Encrypted private app data and decentralized backup storage.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/sia/resolve"),
            adapter: .remote(
                issueNumber: 123,
                handlerID: "sia.renterd-object",
                locatorKind: "Sia object ID, Skylink, or renterd path",
                trustBoundary: "A native/local adapter bridges renterd or host retrieval while encryption keys and object integrity stay app-owned.",
                verificationRequirements: [
                    "Preserve object path, bucket, skylink, and encryption metadata.",
                    "Validate object checksum and decrypt locally when keys are user-held."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "storj",
            title: "Storj",
            schemes: ["storj"],
            distributionRole: "Encrypted object storage fallback for app data and backups.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/storj/resolve"),
            adapter: .remote(
                issueNumber: 124,
                handlerID: "storj.uplink-object",
                locatorKind: "Storj bucket and object path",
                trustBoundary: "A native/local adapter bridges uplink access while encryption passphrases, grants, and object validation remain separate from browsing state.",
                verificationRequirements: [
                    "Preserve bucket, object key, grant scope, version, and path.",
                    "Validate object checksum and avoid leaking encryption grants to generic page context."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "tahoe-lafs",
            title: "Tahoe-LAFS",
            schemes: ["tahoe", "lafs"],
            distributionRole: "Least-authority private app data replicated across storage grids.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/tahoe-lafs/resolve"),
            adapter: .remote(
                issueNumber: 125,
                handlerID: "tahoe.capability",
                locatorKind: "Tahoe-LAFS capability URI",
                trustBoundary: "A native/local adapter relays grid access while the app treats Tahoe capabilities as secrets and least-authority access tokens.",
                verificationRequirements: [
                    "Preserve read/write capability type without promoting it into visible page text.",
                    "Verify immutable directory or file hashes when capabilities include them."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "autonomi",
            title: "Autonomi",
            schemes: ["autonomi", "safe"],
            distributionRole: "Encrypted autonomous storage for app data, app publishing, and private distribution.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/autonomi/resolve"),
            adapter: .remote(
                issueNumber: 126,
                handlerID: "autonomi.address",
                locatorKind: "Autonomi address or SAFE URL",
                trustBoundary: "A native/local adapter bridges network lookup while app-held keys and content address checks remain the trust boundary.",
                verificationRequirements: [
                    "Preserve address, data map, and private access metadata.",
                    "Verify encrypted chunk map and content address before install or render."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "bittorrent",
            title: "BitTorrent / WebTorrent",
            schemes: ["magnet", "bittorrent", "webtorrent"],
            distributionRole: "Hot public release distribution with signed manifests as the trust root.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/bittorrent/resolve"),
            adapter: .remote(
                issueNumber: 127,
                handlerID: "bittorrent.infohash",
                locatorKind: "BTIH/BTMH infohash or torrent URI",
                trustBoundary: "A native/local adapter can seed or fetch torrent data while signed manifests and infohash verification stay visible to the app.",
                verificationRequirements: [
                    "Preserve xt, dn, tr, ws, and exact magnet parameters.",
                    "Verify infohash and signed release manifest before trusting downloaded app content."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "ceramic",
            title: "Ceramic",
            schemes: ["ceramic", "ceramic-stream"],
            distributionRole: "Mutable app metadata, profiles, ratings, and install records.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/ceramic/resolve"),
            adapter: .remote(
                issueNumber: 128,
                handlerID: "ceramic.stream",
                locatorKind: "Ceramic stream ID or commit ID",
                trustBoundary: "A native/local adapter resolves stream state while DID signatures, anchors, and commit history remain explicit verification inputs.",
                verificationRequirements: [
                    "Preserve stream ID, commit ID, controller DID, and model hints.",
                    "Verify signed commits and anchor proofs before trusting mutable metadata."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "orbitdb",
            title: "OrbitDB",
            schemes: ["orbitdb"],
            distributionRole: "Peer-synced app databases and local-first collaboration state.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/orbitdb/resolve"),
            adapter: .remote(
                issueNumber: 129,
                handlerID: "orbitdb.address",
                locatorKind: "OrbitDB address",
                trustBoundary: "A native/local adapter can bridge replication while access-controller checks and signed log heads stay local verification targets.",
                verificationRequirements: [
                    "Preserve database address, store type, and access-controller metadata.",
                    "Verify signed operation log entries before treating collaborative state as trusted."
                ]
            )
        ),
        DecentralizedStorageNetwork(
            id: "radicle",
            title: "Radicle",
            schemes: ["rad", "radicle"],
            distributionRole: "Peer-to-peer source distribution, recipes, and code provenance.",
            gatewayStrategy: .remoteRuntime(path: "/dweb/radicle/resolve"),
            adapter: .remote(
                issueNumber: 130,
                handlerID: "radicle.repository",
                locatorKind: "Radicle repository ID, NID, or URN",
                trustBoundary: "A native/local adapter bridges seed lookup while repository identity, signed refs, and code provenance stay app-visible.",
                verificationRequirements: [
                    "Preserve repository ID, revision, path, and seed hints.",
                    "Verify signed refs and expected repository identity before installing code."
                ]
            )
        )
    ]

    static var supportedSchemes: Set<String> {
        Set(supported.flatMap(\.schemes))
    }

    static func profile(forScheme scheme: String) -> DecentralizedStorageNetwork? {
        let normalizedScheme = scheme.lowercased()
        return supported.first { network in
            network.schemes.contains(normalizedScheme)
        }
    }

    func gatewayURL(for url: URL) -> URL? {
        guard let locator = Self.locatorAndPath(from: url) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        switch gatewayStrategy {
        case .pathGateway(let host, let namespace):
            components.host = host
            components.path = "/\(namespace)/\(locator.root)\(locator.path)"
        case .rootGateway(let host):
            components.host = host
            components.path = "/\(locator.root)\(locator.path)"
        case .remoteRuntime:
            return nil
        case .none:
            return nil
        }
        components.query = url.query
        components.fragment = url.fragment
        return components.url
    }

    func contentResolution(
        for originalInput: String,
        url: URL,
        nativeAdapters: DecentralizedStorageNativeAdapterConfiguration,
        remoteRuntimeBaseURL: URL?,
        decentralizedGatewayHost: String,
        walrusAggregatorBaseURL: URL
    ) -> DecentralizedStorageContentResolution {
        let locator = adapterLocator(for: url, originalInput: originalInput)

        if let resolvedURL = gatewayURL(for: url) {
            return DecentralizedStorageContentResolution(
                state: .loadableGateway,
                url: resolvedURL,
                locator: locator,
                message: "Resolved \(title) through a content-loadable decentralized storage gateway.",
                requirement: nil
            )
        }

        if let resolvedURL = opportunisticContentGatewayURL(
            for: url,
            decentralizedGatewayHost: decentralizedGatewayHost,
            walrusAggregatorBaseURL: walrusAggregatorBaseURL
        ) {
            return DecentralizedStorageContentResolution(
                state: .loadableGateway,
                url: resolvedURL,
                locator: locator,
                message: "Resolved \(title) through a protocol-specific content gateway while preserving \(adapter.locatorKind).",
                requirement: nil
            )
        }

        if let endpoint = nativeAdapters.endpoint(for: id),
           let resolvedURL = nativeAdapterURL(for: originalInput, url: url, endpoint: endpoint) {
            return DecentralizedStorageContentResolution(
                state: .nativeAdapter,
                url: resolvedURL,
                locator: locator,
                message: "Routed \(title) URI through \(endpoint.displayName) using \(adapter.handlerID). Trust boundary: \(endpoint.trustBoundary)",
                requirement: nil
            )
        }

        if let remoteRuntimeBaseURL,
           let resolvedURL = remoteRuntimeURL(for: originalInput, url: url, baseURL: remoteRuntimeBaseURL) {
            return DecentralizedStorageContentResolution(
                state: .remoteRuntime,
                url: resolvedURL,
                locator: locator,
                message: "Routed \(title) URI through the configured remote \(adapter.handlerID) content resolver. Trust boundary: \(adapter.trustBoundary)",
                requirement: nil
            )
        }

        let requirement = resolverRequirement(for: url)
        return DecentralizedStorageContentResolution(
            state: requirement.resolverName == "Unsupported locator" ? .unsupportedLocator : .localResolverRequired,
            url: nil,
            locator: locator,
            message: "\(title) URI is recognized, but this locator is not content-loadable in the mobile build without \(requirement.resolverName). \(requirement.reason) Configure \(requirement.configurationHint). Native adapter issue: \(requirement.issueReference ?? "untracked").",
            requirement: requirement
        )
    }

    func remoteRuntimeURL(for originalInput: String, url: URL, baseURL: URL) -> URL? {
        guard case .remoteRuntime(let routePath) = gatewayStrategy,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resolverPath = routePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joinedPath = [basePath, resolverPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.path = joinedPath.isEmpty ? "" : "/\(joinedPath)"

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "network", value: id))
        queryItems.append(URLQueryItem(name: "scheme", value: url.scheme?.lowercased() ?? primaryScheme))
        queryItems.append(URLQueryItem(name: "adapter", value: adapter.handlerID))
        queryItems.append(URLQueryItem(name: "resolution_stage", value: adapter.stage.rawValue))
        queryItems.append(URLQueryItem(name: "locator_kind", value: adapter.locatorKind))
        queryItems.append(URLQueryItem(name: "locator", value: adapterLocator(for: url, originalInput: originalInput)))
        if let issueNumber = adapter.issueNumber {
            queryItems.append(URLQueryItem(name: "native_issue", value: "\(issueNumber)"))
        }
        queryItems.append(URLQueryItem(name: "uri", value: originalInput))
        components.queryItems = queryItems
        components.fragment = nil
        return components.url
    }

    func nativeAdapterURL(
        for originalInput: String,
        url: URL,
        endpoint: DecentralizedStorageNativeAdapterEndpoint
    ) -> URL? {
        guard case .remoteRuntime = gatewayStrategy,
              var components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let adapterPath = endpoint.routePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joinedPath = [basePath, adapterPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.path = joinedPath.isEmpty ? "" : "/\(joinedPath)"

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "network", value: id))
        queryItems.append(URLQueryItem(name: "scheme", value: url.scheme?.lowercased() ?? primaryScheme))
        queryItems.append(URLQueryItem(name: "adapter", value: adapter.handlerID))
        queryItems.append(URLQueryItem(name: "resolution_stage", value: DecentralizedStorageAdapterStage.nativeLocalAdapter.rawValue))
        queryItems.append(URLQueryItem(name: "locator_kind", value: adapter.locatorKind))
        queryItems.append(URLQueryItem(name: "locator", value: adapterLocator(for: url, originalInput: originalInput)))
        queryItems.append(URLQueryItem(name: "credential_scoped", value: endpoint.requiresCredentialScope ? "true" : "false"))
        if let issueNumber = adapter.issueNumber {
            queryItems.append(URLQueryItem(name: "native_issue", value: "\(issueNumber)"))
        }
        queryItems.append(URLQueryItem(name: "uri", value: originalInput))
        components.queryItems = queryItems
        components.fragment = nil
        return components.url
    }

    func adapterLocator(for url: URL, originalInput: String) -> String {
        if id == "bittorrent",
           let xt = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name.lowercased() == "xt" })?
                .value,
           !xt.isEmpty {
            return xt
        }

        if let locator = Self.locatorAndPath(from: url) {
            return locator.path.isEmpty ? locator.root : "\(locator.root)\(locator.path)"
        }

        let schemePrefix = "\(url.scheme ?? primaryScheme):"
        let locator = originalInput.hasPrefix(schemePrefix)
            ? String(originalInput.dropFirst(schemePrefix.count))
            : originalInput
        let trimmedLocator = locator.trimmingCharacters(in: CharacterSet(charactersIn: "/?#"))
        return trimmedLocator.isEmpty ? originalInput : trimmedLocator
    }

    private func opportunisticContentGatewayURL(
        for url: URL,
        decentralizedGatewayHost: String,
        walrusAggregatorBaseURL: URL
    ) -> URL? {
        switch id {
        case "filecoin":
            return filecoinGatewayURL(for: url, host: decentralizedGatewayHost)
        case "walrus":
            return walrusBlobGatewayURL(for: url, baseURL: walrusAggregatorBaseURL)
        case "bittorrent":
            return bittorrentWebSeedURL(for: url)
        default:
            return nil
        }
    }

    private func filecoinGatewayURL(for url: URL, host: String) -> URL? {
        guard url.scheme?.lowercased() != "piececid",
              let locator = Self.locatorAndPath(from: url),
              Self.isIPFSDataCID(locator.root) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/ipfs/\(locator.root)\(locator.path)"
        components.query = url.query
        components.fragment = url.fragment
        return components.url
    }

    private func walrusBlobGatewayURL(for url: URL, baseURL: URL) -> URL? {
        guard let locator = Self.locatorAndPath(from: url),
              !locator.root.isEmpty,
              locator.path.isEmpty,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resolverPath = "v1/blobs/\(locator.root)"
        let joinedPath = [basePath, resolverPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.path = "/\(joinedPath)"
        components.query = url.query
        components.fragment = url.fragment
        return components.url
    }

    private func bittorrentWebSeedURL(for url: URL) -> URL? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let seedNames = ["as", "xs", "ws"]
        for seedName in seedNames {
            if let seed = items.first(where: { $0.name.lowercased() == seedName })?.value,
               let seedURL = URL(string: seed),
               let scheme = seedURL.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                return seedURL
            }
        }
        return nil
    }

    private func resolverRequirement(for url: URL) -> DecentralizedStorageResolverRequirement {
        let locator = adapterLocator(for: url, originalInput: url.absoluteString)
        if id == "filecoin",
           url.scheme?.lowercased() == "piececid" || locator.hasPrefix("baga") {
            return DecentralizedStorageResolverRequirement(
                resolverName: "a Filecoin retrieval client or CAR/piece resolver",
                reason: "Piece CIDs and deal references need Filecoin retrieval, CAR root validation, and piece inclusion checks; an IPFS gateway cannot safely infer the payload bytes.",
                configurationHint: "a Filecoin-capable storage resolver or native Filecoin stack",
                issueNumber: adapter.issueNumber
            )
        }

        switch id {
        case "filecoin":
            return DecentralizedStorageResolverRequirement(
                resolverName: "a Filecoin retrieval client",
                reason: "Only IPFS-compatible data CIDs can use the bundled gateway bridge; provider, actor, and deal locators need Filecoin retrieval.",
                configurationHint: "a Filecoin-capable storage resolver",
                issueNumber: adapter.issueNumber
            )
        case "walrus":
            return DecentralizedStorageResolverRequirement(
                resolverName: "Unsupported locator",
                reason: "The bundled Walrus HTTP path fetches one blob ID at a time; path-bearing Walrus site and quilt locators need a Walrus Sites portal or quilt-aware resolver.",
                configurationHint: "a Walrus Sites portal, quilt resolver, or remote storage resolver",
                issueNumber: adapter.issueNumber
            )
        case "iroh":
            return DecentralizedStorageResolverRequirement(
                resolverName: "an Iroh endpoint and iroh-blobs store",
                reason: "Iroh blob tickets include peer dialing information and require the Iroh blobs protocol for verified BLAKE3 streaming.",
                configurationHint: "a native Iroh blobs runtime or local resolver service",
                issueNumber: adapter.issueNumber
            )
        case "hypercore":
            return DecentralizedStorageResolverRequirement(
                resolverName: "a Hypercore/Hyperdrive runtime",
                reason: "Hypercore feeds require discovery, replication, and signed feed or Merkle tree verification before bytes can be trusted.",
                configurationHint: "a native Hypercore stack or local Hyperdrive resolver",
                issueNumber: adapter.issueNumber
            )
        case "sia":
            return DecentralizedStorageResolverRequirement(
                resolverName: "a Sia renterd or host retrieval gateway",
                reason: "Sia object paths and Skylinks require renter credentials, host retrieval, or object metadata before the app can fetch bytes.",
                configurationHint: "a renterd-backed storage resolver",
                issueNumber: adapter.issueNumber
            )
        case "storj":
            return DecentralizedStorageResolverRequirement(
                resolverName: "a Storj access grant, S3 gateway, or linksharing URL",
                reason: "Storj bucket/object URIs are encrypted and scoped by grants; the browser must not invent or expose credentials.",
                configurationHint: "a Storj linkshare or grant-aware resolver",
                issueNumber: adapter.issueNumber
            )
        case "tahoe-lafs":
            return DecentralizedStorageResolverRequirement(
                resolverName: "a Tahoe-LAFS gateway",
                reason: "Tahoe capabilities are least-authority secrets and must be dereferenced through a user-selected grid gateway.",
                configurationHint: "a Tahoe WebAPI endpoint",
                issueNumber: adapter.issueNumber
            )
        case "autonomi":
            return DecentralizedStorageResolverRequirement(
                resolverName: "an Autonomi client",
                reason: "Autonomi data maps and private access metadata require the Autonomi network client and local decryption path.",
                configurationHint: "a native Autonomi client or local resolver",
                issueNumber: adapter.issueNumber
            )
        case "bittorrent":
            return DecentralizedStorageResolverRequirement(
                resolverName: "a BitTorrent/WebTorrent engine",
                reason: "Magnet links without HTTP web seeds need tracker/DHT or WebRTC peer discovery plus infohash verification.",
                configurationHint: "a native torrent engine, WebTorrent runtime, or remote storage resolver",
                issueNumber: adapter.issueNumber
            )
        case "ceramic":
            return DecentralizedStorageResolverRequirement(
                resolverName: "a Ceramic node",
                reason: "Ceramic streams need event loading, DID signature validation, and anchor proof checks.",
                configurationHint: "a Ceramic HTTP/API node or native Ceramic client",
                issueNumber: adapter.issueNumber
            )
        case "orbitdb":
            return DecentralizedStorageResolverRequirement(
                resolverName: "an OrbitDB/IPFS replication runtime",
                reason: "OrbitDB addresses resolve through IPFS/libp2p replication and signed operation logs.",
                configurationHint: "an OrbitDB-capable local or remote resolver",
                issueNumber: adapter.issueNumber
            )
        case "radicle":
            return DecentralizedStorageResolverRequirement(
                resolverName: "a Radicle node",
                reason: "Radicle repository URNs require seed discovery, Git object retrieval, and signed ref verification.",
                configurationHint: "a Radicle node or repository resolver",
                issueNumber: adapter.issueNumber
            )
        default:
            return DecentralizedStorageResolverRequirement(
                resolverName: "a protocol-specific resolver",
                reason: "The URI is registered but this build has no content retrieval path for the locator.",
                configurationHint: "a storage resolver for \(title)",
                issueNumber: adapter.issueNumber
            )
        }
    }

    private static func locatorAndPath(from url: URL) -> (root: String, path: String)? {
        var root = url.host ?? ""
        var path = url.path

        if root.isEmpty {
            let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = trimmedPath.split(separator: "/", maxSplits: 1).map(String.init)
            root = parts.first ?? ""
            path = parts.count > 1 ? "/\(parts[1])" : ""
        }

        guard !root.isEmpty else {
            return nil
        }

        return (root: root, path: path)
    }

    private static func isIPFSDataCID(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return normalized.hasPrefix("Qm")
            || normalized.hasPrefix("bafy")
            || normalized.hasPrefix("bafk")
    }
}

struct RuntimeFeatureExplanation: Equatable {
    let overview: String
    let bridgeBehavior: String
    let detailPoints: [String]
}

enum MobileRuntimeFeature: String, CaseIterable, Identifiable {
    case webBrowsing
    case tabs
    case decentralizedProtocols
    case architectureOverview
    case chainTrust
    case mcpServers
    case a2uiRendering
    case logosRuntime
    case aztecProtocol
    case afmServices
    case copilot
    case wallet
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webBrowsing: "Web browsing"
        case .tabs: "Tabs and history"
        case .decentralizedProtocols: "DWeb URI resolution"
        case .architectureOverview: "Architecture"
        case .chainTrust: "Chain trust"
        case .mcpServers: "MCP servers"
        case .a2uiRendering: "A2UI rendering"
        case .logosRuntime: "Logos runtime"
        case .aztecProtocol: "Aztec protocol"
        case .afmServices: "AFM services"
        case .copilot: "AI Copilot"
        case .wallet: "Wallet policies"
        case .downloads: "Downloads"
        }
    }

    var status: String {
        switch self {
        case .webBrowsing: "Native WKWebView"
        case .tabs: "Native Swift state"
        case .decentralizedProtocols: "Native/local adapters"
        case .architectureOverview: "Light clients + AF Market + ZeroK"
        case .chainTrust: "Gateway/RPC fallback"
        case .mcpServers: "HTTP, WebSocket, STDIO"
        case .a2uiRendering: "Native SwiftUI widgets"
        case .logosRuntime: "Basecamp modules"
        case .aztecProtocol: "PXE + private contracts"
        case .afmServices: "Router, registry, pipelines"
        case .copilot: "Local command bridge"
        case .wallet: "Local policy bridge"
        case .downloads: "Native URLSession"
        }
    }

    var systemImage: String {
        switch self {
        case .webBrowsing: "safari"
        case .tabs: "rectangle.on.rectangle"
        case .decentralizedProtocols: "link"
        case .architectureOverview: "square.stack.3d.up"
        case .chainTrust: "checkmark.shield"
        case .mcpServers: "network"
        case .a2uiRendering: "square.grid.2x2"
        case .logosRuntime: "shippingbox"
        case .aztecProtocol: "lock.shield"
        case .afmServices: "point.3.connected.trianglepath.dotted"
        case .copilot: "sparkles"
        case .wallet: "wallet.pass"
        case .downloads: "arrow.down.circle"
        }
    }

    var isAvailableOnMobile: Bool {
        true
    }

    var explanation: RuntimeFeatureExplanation {
        switch self {
        case .webBrowsing:
            RuntimeFeatureExplanation(
                overview: "Loads standard HTTP and HTTPS pages with native WKWebView while the app keeps browser state in Swift.",
                bridgeBehavior: "This path is fully native on iOS and does not need the desktop Tauri runtime.",
                detailPoints: [
                    "Address-bar input is normalized before WebKit receives a request.",
                    "Page title, loading, and back-forward state flow back into the tab model.",
                    "Unsupported schemes are stopped before WebKit can attempt to open them directly."
                ]
            )
        case .tabs:
            RuntimeFeatureExplanation(
                overview: "Tracks tabs, history, bookmarks, and toolbar commands inside the Swift shell.",
                bridgeBehavior: "The current bridge stores this state in memory so the iOS app can run independently.",
                detailPoints: [
                    "Opening, closing, and activating tabs updates the same model used by the browser surface.",
                    "History entries are deduplicated at the front of the list to avoid repeated reload noise.",
                    "Toolbar actions are translated into typed web-view commands instead of stringly callbacks."
                ]
            )
        case .decentralizedProtocols:
            RuntimeFeatureExplanation(
                overview: "Recognizes decentralized web, app distribution, and storage URIs before search fallback, including IPFS, IPNS, ENS, Swarm, Arweave, Filecoin, Walrus, Iroh, Hypercore, Sia, Storj, Tahoe-LAFS, Autonomi, BitTorrent/WebTorrent, Ceramic, OrbitDB, and Radicle.",
                bridgeBehavior: "Today the iOS bridge resolves to content-loadable URLs for IPFS/IPNS through dweb.link, ENS through .limo, Swarm through gateway.ethswarm.org, Arweave through arweave.net, Filecoin data CIDs through the IPFS-compatible gateway path, Walrus blob IDs through the configured Walrus aggregator, and magnet links that include HTTP web seeds. Other Filecoin locators plus Iroh, Hypercore, Sia, Storj, Tahoe-LAFS, Autonomi, BitTorrent/WebTorrent without web seeds, Ceramic, OrbitDB, and Radicle route through protocol-specific local native adapter endpoints before any configured remote resolver is considered. This preserves the embedded light-client contract for chain-backed state: Ethereum and Substrate/Polkadot resolution must graduate to local verification instead of trusting centralized RPC endpoints.",
                detailPoints: [
                    "ipfs:// and ipns:// inputs are converted into HTTPS gateway paths before WKWebView loads them.",
                    "bzz://, swarm://, ar://, arweave://, Filecoin data-CID, Walrus blob-ID, and HTTP-web-seeded magnet inputs can resolve through content-loadable gateway adapters while keeping their original decentralized source label.",
                    "Protocols that require peer discovery, user credentials, private capabilities, or daemon state route to local native adapter endpoints with the original URI, network id, scheme, adapter id, locator, native issue, credential-scope flag, and resolution stage preserved for auditability.",
                    "If a local native adapter endpoint is disabled and a remote storage resolver base URL is explicitly configured, the same protocol metadata is handed to that configured resolver as an opt-in fallback.",
                    "Each adapter records the native verification target, such as CAR roots, blob hashes, signed feeds, encrypted object checksums, Tahoe capabilities, infohashes, DID commits, operation logs, or signed repository refs.",
                    "ENS-style names are intercepted before the generic HTTPS fallback so they can use decentralized resolution rules.",
                    "Embedded light clients verify block headers and essential proofs locally for chain-backed resolution, wallet state, transaction broadcast, and AFM settlement checks.",
                    "External RPC endpoints should remain development or fallback transports; they should not become the trust root for decentralized browsing.",
                    "Resolution results preserve a clear source, making it possible to show whether content came from native, light-client, gateway, or remote runtime resolution."
                ]
            )
        case .architectureOverview:
            RuntimeFeatureExplanation(
                overview: "Explains how the Swift browser shell, embedded blockchain light clients, AF Market, AFM services, ZeroK, and the LLM Gateway fit together.",
                bridgeBehavior: "The iOS shell keeps navigation, history, wallet policy, and selected context local; embedded light clients verify chain state; AF Market routes work through AFM router, registry, and pipelines; privacy-sensitive LLM calls use the ZeroK LLM Gateway path documented in ../ZeroK.",
                detailPoints: [
                    "Embedded Ethereum-compatible and Substrate/Polkadot light clients are the chain-trust layer: they verify headers and essential proofs locally for ENS, wallet state, transaction broadcast, escrow status, and proof settlement.",
                    "Each blockchain needs its own light-client verifier and consensus rules; routing every chain through a centralized RPC provider would collapse the decentralized trust boundary.",
                    "AF Market is the pack discovery and install surface. The AFM router selects an expert or pack, registry supplies deterministic metadata and signing keys, and pipelines queues the selected work.",
                    "ZeroK LLM Gateway calls are sent as encrypted envelopes with token-class padding and ZK-ready usage tickets, so relays cannot read prompts and billing authorization can be proven without revealing identity.",
                    "The optional privacy relay hides the client IP from the gateway, while the gateway still decrypts for provider-bound inference and enforces replay protection with nullifiers.",
                    "The visible HTTPS starting points are https://zerok.cloud for ZeroK and https://llmos.showntell.dev for the LLM Gateway and LLM OS surface.",
                    "The app should send only selected, redacted page context to the gateway; browser history, long-term memory, and tab state remain in the Swift app unless a user action shares them.",
                    "Provider boundary: upstream LLM infrastructure can still correlate decrypted prompt content and timing unless future confidential inference or enclave-backed execution is added."
                ]
            )
        case .chainTrust:
            RuntimeFeatureExplanation(
                overview: "Reports chain trust state through one Swift registry for browser resolution, wallet state, Copilot actions, and AFM settlement evidence.",
                bridgeBehavior: "The current bridge labels gateway/RPC fallback separately from proof-checked settlement evidence and future embedded light-client verification.",
                detailPoints: [
                    "Bitcoin, Ethereum/EVM/L2s, Solana, Cosmos/Tendermint, Polkadot/Substrate, Avalanche, TRON, XRP Ledger, Sui, and Aptos report through the same status model.",
                    "Bitcoin has a Swift light-client contract for SPV header sync, BIP157/158 compact-filter readiness, Merkle inclusion checks, stale peers, and reorg transitions.",
                    "Gateway or RPC data stays marked as fallback and is not presented as local verification.",
                    "AFMarket settlement receipts can raise a chain entry to proof-checked without implying full light-client verification.",
                    "Future chain-specific clients can plug in verified, syncing, stale, failed, and unavailable states without changing UI contracts."
                ]
            )
        case .mcpServers:
            RuntimeFeatureExplanation(
                overview: "Connects Model Context Protocol servers so Copilot and future agent workflows can use external tools, resources, and prompts.",
                bridgeBehavior: "The Swift bridge keeps editable MCP server configuration and connection state in app state today; the same contract can be backed by the desktop MCP profile service later.",
                detailPoints: [
                    "HTTP, WebSocket, and STDIO transports are modeled explicitly so endpoint and program validation match the desktop manifest shape.",
                    "Disabled servers stay inert until the user enables and connects them.",
                    "Connection results record status text and discovered tool names so the UI can show negotiated capability readiness.",
                    "Secrets should move through the existing encrypted MCP profile/keyring service before production use."
                ]
            )
        case .a2uiRendering:
            RuntimeFeatureExplanation(
                overview: "Offers an A2UI App Store for installing A2UI-powered apps, then renders each app's A2UI v0.9 token stream as native SwiftUI widgets through the imported a2ui-swift renderer.",
                bridgeBehavior: "The A2UI panel keeps app catalog, install, open, and runtime selection state in Swift, feeds installed app tokens or raw LLM/gateway output into A2UIStreamParser, processes decoded A2uiMessage values with SurfaceViewModel, renders the result through A2UISurfaceView, and keeps the selected runtime profile available for action routing.",
                detailPoints: [
                    "The App Store catalog exposes installable A2UI apps with categories, runtime profile IDs, required capabilities, install notes, sample prompts, and preview token streams.",
                    "The app links A2UISwiftCore for token parsing, schema decoding, and surface state.",
                    "The app links A2UISwiftUI for the native widget catalog including text, cards, rows, columns, text fields, and buttons.",
                    "Resolved button actions are logged locally today and can be routed through the same approval boundaries used by Copilot, wallet, MCP, ZeroK, and LLM Gateway flows.",
                    "A2UI apps can stay in the native SwiftUI profile or target Logos Basecamp when they need decentralized storage, messaging, blockchain, wallet, or AI-inspection modules.",
                    "A2UI apps can target Aztec Network when they need PXE-backed private execution, Noir smart contracts, private state, public state, or Ethereum L1/L2 messaging.",
                    "The renderer is isolated behind a Swift wrapper so future tokens from https://zerok.cloud and https://llmos.showntell.dev can use the same surface contract."
                ]
            )
        case .logosRuntime:
            RuntimeFeatureExplanation(
                overview: "Offers Logos Basecamp as the local-first, decentralised runtime profile for A2UI apps that need modular storage, messaging, blockchain, wallet, and AI-inspection capabilities.",
                bridgeBehavior: "The Swift app currently exposes the Logos runtime as a selectable A2UI profile with Basecamp launch and isolation guidance; the next bridge layer should start or attach to Logos modules instead of treating it as an external web page.",
                detailPoints: [
                    "Logos Basecamp lives at https://github.com/logos-co/logos-basecamp and the full docs live at https://github.com/logos-co/logos-docs.",
                    "Basecamp starts the Logos core runtime and loads configured module profiles for decentralized apps.",
                    "The Logos networking layer covers discovery, peering, and mixnet routing so capability discovery is not pinned to a centralized registry.",
                    "Important modules for dBrowser A2UI apps are Storage, Messaging / Logos Delivery, Blockchain / Execution Zone, and LEZ Wallet flows for private and public state.",
                    "Use nix build '.#bin-macos-app' and open result/LogosBasecamp.app for the macOS bundle, or use LogosBasecamp --user-dir <path> / LOGOS_USER_DIR=<path> for isolated app profiles.",
                    "Basecamp also exposes MCP/QML Inspector support, which lines up with the app's MCP server UI and AI assistant control surface."
                ]
            )
        case .aztecProtocol:
            RuntimeFeatureExplanation(
                overview: "Offers Aztec Network as the privacy-first Ethereum L2 protocol profile for A2UI apps that need private smart contracts, private state, public state, and proof-backed settlement.",
                bridgeBehavior: "The Swift app currently exposes Aztec as a selectable A2UI profile with local-network, Aztec.js, Aztec.nr, PXE, and MCP guidance; the next bridge layer should embed or broker PXE and wallet access instead of only launching external tooling.",
                detailPoints: [
                    "Aztec docs live at https://docs.aztec.network/ and the monorepo lives at https://github.com/AztecProtocol/aztec-packages.",
                    "Aztec is a privacy-first Layer 2 zkRollup on Ethereum, not EVM compatible, with a privacy-preserving virtual machine for private and public execution.",
                    "Private functions execute and prove on the user's device through the Private Execution Environment (PXE), while public functions execute in the Aztec Virtual Machine.",
                    "PXE stores secrets, notes, nullifier keys, incoming viewing keys, outgoing viewing keys, tagging keys, and private proof inputs locally.",
                    "Aztec.nr is the Noir framework for contracts; use the aztec CLI wrapper with aztec compile and aztec test rather than direct nargo compile or nargo test for Aztec contracts.",
                    "Aztec.js communicates with PXE for accounts, contract deployment, reads, and transactions; current docs use @aztec/aztec.js@4.2.0 for the alpha/testnet line.",
                    "The network path includes permissionless sequencers, decentralized provers, rollup proofs posted to Ethereum, and L1 to L2 messaging.",
                    "Aztec publishes AI tooling guidance, docs llms.txt, @aztec/mcp-server, noir-mcp-server, and Aztec/Noir skill references for current protocol context."
                ]
            )
        case .afmServices:
            RuntimeFeatureExplanation(
                overview: "Connects the Swift shell to the AFM router, registry, and pipelines services from the shared workspace.",
                bridgeBehavior: "The bridge checks service health, reads pack metadata, asks the router for a Copilot selection, and enqueues work in pipelines when endpoints are reachable.",
                detailPoints: [
                    "Router calls use the same /route contract as the workspace service.",
                    "Registry calls load pack metadata so mobile status reflects the available AFM catalog.",
                    "Pipelines calls queue service-backed Copilot jobs while keeping a local fallback for offline development."
                ]
            )
        case .copilot:
            RuntimeFeatureExplanation(
                overview: "Creates a mobile command surface for Copilot tasks tied to the active browsing context.",
                bridgeBehavior: "The bridge routes through AFM services when available and falls back to deterministic local summaries when those services are offline.",
                detailPoints: [
                    "Prompts can carry the active page URL so Copilot has a target for future page-context extraction.",
                    "Suggested actions stay explicit so wallet and download operations can remain approval-gated.",
                    "The bridge API is asynchronous, matching the shape needed for real model runs and cancellation."
                ]
            )
        case .wallet:
            RuntimeFeatureExplanation(
                overview: "Models wallet connection state and spend-policy decisions for browser actions.",
                bridgeBehavior: "The current iOS bridge is a local policy simulator; it does not custody production keys yet.",
                detailPoints: [
                    "Connect and disconnect actions update a typed wallet state object.",
                    "Spend evaluation rejects invalid requests and requires explicit approval above the local policy limit.",
                    "The same contract can be backed by Secure Enclave keys, WalletConnect, or a desktop wallet bridge."
                ]
            )
        case .downloads:
            RuntimeFeatureExplanation(
                overview: "Starts, tracks, cancels, and completes browser downloads through native iOS networking.",
                bridgeBehavior: "The bridge stores download items in Swift state and uses URLSession for real transfer work.",
                detailPoints: [
                    "Queued mode lets tests and future approval flows create download records without touching the network.",
                    "Completed files are moved into the app temporary directory with the response filename when available.",
                    "Cancellation and failures update typed states so the UI can avoid pretending unsupported actions worked."
                ]
            )
        }
    }
}

enum BrowserAddressResolution: Equatable {
    case home
    case web(URL)
    case unsupported(raw: String, message: String)
}

enum BrowserURLResolver {
    static let homeURLString = "about:home"
    static let defaultSearchEndpoint = "https://duckduckgo.com/"

    static func resolve(_ rawInput: String) -> BrowserAddressResolution {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return .home
        }

        if input.caseInsensitiveCompare(homeURLString) == .orderedSame || input.caseInsensitiveCompare("about:blank") == .orderedSame {
            return .home
        }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return .web(url)
            case "ens":
                return .unsupported(
                    raw: input,
                    message: "The iOS runtime bridge will resolve this decentralized name."
                )
            default:
                if let profile = DecentralizedStorageNetwork.profile(forScheme: scheme) {
                    return .unsupported(
                        raw: input,
                        message: "The iOS runtime bridge will resolve this \(profile.title) URI."
                    )
                }

                return .unsupported(
                    raw: input,
                    message: "The iOS runtime bridge is preserving this \(scheme): URI until a native handler is registered."
                )
            }
        }

        if looksLikeDecentralizedName(input) {
            return .unsupported(
                raw: input,
                message: "The iOS runtime bridge could not resolve this decentralized name."
            )
        }

        if looksLikeHost(input), let url = URL(string: "https://\(input)") {
            return .web(url)
        }

        return .web(searchURL(for: input))
    }

    private static func looksLikeHost(_ input: String) -> Bool {
        guard !input.contains(" ") else { return false }
        guard input.contains(".") || input.caseInsensitiveCompare("localhost") == .orderedSame else { return false }
        return true
    }

    private static func looksLikeDecentralizedName(_ input: String) -> Bool {
        let lowercased = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.contains(" ") else { return false }
        let name = lowercased.split(separator: "/").first.map(String.init) ?? lowercased
        return [".eth", ".crypto", ".blockchain"].contains { name.hasSuffix($0) }
    }

    private static func searchURL(for query: String) -> URL {
        var components = URLComponents(string: defaultSearchEndpoint)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }
}
