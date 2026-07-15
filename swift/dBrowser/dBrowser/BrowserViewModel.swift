import Foundation
import Combine

private struct PendingFreshCopilotContext {
    let runID: UUID
    let prompt: String
    let tabID: UUID
    let targetURLString: String
    let conversationID: UUID
    let model: LLMModelProfile
    let relatedTabIDs: [UUID]
    let navigationGeneration: UInt64
    let fileAttachments: [LLMTextFileAttachment]
    let sourceMessageID: UUID?
    let regeneratedFromMessageID: UUID?
}

private struct PageSnapshotCaptureContext {
    let tabID: UUID
    let targetURLString: String
    let navigationGeneration: UInt64
}

private struct CopilotRunPageBinding {
    let tabID: UUID
    let targetPageCommitment: String
    let navigationGeneration: UInt64
}

private enum CopilotRunContextPolicy {
    case standard
    case disclosedResearchSourcesOnly
}

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var tabs: [BrowserTab]
    @Published var activeTabID: UUID
    @Published var addressText: String
    @Published var selectedPanel: BrowserPanel?
    @Published var history: [BrowserHistoryEntry] = []
    @Published var bookmarks: [BrowserBookmark] = BrowserBookmark.defaults
    @Published var webCommand: BrowserWebCommandRequest?
    @Published var automationRequest: BrowserAutomationRequest?
    @Published var adBlockingMode: BrowserAdBlockingMode
    @Published var automationResults: [BrowserAutomationResult] = []
    @Published var latestDOMQueryResult: DOMQueryResult?
    @Published var latestPageSnapshot: PageSnapshot?
    @Published var latestTextSelection: BrowserTextSelection?
    @Published private(set) var pageSnapshotsByTabID: [UUID: PageSnapshot] = [:]
    @Published private(set) var selectedCopilotContextTabIDs: Set<UUID> = []
    @Published private(set) var inactiveTabCaptureState: InactiveTabCaptureState = .idle
    @Published var copilotRuns: [CopilotRun] = []
    @Published private(set) var copilotRunPresentations: [UUID: CopilotRunPresentation] = [:]
    @Published private(set) var copilotToolProposals: [CopilotToolProposal] = []
    @Published var copilotWorkflows: [SavedCopilotWorkflow] = []
    @Published private(set) var scheduledWorkflowStates: [CopilotScheduledWorkflowState] = []
    @Published var researchLedgers: [BrowserResearchLedger] = []
    @Published private(set) var searchSessionsByTabID: [UUID: BrowserSearchSession] = [:]
    @Published private(set) var researchSynthesisResultsBySessionID: [UUID: BrowserResearchSynthesisResult] = [:]
    @Published private(set) var researchSynthesisErrorsBySessionID: [UUID: String] = [:]
    @Published var developerWorkflowRuns: [BrowserDeveloperWorkflowRun] = []
    @Published var runtimeFeatureStates: [RuntimeFeatureState]
    @Published var chainTrustSnapshot: ChainTrustRegistry
    @Published var afmServiceSnapshot: AFMServiceSnapshot
    @Published var llmRouterServiceSnapshot: LLMRouterServiceSnapshot
    @Published var llmGatewayServiceSnapshot: LLMGatewayServiceSnapshot
    @Published var walletPortfolio: WalletPortfolioSnapshot
    @Published var mcpServers: [MCPServerConfiguration]
    @Published var selectedAFMPackID: String?
    @Published var afmTrainingJobs: [AFMExpertTrainingJob]
    @Published var latestAFMA2ACallResult: AFMA2ACallResult?
    @Published var openMindCapabilityState: OpenMindMemoryCapabilityState
    @Published var openMindContinuityState: OpenMindContinuityState
    @Published var openMindPostureState: OpenMindPostureState
    @Published var openMindReviewTasks: [OpenMindReviewTask]
    @Published var latestOpenMindRecall: OpenMindMemoryRecallResult?
    @Published var latestOpenMindStepUpRequest: OpenMindStepUpRequest?
    @Published var latestOpenMindWriteback: OpenMindWritebackOutcome?
    @Published var latestOpenMindCorrection: OpenMindCorrectionOutcome?
    @Published var llmConversation: LLMConversation
    @Published private(set) var llmConversations: [LLMConversation]
    @Published var llmModelOptions: [LLMModelProfile]
    @Published var selectedLLMModelID: String
    @Published var localLLMState: LocalLLMManagementState
    @Published var latestLLMGatewayTokenPurchase: LLMGatewayTokenPurchaseReceipt?
    @Published var llmGatewayTokenPurchaseError: String?
    @Published var isBuyingLLMGatewayTokens: Bool = false

    /// The Hyperactive Web navigation fabric (UIK): discovers service cards from
    /// `/.well-known/agent-card.json` as the user navigates and renders their
    /// capability surfaces. `nil` if its retention store could not be opened.
    @Published var hyperactiveWeb: HyperactiveWebCoordinator?

    /// Most-recently-created view model, used so App Intents can reach the live
    /// browser for foreground-only system handoffs.
    static weak var shared: BrowserViewModel?

    let runtimeBridge: MobileRuntimeBridge
    let connectorCoordinator: BrowserConnectorCoordinator
    private let workflowStore: CopilotWorkflowStore
    private let researchLedgerStore: ResearchLedgerStore
    private let browserSearchService: any BrowserSearchServicing
    private let developerWorkflowStore: DeveloperWorkflowStore
    private let historyService: BrowserHistoryService
    private let llmConversationStore: LLMConversationStore
    private var llmConversationArchive: LLMConversationStorePayload
    private let openMindMemoryClient: OpenMindMemoryClient
    private let localLLMManager: LocalLLMManaging
    private let adBlockingDefaults: UserDefaults
    private let freshCopilotContextTimeoutSeconds: TimeInterval
    private let automationRequestTimeoutSeconds: TimeInterval
    private var copilotTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingFreshCopilotContexts: [UUID: PendingFreshCopilotContext] = [:]
    private var freshCopilotContextTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var automationTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var pageNavigationGenerations: [UUID: UInt64] = [:]
    private var pageSnapshotCaptureContexts: [UUID: PageSnapshotCaptureContext] = [:]
    private var inactiveTabCaptureRequestID: UUID?
    private var toolProposalByAutomationRequestID: [UUID: UUID] = [:]
    private var pageBindingByCopilotRunID: [UUID: CopilotRunPageBinding] = [:]
    private var workflowByCopilotRunID: [UUID: UUID] = [:]
    private var everyLaunchWorkflowIDsRunThisSession: Set<UUID> = []
    private var sourceMessageByCopilotRunID: [UUID: UUID] = [:]
    private var regeneratedAssistantByCopilotRunID: [UUID: UUID] = [:]
    private var workflowMonitorTask: Task<Void, Never>?
    private var searchTasksByTabID: [UUID: Task<Void, Never>] = [:]
    private var pendingResearchSynthesisByRunID: [UUID: (sessionID: UUID, request: BrowserResearchSynthesisRequest)] = [:]
    private var terminalAutomationRequestIDs: Set<UUID> = []
    private var terminalAutomationRequestOrder: [UUID] = []
    private var approvedAutomationDispatchOwners: [UUID: UUID] = [:]
    private static let maximumRelatedCopilotTabs = 4
    private static let maximumTerminalAutomationRequestIDs = 512

    convenience init(initialURL: String = "about:home") {
        self.init(initialURL: initialURL, runtimeBridge: MobileRuntimeBridge())
    }

    init(
        initialURL: String,
        runtimeBridge: MobileRuntimeBridge,
        copilotWorkflowStore: CopilotWorkflowStore = CopilotWorkflowStore(),
        researchLedgerStore: ResearchLedgerStore = ResearchLedgerStore(),
        browserSearchService: (any BrowserSearchServicing)? = nil,
        connectorCoordinator: BrowserConnectorCoordinator? = nil,
        developerWorkflowStore: DeveloperWorkflowStore = DeveloperWorkflowStore(),
        smartHistoryStore: SmartHistoryStore = SmartHistoryStore(),
        llmConversationStore: LLMConversationStore = LLMConversationStore(),
        openMindMemoryClient: OpenMindMemoryClient? = nil,
        localLLMManager: LocalLLMManaging? = nil,
        adBlockingDefaults: UserDefaults = .standard,
        adBlockingMode: BrowserAdBlockingMode? = nil,
        freshCopilotContextTimeoutSeconds: TimeInterval = 5,
        automationRequestTimeoutSeconds: TimeInterval = 3
    ) {
        let tab = BrowserTab(urlString: initialURL)
        let historyService = BrowserHistoryService(store: smartHistoryStore)
        let initialLLMModelOptions = LLMModelRegistry.models(
            afmSnapshot: runtimeBridge.afmServiceSnapshot,
            llmRouterSnapshot: runtimeBridge.llmRouterServiceSnapshot,
            llmGatewaySnapshot: runtimeBridge.llmGatewayServiceSnapshot
        )
        var restoredLLMArchive = llmConversationStore.load()
        let reconciliation = Self.reconcileRestoredToolProposals(in: restoredLLMArchive)
        restoredLLMArchive = reconciliation.payload
        let restoredLLMState = Self.restoredLLMState(
            from: restoredLLMArchive,
            models: initialLLMModelOptions
        )
        restoredLLMArchive.upsertConversation(restoredLLMState.conversation, select: true)
        restoredLLMArchive.selectedModelID = restoredLLMState.selectedModelID
        self.runtimeBridge = runtimeBridge
        self.connectorCoordinator = connectorCoordinator ?? BrowserConnectorCoordinator()
        self.workflowStore = copilotWorkflowStore
        self.researchLedgerStore = researchLedgerStore
        self.browserSearchService = browserSearchService ?? BrowserJSONSearchClient()
        self.developerWorkflowStore = developerWorkflowStore
        self.historyService = historyService
        self.llmConversationStore = llmConversationStore
        self.llmConversationArchive = restoredLLMArchive
        self.openMindMemoryClient = openMindMemoryClient ?? OpenMindMemoryClient()
        self.localLLMManager = localLLMManager ?? LocalLLMManager()
        self.adBlockingDefaults = adBlockingDefaults
        self.freshCopilotContextTimeoutSeconds = max(0.01, freshCopilotContextTimeoutSeconds)
        self.automationRequestTimeoutSeconds = max(0.01, automationRequestTimeoutSeconds)
        self.adBlockingMode = adBlockingMode ?? BrowserAdBlockingSettings.load(defaults: adBlockingDefaults)
        self.runtimeFeatureStates = runtimeBridge.featureStates
        self.chainTrustSnapshot = runtimeBridge.chainTrustSnapshot
        self.afmServiceSnapshot = runtimeBridge.afmServiceSnapshot
        self.llmRouterServiceSnapshot = runtimeBridge.llmRouterServiceSnapshot
        self.llmGatewayServiceSnapshot = runtimeBridge.llmGatewayServiceSnapshot
        self.walletPortfolio = runtimeBridge.walletPortfolio
        self.mcpServers = runtimeBridge.mcpServers
        self.afmTrainingJobs = runtimeBridge.afmTrainingJobs
        self.latestAFMA2ACallResult = runtimeBridge.latestAFMA2ACallResult
        self.openMindCapabilityState = .disabled
        self.openMindContinuityState = .disabled
        self.openMindPostureState = .disabled
        self.openMindReviewTasks = []
        self.llmModelOptions = initialLLMModelOptions
        self.selectedLLMModelID = restoredLLMState.selectedModelID
        self.llmConversation = restoredLLMState.conversation
        self.llmConversations = restoredLLMArchive.conversations
        self.copilotToolProposals = Array(restoredLLMState.conversation.toolProposals.reversed())
        self.localLLMState = self.localLLMManager.currentState
        self.tabs = [tab]
        self.activeTabID = tab.id
        self.addressText = initialURL
        self.history = historyService.initialHistory
        self.copilotWorkflows = copilotWorkflowStore.load()
        self.researchLedgers = researchLedgerStore.load()
        self.developerWorkflowRuns = developerWorkflowStore.load()
        if restoredLLMState.shouldPersist || reconciliation.didChange {
            persistLLMConversation()
        }
        self.hyperactiveWeb = try? HyperactiveWebCoordinator(
            mcpServers: runtimeBridge.mcpServers,
            rootDirectory: Self.hyperactiveWebRoot(),
            openMind: self.openMindMemoryClient
        )
        self.hyperactiveWeb?.walletAuthorize = { [weak self] requirement in
            guard let self else { return nil }
            return await self.authorizeHyperactiveWebPayment(requirement)
        }
        Self.shared = self
        DBrowserAppIntentHandoffCenter.drainPendingHandoffs(into: self)
    }

    /// On-disk retention root for the Hyperactive Web (durable artifacts +
    /// OpenMind mirror provenance).
    private static func hyperactiveWebRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("dBrowser/HyperactiveWeb", isDirectory: true)
    }

    func authorizeHyperactiveWebPayment(_ requirement: X402PaymentRequirement) async -> X402PaymentPayload? {
        guard let payload = await authorizeX402Payment(
            requirement,
            reason: "Hyperactive Web x402 payment for \(requirement.resourceURLString)"
        ) else {
            return nil
        }
        guard Self.hyperactiveWebPaymentPolicyAllows(requirement: requirement, payload: payload) else {
            return nil
        }
        return payload
    }

    func refreshLLMGatewayTokenPackages() async {
        let snapshot = await runtimeBridge.refreshLLMGatewayTokenPackages()
        llmGatewayServiceSnapshot = snapshot
        runtimeFeatureStates = runtimeBridge.featureStates
        llmModelOptions = LLMModelRegistry.models(
            afmSnapshot: afmServiceSnapshot,
            llmRouterSnapshot: llmRouterServiceSnapshot,
            llmGatewaySnapshot: snapshot
        )
        normalizeSelectedLLMModelIfNeeded()
    }

    @discardableResult
    func buyLLMGatewayTokens(packageID: String) async -> LLMGatewayTokenPurchaseReceipt? {
        guard isBuyingLLMGatewayTokens == false else { return nil }
        isBuyingLLMGatewayTokens = true
        llmGatewayTokenPurchaseError = nil
        defer { isBuyingLLMGatewayTokens = false }

        let snapshot = await runtimeBridge.refreshLLMGatewayTokenPackages()
        llmGatewayServiceSnapshot = snapshot
        guard let package = snapshot.tokenPackages.first(where: { $0.id == packageID }) else {
            llmGatewayTokenPurchaseError = "LLM Gateway token package is no longer available."
            return nil
        }

        let resourceURLString = package.purchaseURLString ?? "llm-gateway://tokens/\(package.id)"
        let requirement = package.x402Requirement(resourceURLString: resourceURLString)
        guard let paymentPayload = await authorizeX402Payment(
            requirement,
            reason: "LLM Gateway token purchase for \(package.displayName)"
        ) else {
            llmGatewayTokenPurchaseError = "Wallet policy did not authorize the LLM Gateway token purchase."
            walletPortfolio = runtimeBridge.walletPortfolio
            runtimeFeatureStates = runtimeBridge.featureStates
            return nil
        }

        do {
            let receipt = try await runtimeBridge.purchaseLLMGatewayTokens(
                package: package,
                paymentPayload: paymentPayload
            )
            latestLLMGatewayTokenPurchase = receipt
            llmGatewayServiceSnapshot = runtimeBridge.llmGatewayServiceSnapshot
            walletPortfolio = runtimeBridge.walletPortfolio
            runtimeFeatureStates = runtimeBridge.featureStates
            llmModelOptions = LLMModelRegistry.models(
                afmSnapshot: afmServiceSnapshot,
                llmRouterSnapshot: llmRouterServiceSnapshot,
                llmGatewaySnapshot: llmGatewayServiceSnapshot
            )
            normalizeSelectedLLMModelIfNeeded()
            return receipt
        } catch {
            llmGatewayTokenPurchaseError = error.localizedDescription
            return nil
        }
    }

    private func authorizeX402Payment(
        _ requirement: X402PaymentRequirement,
        reason: String
    ) async -> X402PaymentPayload? {
        guard requirement.expiresAt > Date(),
              requirement.amountMinorUnits > 0,
              !requirement.payTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let chainRef = Self.hyperactiveWebChainRef(for: requirement.network, portfolio: runtimeBridge.walletPortfolio)
        else { return nil }

        let transfer = WalletTransferRequest(
            chainRef: chainRef,
            amount: Self.hyperactiveWebPaymentAmount(fromMinorUnits: requirement.amountMinorUnits),
            asset: requirement.asset,
            destination: requirement.payTo,
            memo: requirement.facilitatorURLString,
            reason: reason
        )
        let preview = await runtimeBridge.previewWalletTransfer(transfer)
        guard preview.status == .ready else { return nil }

        let receipt = await runtimeBridge.signWalletTransfer(transfer)
        walletPortfolio = runtimeBridge.walletPortfolio
        runtimeFeatureStates = runtimeBridge.featureStates
        guard receipt.status == .policySigned, let signatureDigest = receipt.signatureDigest else { return nil }
        return X402PaymentPayload(
            requirementHash: requirement.requirementHash,
            walletAccount: receipt.fromAddress,
            transactionReference: receipt.transactionHash,
            signatureReference: "wallet-policy:\(signatureDigest)"
        )
    }

    static func hyperactiveWebChainRef(for network: String, portfolio: WalletPortfolioSnapshot) -> String? {
        let normalized = network
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard !normalized.isEmpty else { return portfolio.activeChainRef }
        if portfolio.network(forChainRef: normalized) != nil { return normalized }

        let aliases = [
            "eth": "ethereum-mainnet",
            "ethereum": "ethereum-mainnet",
            "ethereum-mainnet": "ethereum-mainnet",
            "mainnet": "ethereum-mainnet",
            "base": "base-mainnet",
            "base-mainnet": "base-mainnet",
            "base-sepolia": "base-sepolia",
            "arbitrum": "arbitrum-one",
            "arbitrum-one": "arbitrum-one",
            "optimism": "optimism-mainnet",
            "optimism-mainnet": "optimism-mainnet",
            "polygon": "polygon-mainnet",
            "polygon-mainnet": "polygon-mainnet",
            "matic": "polygon-mainnet",
            "bnb": "bnb-smart-chain",
            "bsc": "bnb-smart-chain",
            "bnb-smart-chain": "bnb-smart-chain",
            "avalanche": "avalanche-c",
            "avalanche-c": "avalanche-c"
        ]
        if let chainRef = aliases[normalized], portfolio.network(forChainRef: chainRef) != nil {
            return chainRef
        }

        return portfolio.networks.first { network in
            network.chainRef.contains(normalized) || network.displayName.lowercased().contains(normalized)
        }?.chainRef
    }

    static func hyperactiveWebPaymentAmount(fromMinorUnits minorUnits: Int, decimals: Int = 2) -> Decimal {
        let scale = Decimal(pow(10.0, Double(decimals)))
        return Decimal(minorUnits) / scale
    }

    static func hyperactiveWebPaymentPolicyAllows(
        requirement: X402PaymentRequirement,
        payload: X402PaymentPayload,
        now: Date = Date()
    ) -> Bool {
        let intent = AgenticPaymentIntent(
            id: "hyperactive-web-\(requirement.id)",
            objective: "Authorize Hyperactive Web x402 payment for \(requirement.resourceURLString)",
            merchantID: URL(string: requirement.resourceURLString)?.host ?? requirement.payTo,
            counterpartyID: requirement.payTo,
            amountMinorUnits: requirement.amountMinorUnits,
            currencyOrAsset: requirement.asset,
            protocolName: .x402,
            risk: .low,
            pageSnapshotHash: requirement.requirementHash,
            expiresAt: requirement.expiresAt,
            recurringPolicy: nil
        )
        let review = AgenticPaymentReview(
            id: "review-\(intent.id)",
            intent: intent,
            eudiDecision: nil,
            visaTrustedAgent: nil,
            acpCheckout: nil,
            ap2Mandates: [],
            x402Requirement: requirement,
            x402Payload: payload,
            notabeneTransfer: nil,
            userApproved: true
        )
        return AgenticPaymentPolicyEngine.evaluate(review, now: now).kind == .allow
    }

    var activeTabIndex: Int? {
        tabs.firstIndex { $0.id == activeTabID }
    }

    var activeTab: BrowserTab? {
        guard let index = activeTabIndex else { return nil }
        return tabs[index]
    }

    func navigationGeneration(for tabID: UUID) -> UInt64 {
        pageNavigationGenerations[tabID] ?? 0
    }

    var canAttachActivePageToCopilotContext: Bool {
        activeTab.map { isCopilotContextEligible($0) && !$0.isLoading } == true
    }

    var isWaitingForActivePageContext: Bool {
        activeTab.map { isCopilotContextEligible($0) && $0.isLoading } == true
    }

    var canRequestActivePageSnapshot: Bool {
        canAttachActivePageToCopilotContext
            && activeTab?.isLoading == false
            && pendingFreshCopilotContexts.isEmpty
            && automationRequest == nil
    }

    var canSendCopilotMessageWithFreshContext: Bool {
        guard let tab = activeTab else { return false }
        guard isCopilotContextEligible(tab) else { return true }
        return !tab.isLoading && pendingFreshCopilotContexts.isEmpty && automationRequest == nil
    }

    var copilotContextTabOptions: [CopilotContextTabOption] {
        tabs.compactMap { tab in
            guard tab.id != activeTabID, isCopilotContextEligible(tab) else { return nil }
            let hasCurrentSnapshot = currentPageSnapshot(for: tab) != nil
            return CopilotContextTabOption(
                id: tab.id,
                title: tab.title,
                displayURL: LLMPageContextSanitizer.sanitizedURLString(tab.displayURL),
                isSelected: hasCurrentSnapshot && selectedCopilotContextTabIDs.contains(tab.id),
                isAvailable: hasCurrentSnapshot,
                availabilityLabel: hasCurrentSnapshot
                    ? "Ready to share"
                    : "Capture this tab before selecting it"
            )
        }
    }

    func setCopilotContextTab(_ id: UUID, isSelected: Bool) {
        if !isSelected {
            selectedCopilotContextTabIDs.remove(id)
            return
        }

        guard
            selectedCopilotContextTabIDs.count < Self.maximumRelatedCopilotTabs,
            let tab = tabs.first(where: { $0.id == id }),
            tab.id != activeTabID,
            isCopilotContextEligible(tab),
            currentPageSnapshot(for: tab) != nil
        else {
            return
        }
        selectedCopilotContextTabIDs.insert(id)
    }

    var canGoBack: Bool {
        activeTab?.canGoBack ?? false
    }

    var canGoForward: Bool {
        activeTab?.canGoForward ?? false
    }

    var unavailableFeatureCount: Int {
        runtimeFeatureStates.filter { !$0.isAvailable }.count
    }

    var activeCopilotRunCount: Int {
        copilotRuns.filter { $0.status == .queued || $0.status == .running }.count
    }

    var canChangeLLMConversation: Bool {
        automationRequest?.approvalGrant == nil
    }

    var availableAFMPacks: [AFMPackSummary] {
        afmServiceSnapshot.availablePacks
    }

    var afmPeerExperts: [AFMA2APeerExpert] {
        Self.uniquePeerExperts(afmServiceSnapshot.peerExperts + afmTrainingJobs.map(\.peerExpert))
            .sorted { $0.displayName < $1.displayName }
    }

    var activeLLMModel: LLMModelProfile {
        llmModelOptions.first { $0.id == selectedLLMModelID }
            ?? LLMModelRegistry.model(
                withID: selectedLLMModelID,
                afmSnapshot: afmServiceSnapshot,
                llmRouterSnapshot: llmRouterServiceSnapshot,
                llmGatewaySnapshot: llmGatewayServiceSnapshot
            )
            ?? LLMModelRegistry.models(
                afmSnapshot: afmServiceSnapshot,
                llmRouterSnapshot: llmRouterServiceSnapshot,
                llmGatewaySnapshot: llmGatewayServiceSnapshot
            )[0]
    }

    func activateTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if activeTabID != id {
            cancelPendingFreshCopilotRuns(boundTo: activeTabID, reason: "Active tab changed before its page snapshot was ready.")
            invalidateAutomationRequest(boundTo: activeTabID)
        }
        if selectedPanel != .copilot {
            selectedPanel = nil
        }
        activeTabID = id
        selectedCopilotContextTabIDs.remove(id)
        latestDOMQueryResult = nil
        latestTextSelection = nil
        latestPageSnapshot = nil
        latestPageSnapshot = activeTab.flatMap { currentPageSnapshot(for: $0) }
        addressText = activeTab?.urlString ?? BrowserURLResolver.homeURLString
    }

    func newTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        activateTab(tab.id)
    }

    func selectPanel(_ panel: BrowserPanel?) {
        selectedPanel = panel
    }

    @discardableResult
    func handleSystemHandoff(_ handoff: DBrowserAppIntentHandoff) -> String {
        switch handoff {
        case .openDestination(let destination):
            selectPanel(destination.panel)
            return "Opened \(destination.title) in dBrowser."
        case .startCopilotPrompt(let prompt):
            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            selectPanel(.copilot)
            guard !trimmedPrompt.isEmpty else {
                return "Opened dBrowser Copilot."
            }
            if sendLLMMessageWithFreshContext(trimmedPrompt) != nil {
                return "Started Copilot in dBrowser."
            }
            return "Could not start Copilot in dBrowser."
        case .runWorkflow(let id, let title):
            selectPanel(.copilot)
            guard copilotWorkflows.contains(where: { $0.id == id && $0.isEnabled }) else {
                return "“\(title)” is disabled or no longer exists."
            }
            if runWorkflow(id) != nil {
                return "Running “\(title)” in dBrowser."
            }
            return "Could not start “\(title)”."
        }
    }

    func closeTab(_ id: UUID) {
        searchTasksByTabID.removeValue(forKey: id)?.cancel()
        searchSessionsByTabID[id] = nil
        cancelCopilotRuns(boundTo: id, reason: "Target tab closed.")
        invalidateAutomationRequest(boundTo: id)
        invalidatePageSnapshotCaptures(boundTo: id)
        invalidatePageContext(for: id)
        pageNavigationGenerations[id] = nil
        guard tabs.count > 1 else {
            tabs[0] = BrowserTab(id: tabs[0].id)
            activeTabID = tabs[0].id
            addressText = tabs[0].urlString
            return
        }

        let wasActive = activeTabID == id
        tabs.removeAll { $0.id == id }
        if wasActive {
            activeTabID = tabs.first?.id ?? UUID()
            selectedCopilotContextTabIDs.remove(activeTabID)
            latestPageSnapshot = nil
            latestPageSnapshot = activeTab.flatMap { currentPageSnapshot(for: $0) }
            addressText = activeTab?.urlString ?? BrowserURLResolver.homeURLString
        }
    }

    func navigateFromAddress() {
        navigate(addressText)
    }

    func addressAutocompleteSuggestions(limit: Int = 6) -> [BrowserAddressSuggestion] {
        historyService.autocompleteSuggestions(matching: addressText, in: history, limit: limit)
    }

    func openAddressSuggestion(_ suggestion: BrowserAddressSuggestion) {
        navigate(suggestion.urlString)
    }

    func navigate(_ rawInput: String) {
        guard let index = activeTabIndex else { return }
        if selectedPanel != .copilot {
            selectedPanel = nil
        }
        cancelCopilotRuns(boundTo: tabs[index].id, reason: "Manual navigation took over the tab.")
        beginPageNavigation(
            for: tabs[index].id,
            reason: "Manual navigation invalidated the pending page capture."
        )

        switch BrowserURLResolver.resolve(rawInput) {
        case .home:
            tabs[index].title = "Home"
            tabs[index].urlString = BrowserURLResolver.homeURLString
            tabs[index].loadURLString = nil
            tabs[index].mobileNotice = nil
            tabs[index].isLoading = false
            tabs[index].isPrivateOverlay = false
            tabs[index].privateOverlayNetworkID = nil
            tabs[index].isTorrentTransfer = false
            tabs[index].torrentTransferNetworkID = nil
            addressText = BrowserURLResolver.homeURLString
            searchSessionsByTabID[tabs[index].id] = nil
        case .search(let query):
            startNativeSearch(query, tabID: tabs[index].id)
        case .web(let url):
            let title = titleForURL(url)
            tabs[index].title = title
            tabs[index].urlString = url.absoluteString
            tabs[index].loadURLString = nil
            tabs[index].mobileNotice = nil
            tabs[index].isLoading = true
            tabs[index].isPrivateOverlay = false
            tabs[index].privateOverlayNetworkID = nil
            tabs[index].isTorrentTransfer = false
            tabs[index].torrentTransferNetworkID = nil
            addressText = url.absoluteString
            recordHistory(title: title, urlString: url.absoluteString)
            probeHyperactiveWeb(url)
            searchSessionsByTabID[tabs[index].id] = nil
        case .privateOverlay(let raw, let network, let message):
            resolveThroughRuntimeBridge(raw: raw, fallbackMessage: message, tabID: tabs[index].id, privateOverlayNetwork: network)
        case .unsupported(let raw, let message):
            resolveThroughRuntimeBridge(raw: raw, fallbackMessage: message, tabID: tabs[index].id)
        }
    }

    private func startNativeSearch(_ query: String, tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        searchTasksByTabID[tabID]?.cancel()
        let session = BrowserSearchSession.loading(query: query)
        searchSessionsByTabID[tabID] = session
        researchSynthesisErrorsBySessionID[session.id] = nil
        tabs[index].title = "Search: \(SmartHistoryIndexer.boundedText(query, limit: 48))"
        var components = URLComponents()
        components.scheme = "about"
        components.path = "search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        tabs[index].urlString = components.string ?? "about:search"
        tabs[index].loadURLString = nil
        tabs[index].mobileNotice = nil
        tabs[index].isLoading = true
        tabs[index].isPrivateOverlay = false
        tabs[index].privateOverlayNetworkID = nil
        tabs[index].isTorrentTransfer = false
        tabs[index].torrentTransferNetworkID = nil
        addressText = query

        searchTasksByTabID[tabID] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await browserSearchService.search(BrowserSearchRequest(query: query))
                guard !Task.isCancelled,
                      searchSessionsByTabID[tabID]?.id == session.id else { return }
                searchSessionsByTabID[tabID] = session.applying(response)
                if let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) {
                    tabs[tabIndex].isLoading = false
                }
            } catch is CancellationError {
                guard searchSessionsByTabID[tabID]?.id == session.id else { return }
                var cancelled = session
                cancelled.status = .cancelled
                cancelled.completedAt = Date()
                searchSessionsByTabID[tabID] = cancelled
            } catch {
                guard searchSessionsByTabID[tabID]?.id == session.id else { return }
                let configurationRequired = (error as? BrowserSearchClientError) == .configurationRequired
                searchSessionsByTabID[tabID] = session.failing(
                    error.localizedDescription,
                    configurationRequired: configurationRequired
                )
                if let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) {
                    tabs[tabIndex].isLoading = false
                }
            }
            searchTasksByTabID[tabID] = nil
        }
    }

    func openSearchResult(_ result: BrowserSearchResult) {
        navigate(result.urlString)
    }

    @discardableResult
    func synthesizeSearchSession(tabID: UUID) -> UUID? {
        guard let session = searchSessionsByTabID[tabID],
              activeTabID == tabID,
              session.status == .completed,
              !session.results.isEmpty else { return nil }
        let request = BrowserResearchSynthesisRequest(
            query: session.query,
            sources: session.results.map { BrowserResearchSource(result: $0) }
        )
        guard !request.sources.isEmpty else { return nil }
        selectedPanel = .copilot
        let model = activeLLMModel
        let renderedContext = LLMRenderedConversationContext(
            prompt: request.prompt,
            includedMessageIDs: [],
            compressedMessageIDs: [],
            estimatedPromptTokens: LLMConversationContextRenderer.estimatedTokens(for: request.prompt),
            wasCompressed: false,
            snapshotCommitment: nil,
            memoryContextIDs: [],
            contextMinimization: model.contextMinimization
        )
        guard renderedContext.estimatedPromptTokens
                <= LLMConversationContextRenderer.effectiveTokenBudget(for: model) else {
            researchSynthesisErrorsBySessionID[session.id] = "The disclosed research sources exceed the selected model's input budget."
            return nil
        }
        let sourceCitations = request.sources.map { source in
            LLMSourceCitation(
                id: source.id,
                kind: .research,
                title: source.title,
                source: "native research search",
                urlString: source.urlString,
                excerpt: source.evidence
            )
        }
        let userMessage = LLMConversationMessage(
            role: .user,
            text: "Research: \(request.query)",
            sourceCitations: sourceCitations
        )
        let conversationBeforeResearch = llmConversation
        llmConversation.appendMessage(userMessage)
        llmConversation.appendEvent(
            LLMConversationEvent(
                kind: .userMessageAdded,
                message: "Added a source-only research synthesis request.",
                toModelID: model.id,
                relatedMessageID: userMessage.id
            )
        )
        llmConversation.appendEvent(
            LLMConversationEvent(
                kind: .researchSourcesAttached,
                message: "Attached \(sourceCitations.count) disclosed native-search source\(sourceCitations.count == 1 ? "" : "s"); page, memory, and prior conversation context are excluded from this run.",
                toModelID: model.id,
                relatedMessageID: userMessage.id
            )
        )
        guard let runID = startCopilotRun(
            prompt: request.prompt,
            conversationID: llmConversation.id,
            model: model,
            renderedContext: renderedContext,
            recordsAssistantMessage: true,
            boundTabID: tabID,
            contextPolicy: .disclosedResearchSourcesOnly
        ) else {
            llmConversation = conversationBeforeResearch
            return nil
        }
        sourceMessageByCopilotRunID[runID] = userMessage.id
        pendingResearchSynthesisByRunID[runID] = (session.id, request)
        researchSynthesisErrorsBySessionID[session.id] = nil
        persistLLMConversation()
        return runID
    }

    /// Probe a navigated page for a Hyperactive Web service card. If one is
    /// found, the capability surface is rendered and the panel is surfaced so the
    /// user can act on it alongside the page.
    private func probeHyperactiveWeb(_ url: URL) {
        guard let coordinator = hyperactiveWeb else { return }
        Task { [weak self] in
            let entered = await coordinator.discover(urlString: url.absoluteString)
            guard entered, let self else { return }
            if self.selectedPanel == nil {
                self.selectedPanel = .hyperactiveWeb
            }
        }
    }

    func refreshRuntimeBridgeStatus() async {
        runtimeFeatureStates = await runtimeBridge.refreshStatus()
        chainTrustSnapshot = runtimeBridge.chainTrustSnapshot
        afmServiceSnapshot = runtimeBridge.afmServiceSnapshot
        llmRouterServiceSnapshot = runtimeBridge.llmRouterServiceSnapshot
        llmGatewayServiceSnapshot = runtimeBridge.llmGatewayServiceSnapshot
        walletPortfolio = runtimeBridge.walletPortfolio
        mcpServers = runtimeBridge.mcpServers
        afmTrainingJobs = runtimeBridge.afmTrainingJobs
        latestAFMA2ACallResult = runtimeBridge.latestAFMA2ACallResult
        llmModelOptions = LLMModelRegistry.models(
            afmSnapshot: afmServiceSnapshot,
            llmRouterSnapshot: llmRouterServiceSnapshot,
            llmGatewaySnapshot: llmGatewayServiceSnapshot
        )
        normalizeSelectedLLMModelIfNeeded()
        async let openMindState = openMindMemoryClient.refreshRuntimeState()
        async let reviewTasks = openMindMemoryClient.refreshReviewTasks()
        let resolvedOpenMindState = await openMindState
        openMindCapabilityState = resolvedOpenMindState.capability
        openMindContinuityState = resolvedOpenMindState.continuity
        openMindPostureState = resolvedOpenMindState.posture
        openMindReviewTasks = await reviewTasks
        if let selectedAFMPackID, !afmServiceSnapshot.availablePacks.contains(where: { $0.id == selectedAFMPackID }) {
            self.selectedAFMPackID = nil
        }
    }

    func connectWallet() async {
        _ = await runtimeBridge.connectWallet()
        walletPortfolio = runtimeBridge.walletPortfolio
        runtimeFeatureStates = runtimeBridge.featureStates
    }

    func createEmbeddedWallet(label: String = "Embedded browser wallet") async {
        _ = await runtimeBridge.createEmbeddedWallet(label: label)
        walletPortfolio = runtimeBridge.walletPortfolio
        runtimeFeatureStates = runtimeBridge.featureStates
    }

    func disconnectWallet() async {
        _ = await runtimeBridge.disconnectWallet()
        walletPortfolio = runtimeBridge.walletPortfolio
        runtimeFeatureStates = runtimeBridge.featureStates
    }

    func switchWalletNetwork(_ chainRef: String) async {
        _ = await runtimeBridge.switchWalletNetwork(chainRef)
        walletPortfolio = runtimeBridge.walletPortfolio
        runtimeFeatureStates = runtimeBridge.featureStates
    }

    func previewWalletTransfer(_ request: WalletTransferRequest) async -> WalletTransferPreview {
        await runtimeBridge.previewWalletTransfer(request)
    }

    func signWalletTransfer(_ request: WalletTransferRequest) async -> WalletTransferReceipt {
        let receipt = await runtimeBridge.signWalletTransfer(request)
        walletPortfolio = runtimeBridge.walletPortfolio
        return receipt
    }

    func blockchainHostContract(
        for principal: LocalCapabilityPrincipal,
        grant: BlockchainCapabilityGrant
    ) -> BlockchainHostContract {
        runtimeBridge.blockchainHostContract(for: principal, grant: grant)
    }

    func prepareWalletTransaction(
        _ request: WalletTransferRequest,
        principal: LocalCapabilityPrincipal,
        grant: BlockchainCapabilityGrant
    ) async -> WalletPreparedTransaction {
        await runtimeBridge.prepareWalletTransaction(request, principal: principal, grant: grant)
    }

    func simulateWalletTransaction(_ prepared: WalletPreparedTransaction) async -> WalletTransactionSimulation {
        await runtimeBridge.simulateWalletTransaction(prepared)
    }

    func requestWalletSignature(
        _ prepared: WalletPreparedTransaction,
        grant: BlockchainCapabilityGrant
    ) async -> WalletTransferReceipt {
        let receipt = await runtimeBridge.requestWalletSignature(prepared, grant: grant)
        walletPortfolio = runtimeBridge.walletPortfolio
        return receipt
    }

    func requestWalletBroadcast(
        _ receipt: WalletTransferReceipt,
        principal: LocalCapabilityPrincipal,
        grant: BlockchainCapabilityGrant
    ) async -> WalletBroadcastResult {
        await runtimeBridge.requestWalletBroadcast(receipt, principal: principal, grant: grant)
    }

    @discardableResult
    func updateMCPServer(_ server: MCPServerConfiguration) async -> [MCPServerConfiguration] {
        let servers = await runtimeBridge.updateMCPServer(server)
        mcpServers = servers
        runtimeFeatureStates = runtimeBridge.featureStates
        return servers
    }

    @discardableResult
    func addMCPServer(transport: MCPServerTransport) async -> MCPServerConfiguration {
        let server = await runtimeBridge.addMCPServer(transport: transport)
        mcpServers = runtimeBridge.mcpServers
        runtimeFeatureStates = runtimeBridge.featureStates
        return server
    }

    @discardableResult
    func removeMCPServer(_ id: String) async -> [MCPServerConfiguration] {
        let servers = await runtimeBridge.removeMCPServer(id)
        mcpServers = servers
        runtimeFeatureStates = runtimeBridge.featureStates
        return servers
    }

    @discardableResult
    func connectMCPServer(_ id: String) async -> MCPServerConfiguration? {
        let server = await runtimeBridge.connectMCPServer(id)
        mcpServers = runtimeBridge.mcpServers
        runtimeFeatureStates = runtimeBridge.featureStates
        return server
    }

    @discardableResult
    func disconnectMCPServer(_ id: String) async -> MCPServerConfiguration? {
        let server = await runtimeBridge.disconnectMCPServer(id)
        mcpServers = runtimeBridge.mcpServers
        runtimeFeatureStates = runtimeBridge.featureStates
        return server
    }

    func selectAFMPack(_ id: String?) {
        guard let id, !id.isEmpty else {
            selectedAFMPackID = nil
            return
        }
        guard afmServiceSnapshot.availablePacks.contains(where: { $0.id == id }) else { return }
        selectedAFMPackID = id
    }

    @discardableResult
    func createAFMExpertTrainingJob(_ request: AFMExpertTrainingRequest) async -> AFMExpertTrainingJob {
        let job = await runtimeBridge.createAFMExpertTrainingJob(request)
        afmTrainingJobs = runtimeBridge.afmTrainingJobs
        runtimeFeatureStates = runtimeBridge.featureStates
        return job
    }

    @discardableResult
    func createDemoAFMExpertTrainingJob() async -> AFMExpertTrainingJob {
        await createAFMExpertTrainingJob(.demo)
    }

    @discardableResult
    func publishAFMExpertTrainingJob(_ id: UUID) async -> AFMExpertTrainingJob? {
        let job = await runtimeBridge.publishAFMExpertTrainingJob(id)
        afmTrainingJobs = runtimeBridge.afmTrainingJobs
        afmServiceSnapshot = runtimeBridge.afmServiceSnapshot
        runtimeFeatureStates = runtimeBridge.featureStates
        llmModelOptions = LLMModelRegistry.models(
            afmSnapshot: afmServiceSnapshot,
            llmRouterSnapshot: llmRouterServiceSnapshot,
            llmGatewaySnapshot: llmGatewayServiceSnapshot
        )
        normalizeSelectedLLMModelIfNeeded()
        return job
    }

    @discardableResult
    func callAFMPeerExpert(_ request: AFMA2ACallRequest) async -> AFMA2ACallResult {
        let result = await runtimeBridge.callAFMPeerExpert(request)
        latestAFMA2ACallResult = runtimeBridge.latestAFMA2ACallResult
        return result
    }

    func selectLLMModel(_ id: String) {
        guard let model = llmModelOptions.first(where: { $0.id == id }) else { return }
        guard model.availability.isRunnable else { return }
        guard selectedLLMModelID != id else { return }
        let previous = selectedLLMModelID
        selectedLLMModelID = id
        llmConversation.switchModel(to: id, displayName: model.displayName)
        persistLLMConversation()
        appendConversationLinkedCopilotEvent(
            kind: .modelSwitched,
            message: "Conversation switched model from \(previous) to \(model.displayName)."
        )
    }

    func refreshLocalLLMManagement() async {
        await performLocalLLMAction {
            await localLLMManager.refresh()
        }
    }

    func connectLocalLLMControlPlane() async {
        await performLocalLLMAction {
            await localLLMManager.connect()
        }
    }

    func bootstrapLocalLLMControlPlane() async {
        await performLocalLLMAction {
            await localLLMManager.bootstrapEmbeddedControlPlane()
        }
    }

    func importRecommendedLocalLLM() async {
        await performLocalLLMAction {
            await localLLMManager.importRecommendedModel()
        }
    }

    func inspectLocalLLMModel(_ id: String) async {
        await performLocalLLMAction {
            await localLLMManager.inspectModel(id: id)
        }
    }

    func validateLocalLLMModel(_ id: String) async {
        await performLocalLLMAction {
            await localLLMManager.validateModel(id: id)
        }
    }

    func warmLocalLLMModel(_ id: String) async {
        await performLocalLLMAction {
            await localLLMManager.warmModel(id: id)
        }
    }

    func stopLocalLLMEngine(_ id: String) async {
        await performLocalLLMAction {
            await localLLMManager.stopEngine(id: id)
        }
    }

    func installLocalLLMBackend(_ id: String) async {
        await performLocalLLMAction {
            await localLLMManager.installBackend(id: id)
        }
    }

    func openBookmark(_ bookmark: BrowserBookmark) {
        navigate(bookmark.urlString)
    }

    func openHistoryEntry(_ entry: BrowserHistoryEntry) {
        if activeTab?.urlString == entry.urlString {
            selectedPanel = nil
            reload()
            return
        }
        navigate(entry.urlString)
    }

    func addActivePageBookmark() {
        guard let tab = activeTab else { return }
        guard tab.urlString != BrowserURLResolver.homeURLString else { return }
        guard !tab.isTraceMinimized else { return }
        guard bookmarks.contains(where: { $0.urlString == tab.urlString }) == false else { return }
        bookmarks.insert(BrowserBookmark(title: tab.title, urlString: tab.urlString), at: 0)
    }

    func goBack() {
        if let activeTab {
            beginPageNavigation(for: activeTab.id, reason: "Back navigation invalidated the pending page capture.")
        }
        issueCommand(.back)
    }

    func goForward() {
        if let activeTab {
            beginPageNavigation(for: activeTab.id, reason: "Forward navigation invalidated the pending page capture.")
        }
        issueCommand(.forward)
    }

    func reload() {
        if let activeTab {
            beginPageNavigation(for: activeTab.id, reason: "Reload invalidated the pending page capture.")
        }
        issueCommand(.reload)
    }

    func toggleAdBlocking() {
        adBlockingMode = adBlockingMode.toggled
        BrowserAdBlockingSettings.save(adBlockingMode, defaults: adBlockingDefaults)
        reload()
    }

    func stop() {
        issueCommand(.stop)
        if let activeTab {
            cancelCopilotRuns(boundTo: activeTab.id, reason: "Stop requested by the user.")
        }
    }

    @discardableResult
    func requestDOMQuery(_ request: DOMQueryRequest = DOMQueryRequest()) -> BrowserAutomationRequest? {
        issueAutomationRequest(.domQuery(request))
    }

    @discardableResult
    func requestPageSnapshot(_ request: PageSnapshotRequest = PageSnapshotRequest()) -> BrowserAutomationRequest? {
        guard canRequestActivePageSnapshot else { return nil }
        return issueAutomationRequest(.pageSnapshot(request))
    }

    @discardableResult
    func requestTextSelection(_ request: BrowserTextSelectionRequest = BrowserTextSelectionRequest()) -> BrowserAutomationRequest? {
        guard let tab = activeTab, isCopilotContextEligible(tab), !tab.isLoading else { return nil }
        latestTextSelection = nil
        return issueAutomationRequest(.textSelection(request))
    }

    func prepareInactiveTabCapture(_ tabID: UUID) {
        guard automationRequest == nil,
              pendingFreshCopilotContexts.isEmpty,
              tabID != activeTabID,
              let tab = tabs.first(where: { $0.id == tabID }),
              isCopilotContextEligible(tab),
              !tab.isLoading else {
            inactiveTabCaptureState = InactiveTabCaptureState(
                phase: .failed,
                tabID: tabID,
                tabTitle: tabs.first(where: { $0.id == tabID })?.title,
                targetURLString: nil,
                displayURLString: nil,
                navigationGeneration: nil,
                message: "That inactive tab is not eligible for a one-time live capture."
            )
            return
        }
        inactiveTabCaptureState = InactiveTabCaptureState(
            phase: .awaitingConfirmation,
            tabID: tab.id,
            tabTitle: tab.title,
            targetURLString: tab.urlString,
            displayURLString: LLMPageContextSanitizer.sanitizedURLString(tab.urlString),
            navigationGeneration: pageNavigationGenerations[tab.id] ?? 0,
            message: "Capture one bounded snapshot from this inactive tab now? It will not be attached until you select it."
        )
    }

    @discardableResult
    func confirmInactiveTabCapture() -> BrowserAutomationRequest? {
        guard inactiveTabCaptureState.phase == .awaitingConfirmation,
              let tabID = inactiveTabCaptureState.tabID,
              let tab = tabs.first(where: { $0.id == tabID }),
              tab.id != activeTabID,
              isCopilotContextEligible(tab),
              !tab.isLoading else {
            cancelInactiveTabCapture()
            return nil
        }
        guard tab.urlString == inactiveTabCaptureState.targetURLString,
              (pageNavigationGenerations[tab.id] ?? 0) == inactiveTabCaptureState.navigationGeneration else {
            inactiveTabCaptureState = InactiveTabCaptureState(
                phase: .failed,
                tabID: tab.id,
                tabTitle: tab.title,
                targetURLString: nil,
                displayURLString: LLMPageContextSanitizer.sanitizedURLString(tab.urlString),
                navigationGeneration: nil,
                message: "That inactive tab changed after review. Nothing was captured; choose it again to review the current page."
            )
            return nil
        }
        guard let request = issueAutomationRequest(.pageSnapshot(PageSnapshotRequest()), for: tab) else {
            inactiveTabCaptureState.phase = .failed
            inactiveTabCaptureState.message = "Another browser capture or action is already in progress."
            return nil
        }
        inactiveTabCaptureRequestID = request.id
        inactiveTabCaptureState.phase = .capturing
        inactiveTabCaptureState.message = "Capturing one bounded snapshot from \(tab.title)."
        return request
    }

    func cancelInactiveTabCapture() {
        if let requestID = inactiveTabCaptureRequestID, automationRequest?.id == requestID {
            automationTimeoutTasks.removeValue(forKey: requestID)?.cancel()
            markAutomationRequestTerminal(requestID)
            automationRequest = nil
        }
        inactiveTabCaptureRequestID = nil
        inactiveTabCaptureState = .idle
    }

    @discardableResult
    func requestDOMAction(_ action: BrowserDOMAction) -> BrowserAutomationRequest? {
        guard let tab = activeTab else { return nil }
        let target = targetElement(for: action)
        if let approval = BrowserAutomationApprovalPolicy.evaluate(
            action: action,
            currentURLString: tab.urlString,
            target: target
        ) {
            let requestID = UUID()
            let result = BrowserAutomationResult(
                requestID: requestID,
                tabID: tab.id,
                status: .needsApproval,
                message: approval.summary,
                approval: approval
            )
            applyAutomationResult(result, allowsLocallyGeneratedApproval: true)
            return nil
        }

        return issueAutomationRequest(.action(action))
    }

    @discardableResult
    func approveToolProposal(_ proposalID: UUID, now: Date = Date()) -> BrowserAutomationRequest? {
        guard let index = copilotToolProposals.firstIndex(where: { $0.id == proposalID }) else { return nil }
        var proposal = copilotToolProposals[index]
        guard proposal.status == .pendingApproval else { return nil }
        guard proposal.expiresAt > now else {
            proposal.status = .expired
            proposal.statusMessage = "Approval expired before execution."
            copilotToolProposals[index] = proposal
            updateConversationToolProposal(proposal, eventKind: .toolDenied)
            return nil
        }
        guard let tab = tabs.first(where: { $0.id == proposal.targetTabID }),
              isCopilotContextEligible(tab),
              LLMPageContextSanitizer.sanitizedURLString(tab.urlString) == proposal.targetURLString,
              (pageNavigationGenerations[tab.id] ?? 0) == proposal.navigationGeneration else {
            proposal.status = .expired
            proposal.statusMessage = "The tab navigated after this tool was proposed."
            copilotToolProposals[index] = proposal
            updateConversationToolProposal(proposal, eventKind: .toolDenied)
            return nil
        }
        guard tab.id == activeTabID else {
            proposal.statusMessage = "Activate the bound tab and review the exact page before approving this tool."
            copilotToolProposals[index] = proposal
            updateConversationToolProposal(proposal, eventKind: .toolProposed)
            return nil
        }
        guard let targetPageCommitment = proposal.targetPageCommitment,
              let commandCommitment = proposal.commandCommitment,
              let approvalBindingCommitment = proposal.approvalBindingCommitment,
              CopilotToolProposalFactory.isCanonicalCommitment(proposal.argumentCommitment),
              CopilotToolProposalFactory.pageCommitment(urlString: tab.urlString) == targetPageCommitment,
              CopilotToolProposalFactory.commandCommitment(proposal.command) == commandCommitment,
              CopilotToolProposalFactory.approvalBindingCommitment(
                  proposalID: proposal.id,
                  sourceRunID: proposal.sourceRunID,
                  targetTabID: proposal.targetTabID,
                  targetPageCommitment: targetPageCommitment,
                  navigationGeneration: proposal.navigationGeneration,
                  argumentCommitment: proposal.argumentCommitment,
                  commandCommitment: commandCommitment,
                  expiresAt: proposal.expiresAt
              ) == approvalBindingCommitment else {
            proposal.status = .expired
            proposal.statusMessage = CopilotToolProposalError.staleOrTamperedProposal.localizedDescription
            copilotToolProposals[index] = proposal
            updateConversationToolProposal(proposal, eventKind: .toolDenied)
            return nil
        }
        let grant = BrowserAutomationApprovalGrant(
            proposalID: proposal.id,
            sourceRunID: proposal.sourceRunID,
            targetTabID: proposal.targetTabID,
            targetURLString: proposal.targetURLString,
            targetPageCommitment: targetPageCommitment,
            navigationGeneration: proposal.navigationGeneration,
            argumentCommitment: proposal.argumentCommitment,
            commandCommitment: commandCommitment,
            approvalBindingCommitment: approvalBindingCommitment,
            approvedAt: now,
            expiresAt: proposal.expiresAt
        )
        guard let request = issueAutomationRequest(proposal.command.browserCommand, for: tab, approvalGrant: grant) else {
            return nil
        }
        proposal.status = .executing
        proposal.statusMessage = "Approved once and executing against the bound page."
        proposal.automationRequestID = request.id
        copilotToolProposals[index] = proposal
        toolProposalByAutomationRequestID[request.id] = proposal.id
        updateConversationToolProposal(proposal, eventKind: .toolApproved)
        appendCopilotEvent(
            runID: proposal.sourceRunID,
            kind: .actionRequested,
            message: "Approved tool \(proposal.toolName) for one execution."
        )
        return request
    }

    func denyToolProposal(_ proposalID: UUID) {
        guard let index = copilotToolProposals.firstIndex(where: {
            $0.id == proposalID && $0.status == .pendingApproval
        }) else { return }
        copilotToolProposals[index].status = .denied
        copilotToolProposals[index].statusMessage = "Denied by the user; nothing executed."
        updateConversationToolProposal(copilotToolProposals[index], eventKind: .toolDenied)
        appendCopilotEvent(
            runID: copilotToolProposals[index].sourceRunID,
            kind: .approvalRequired,
            message: "Denied tool \(copilotToolProposals[index].toolName)."
        )
    }

    func applyAutomationResult(_ result: BrowserAutomationResult) {
        applyAutomationResult(result, allowsLocallyGeneratedApproval: false)
    }

    /// Atomically claims a provider-approved request before WebKit dispatch.
    /// This state lives above a representable coordinator so view/panel
    /// recreation cannot execute the same one-time grant again.
    func claimApprovedAutomationDispatch(_ requestID: UUID, ownerID: UUID) -> Bool {
        guard automationRequest?.id == requestID,
              automationRequest?.approvalGrant != nil,
              !terminalAutomationRequestIDs.contains(requestID) else {
            return false
        }
        guard approvedAutomationDispatchOwners[requestID] == nil else {
            return false
        }
        approvedAutomationDispatchOwners[requestID] = ownerID
        return true
    }

    private func applyAutomationResult(
        _ result: BrowserAutomationResult,
        allowsLocallyGeneratedApproval: Bool
    ) {
        guard !terminalAutomationRequestIDs.contains(result.requestID) else {
            automationTimeoutTasks.removeValue(forKey: result.requestID)?.cancel()
            pageSnapshotCaptureContexts[result.requestID] = nil
            if automationRequest?.id == result.requestID {
                automationRequest = nil
            }
            return
        }
        if let issuedRequest = automationRequest,
           issuedRequest.id == result.requestID,
           issuedRequest.approvalGrant != nil {
            guard let resultOwnerID = result.approvedAutomationDispatchOwnerID,
                  approvedAutomationDispatchOwners[result.requestID] == resultOwnerID else {
                // A replacement representable may still observe the published
                // request. It cannot fail, complete, or otherwise consume a
                // grant owned by the coordinator that performed the dispatch.
                return
            }
        }
        let registeredCapture = pageSnapshotCaptureContexts[result.requestID]
        let matchesIssuedAutomation = automationRequest?.id == result.requestID
            && automationRequest?.tabID == result.tabID
        if allowsLocallyGeneratedApproval {
            guard result.approval != nil else { return }
        } else if result.pageSnapshot != nil {
            guard registeredCapture?.tabID == result.tabID else { return }
        } else {
            guard registeredCapture?.tabID == result.tabID || matchesIssuedAutomation else { return }
        }
        let resultTab = tabs.first(where: { $0.id == result.tabID })
        let isTraceMinimizedResult = resultTab?.isTraceMinimized == true
        let captureContext = pageSnapshotCaptureContexts.removeValue(forKey: result.requestID)
        markAutomationRequestTerminal(result.requestID)
        let captureMatchesCurrentNavigation = captureContext.map { context in
            context.tabID == result.tabID
                && context.targetURLString == resultTab?.urlString
                && context.navigationGeneration == (pageNavigationGenerations[result.tabID] ?? 0)
        } ?? false
        automationTimeoutTasks.removeValue(forKey: result.requestID)?.cancel()
        if automationRequest?.id == result.requestID {
            automationRequest = nil
        }
        var storedResult = result
        if isTraceMinimizedResult {
            storedResult.domQuery = nil
            storedResult.pageSnapshot = nil
            storedResult.textSelection = nil
            invalidatePageContext(for: result.tabID)
        } else if let snapshot = storedResult.pageSnapshot,
                  result.status != .success
                    || resultTab == nil
                    || snapshot.urlString != resultTab?.urlString
                    || resultTab.map({ isCopilotContextEligible($0) }) != true
                    || !captureMatchesCurrentNavigation {
            storedResult.pageSnapshot = nil
        }
        if let selection = storedResult.textSelection,
           result.status != .success
                || resultTab == nil
                || selection.urlString != LLMPageContextSanitizer.sanitizedURLString(resultTab?.urlString)
                || resultTab.map({ isCopilotContextEligible($0) }) != true
                || !captureMatchesCurrentNavigation {
            storedResult.textSelection = nil
        }

        automationResults.insert(storedResult, at: 0)
        if automationResults.count > 100 {
            automationResults.removeLast(automationResults.count - 100)
        }

        if let domQuery = storedResult.domQuery, result.tabID == activeTabID {
            latestDOMQueryResult = domQuery
        }

        if let snapshot = storedResult.pageSnapshot {
            pageSnapshotsByTabID[result.tabID] = snapshot
            if result.tabID == activeTabID {
                latestPageSnapshot = snapshot
            }
            updateSmartHistorySummary(from: snapshot)
            appendDeveloperWorkflowSnapshotEvidence(snapshot, tabID: result.tabID)
        }

        if let selection = storedResult.textSelection, result.tabID == activeTabID {
            latestTextSelection = selection
        }

        if let approval = storedResult.approval {
            appendApproval(approval, tabID: result.tabID)
        }

        resolveInactiveTabCapture(with: storedResult)
        resolveToolProposal(with: storedResult)

        resumeFreshCopilotContext(with: storedResult)
    }

    @discardableResult
    func runCopilot(prompt: String) -> UUID? {
        startCopilotRun(
            prompt: prompt,
            conversationID: nil,
            model: activeLLMModel,
            renderedContext: nil,
            recordsAssistantMessage: false
        )
    }

    @discardableResult
    func sendLLMMessage(
        _ text: String,
        fileAttachments: [LLMTextFileAttachment] = [],
        sourceMessageID: UUID? = nil,
        regeneratedFromMessageID: UUID? = nil
    ) -> UUID? {
        guard let tab = activeTab else { return nil }
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }

        let model = activeLLMModel
        let snapshot = currentPageSnapshot(for: tab)
        let relatedContext = isCopilotContextEligible(tab) ? selectedRelatedPageContext(for: tab) : []
        return launchLLMConversationMessage(
            prompt: prompt,
            tab: tab,
            snapshot: snapshot,
            relatedContext: relatedContext,
            model: model,
            fileAttachments: fileAttachments,
            sourceMessageID: sourceMessageID,
            regeneratedFromMessageID: regeneratedFromMessageID
        )
    }

    @discardableResult
    func sendLLMMessageWithFreshContext(
        _ text: String,
        fileAttachments: [LLMTextFileAttachment] = [],
        sourceMessageID: UUID? = nil,
        regeneratedFromMessageID: UUID? = nil
    ) -> UUID? {
        guard let tab = activeTab else { return nil }
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        // Keep the idle guarantee in the model boundary, not only in SwiftUI.
        // App Intents, saved workflows, and other callers share this entry point.
        guard activeCopilotRunCount == 0 else { return nil }

        guard isCopilotContextEligible(tab) else {
            return sendLLMMessage(
                prompt,
                fileAttachments: fileAttachments,
                sourceMessageID: sourceMessageID,
                regeneratedFromMessageID: regeneratedFromMessageID
            )
        }
        guard !tab.isLoading, pendingFreshCopilotContexts.isEmpty, automationRequest == nil else { return nil }

        let model = activeLLMModel
        let relatedTabIDs = selectedRelatedPageContext(for: tab).map(\.tabID)
        let navigationGeneration = pageNavigationGenerations[tab.id] ?? 0
        let runID = UUID()
        let request = BrowserAutomationRequest(
            tabID: tab.id,
            command: .pageSnapshot(PageSnapshotRequest()),
            timeoutSeconds: freshCopilotContextTimeoutSeconds,
            navigationGeneration: navigationGeneration
        )
        let run = CopilotRun(
            id: runID,
            prompt: prompt,
            activeTabID: tab.id,
            targetURLString: tab.urlString,
            conversationID: llmConversation.id,
            modelID: model.id,
            contextTabIDs: relatedTabIDs,
            status: .queued,
            events: [
                CopilotRunEvent(
                    kind: .queued,
                    message: "Queued a fresh-context Copilot run for \(tab.displayURL) with \(model.displayName)."
                ),
                CopilotRunEvent(
                    kind: .pageSnapshotRequested,
                    message: "Waiting for a fresh, bounded snapshot of the active tab before model execution."
                )
            ]
        )
        copilotRuns.insert(run, at: 0)
        copilotRunPresentations[runID] = CopilotRunPresentation(
            runID: runID,
            phase: .waitingForContext,
            partialText: "",
            statusMessage: "Waiting for a fresh page snapshot.",
            providerBoundary: model.trustBoundary.title
        )
        pendingFreshCopilotContexts[request.id] = PendingFreshCopilotContext(
            runID: runID,
            prompt: prompt,
            tabID: tab.id,
            targetURLString: tab.urlString,
            conversationID: llmConversation.id,
            model: model,
            relatedTabIDs: relatedTabIDs,
            navigationGeneration: navigationGeneration,
            fileAttachments: Array(fileAttachments.prefix(LLMTextFileAttachmentPolicy.maximumAttachments)),
            sourceMessageID: sourceMessageID,
            regeneratedFromMessageID: regeneratedFromMessageID
        )
        registerPageSnapshotCapture(request, for: tab)
        automationRequest = request
        scheduleFreshCopilotContextTimeout(for: request.id, after: request.timeoutSeconds)
        return runID
    }

    private func launchLLMConversationMessage(
        prompt: String,
        tab: BrowserTab,
        snapshot: PageSnapshot?,
        relatedContext: [(tabID: UUID, snapshot: PageSnapshot)],
        model: LLMModelProfile,
        fileAttachments: [LLMTextFileAttachment] = [],
        sourceMessageID: UUID? = nil,
        regeneratedFromMessageID: UUID? = nil,
        queuedRunID: UUID? = nil
    ) -> UUID? {
        let relatedSnapshots = relatedContext.map(\.snapshot)
        let conversationBeforeMutation = llmConversation
        let userMessage = LLMConversationMessage(
            role: .user,
            text: prompt,
            pageURLString: isCopilotContextEligible(tab) ? tab.urlString : nil,
            snapshotAttachment: snapshot.map(LLMPageSnapshotAttachment.init(snapshot:)),
            relatedSnapshotAttachments: relatedSnapshots.map(LLMPageSnapshotAttachment.init(snapshot:)),
            fileAttachments: fileAttachments,
            sourceMessageID: sourceMessageID,
            regeneratedFromMessageID: regeneratedFromMessageID
        )
        var candidateConversation = llmConversation
        candidateConversation.appendMessage(userMessage)
        var renderedContext = LLMConversationContextRenderer.render(
            conversation: candidateConversation,
            model: model,
            latestPageSnapshot: snapshot,
            relatedPageSnapshots: relatedSnapshots
        )
        let effectiveTokenBudget = LLMConversationContextRenderer.effectiveTokenBudget(for: model)
        guard renderedContext.estimatedPromptTokens <= effectiveTokenBudget else {
            if let queuedRunID {
                finishCopilotRun(
                    queuedRunID,
                    status: .failed,
                    result: nil,
                    message: "The required Copilot prompt exceeded \(model.displayName)'s \(effectiveTokenBudget)-token input budget; no memory or model provider received it."
                )
                return queuedRunID
            }
            return nil
        }

        llmConversation.appendMessage(userMessage)
        llmConversation.appendEvent(
            LLMConversationEvent(
                kind: .userMessageAdded,
                message: "Added user message for \(model.displayName).",
                toModelID: model.id,
                relatedMessageID: userMessage.id
            )
        )

        if snapshot != nil {
            llmConversation.appendEvent(
                LLMConversationEvent(
                    kind: .pageSnapshotAttached,
                    message: "Attached active page snapshot to the conversation.",
                    relatedMessageID: userMessage.id
                )
            )
        }
        if !relatedSnapshots.isEmpty {
            llmConversation.appendEvent(
                LLMConversationEvent(
                    kind: .pageSnapshotAttached,
                    message: "Attached \(relatedSnapshots.count) explicitly selected related page snapshot\(relatedSnapshots.count == 1 ? "" : "s") to the conversation.",
                    relatedMessageID: userMessage.id
                )
            )
        }
        if regeneratedFromMessageID != nil {
            llmConversation.appendEvent(
                LLMConversationEvent(
                    kind: .regenerated,
                    message: "Regenerated an assistant response from linked source message \(sourceMessageID?.uuidString ?? userMessage.id.uuidString).",
                    relatedMessageID: userMessage.id
                )
            )
        }
        if renderedContext.wasCompressed {
            guard let committedContext = renderContextWithCommittedSummaryArtifact(
                startingWith: renderedContext,
                conversationAtBoundary: llmConversation,
                model: model,
                latestPageSnapshot: snapshot,
                relatedPageSnapshots: relatedSnapshots,
                memoryRecall: nil
            ) else {
                llmConversation = conversationBeforeMutation
                if let queuedRunID {
                    finishCopilotRun(
                        queuedRunID,
                        status: .failed,
                        result: nil,
                        message: "The compressed context could not be linked to an exact committed summary artifact within \(model.displayName)'s input budget; no conversation mutation, memory access, or model execution was retained."
                    )
                    return queuedRunID
                }
                return nil
            }
            renderedContext = committedContext
        }
        guard renderedContext.estimatedPromptTokens <= effectiveTokenBudget else {
            // Artifact creation is transactional: a larger linked-artifact
            // rendering must not leave the user turn or artifact in the
            // canonical archive when the final provider envelope cannot fit.
            llmConversation = conversationBeforeMutation
            if let queuedRunID {
                finishCopilotRun(
                    queuedRunID,
                    status: .failed,
                    result: nil,
                    message: "The linked context summary could not fit inside \(model.displayName)'s \(effectiveTokenBudget)-token input budget; no conversation mutation, memory access, or model execution was retained."
                )
                return queuedRunID
            }
            return nil
        }
        persistLLMConversation()

        if renderedContext.wasCompressed {
            appendContextCompressionEvent(renderedContext, model: model)
        }

        let launchedRunID = startCopilotRun(
            prompt: prompt,
            conversationID: llmConversation.id,
            model: model,
            renderedContext: renderedContext,
            recordsAssistantMessage: true,
            boundTabID: tab.id,
            pageSnapshot: snapshot,
            relatedPageSnapshots: relatedSnapshots,
            contextTabIDs: relatedContext.map(\.tabID),
            runID: queuedRunID,
            reusesQueuedRun: queuedRunID != nil
        )
        if let launchedRunID {
            sourceMessageByCopilotRunID[launchedRunID] = userMessage.id
            if let regeneratedFromMessageID {
                regeneratedAssistantByCopilotRunID[launchedRunID] = regeneratedFromMessageID
            }
        }
        return launchedRunID
    }

    private func resumeFreshCopilotContext(with result: BrowserAutomationResult) {
        guard let pending = takePendingFreshCopilotContext(for: result.requestID) else { return }
        guard isCopilotRunActive(pending.runID) else { return }
        guard
            result.status == .success,
            result.tabID == pending.tabID,
            activeTabID == pending.tabID,
            let tab = tabs.first(where: { $0.id == pending.tabID }),
            isCopilotContextEligible(tab),
            tab.urlString == pending.targetURLString,
            let snapshot = result.pageSnapshot,
            snapshot.urlString == pending.targetURLString,
            pending.conversationID == llmConversation.id,
            pending.navigationGeneration == (pageNavigationGenerations[pending.tabID] ?? 0)
        else {
            finishCopilotRun(
                pending.runID,
                status: .failed,
                result: nil,
                message: "Fresh page context was unavailable or stale; no model received the prompt."
            )
            return
        }

        let relatedContext = selectedRelatedPageContext(
            for: tab,
            restrictedTo: Set(pending.relatedTabIDs)
        )
        guard launchLLMConversationMessage(
            prompt: pending.prompt,
            tab: tab,
            snapshot: snapshot,
            relatedContext: relatedContext,
            model: pending.model,
            fileAttachments: pending.fileAttachments,
            sourceMessageID: pending.sourceMessageID,
            regeneratedFromMessageID: pending.regeneratedFromMessageID,
            queuedRunID: pending.runID
        ) != nil else {
            finishCopilotRun(
                pending.runID,
                status: .failed,
                result: nil,
                message: "Fresh page context could not start the Copilot run."
            )
            return
        }
    }

    func startNewLLMConversation() {
        guard canChangeLLMConversation else { return }
        let previousConversationID = llmConversation.id
        let activeConversationRunIDs = copilotRuns
            .filter { $0.conversationID == previousConversationID && ($0.status == .queued || $0.status == .running) }
            .map(\.id)
        activeConversationRunIDs.forEach(cancelCopilotRun)

        llmConversationArchive.upsertConversation(llmConversation)
        normalizeSelectedLLMModelIfNeeded()
        let model = activeLLMModel
        llmConversation = LLMConversation(activeModelID: model.id)
        selectedLLMModelID = model.id
        latestOpenMindRecall = nil
        latestOpenMindStepUpRequest = nil
        latestOpenMindWriteback = nil
        latestOpenMindCorrection = nil
        copilotToolProposals = []
        persistLLMConversation()
    }

    @discardableResult
    func regenerateLastAssistantMessage() -> UUID? {
        guard activeCopilotRunCount == 0,
              let assistantIndex = llmConversation.messages.lastIndex(where: { $0.role == .assistant }) else {
            return nil
        }
        let assistant = llmConversation.messages[assistantIndex]
        let source: LLMConversationMessage? = {
            if let sourceMessageID = assistant.sourceMessageID,
               let linked = llmConversation.messages.first(where: { $0.id == sourceMessageID }) {
                return linked
            }
            return llmConversation.messages[..<assistantIndex].last(where: { $0.role == .user })
        }()
        guard let source else { return nil }
        return sendLLMMessageWithFreshContext(
            source.text,
            fileAttachments: source.fileAttachments,
            sourceMessageID: source.id,
            regeneratedFromMessageID: assistant.id
        )
    }

    @discardableResult
    func selectLLMConversation(_ id: UUID) -> Bool {
        guard canChangeLLMConversation else { return false }
        guard id != llmConversation.id,
              let selected = llmConversationArchive.conversations.first(where: { $0.id == id }) else {
            return id == llmConversation.id
        }
        let activeConversationRunIDs = copilotRuns
            .filter { $0.conversationID == llmConversation.id && ($0.status == .queued || $0.status == .running) }
            .map(\.id)
        activeConversationRunIDs.forEach(cancelCopilotRun)
        llmConversationArchive.upsertConversation(llmConversation)
        guard llmConversationArchive.selectConversation(selected.id) else { return false }
        llmConversation = selected
        selectedLLMModelID = selected.activeModelID
        copilotToolProposals = Array(selected.toolProposals.reversed())
        normalizeSelectedLLMModelIfNeeded()
        latestOpenMindRecall = nil
        latestOpenMindStepUpRequest = nil
        latestOpenMindWriteback = nil
        latestOpenMindCorrection = nil
        persistLLMConversation()
        return true
    }

    @discardableResult
    func deleteLLMConversation(_ id: UUID) -> Bool {
        guard canChangeLLMConversation else { return false }
        guard llmConversationArchive.removeConversation(id) else { return false }
        if id == llmConversation.id {
            llmConversation = llmConversationArchive.conversation
            selectedLLMModelID = llmConversation.activeModelID
            copilotToolProposals = Array(llmConversation.toolProposals.reversed())
            normalizeSelectedLLMModelIfNeeded()
        }
        llmConversations = llmConversationArchive.conversations
        persistLLMConversation()
        return true
    }

    var developerWorkflowTemplates: [BrowserDeveloperWorkflowTemplate] {
        BrowserDeveloperWorkflowTemplate.localFirstDefaults
    }

    var developerAutomationSurfaces: [BrowserDeveloperAutomationSurface] {
        BrowserDeveloperAutomationSurface.localFirstSurfaces()
    }

    @discardableResult
    func startDeveloperWorkflow(
        _ template: BrowserDeveloperWorkflowTemplate,
        entryPoint: BrowserDeveloperWorkflowEntryPoint = .copilot
    ) -> UUID? {
        guard template.entryPoints.contains(entryPoint) else { return nil }
        guard let tab = activeTab else { return nil }
        let activeURLString = tab.isTraceMinimized ? nil : tab.urlString
        let snapshot = !tab.isTraceMinimized && latestPageSnapshot?.urlString == tab.urlString ? latestPageSnapshot : nil
        var run = BrowserDeveloperWorkflowRun.draft(
            from: template,
            activeURLString: activeURLString,
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        run.status = .running

        if entryPoint == .copilot {
            let copilotRunID = startCopilotRun(
                prompt: run.prompt,
                conversationID: nil,
                model: activeLLMModel,
                renderedContext: nil,
                recordsAssistantMessage: false
            )
            guard let copilotRunID else { return nil }
            run.copilotRunID = copilotRunID
        }

        developerWorkflowRuns.insert(run, at: 0)
        persistDeveloperWorkflowRuns()
        return run.id
    }

    func appendDeveloperWorkflowEvidence(_ item: BrowserDeveloperEvidenceItem, to runID: UUID) {
        guard let index = developerWorkflowRuns.firstIndex(where: { $0.id == runID }) else { return }
        developerWorkflowRuns[index].appendEvidence(item)
        persistDeveloperWorkflowRuns()
    }

    @discardableResult
    private func startCopilotRun(
        prompt: String,
        conversationID: UUID?,
        model: LLMModelProfile,
        renderedContext: LLMRenderedConversationContext?,
        recordsAssistantMessage: Bool,
        boundTabID: UUID? = nil,
        pageSnapshot: PageSnapshot? = nil,
        relatedPageSnapshots: [PageSnapshot] = [],
        contextTabIDs: [UUID] = [],
        runID existingRunID: UUID? = nil,
        reusesQueuedRun: Bool = false,
        contextPolicy: CopilotRunContextPolicy = .standard
    ) -> UUID? {
        guard let tab = boundTabID.flatMap({ id in tabs.first(where: { $0.id == id }) }) ?? activeTab else { return nil }
        let runID = existingRunID ?? UUID()
        let isTraceMinimized = tab.isTraceMinimized
        let usesSourceOnlyResearch = contextPolicy == .disclosedResearchSourcesOnly
        let targetURLString = !usesSourceOnlyResearch && isCopilotContextEligible(tab)
            ? tab.urlString
            : nil
        let snapshot = !usesSourceOnlyResearch && isCopilotContextEligible(tab)
            ? (pageSnapshot ?? currentPageSnapshot(for: tab))
            : nil
        let boundedRelatedSnapshots = usesSourceOnlyResearch
            ? []
            : Array(relatedPageSnapshots.prefix(LLMRelatedPageSnapshotPolicy.maximumSnapshots))
        let boundedContextTabIDs = usesSourceOnlyResearch
            ? []
            : Array(contextTabIDs.prefix(LLMRelatedPageSnapshotPolicy.maximumSnapshots))
        let traceMinimizedDescription = tab.isTorrentTransfer ? "a torrent transfer tab" : "a private-overlay tab"
        let preferredPackID = selectedAFMPackID
        let providerPromptForBudget: String = {
            if let renderedContext {
                return renderedContext.prompt
            }
            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedPrompt.isEmpty ? "Assist with the current browsing task." : trimmedPrompt
        }()
        let effectiveTokenBudget = LLMConversationContextRenderer.effectiveTokenBudget(for: model)
        guard LLMConversationContextRenderer.estimatedTokens(for: providerPromptForBudget) <= effectiveTokenBudget else {
            if reusesQueuedRun {
                finishCopilotRun(
                    runID,
                    status: .failed,
                    result: nil,
                    message: "The required Copilot prompt exceeded \(model.displayName)'s \(effectiveTokenBudget)-token input budget; no memory or model provider received it."
                )
                return runID
            }
            return nil
        }
        var events = [
            CopilotRunEvent(kind: .queued, message: "Queued Copilot run for \(isTraceMinimized ? traceMinimizedDescription : tab.displayURL) with \(model.displayName).")
        ]
        if isTraceMinimized {
            events.append(
                CopilotRunEvent(kind: .pageSnapshotRequested, message: "Skipped page snapshot and page URL context for \(traceMinimizedDescription).")
            )
        } else if snapshot != nil {
            events.append(
                CopilotRunEvent(kind: .pageSnapshotAttached, message: "Attached a bounded snapshot of the active page.")
            )
        } else {
            events.append(
                CopilotRunEvent(kind: .pageSnapshotRequested, message: "No current page snapshot was available for this compatibility run.")
            )
        }
        if !boundedRelatedSnapshots.isEmpty {
            events.append(
                CopilotRunEvent(
                    kind: .relatedPageContextAttached,
                    message: "Selected \(boundedRelatedSnapshots.count) related page snapshot\(boundedRelatedSnapshots.count == 1 ? "" : "s") for bounded context rendering."
                )
            )
        }
        if renderedContext?.wasCompressed == true {
            events.append(
                CopilotRunEvent(
                    kind: .conversationContextCompressed,
                    message: "Compressed prior conversation context for \(model.displayName)."
                )
            )
        }
        let run = CopilotRun(
            id: runID,
            prompt: prompt,
            activeTabID: tab.id,
            targetURLString: targetURLString,
            conversationID: conversationID,
            modelID: model.id,
            contextTabIDs: boundedContextTabIDs,
            status: .running,
            events: events,
            usage: nil
        )
        if reusesQueuedRun {
            guard let runIndex = copilotRuns.firstIndex(where: { $0.id == runID && $0.status == .queued }) else {
                return nil
            }
            copilotRuns[runIndex].status = .running
            copilotRuns[runIndex].targetURLString = targetURLString
            copilotRuns[runIndex].contextTabIDs = boundedContextTabIDs
            copilotRuns[runIndex].usage = nil
            copilotRuns[runIndex].events.append(
                CopilotRunEvent(kind: .pageSnapshotAttached, message: "Validated and attached the fresh active-page snapshot.")
            )
            if !boundedRelatedSnapshots.isEmpty {
                copilotRuns[runIndex].events.append(
                    CopilotRunEvent(
                        kind: .relatedPageContextAttached,
                        message: "Selected \(boundedRelatedSnapshots.count) related page snapshot\(boundedRelatedSnapshots.count == 1 ? "" : "s") for bounded context rendering."
                    )
                )
            }
            if renderedContext?.wasCompressed == true {
                copilotRuns[runIndex].events.append(
                    CopilotRunEvent(
                        kind: .conversationContextCompressed,
                        message: "Compressed prior conversation context for \(model.displayName)."
                    )
                )
            }
        } else {
            copilotRuns.insert(run, at: 0)
        }
        if let workflowID = workflowByCopilotRunID[runID],
           let workflow = copilotWorkflows.first(where: { $0.id == workflowID }) {
            recordScheduledWorkflowState(
                workflow: workflow,
                phase: .running,
                message: "Workflow is running with fresh page context and normal approval boundaries.",
                runID: runID
            )
        }
        if let targetURLString,
           snapshot?.urlString == targetURLString,
           let targetPageCommitment = CopilotToolProposalFactory.pageCommitment(
               urlString: targetURLString
           ) {
            pageBindingByCopilotRunID[runID] = CopilotRunPageBinding(
                tabID: tab.id,
                targetPageCommitment: targetPageCommitment,
                navigationGeneration: pageNavigationGenerations[tab.id] ?? 0
            )
        } else {
            pageBindingByCopilotRunID[runID] = nil
        }
        copilotRunPresentations[runID] = CopilotRunPresentation(
            runID: runID,
            phase: .recallingMemory,
            partialText: "",
            statusMessage: "Checking governed memory before model work begins.",
            providerBoundary: "\(model.trustBoundary.title) · \(model.providerKind.title)"
        )
        if recordsAssistantMessage, let conversationID {
            llmConversation.appendEvent(
                LLMConversationEvent(
                    kind: .assistantRunStarted,
                    message: "Started \(model.displayName) run.",
                    toModelID: model.id,
                    relatedRunID: runID
                )
            )
            assert(conversationID == llmConversation.id)
            persistLLMConversation()
        }
        let conversationAtLaunch = llmConversation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if contextPolicy == .standard {
                appendCopilotEvent(runID: runID, kind: .memoryAccessStarted, message: "Requested governed memory from OpenMind.")
            }
            latestOpenMindStepUpRequest = nil
            let memoryRecall: OpenMindMemoryRecallResult
            if contextPolicy == .disclosedResearchSourcesOnly {
                memoryRecall = .unavailable(
                    "Memory recall is disabled for source-only research synthesis."
                )
            } else if model.trustBoundary == .onDevice, openMindMemoryClient.hasRemoteHTTPEndpoint {
                memoryRecall = .unavailable(
                    "Remote OpenMind recall was blocked to preserve the selected on-device model boundary."
                )
            } else {
                memoryRecall = await openMindMemoryClient.recall(
                    prompt: prompt,
                    pageURLString: LLMPageContextSanitizer.sanitizedURLString(targetURLString),
                    pageSnapshot: snapshot
                )
            }
            latestOpenMindRecall = memoryRecall
            latestOpenMindStepUpRequest = memoryRecall.stepUpRequest
            appendCopilotEvent(
                runID: runID,
                kind: copilotEventKind(for: memoryRecall),
                message: copilotMemoryMessage(for: memoryRecall)
            )
            guard !Task.isCancelled, isCopilotRunActive(runID) else { return }
            var renderedWithMemory = contextPolicy == .disclosedResearchSourcesOnly
                ? renderedContext
                : recordsAssistantMessage
                ? LLMConversationContextRenderer.render(
                    conversation: conversationAtLaunch,
                    model: model,
                    latestPageSnapshot: snapshot,
                    relatedPageSnapshots: boundedRelatedSnapshots,
                    memoryRecall: memoryRecall
                )
                : renderedContext
            if let renderedWithMemory,
               renderedWithMemory.estimatedPromptTokens > LLMConversationContextRenderer.effectiveTokenBudget(for: model) {
                finishCopilotRun(
                    runID,
                    status: .failed,
                    result: nil,
                    message: "Approved memory could not fit inside \(model.displayName)'s input budget; no model provider received the prompt."
                )
                return
            }
            if recordsAssistantMessage,
               let memoryExpandedContext = renderedWithMemory,
               memoryExpandedContext.wasCompressed,
               memoryExpandedContext.compressedMessageIDs != renderedContext?.compressedMessageIDs {
                let conversationBeforeMemorySummary = llmConversation
                guard let committedContext = renderContextWithCommittedSummaryArtifact(
                    startingWith: memoryExpandedContext,
                    conversationAtBoundary: conversationAtLaunch,
                    model: model,
                    latestPageSnapshot: snapshot,
                    relatedPageSnapshots: boundedRelatedSnapshots,
                    memoryRecall: memoryRecall
                ) else {
                    llmConversation = conversationBeforeMemorySummary
                    finishCopilotRun(
                        runID,
                        status: .failed,
                        result: nil,
                        message: "Memory-expanded context could not be linked to a committed summary artifact within \(model.displayName)'s input budget; no unlinked summary or model execution was retained."
                    )
                    return
                }
                renderedWithMemory = committedContext
                appendContextCompressionEvent(committedContext, model: model, runID: runID)
                appendCopilotEvent(
                    runID: runID,
                    kind: .conversationContextCompressed,
                    message: "Compressed prior conversation context after memory recall."
                )
            }

            if recordsAssistantMessage,
               conversationID == llmConversation.id,
               let renderedWithMemory,
               !renderedWithMemory.memoryContextIDs.isEmpty {
                let includedCount = renderedWithMemory.memoryContextIDs.count
                llmConversation.appendEvent(
                    LLMConversationEvent(
                        kind: .memoryContextAttached,
                        message: "Attached \(includedCount) approved memory citation\(includedCount == 1 ? "" : "s") after bounded context packing.",
                        toModelID: model.id,
                        relatedRunID: runID
                    )
                )
                persistLLMConversation()
            }

            if let renderedWithMemory, !renderedWithMemory.omittedRelatedSnapshotCommitments.isEmpty {
                appendCopilotEvent(
                    runID: runID,
                    kind: .relatedPageContextAttached,
                    message: "Omitted \(renderedWithMemory.omittedRelatedSnapshotCommitments.count) selected related page snapshot\(renderedWithMemory.omittedRelatedSnapshotCommitments.count == 1 ? "" : "s") from the provider envelope to honor the model token budget; commitments remain in the local ledger: \(renderedWithMemory.omittedRelatedSnapshotCommitments.joined(separator: ", "))."
                )
            }

            let disclosedRelatedSnapshots: [PageSnapshot] = {
                guard let renderedWithMemory else { return boundedRelatedSnapshots }
                let disclosedCommitments = Set(renderedWithMemory.relatedSnapshotCommitments)
                return boundedRelatedSnapshots.filter { snapshot in
                    OpenMindMemoryClient.snapshotCommitment(for: snapshot).map {
                        disclosedCommitments.contains($0)
                    } == true
                }
            }()
            let providerConversationID = usesSourceOnlyResearch ? nil : conversationID
            let providerRunID: UUID? = usesSourceOnlyResearch ? nil : runID

            appendCopilotEvent(runID: runID, kind: .modelStarted, message: "Started \(model.displayName) model bridge.")
            copilotRunPresentations[runID]?.phase = .invokingModel
            copilotRunPresentations[runID]?.statusMessage = "Waiting for \(model.displayName)."
            let result = await runtimeBridge.runCopilot(
                CopilotRunRequest(
                    prompt: prompt,
                    pageURLString: LLMPageContextSanitizer.sanitizedURLString(targetURLString),
                    pageSnapshot: snapshot,
                    relatedPageSnapshots: disclosedRelatedSnapshots,
                    preferredAFMPackID: preferredPackID,
                    preferredModelID: model.id,
                    conversationID: providerConversationID,
                    runID: providerRunID,
                    renderedConversationContext: renderedWithMemory,
                    memoryRecall: memoryRecall
                ),
                onTextDelta: { [weak self] delta in
                    guard let self, isCopilotRunActive(runID) else { return }
                    guard !usesSourceOnlyResearch else {
                        copilotRunPresentations[runID]?.phase = .streaming
                        copilotRunPresentations[runID]?.statusMessage = "Receiving source-only research synthesis for validation."
                        return
                    }
                    copilotRunPresentations[runID]?.append(delta: delta)
                    copilotRunPresentations[runID]?.statusMessage = "Streaming verified provider output."
                }
            )

            guard !Task.isCancelled else {
                finishCopilotRun(runID, status: .cancelled, result: nil, message: "Run cancelled before completion.")
                return
            }

            runtimeFeatureStates = runtimeBridge.featureStates
            chainTrustSnapshot = runtimeBridge.chainTrustSnapshot
            if let executionFailureMessage = result.executionFailureMessage {
                finishCopilotRun(
                    runID,
                    status: .failed,
                    result: model.providerKind == .localMLX || usesSourceOnlyResearch ? nil : result,
                    message: usesSourceOnlyResearch
                        ? "Source-only research synthesis failed before validation; no provider output was retained."
                        : executionFailureMessage
                )
                return
            }
            let provider = result.usageProviderKey ?? (result.mode == .service ? "afm" : "local")
            let finalUsage = CopilotCreditUsage.estimate(
                prompt: renderedWithMemory?.prompt ?? prompt,
                snapshot: snapshot,
                provider: provider
            )
            if !usesSourceOnlyResearch {
                appendAFMarketEvents(runID: runID, result: result)
                appendLLMRouterEvents(runID: runID, result: result)
                appendLLMGatewayEvents(runID: runID, result: result)
            }
            if usesSourceOnlyResearch {
                copilotRunPresentations[runID]?.phase = result.transport == .streaming
                    ? .streaming
                    : .bufferedResponse
                copilotRunPresentations[runID]?.partialText = ""
                copilotRunPresentations[runID]?.statusMessage = "Validating source-only research synthesis."
            } else if result.transport == .streaming {
                copilotRunPresentations[runID]?.phase = .streaming
                copilotRunPresentations[runID]?.partialText = result.summary
                copilotRunPresentations[runID]?.statusMessage = "Received transport-streamed provider output."
            } else {
                copilotRunPresentations[runID]?.phase = .bufferedResponse
                copilotRunPresentations[runID]?.partialText = result.summary
                copilotRunPresentations[runID]?.statusMessage = "Provider returned a buffered terminal response."
            }
            if recordsAssistantMessage, !usesSourceOnlyResearch, result.mode != model.runtimeMode {
                appendProviderFallback(runID: runID, requestedModel: model, actualMode: result.mode)
            }
            let validatedResearchSynthesis: BrowserResearchSynthesisResult?
            do {
                validatedResearchSynthesis = try validatePendingResearchSynthesis(
                    runID: runID,
                    responseText: result.summary
                )
            } catch {
                copilotRunPresentations[runID]?.partialText = ""
                finishCopilotRun(
                    runID,
                    status: .failed,
                    result: nil,
                    message: "Source-only research synthesis failed validation; no provider output was retained."
                )
                return
            }
            let finalResult = validatedResearchSynthesis.map {
                sanitizedResearchResult(from: result, answer: $0.answer)
            } ?? result
            if let validatedResearchSynthesis {
                copilotRunPresentations[runID]?.partialText = validatedResearchSynthesis.answer
                copilotRunPresentations[runID]?.statusMessage = "Validated source-only research synthesis."
            }
            let researchSourceCitations = validatedResearchSynthesis?.citations.map { citation in
                LLMSourceCitation(
                    id: citation.source.id,
                    kind: .research,
                    title: citation.source.title,
                    source: "native research search",
                    urlString: citation.source.urlString,
                    excerpt: citation.claim
                )
            } ?? []
            if recordsAssistantMessage, conversationID == llmConversation.id {
                let disclosedMemoryCitations = LLMMemoryContextPolicy.disclosedCitations(
                    from: memoryRecall.memories,
                    matching: renderedWithMemory?.memoryContextIDs ?? []
                )
                appendAssistantConversationMessage(
                    result: finalResult,
                    runID: runID,
                    model: model,
                    targetURLString: targetURLString,
                    memoryCitations: disclosedMemoryCitations,
                    sourceCitations: researchSourceCitations,
                    contextSummaryArtifactID: renderedWithMemory?.contextSummaryArtifactID,
                    usage: finalUsage
                )
            }
            finishCopilotRun(
                runID,
                status: .completed,
                result: finalResult,
                usage: finalUsage,
                message: usesSourceOnlyResearch
                    ? "Completed validated source-only research synthesis."
                    : "Completed Copilot run with \(provider) execution."
            )
        }
        copilotTasks[runID] = task
        return runID
    }

    @discardableResult
    func requestOpenMindStepUp() -> Task<Void, Never>? {
        guard let recall = latestOpenMindRecall,
              recall.decision.status == .stepUpRequired,
              let intent = recall.intent else {
            return nil
        }

        return Task { @MainActor [weak self] in
            guard let self else { return }
            let request = await openMindMemoryClient.requestStepUpGrant(
                intent: intent,
                decision: recall.decision,
                justification: recall.decision.stepUpPrompt ?? recall.decision.reason
            )
            latestOpenMindStepUpRequest = request
            if var updatedRecall = latestOpenMindRecall {
                updatedRecall.stepUpRequest = request
                latestOpenMindRecall = updatedRecall
            }
        }
    }

    @discardableResult
    func requestOpenMindWriteback(for runID: UUID) -> Task<Void, Never>? {
        guard copilotRuns.contains(where: { $0.id == runID }) else { return nil }
        return Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await writeBackOpenMindMemory(for: runID)
        }
    }

    @discardableResult
    func requestOpenMindCorrection(targetID: String, correctionText: String) -> Task<Void, Never>? {
        let trimmedTarget = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrection = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty, !trimmedCorrection.isEmpty else {
            return nil
        }

        return Task { @MainActor [weak self] in
            guard let self else { return }
            let run = copilotRuns.first
            if let runID = run?.id {
                appendCopilotEvent(
                    runID: runID,
                    kind: .memoryCorrectionRequested,
                    message: "Requested OpenMind correction for \(trimmedTarget)."
                )
            }

            let snapshot = latestPageSnapshot?.urlString == run?.targetURLString ? latestPageSnapshot : nil
            let request = OpenMindCorrectionRequest(
                targetID: trimmedTarget,
                correctionText: trimmedCorrection,
                actor: "dBrowser.user",
                source: OpenMindActionSource(
                    product: "dBrowser.swift",
                    runID: run?.id,
                    pageURLString: LLMPageContextSanitizer.sanitizedURLString(
                        run?.targetURLString ?? (activeTab?.isTraceMinimized == true ? nil : activeTab?.urlString)
                    ),
                    snapshotCommitment: OpenMindMemoryClient.snapshotCommitment(for: snapshot),
                    prompt: run?.prompt
                ),
                idempotencyKey: Self.stableCorrectionKey(targetID: trimmedTarget, correctionText: trimmedCorrection)
            )
            let outcome = await openMindMemoryClient.createCorrection(request)
            latestOpenMindCorrection = outcome
            openMindReviewTasks = await openMindMemoryClient.refreshReviewTasks()

            if let runID = run?.id {
                appendCopilotEvent(
                    runID: runID,
                    kind: copilotCorrectionEventKind(for: outcome),
                    message: copilotCorrectionMessage(for: outcome)
                )
            }
        }
    }

    @discardableResult
    func writeBackOpenMindMemory(for runID: UUID) async -> OpenMindWritebackOutcome {
        guard let run = copilotRuns.first(where: { $0.id == runID }) else {
            let outcome = OpenMindWritebackOutcome(
                status: .unavailable,
                revisionID: nil,
                message: "Copilot run is no longer available for memory writeback."
            )
            latestOpenMindWriteback = outcome
            return outcome
        }

        guard let result = run.result else {
            let outcome = OpenMindWritebackOutcome(
                status: .denied,
                revisionID: nil,
                message: "Copilot run has no completed result to remember."
            )
            latestOpenMindWriteback = outcome
            appendCopilotEvent(runID: runID, kind: .memoryWritebackDenied, message: outcome.message)
            return outcome
        }

        if openMindPostureState.status == .available && !openMindPostureState.allowsMemoryWriteback {
            let outcome = OpenMindWritebackOutcome(
                status: .denied,
                revisionID: nil,
                message: openMindPostureState.userMessage ?? openMindPostureState.summary
            )
            latestOpenMindWriteback = outcome
            appendCopilotEvent(runID: runID, kind: .memoryWritebackDenied, message: "OpenMind posture blocked writeback: \(outcome.message)")
            return outcome
        }

        appendCopilotEvent(runID: runID, kind: .memoryWritebackRequested, message: "Requested explicit OpenMind memory writeback.")
        let snapshot = latestPageSnapshot?.urlString == run.targetURLString ? latestPageSnapshot : nil
        let request = OpenMindWritebackRequest(
            runID: run.id,
            prompt: run.prompt,
            pageURLString: LLMPageContextSanitizer.sanitizedURLString(run.targetURLString),
            summary: result.summary,
            source: "dBrowser.copilot",
            snapshotCommitment: OpenMindMemoryClient.snapshotCommitment(for: snapshot),
            idempotencyKey: "copilot-\(run.id.uuidString)-writeback"
        )
        let outcome = await openMindMemoryClient.writeback(request)
        latestOpenMindWriteback = outcome
        appendCopilotEvent(
            runID: runID,
            kind: copilotWritebackEventKind(for: outcome),
            message: copilotWritebackMessage(for: outcome)
        )
        return outcome
    }

    func cancelCopilotRun(_ id: UUID) {
        copilotTasks[id]?.cancel()
        copilotTasks[id] = nil
        finishCopilotRun(id, status: .cancelled, result: nil, message: "Run cancelled.")
    }

    @discardableResult
    func saveCopilotWorkflow(
        title: String,
        promptTemplate: String,
        targetURLPattern: String? = nil,
        allowedActions: [BrowserDOMAction.Kind] = [],
        schedule: CopilotWorkflowSchedule = .manual
    ) -> SavedCopilotWorkflow {
        let workflow = SavedCopilotWorkflow(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled workflow" : title,
            promptTemplate: promptTemplate,
            targetURLPattern: targetURLPattern,
            allowedActions: allowedActions,
            schedule: schedule
        )
        copilotWorkflows.insert(workflow, at: 0)
        persistWorkflows()
        return workflow
    }

    @discardableResult
    func runWorkflow(_ id: UUID) -> UUID? {
        guard let index = copilotWorkflows.firstIndex(where: { $0.id == id }) else { return nil }
        guard copilotWorkflows[index].isEnabled else { return nil }
        guard activeCopilotRunCount == 0 else {
            recordScheduledWorkflowState(
                workflow: copilotWorkflows[index],
                phase: .waitingForUser,
                message: "The workflow is waiting for Copilot to become idle."
            )
            return nil
        }
        guard let activeTab, isCopilotContextEligible(activeTab),
              copilotWorkflows[index].targetMatches(activeTab.urlString) else {
            recordScheduledWorkflowState(
                workflow: copilotWorkflows[index],
                phase: .waitingForUser,
                message: "Open a tab matching the workflow target before running it."
            )
            return nil
        }
        guard let runID = sendLLMMessageWithFreshContext(copilotWorkflows[index].promptTemplate) else {
            recordScheduledWorkflowState(
                workflow: copilotWorkflows[index],
                phase: .waitingForUser,
                message: "The workflow is waiting for a visible, fully loaded page and an idle Copilot."
            )
            return nil
        }
        copilotWorkflows[index].lastRunAt = Date()
        if copilotWorkflows[index].schedule.kind == .everyLaunch {
            everyLaunchWorkflowIDsRunThisSession.insert(id)
        }
        workflowByCopilotRunID[runID] = id
        recordScheduledWorkflowState(
            workflow: copilotWorkflows[index],
            phase: .queued,
            message: "Workflow queued with the normal fresh-context and approval boundaries.",
            runID: runID
        )
        persistWorkflows()
        return runID
    }

    func startWorkflowScheduler() {
        guard workflowMonitorTask == nil else { return }
        evaluateScheduledWorkflows()
        workflowMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    return
                }
                guard let self else { return }
                self.evaluateScheduledWorkflows()
            }
        }
    }

    func stopWorkflowScheduler() {
        workflowMonitorTask?.cancel()
        workflowMonitorTask = nil
    }

    func evaluateScheduledWorkflows(now: Date = Date()) {
        for workflow in copilotWorkflows where workflow.isDue(
            now: now,
            hasRunThisLaunch: everyLaunchWorkflowIDsRunThisSession.contains(workflow.id)
        ) {
            if let current = scheduledWorkflowStates.first(where: { $0.workflowID == workflow.id }),
               current.phase == .queued || current.phase == .running {
                continue
            }
            guard let activeTab, isCopilotContextEligible(activeTab),
                  workflow.targetMatches(activeTab.urlString) else {
                recordScheduledWorkflowState(
                    workflow: workflow,
                    phase: .waitingForUser,
                    message: "Due, but waiting for a visible tab matching \(workflow.targetURLPattern ?? "its target").",
                    now: now
                )
                continue
            }
            guard activeTab.isLoading == false,
                  pendingFreshCopilotContexts.isEmpty,
                  automationRequest == nil,
                  activeCopilotRunCount == 0 else {
                recordScheduledWorkflowState(
                    workflow: workflow,
                    phase: .waitingForUser,
                    message: "Due, but waiting for the visible page to finish loading and Copilot to become idle.",
                    now: now
                )
                continue
            }
            guard let runID = sendLLMMessageWithFreshContext(workflow.promptTemplate),
                  let index = copilotWorkflows.firstIndex(where: { $0.id == workflow.id }) else {
                recordScheduledWorkflowState(
                    workflow: workflow,
                    phase: .waitingForUser,
                    message: "Due, but could not establish a fresh approved context.",
                    now: now
                )
                continue
            }
            copilotWorkflows[index].lastRunAt = now
            if workflow.schedule.kind == .everyLaunch {
                everyLaunchWorkflowIDsRunThisSession.insert(workflow.id)
            }
            workflowByCopilotRunID[runID] = workflow.id
            recordScheduledWorkflowState(
                workflow: copilotWorkflows[index],
                phase: .queued,
                message: "Scheduled workflow queued visibly with fresh context.",
                now: now,
                runID: runID
            )
            persistWorkflows()
        }
    }

    private func recordScheduledWorkflowState(
        workflow: SavedCopilotWorkflow,
        phase: CopilotScheduledWorkflowPhase,
        message: String,
        now: Date = Date(),
        runID: UUID? = nil
    ) {
        let state = CopilotScheduledWorkflowState(
            workflowID: workflow.id,
            title: workflow.title,
            phase: phase,
            message: message,
            evaluatedAt: now,
            runID: runID
        )
        if let index = scheduledWorkflowStates.firstIndex(where: { $0.workflowID == workflow.id }) {
            scheduledWorkflowStates[index] = state
        } else {
            scheduledWorkflowStates.insert(state, at: 0)
        }
    }

    func setWorkflow(_ id: UUID, isEnabled: Bool) {
        guard let index = copilotWorkflows.firstIndex(where: { $0.id == id }) else { return }
        copilotWorkflows[index].isEnabled = isEnabled
        persistWorkflows()
    }

    func deleteWorkflow(_ id: UUID) {
        copilotWorkflows.removeAll { $0.id == id }
        persistWorkflows()
    }

    func smartHistoryRecall(_ query: String, limit: Int = 6) -> [SmartHistoryRecallResult] {
        historyService.smartHistoryRecall(query, in: history, limit: limit)
    }

    func setSmartHistoryIndexing(enabled: Bool, forDomain domain: String) {
        history = historyService.settingIndexing(enabled: enabled, forDomain: domain, in: history)
    }

    func clearSmartHistorySummaries() {
        history = historyService.clearingSummaries(in: history)
    }

    func deleteHistoryEntry(_ id: UUID) {
        history = historyService.deleting(id: id, from: history)
    }

    func applyNavigationUpdate(_ update: BrowserNavigationUpdate) {
        guard let index = tabs.firstIndex(where: { $0.id == update.tabID }) else { return }
        let updatedURLString = update.urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlDidChange = updatedURLString.map { !$0.isEmpty && $0 != tabs[index].urlString } == true
        let didStartLoading = update.isLoading && !tabs[index].isLoading
        if !tabs[index].isTraceMinimized, urlDidChange || didStartLoading {
            beginPageNavigation(
                for: update.tabID,
                reason: "The page navigated before its fresh snapshot was ready."
            )
        }
        if let title = update.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            tabs[index].title = title
        }
        if let urlString = update.urlString, !urlString.isEmpty {
            if tabs[index].isTraceMinimized {
                tabs[index].loadURLString = urlString
            } else {
                tabs[index].urlString = urlString
            }
            if update.tabID == activeTabID {
                addressText = tabs[index].isTraceMinimized ? tabs[index].urlString : urlString
            }
        }
        tabs[index].isLoading = update.isLoading
        tabs[index].canGoBack = update.canGoBack
        tabs[index].canGoForward = update.canGoForward

        if !tabs[index].isTraceMinimized, !update.isLoading, let urlString = update.urlString, !urlString.isEmpty {
            recordHistory(title: tabs[index].title, urlString: urlString)
        }
    }

    private func issueCommand(_ command: BrowserWebCommand) {
        guard let tab = activeTab else { return }
        webCommand = BrowserWebCommandRequest(tabID: tab.id, command: command)
    }

    @discardableResult
    private func issueAutomationRequest(_ command: BrowserAutomationCommand) -> BrowserAutomationRequest? {
        guard let tab = activeTab else { return nil }
        return issueAutomationRequest(command, for: tab)
    }

    @discardableResult
    private func issueAutomationRequest(
        _ command: BrowserAutomationCommand,
        for tab: BrowserTab,
        approvalGrant: BrowserAutomationApprovalGrant? = nil
    ) -> BrowserAutomationRequest? {
        guard pendingFreshCopilotContexts.isEmpty, automationRequest == nil else { return nil }
        let request = BrowserAutomationRequest(
            tabID: tab.id,
            command: command,
            timeoutSeconds: automationRequestTimeoutSeconds,
            navigationGeneration: pageNavigationGenerations[tab.id] ?? 0,
            approvalGrant: approvalGrant
        )
        switch command {
        case .pageSnapshot, .textSelection:
            registerPageSnapshotCapture(request, for: tab)
        case .domQuery, .action:
            break
        }
        automationRequest = request
        scheduleAutomationTimeout(for: request)
        return request
    }

    private func resolveThroughRuntimeBridge(
        raw: String,
        fallbackMessage: String,
        tabID: UUID,
        privateOverlayNetwork: PrivateOverlayNetwork? = nil
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let torrentTransferNetwork = DecentralizedStorageNetwork.privacyScopedTransferProfile(forInput: raw)
        tabs[index].title = privateOverlayNetwork?.title ?? torrentTransferNetwork?.title ?? "Runtime bridge"
        tabs[index].urlString = raw
        tabs[index].loadURLString = nil
        if privateOverlayNetwork != nil {
            tabs[index].mobileNotice = "Resolving through the local private-overlay adapter."
        } else if torrentTransferNetwork != nil {
            tabs[index].mobileNotice = "Resolving through the local torrent transfer adapter."
        } else {
            tabs[index].mobileNotice = "Resolving through the iOS runtime bridge."
        }
        tabs[index].isLoading = true
        tabs[index].canGoBack = false
        tabs[index].canGoForward = false
        tabs[index].isPrivateOverlay = privateOverlayNetwork != nil
        tabs[index].privateOverlayNetworkID = privateOverlayNetwork?.id
        tabs[index].isTorrentTransfer = torrentTransferNetwork != nil
        tabs[index].torrentTransferNetworkID = torrentTransferNetwork?.id
        if privateOverlayNetwork != nil || torrentTransferNetwork != nil {
            latestDOMQueryResult = nil
            latestPageSnapshot = nil
        }
        addressText = raw

        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolution = await runtimeBridge.resolve(raw)
            applyRuntimeResolution(resolution, tabID: tabID, fallbackMessage: fallbackMessage)
        }
    }

    private func applyRuntimeResolution(
        _ resolution: RuntimeBridgeResolution,
        tabID: UUID,
        fallbackMessage: String
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let privateOverlayNetwork = PrivateOverlayNetwork.profile(forInput: resolution.originalInput)
        let torrentTransferNetwork = DecentralizedStorageNetwork.privacyScopedTransferProfile(forInput: resolution.originalInput)
        let isPrivateOverlayResolution = resolution.source == .privateOverlayLocalAdapter
            || resolution.source == .privateOverlayAdapterRequired
            || privateOverlayNetwork != nil
        let isTorrentTransferResolution = torrentTransferNetwork != nil
            && (resolution.source == .decentralizedStorageNativeAdapter
                || resolution.source == .decentralizedStorageResolverRequired)
        guard let resolvedURLString = resolution.resolvedURLString, let url = URL(string: resolvedURLString) else {
            tabs[index].title = privateOverlayNetwork?.title ?? torrentTransferNetwork?.title ?? "Mobile runtime"
            tabs[index].urlString = resolution.originalInput
            tabs[index].loadURLString = nil
            tabs[index].mobileNotice = resolution.message ?? fallbackMessage
            tabs[index].isLoading = false
            tabs[index].canGoBack = false
            tabs[index].canGoForward = false
            tabs[index].isPrivateOverlay = isPrivateOverlayResolution
            tabs[index].privateOverlayNetworkID = privateOverlayNetwork?.id
            tabs[index].isTorrentTransfer = isTorrentTransferResolution
            tabs[index].torrentTransferNetworkID = torrentTransferNetwork?.id
            if tabID == activeTabID {
                addressText = resolution.originalInput
            }
            return
        }

        if isPrivateOverlayResolution {
            tabs[index].title = privateOverlayNetwork?.title ?? "Private overlay"
            tabs[index].urlString = resolution.originalInput
            tabs[index].loadURLString = resolvedURLString
            tabs[index].mobileNotice = nil
            tabs[index].isLoading = true
            tabs[index].isPrivateOverlay = true
            tabs[index].privateOverlayNetworkID = privateOverlayNetwork?.id
            tabs[index].isTorrentTransfer = false
            tabs[index].torrentTransferNetworkID = nil
            if tabID == activeTabID {
                addressText = resolution.originalInput
            }
            return
        }

        if isTorrentTransferResolution {
            tabs[index].title = torrentTransferNetwork?.title ?? "Torrent transfer"
            tabs[index].urlString = resolution.originalInput
            tabs[index].loadURLString = resolvedURLString
            tabs[index].mobileNotice = nil
            tabs[index].isLoading = true
            tabs[index].isPrivateOverlay = false
            tabs[index].privateOverlayNetworkID = nil
            tabs[index].isTorrentTransfer = true
            tabs[index].torrentTransferNetworkID = torrentTransferNetwork?.id
            if tabID == activeTabID {
                addressText = resolution.originalInput
            }
            return
        }

        let title = titleForURL(url)
        tabs[index].title = title
        tabs[index].urlString = resolvedURLString
        tabs[index].loadURLString = nil
        tabs[index].mobileNotice = nil
        tabs[index].isLoading = true
        tabs[index].isPrivateOverlay = false
        tabs[index].privateOverlayNetworkID = nil
        tabs[index].isTorrentTransfer = false
        tabs[index].torrentTransferNetworkID = nil
        if tabID == activeTabID {
            addressText = resolvedURLString
        }
        recordHistory(title: title, urlString: resolvedURLString)
    }

    private func recordHistory(title: String, urlString: String) {
        history = historyService.recording(title: title, urlString: urlString, into: history)
    }

    private func updateSmartHistorySummary(from snapshot: PageSnapshot) {
        history = historyService.updatingSummary(from: snapshot, in: history)
    }

    private func persistWorkflows() {
        workflowStore.save(copilotWorkflows)
    }

    func persistResearchLedgers() {
        researchLedgerStore.save(researchLedgers)
    }

    func persistDeveloperWorkflowRuns() {
        developerWorkflowStore.save(developerWorkflowRuns)
    }

    private func persistLLMConversation() {
        llmConversationArchive.upsertConversation(llmConversation, select: true)
        llmConversationArchive.selectedModelID = selectedLLMModelID
        llmConversations = llmConversationArchive.conversations
        llmConversationStore.save(llmConversationArchive)
    }

    private func normalizeSelectedLLMModelIfNeeded() {
        let restoredModel = Self.restoredLLMModel(for: selectedLLMModelID, models: llmModelOptions)
        guard restoredModel.id != selectedLLMModelID else { return }
        selectedLLMModelID = restoredModel.id
        llmConversation.switchModel(to: restoredModel.id, displayName: restoredModel.displayName)
        persistLLMConversation()
    }

    private static func restoredLLMState(
        from payload: LLMConversationStorePayload,
        models: [LLMModelProfile]
    ) -> (conversation: LLMConversation, selectedModelID: String, shouldPersist: Bool) {
        let requestedModelID = payload.selectedModelID.isEmpty ? payload.conversation.activeModelID : payload.selectedModelID
        let restoredModel = restoredLLMModel(for: requestedModelID, models: models)
        var conversation = payload.conversation
        var shouldPersist = payload.selectedModelID != restoredModel.id || payload.conversation.activeModelID != restoredModel.id
        if conversation.activeModelID != restoredModel.id {
            conversation.switchModel(to: restoredModel.id, displayName: restoredModel.displayName)
            shouldPersist = true
        }
        return (conversation, restoredModel.id, shouldPersist)
    }

    private static func reconcileRestoredToolProposals(
        in payload: LLMConversationStorePayload
    ) -> (payload: LLMConversationStorePayload, didChange: Bool) {
        var didChange = false
        let conversations = payload.conversations.map { archived -> LLMConversation in
            var conversation = archived
            for index in conversation.toolProposals.indices {
                let eventKind: LLMConversationEventKind
                switch conversation.toolProposals[index].status {
                case .pendingApproval:
                    conversation.toolProposals[index].status = .expired
                    conversation.toolProposals[index].statusMessage = "The app relaunched without the proposal's original tab and page generation. Nothing executed."
                    eventKind = .toolDenied
                case .approved, .executing:
                    conversation.toolProposals[index].status = .consumed
                    conversation.toolProposals[index].statusMessage = "The app relaunched after this one-time approval began. Its outcome is unconfirmed and it will not be retried."
                    eventKind = .toolExecuted
                case .denied, .completed, .failed, .expired, .consumed:
                    continue
                }
                didChange = true
                let proposal = conversation.toolProposals[index]
                conversation.appendEvent(
                    LLMConversationEvent(
                        kind: eventKind,
                        message: proposal.statusMessage,
                        relatedRunID: proposal.sourceRunID,
                        relatedToolProposalID: proposal.id
                    )
                )
            }
            return conversation
        }
        guard didChange else { return (payload, false) }
        return (
            LLMConversationStorePayload(
                conversations: conversations,
                selectedConversationID: payload.selectedConversationID,
                selectedModelID: payload.selectedModelID
            ),
            true
        )
    }

    private static func restoredLLMModel(for id: String, models: [LLMModelProfile]) -> LLMModelProfile {
        if let model = models.first(where: { $0.id == id && $0.availability.isRunnable }) {
            return model
        }
        if let defaultModel = models.first(where: { $0.id == LLMModelRegistry.defaultModelID }) {
            return defaultModel
        }
        return models[0]
    }

    private func targetElement(for action: BrowserDOMAction) -> DOMElementRecord? {
        guard let latestDOMQueryResult else { return nil }
        if let elementIndex = action.elementIndex {
            return latestDOMQueryResult.elements.first { $0.index == elementIndex }
        }
        guard let selector = action.selector?.lowercased() else { return nil }
        return latestDOMQueryResult.elements.first { element in
            element.searchableText.contains(selector)
        }
    }

    private func appendDeveloperWorkflowSnapshotEvidence(_ snapshot: PageSnapshot, tabID: UUID) {
        guard let index = developerWorkflowRuns.firstIndex(where: { run in
            guard run.status == .running || run.status == .draft else { return false }
            if let copilotRunID = run.copilotRunID,
               copilotRuns.first(where: { $0.id == copilotRunID })?.activeTabID != tabID {
                return false
            }
            if let sourceURLString = run.sourceURLString {
                return sourceURLString == snapshot.urlString
            }
            return true
        }) else {
            return
        }

        let alreadyCaptured = developerWorkflowRuns[index].evidenceItems.contains {
            $0.kind == .pageSnapshot && $0.sourceURLString == snapshot.urlString
        }
        guard !alreadyCaptured else { return }

        developerWorkflowRuns[index].appendEvidence(
            BrowserDeveloperEvidenceItem(
                kind: .pageSnapshot,
                title: "Bounded page snapshot",
                summary: "\(snapshot.title): \(snapshot.visibleText.count) text characters, \(snapshot.links.count) links, \(snapshot.formControls.count) form controls.",
                sourceURLString: snapshot.urlString,
                redactionState: snapshot.redactionCount > 0 ? .redacted : .none,
                privacyBoundary: .redactedModelContext,
                metadata: [
                    "title": snapshot.title,
                    "textCharacters": "\(snapshot.visibleText.count)",
                    "redactions": "\(snapshot.redactionCount)"
                ]
            )
        )
        persistDeveloperWorkflowRuns()
    }

    private func syncDeveloperWorkflowRun(
        copilotRunID: UUID,
        status: CopilotRunStatus,
        result: CopilotRunResult?,
        message: String
    ) {
        guard let index = developerWorkflowRuns.firstIndex(where: { $0.copilotRunID == copilotRunID }) else { return }
        let now = Date()
        switch status {
        case .completed:
            developerWorkflowRuns[index].status = developerWorkflowRuns[index].requiresApprovalBeforeMutation ? .waitingForApproval : .completed
        case .cancelled, .failed:
            developerWorkflowRuns[index].status = .blocked
        case .queued, .running:
            developerWorkflowRuns[index].status = .running
        }
        developerWorkflowRuns[index].updatedAt = now
        developerWorkflowRuns[index].localOutput = result?.summary ?? message
        if let result,
           !developerWorkflowRuns[index].evidenceItems.contains(where: { $0.kind == .timestampedNote && $0.title == "Copilot output" }) {
            developerWorkflowRuns[index].appendEvidence(
                BrowserDeveloperEvidenceItem(
                    kind: .timestampedNote,
                    title: "Copilot output",
                    capturedAt: now,
                    summary: result.summary,
                    sourceURLString: developerWorkflowRuns[index].sourceURLString,
                    redactionState: .sensitiveOmitted,
                    privacyBoundary: .localOnly,
                    metadata: ["mode": result.mode.rawValue]
                ),
                now: now
            )
        }
        persistDeveloperWorkflowRuns()
    }

    private func appendApproval(_ approval: BrowserAutomationApproval, tabID: UUID) {
        guard let index = copilotRuns.firstIndex(where: { $0.activeTabID == tabID && $0.status == .running }) else { return }
        copilotRuns[index].approvals.append(approval)
        copilotRuns[index].events.append(
            CopilotRunEvent(kind: .approvalRequired, message: approval.summary)
        )
    }

    private func updateConversationToolProposal(
        _ proposal: CopilotToolProposal,
        eventKind: LLMConversationEventKind
    ) {
        llmConversation.upsertToolProposal(proposal)
        llmConversation.appendEvent(
            LLMConversationEvent(
                kind: eventKind,
                message: proposal.statusMessage,
                relatedRunID: proposal.sourceRunID,
                relatedToolProposalID: proposal.id
            )
        )
        persistLLMConversation()
    }

    private func resolveToolProposal(
        with result: BrowserAutomationResult,
        approvedOutcomeIsAmbiguous: Bool = false
    ) {
        guard let proposalID = toolProposalByAutomationRequestID.removeValue(forKey: result.requestID),
              let index = copilotToolProposals.firstIndex(where: { $0.id == proposalID }) else {
            return
        }
        if approvedOutcomeIsAmbiguous {
            copilotToolProposals[index].status = .consumed
            copilotToolProposals[index].statusMessage = "\(result.message) The approved one-time command may have executed; its outcome is unconfirmed and it will not be retried automatically."
        } else {
            copilotToolProposals[index].status = result.status == .success ? .completed : .failed
            copilotToolProposals[index].statusMessage = result.message
        }
        let proposal = copilotToolProposals[index]
        updateConversationToolProposal(proposal, eventKind: .toolExecuted)
        appendCopilotEvent(
            runID: proposal.sourceRunID,
            kind: !approvedOutcomeIsAmbiguous && result.status == .success ? .actionCompleted : .failed,
            message: proposal.statusMessage
        )
    }

    private func resolveInactiveTabCapture(with result: BrowserAutomationResult) {
        guard inactiveTabCaptureRequestID == result.requestID else { return }
        inactiveTabCaptureRequestID = nil
        if result.status == .success, result.pageSnapshot != nil {
            inactiveTabCaptureState.phase = .captured
            inactiveTabCaptureState.message = "Captured one bounded snapshot. Select the tab context explicitly to attach it."
        } else {
            inactiveTabCaptureState.phase = .failed
            inactiveTabCaptureState.message = result.message
        }
    }

    private func appendCopilotEvent(runID: UUID, kind: CopilotRunEventKind, message: String) {
        guard let index = copilotRuns.firstIndex(where: { $0.id == runID }) else { return }
        copilotRuns[index].events.append(CopilotRunEvent(kind: kind, message: message))
    }

    private func appendConversationLinkedCopilotEvent(kind: CopilotRunEventKind, message: String) {
        guard let runID = copilotRuns.first(where: {
            $0.conversationID == llmConversation.id && ($0.status == .queued || $0.status == .running)
        })?.id else {
            return
        }
        appendCopilotEvent(runID: runID, kind: kind, message: message)
    }

    private func appendContextCompressionEvent(
        _ renderedContext: LLMRenderedConversationContext,
        model: LLMModelProfile,
        runID: UUID? = nil
    ) {
        llmConversation.appendEvent(
            LLMConversationEvent(
                kind: .contextCompressed,
                message: "Compressed \(renderedContext.compressedMessageIDs.count) prior message\(renderedContext.compressedMessageIDs.count == 1 ? "" : "s") for \(model.displayName).",
                toModelID: model.id,
                relatedRunID: runID,
                relatedArtifactID: renderedContext.contextSummaryArtifactID
            )
        )
        persistLLMConversation()
    }

    @discardableResult
    private func ensureContextSummaryArtifact(
        for sourceMessageIDs: [UUID],
        model: LLMModelProfile,
        in conversation: inout LLMConversation
    ) -> LLMContextSummaryArtifact? {
        guard !sourceMessageIDs.isEmpty else { return nil }
        if let existing = conversation.contextSummaryArtifacts.last(where: {
            $0.targetModelID == model.id && $0.sourceMessageIDs == sourceMessageIDs
        }) {
            return existing
        }
        let sourceIDSet = Set(sourceMessageIDs)
        let summary = SmartHistoryIndexer.boundedText(
            conversation.messages
            .filter { sourceIDSet.contains($0.id) }
            .map { "\($0.role.rawValue): \($0.text)" }
            .joined(separator: "\n")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            limit: 1_200
        )
        let protectedKinds: Set<LLMConversationEventKind> = [
            .toolProposed,
            .toolApproved,
            .toolDenied,
            .toolExecuted,
            .memoryContextAttached,
            .providerFallback
        ]
        let protectedEventIDs = conversation.events
            .filter { protectedKinds.contains($0.kind) }
            .map(\.id)
        let artifact = LLMContextSummaryArtifact(
            summary: summary,
            sourceMessageIDs: sourceMessageIDs,
            protectedEventIDs: protectedEventIDs,
            targetModelID: model.id,
            providerProvenance: LLMMessageProviderProvenance(model: model)
        )
        guard conversation.appendContextSummaryArtifact(artifact) else { return nil }
        conversation.appendEvent(
            LLMConversationEvent(
                kind: .summaryArtifactCreated,
                message: "Created linked context summary \(String(artifact.commitment.prefix(18))) for \(sourceMessageIDs.count) source messages.",
                toModelID: model.id,
                relatedArtifactID: artifact.id
            )
        )
        return artifact
    }

    private func renderContextWithCommittedSummaryArtifact(
        startingWith initialContext: LLMRenderedConversationContext,
        conversationAtBoundary: LLMConversation,
        model: LLMModelProfile,
        latestPageSnapshot: PageSnapshot?,
        relatedPageSnapshots: [PageSnapshot],
        memoryRecall: OpenMindMemoryRecallResult?
    ) -> LLMRenderedConversationContext? {
        let effectiveTokenBudget = LLMConversationContextRenderer.effectiveTokenBudget(for: model)
        let maximumAttempts = min(
            max(2, conversationAtBoundary.messages.count + 1),
            LLMContextSummaryArtifactPolicy.maximumArtifactsPerConversation + 1
        )
        var attemptedSourceSets = Set<String>()
        var candidate = initialContext
        var boundaryConversation = conversationAtBoundary

        for _ in 0..<maximumAttempts {
            guard candidate.wasCompressed,
                  candidate.estimatedPromptTokens <= effectiveTokenBudget else {
                return nil
            }
            if let artifactID = candidate.contextSummaryArtifactID,
               let artifactCommitment = candidate.contextSummaryArtifactCommitment,
               let artifact = boundaryConversation.contextSummaryArtifact(withID: artifactID),
               artifact.targetModelID == model.id,
               artifact.sourceMessageIDs == candidate.compressedMessageIDs,
               artifact.commitment == artifactCommitment {
                guard commitContextSummaryArtifact(
                    artifact,
                    conversationID: conversationAtBoundary.id,
                    model: model
                ) else {
                    return nil
                }
                return candidate
            }

            let sourceSetKey = candidate.compressedMessageIDs
                .map(\.uuidString)
                .joined(separator: ",")
            guard attemptedSourceSets.insert(sourceSetKey).inserted,
                  ensureContextSummaryArtifact(
                      for: candidate.compressedMessageIDs,
                      model: model,
                      in: &boundaryConversation
                  ) != nil else {
                return nil
            }
            candidate = LLMConversationContextRenderer.render(
                conversation: boundaryConversation,
                model: model,
                latestPageSnapshot: latestPageSnapshot,
                relatedPageSnapshots: relatedPageSnapshots,
                memoryRecall: memoryRecall
            )
        }
        return nil
    }

    private func commitContextSummaryArtifact(
        _ artifact: LLMContextSummaryArtifact,
        conversationID: UUID,
        model: LLMModelProfile
    ) -> Bool {
        guard llmConversation.id == conversationID else { return false }
        let messageIDs = Set(llmConversation.messages.map(\.id))
        let eventIDsBeforeCommit = Set(llmConversation.events.map(\.id))
        guard artifact.sourceMessageIDs.allSatisfy(messageIDs.contains),
              artifact.protectedEventIDs.allSatisfy(eventIDsBeforeCommit.contains) else {
            return false
        }
        if let existing = llmConversation.contextSummaryArtifact(withID: artifact.id) {
            return existing == artifact
        }

        let conversationBeforeCommit = llmConversation
        guard llmConversation.appendContextSummaryArtifact(artifact) else { return false }
        llmConversation.appendEvent(
            LLMConversationEvent(
                kind: .summaryArtifactCreated,
                message: "Created linked context summary \(String(artifact.commitment.prefix(18))) for \(artifact.sourceMessageIDs.count) source messages.",
                toModelID: model.id,
                relatedArtifactID: artifact.id
            )
        )
        let eventIDsAfterCommit = Set(llmConversation.events.map(\.id))
        guard let committed = llmConversation.contextSummaryArtifact(withID: artifact.id),
              committed == artifact,
              artifact.protectedEventIDs.allSatisfy(eventIDsAfterCommit.contains) else {
            llmConversation = conversationBeforeCommit
            return false
        }
        return true
    }

    private func appendProviderFallback(runID: UUID, requestedModel: LLMModelProfile, actualMode: RuntimeBridgeMode) {
        let message = "\(requestedModel.displayName) requested \(requestedModel.runtimeMode.title) execution; runtime used \(actualMode.title)."
        llmConversation.appendEvent(
            LLMConversationEvent(
                kind: .providerFallback,
                message: message,
                toModelID: requestedModel.id,
                relatedRunID: runID
            )
        )
        persistLLMConversation()
        appendCopilotEvent(runID: runID, kind: .providerFallback, message: message)
    }

    private func appendAssistantConversationMessage(
        result: CopilotRunResult,
        runID: UUID,
        model: LLMModelProfile,
        targetURLString: String?,
        memoryCitations: [LLMMemoryCitation],
        sourceCitations: [LLMSourceCitation] = [],
        contextSummaryArtifactID: UUID?,
        usage: CopilotCreditUsage
    ) {
        let suggestions = result.suggestions.isEmpty ? "" : "\n\n" + result.suggestions.map { "- \($0)" }.joined(separator: "\n")
        let actualModelID = result.llmRouterResponse?.modelID
            ?? result.llmGatewayResponse?.modelID
            ?? model.id
        let boundarySummary = result.llmGatewayResponse?.boundarySummary
            ?? model.contextMinimization.disclosureBoundary
        let provenance = LLMMessageProviderProvenance(
            requestedModelID: model.id,
            actualModelID: actualModelID,
            providerKind: model.providerKind,
            trustBoundary: model.trustBoundary,
            providerDisplayName: model.displayName,
            boundarySummary: boundarySummary,
            afMarketRunnerPackID: result.afmNodeTask?.packID,
            routeID: result.llmRouterResponse?.route
        )
        let assistantMessage = LLMConversationMessage(
            role: .assistant,
            text: result.summary + suggestions,
            modelID: model.id,
            pageURLString: targetURLString,
            memoryCitations: memoryCitations,
            usage: usage,
            sourceRunID: runID,
            sourceCitations: sourceCitations,
            providerProvenance: provenance,
            sourceMessageID: sourceMessageByCopilotRunID[runID],
            regeneratedFromMessageID: regeneratedAssistantByCopilotRunID[runID],
            contextSummaryArtifactID: contextSummaryArtifactID
        )
        llmConversation.appendMessage(assistantMessage)
        llmConversation.appendEvent(
            LLMConversationEvent(
                kind: .assistantMessageAdded,
                message: "Added assistant message from \(model.displayName).",
                toModelID: model.id,
                relatedRunID: runID,
                relatedMessageID: assistantMessage.id
            )
        )
        sourceMessageByCopilotRunID[runID] = nil
        regeneratedAssistantByCopilotRunID[runID] = nil
        persistLLMConversation()
    }

    private func validatePendingResearchSynthesis(
        runID: UUID,
        responseText: String
    ) throws -> BrowserResearchSynthesisResult? {
        guard let pending = pendingResearchSynthesisByRunID.removeValue(forKey: runID) else {
            return nil
        }
        do {
            let envelope = try JSONDecoder().decode(
                BrowserResearchSynthesisEnvelope.self,
                from: Data(responseText.utf8)
            )
            let result = try BrowserResearchSynthesisValidator.validate(
                envelope,
                against: pending.request
            )
            researchSynthesisResultsBySessionID[pending.sessionID] = result
            researchSynthesisErrorsBySessionID[pending.sessionID] = nil
            var ledger = researchLedgers.first(where: {
                $0.topic.caseInsensitiveCompare(pending.request.query) == .orderedSame
            }) ?? BrowserResearchLedger(topic: pending.request.query, entries: [])
            ledger.upsertValidatedSynthesis(result)
            if let index = researchLedgers.firstIndex(where: {
                $0.topic.caseInsensitiveCompare(pending.request.query) == .orderedSame
            }) {
                researchLedgers[index] = ledger
            } else {
                researchLedgers.insert(ledger, at: 0)
            }
            persistResearchLedgers()
            llmConversation.appendEvent(
                LLMConversationEvent(
                    kind: .researchSourcesAttached,
                    message: "Validated and persisted \(result.citations.count) cited research source\(result.citations.count == 1 ? "" : "s").",
                    relatedRunID: runID
                )
            )
            return result
        } catch {
            researchSynthesisErrorsBySessionID[pending.sessionID] =
                "Source-only research synthesis failed validation; no provider output was retained."
            throw error
        }
    }

    private func sanitizedResearchResult(
        from result: CopilotRunResult,
        answer: String
    ) -> CopilotRunResult {
        CopilotRunResult(
            id: result.id,
            title: "Validated source-only research",
            summary: answer,
            suggestions: [],
            ranAt: result.ranAt,
            mode: result.mode,
            transport: result.transport
        )
    }

    private func appendAFMarketEvents(runID: UUID, result: CopilotRunResult) {
        if let install = result.afmInstall {
            appendCopilotEvent(
                runID: runID,
                kind: .afMarketInstallCompleted,
                message: "Installed AFMarket pack \(install.packID) on node with \(install.mode) receipt."
            )
        }

        guard let nodeTask = result.afmNodeTask else { return }
        appendCopilotEvent(
            runID: runID,
            kind: .afMarketDispatchCompleted,
            message: "Node dispatched \(nodeTask.taskID) with \(nodeTask.status) status."
        )
        appendCopilotEvent(
            runID: runID,
            kind: .afMarketAttestationRecorded,
            message: "Recorded \(nodeTask.attestation.mode) attestation \(nodeTask.attestation.outputCommitment)."
        )
        appendCopilotEvent(
            runID: runID,
            kind: .afMarketSettlementRecorded,
            message: "Recorded \(nodeTask.settlement.status) settlement on \(nodeTask.settlement.chainRef ?? "local-devnet")."
        )
        let verificationReport = nodeTask.verificationReport
        appendCopilotEvent(
            runID: runID,
            kind: .afMarketVerificationRecorded,
            message: "\(verificationReport.state.title): \(verificationReport.summary)"
        )
        if let chainTrustUpdate = result.chainTrustUpdate {
            appendCopilotEvent(
                runID: runID,
                kind: .chainTrustUpdated,
                message: "Chain trust \(chainTrustUpdate.state.title): \(chainTrustUpdate.displaySummary)"
            )
        }
    }

    private func appendLLMRouterEvents(runID: UUID, result: CopilotRunResult) {
        guard let response = result.llmRouterResponse else { return }
        appendCopilotEvent(
            runID: runID,
            kind: .modelCompleted,
            message: "LLM router completed \(response.modelID) through \(response.provider.rawValue)."
        )
        guard let run = copilotRuns.first(where: { $0.id == runID }),
              let targetURLString = run.targetURLString,
              let tab = tabs.first(where: { $0.id == run.activeTabID }),
              let pageBinding = pageBindingByCopilotRunID[runID],
              pageBinding.tabID == run.activeTabID,
              pageBinding.navigationGeneration == (pageNavigationGenerations[run.activeTabID] ?? 0),
              CopilotToolProposalFactory.pageCommitment(urlString: targetURLString)
                  == pageBinding.targetPageCommitment,
              CopilotToolProposalFactory.pageCommitment(urlString: tab.urlString)
                  == pageBinding.targetPageCommitment else {
            if !response.toolCalls.isEmpty {
                appendCopilotEvent(
                    runID: runID,
                    kind: .failed,
                    message: "Discarded provider tool proposals because their captured page binding is no longer current."
                )
            }
            return
        }
        let allowedActions: Set<BrowserDOMAction.Kind>? = workflowByCopilotRunID[runID]
            .flatMap { workflowID in copilotWorkflows.first(where: { $0.id == workflowID }) }
            .map { Set($0.allowedActions) }
        for toolCall in response.toolCalls {
            do {
                let proposal = try CopilotToolProposalFactory.make(
                    toolCall: toolCall,
                    sourceRunID: runID,
                    targetTabID: run.activeTabID,
                    targetURLString: targetURLString,
                    navigationGeneration: pageBinding.navigationGeneration,
                    allowedActions: allowedActions
                )
                copilotToolProposals.insert(proposal, at: 0)
                updateConversationToolProposal(proposal, eventKind: .toolProposed)
                appendCopilotEvent(
                    runID: runID,
                    kind: .approvalRequired,
                    message: "LLM router proposed allowlisted tool \(toolCall.name); explicit approval is required."
                )
            } catch {
                appendCopilotEvent(
                    runID: runID,
                    kind: .failed,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func appendLLMGatewayEvents(runID: UUID, result: CopilotRunResult) {
        guard let response = result.llmGatewayResponse else { return }
        let billed = response.billedTokenClass?.rawValue ?? response.tokenClass.rawValue
        appendCopilotEvent(
            runID: runID,
            kind: .modelCompleted,
            message: "LLM Gateway completed \(response.modelID) with \(billed) token-class billing."
        )
    }

    private func isCopilotRunActive(_ id: UUID) -> Bool {
        guard let run = copilotRuns.first(where: { $0.id == id }) else { return false }
        return run.status == .queued || run.status == .running
    }

    private func copilotEventKind(for recall: OpenMindMemoryRecallResult) -> CopilotRunEventKind {
        switch recall.decision.status {
        case .allowed:
            return .memoryAccessCompleted
        case .denied:
            return .memoryAccessDenied
        case .stepUpRequired:
            return .memoryStepUpRequired
        case .unavailable:
            return .memoryUnavailable
        }
    }

    private func copilotMemoryMessage(for recall: OpenMindMemoryRecallResult) -> String {
        switch recall.decision.status {
        case .allowed:
            return recall.memories.isEmpty
                ? "OpenMind allowed recall but returned no matching memories."
                : "OpenMind approved \(recall.memories.count) memory item\(recall.memories.count == 1 ? "" : "s")."
        case .denied:
            return "OpenMind denied memory recall: \(recall.decision.reason)"
        case .stepUpRequired:
            return "OpenMind requires step-up before memory recall: \(recall.decision.stepUpPrompt ?? recall.decision.reason)"
        case .unavailable:
            return "OpenMind memory unavailable: \(recall.decision.reason)"
        }
    }

    private func copilotWritebackEventKind(for outcome: OpenMindWritebackOutcome) -> CopilotRunEventKind {
        switch outcome.status {
        case .recorded:
            return .memoryWritebackRecorded
        case .proposed:
            return .memoryWritebackProposed
        case .denied:
            return .memoryWritebackDenied
        case .unavailable:
            return .memoryWritebackUnavailable
        }
    }

    private func copilotWritebackMessage(for outcome: OpenMindWritebackOutcome) -> String {
        switch outcome.status {
        case .recorded:
            return "OpenMind recorded memory revision \(outcome.revisionID ?? "without revision ID")."
        case .proposed:
            return "OpenMind created a memory proposal: \(outcome.message)"
        case .denied:
            return "OpenMind denied memory writeback: \(outcome.message)"
        case .unavailable:
            return "OpenMind memory writeback unavailable: \(outcome.message)"
        }
    }

    private func copilotCorrectionEventKind(for outcome: OpenMindCorrectionOutcome) -> CopilotRunEventKind {
        switch outcome.status {
        case .recorded:
            return .memoryCorrectionRecorded
        case .proposed:
            return .memoryCorrectionProposed
        case .denied:
            return .memoryCorrectionDenied
        case .unavailable:
            return .memoryCorrectionUnavailable
        }
    }

    private func copilotCorrectionMessage(for outcome: OpenMindCorrectionOutcome) -> String {
        switch outcome.status {
        case .recorded:
            return "OpenMind recorded correction \(outcome.correctionID ?? "without correction ID")."
        case .proposed:
            return "OpenMind queued correction for review: \(outcome.message)"
        case .denied:
            return "OpenMind denied correction: \(outcome.message)"
        case .unavailable:
            return "OpenMind correction unavailable: \(outcome.message)"
        }
    }

    private static func stableCorrectionKey(targetID: String, correctionText: String) -> String {
        let text = "\(targetID)\n\(correctionText)"
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return "correction-\(String(hash, radix: 16))"
    }

    private func performLocalLLMAction(_ action: () async -> LocalLLMManagementState) async {
        guard localLLMState.isWorking == false else { return }
        localLLMState.isWorking = true
        let nextState = await action()
        localLLMState = nextState
    }

    private func isCopilotContextEligible(_ tab: BrowserTab) -> Bool {
        guard
            !tab.isTraceMinimized,
            tab.mobileNotice == nil,
            tab.urlString != BrowserURLResolver.homeURLString,
            let url = URL(string: tab.urlString),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return false
        }
        return true
    }

    private func currentPageSnapshot(for tab: BrowserTab) -> PageSnapshot? {
        guard isCopilotContextEligible(tab) else { return nil }
        if let snapshot = pageSnapshotsByTabID[tab.id], snapshot.urlString == tab.urlString {
            return snapshot
        }
        if tab.id == activeTabID,
           let snapshot = latestPageSnapshot,
           snapshot.urlString == tab.urlString {
            return snapshot
        }
        return nil
    }

    private func selectedRelatedPageContext(
        for activeTab: BrowserTab,
        restrictedTo restrictedTabIDs: Set<UUID>? = nil
    ) -> [(tabID: UUID, snapshot: PageSnapshot)] {
        let eligibleIDs = restrictedTabIDs.map { selectedCopilotContextTabIDs.intersection($0) }
            ?? selectedCopilotContextTabIDs
        return Array(
            tabs.compactMap { tab -> (tabID: UUID, snapshot: PageSnapshot)? in
                guard
                    tab.id != activeTab.id,
                    eligibleIDs.contains(tab.id),
                    let snapshot = currentPageSnapshot(for: tab)
                else {
                    return nil
                }
                return (tab.id, snapshot)
            }
            .prefix(Self.maximumRelatedCopilotTabs)
        )
    }

    private func registerPageSnapshotCapture(_ request: BrowserAutomationRequest, for tab: BrowserTab) {
        switch request.command {
        case .pageSnapshot, .textSelection:
            break
        case .domQuery, .action:
            return
        }
        pageSnapshotCaptureContexts[request.id] = PageSnapshotCaptureContext(
            tabID: tab.id,
            targetURLString: tab.urlString,
            navigationGeneration: pageNavigationGenerations[tab.id] ?? 0
        )
    }

    private func beginPageNavigation(for tabID: UUID, reason: String) {
        searchTasksByTabID.removeValue(forKey: tabID)?.cancel()
        pageNavigationGenerations[tabID] = (pageNavigationGenerations[tabID] ?? 0) &+ 1
        consumeApprovedNavigationAutomationIfNeeded(boundTo: tabID)
        invalidateAutomationRequest(boundTo: tabID)
        expireToolProposals(boundTo: tabID, reason: reason)
        cancelPendingFreshCopilotRuns(boundTo: tabID, reason: reason)
        invalidatePageSnapshotCaptures(boundTo: tabID)
        invalidatePageContext(for: tabID)
    }

    private func consumeApprovedNavigationAutomationIfNeeded(boundTo tabID: UUID) {
        guard let request = automationRequest,
              request.tabID == tabID,
              request.approvalGrant != nil,
              case .action(let action) = request.command,
              [.click, .submit, .navigate].contains(action.kind),
              let proposalID = toolProposalByAutomationRequestID.removeValue(forKey: request.id),
              let proposalIndex = copilotToolProposals.firstIndex(where: { $0.id == proposalID }) else {
            return
        }
        automationTimeoutTasks.removeValue(forKey: request.id)?.cancel()
        markAutomationRequestTerminal(request.id)
        automationRequest = nil
        copilotToolProposals[proposalIndex].status = .consumed
        copilotToolProposals[proposalIndex].statusMessage = "The approved one-time action initiated or coincided with navigation. Its grant was consumed and will not be retried automatically."
        let proposal = copilotToolProposals[proposalIndex]
        updateConversationToolProposal(proposal, eventKind: .toolExecuted)
        appendCopilotEvent(
            runID: proposal.sourceRunID,
            kind: .actionCompleted,
            message: proposal.statusMessage
        )
    }

    private func invalidatePageSnapshotCaptures(boundTo tabID: UUID) {
        let requestIDs = pageSnapshotCaptureContexts
            .filter { $0.value.tabID == tabID }
            .map(\.key)
        for requestID in requestIDs {
            markAutomationRequestTerminal(requestID)
        }
    }

    private func invalidateAutomationRequest(boundTo tabID: UUID) {
        guard let request = automationRequest, request.tabID == tabID else { return }
        automationTimeoutTasks.removeValue(forKey: request.id)?.cancel()
        markAutomationRequestTerminal(request.id)
        automationRequest = nil
        let result = BrowserAutomationResult(
            requestID: request.id,
            tabID: request.tabID,
            status: .failed,
            message: "The page changed before the bound browser operation completed."
        )
        resolveInactiveTabCapture(with: result)
        resolveToolProposal(
            with: result,
            approvedOutcomeIsAmbiguous: request.approvalGrant != nil
        )
    }

    private func expireToolProposals(boundTo tabID: UUID, reason: String) {
        for index in copilotToolProposals.indices where
            copilotToolProposals[index].targetTabID == tabID
                && !copilotToolProposals[index].status.isTerminal {
            copilotToolProposals[index].status = .expired
            copilotToolProposals[index].statusMessage = reason
            updateConversationToolProposal(copilotToolProposals[index], eventKind: .toolDenied)
        }
    }

    private func scheduleAutomationTimeout(for request: BrowserAutomationRequest) {
        automationTimeoutTasks[request.id]?.cancel()
        automationTimeoutTasks[request.id] = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0.01, request.timeoutSeconds) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self, automationRequest?.id == request.id else { return }
            markAutomationRequestTerminal(request.id)
            automationRequest = nil
            automationTimeoutTasks[request.id] = nil
            let result = BrowserAutomationResult(
                requestID: request.id,
                tabID: request.tabID,
                status: .timedOut,
                message: "Automation request timed out before the browser returned a result."
            )
            automationResults.insert(result, at: 0)
            if automationResults.count > 100 {
                automationResults.removeLast(automationResults.count - 100)
            }
            resolveInactiveTabCapture(with: result)
            resolveToolProposal(
                with: result,
                approvedOutcomeIsAmbiguous: request.approvalGrant != nil
            )
        }
    }

    private func markAutomationRequestTerminal(_ requestID: UUID) {
        pageSnapshotCaptureContexts[requestID] = nil
        approvedAutomationDispatchOwners[requestID] = nil
        guard terminalAutomationRequestIDs.insert(requestID).inserted else { return }
        terminalAutomationRequestOrder.append(requestID)
        if terminalAutomationRequestOrder.count > Self.maximumTerminalAutomationRequestIDs {
            let overflowCount = terminalAutomationRequestOrder.count - Self.maximumTerminalAutomationRequestIDs
            let evictedIDs = terminalAutomationRequestOrder.prefix(overflowCount)
            terminalAutomationRequestOrder.removeFirst(overflowCount)
            for evictedID in evictedIDs {
                terminalAutomationRequestIDs.remove(evictedID)
            }
        }
    }

    private func invalidatePageContext(for tabID: UUID) {
        pageSnapshotsByTabID[tabID] = nil
        selectedCopilotContextTabIDs.remove(tabID)
        if tabID == activeTabID {
            latestPageSnapshot = nil
            latestDOMQueryResult = nil
            latestTextSelection = nil
        }
    }

    private func cancelPendingFreshCopilotRuns(boundTo tabID: UUID, reason: String) {
        let runIDs = pendingFreshCopilotContexts.values
            .filter { $0.tabID == tabID }
            .map(\.runID)
        for runID in runIDs where isCopilotRunActive(runID) {
            finishCopilotRun(runID, status: .cancelled, result: nil, message: reason)
        }
    }

    private func scheduleFreshCopilotContextTimeout(for requestID: UUID, after timeoutSeconds: TimeInterval) {
        freshCopilotContextTimeoutTasks[requestID]?.cancel()
        freshCopilotContextTimeoutTasks[requestID] = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0.01, timeoutSeconds) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            timeoutFreshCopilotContext(requestID: requestID)
        }
    }

    private func timeoutFreshCopilotContext(requestID: UUID) {
        guard let pending = takePendingFreshCopilotContext(for: requestID) else { return }
        markAutomationRequestTerminal(requestID)
        finishCopilotRun(
            pending.runID,
            status: .failed,
            result: nil,
            message: "Fresh page capture timed out; no model received the prompt."
        )
    }

    private func takePendingFreshCopilotContext(for requestID: UUID) -> PendingFreshCopilotContext? {
        guard let pending = pendingFreshCopilotContexts.removeValue(forKey: requestID) else { return nil }
        freshCopilotContextTimeoutTasks.removeValue(forKey: requestID)?.cancel()
        if automationRequest?.id == requestID {
            automationRequest = nil
        }
        return pending
    }

    private func removePendingFreshCopilotContext(for runID: UUID) {
        let requestIDs = pendingFreshCopilotContexts
            .filter { $0.value.runID == runID }
            .map(\.key)
        for requestID in requestIDs {
            pendingFreshCopilotContexts[requestID] = nil
            freshCopilotContextTimeoutTasks.removeValue(forKey: requestID)?.cancel()
            markAutomationRequestTerminal(requestID)
            if automationRequest?.id == requestID {
                automationRequest = nil
            }
        }
    }

    private func finishCopilotRun(
        _ id: UUID,
        status: CopilotRunStatus,
        result: CopilotRunResult?,
        usage: CopilotCreditUsage? = nil,
        message: String
    ) {
        removePendingFreshCopilotContext(for: id)
        guard let index = copilotRuns.firstIndex(where: { $0.id == id }) else { return }
        guard copilotRuns[index].status == .queued || copilotRuns[index].status == .running else { return }
        copilotRuns[index].status = status
        copilotRuns[index].finishedAt = Date()
        copilotRuns[index].result = result
        if let usage {
            copilotRuns[index].usage = usage
        }
        let kind: CopilotRunEventKind = {
            switch status {
            case .completed: return .modelCompleted
            case .cancelled: return .cancelled
            case .failed: return .failed
            case .queued, .running: return .modelStarted
            }
        }()
        copilotRuns[index].events.append(CopilotRunEvent(kind: kind, message: message))
        pageBindingByCopilotRunID[id] = nil
        if var presentation = copilotRunPresentations[id] {
            presentation.phase = {
                switch status {
                case .completed: .completed
                case .cancelled: .cancelled
                case .failed: .failed
                case .queued: .waitingForContext
                case .running: .invokingModel
                }
            }()
            presentation.statusMessage = message
            if presentation.partialText.isEmpty, let result {
                presentation.partialText = result.summary
            }
            copilotRunPresentations[id] = presentation
        }
        if let workflowID = workflowByCopilotRunID[id],
           let workflow = copilotWorkflows.first(where: { $0.id == workflowID }) {
            let scheduledPhase: CopilotScheduledWorkflowPhase = {
                switch status {
                case .queued: .queued
                case .running: .running
                case .completed: .completed
                case .cancelled, .failed: .failed
                }
            }()
            recordScheduledWorkflowState(
                workflow: workflow,
                phase: scheduledPhase,
                message: message,
                runID: id
            )
            if status == .completed || status == .cancelled || status == .failed {
                workflowByCopilotRunID[id] = nil
            }
        }
        if status != .completed {
            sourceMessageByCopilotRunID[id] = nil
            regeneratedAssistantByCopilotRunID[id] = nil
            if let pending = pendingResearchSynthesisByRunID.removeValue(forKey: id) {
                researchSynthesisErrorsBySessionID[pending.sessionID] = message
            }
        }
        copilotTasks[id] = nil
        syncDeveloperWorkflowRun(copilotRunID: id, status: status, result: result, message: message)
    }

    private func cancelCopilotRuns(boundTo tabID: UUID, reason: String) {
        let runIDs = copilotRuns
            .filter { $0.activeTabID == tabID && ($0.status == .queued || $0.status == .running) }
            .map(\.id)
        for runID in runIDs {
            copilotTasks[runID]?.cancel()
            copilotTasks[runID] = nil
            finishCopilotRun(runID, status: .cancelled, result: nil, message: reason)
        }
    }

    private func titleForURL(_ url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.absoluteString
    }

    private static func uniquePeerExperts(_ experts: [AFMA2APeerExpert]) -> [AFMA2APeerExpert] {
        var seen = Set<String>()
        return experts.filter { seen.insert($0.id).inserted }
    }
}
