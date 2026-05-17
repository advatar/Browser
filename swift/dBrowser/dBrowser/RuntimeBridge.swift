import Combine
import Foundation

enum RuntimeBridgeMode: String, Equatable {
    case native
    case gateway
    case local
    case service
    case remote
    case unavailable

    var title: String {
        switch self {
        case .native: "Native"
        case .gateway: "Gateway"
        case .local: "Local"
        case .service: "Service"
        case .remote: "Remote"
        case .unavailable: "Unavailable"
        }
    }
}

struct RuntimeFeatureState: Equatable, Identifiable {
    let feature: MobileRuntimeFeature
    var mode: RuntimeBridgeMode
    var isAvailable: Bool
    var status: String

    var id: String { feature.id }
}

struct RuntimeBridgeConfiguration: Equatable {
    var decentralizedGatewayHost: String
    var ensGatewaySuffix: String
    var remoteRuntimeBaseURL: URL?
    var afmServices: AFMServiceEndpointConfiguration
    var openMindMemory: OpenMindMemoryEndpointConfiguration
    var llmRouter: LLMRouterEndpointConfiguration
    var bitcoinLightClient: BitcoinLightClientEndpointConfiguration
    var evmLightClient: EVMLightClientEndpointConfiguration
    var solanaLightClient: SolanaLightClientEndpointConfiguration
    var cosmosLightClient: CosmosLightClientEndpointConfiguration
    var substrateLightClient: SubstrateLightClientEndpointConfiguration
    var avalancheLightClient: AvalancheLightClientEndpointConfiguration
    var tronLightClient: TronLightClientEndpointConfiguration
    var xrplLightClient: XRPLLightClientEndpointConfiguration
    var suiMoveLightClient: MoveLightClientEndpointConfiguration
    var aptosMoveLightClient: MoveLightClientEndpointConfiguration
    var chainTrustRegistry: ChainTrustRegistry
    var mcpServers: [MCPServerConfiguration]

    nonisolated init(
        decentralizedGatewayHost: String = "dweb.link",
        ensGatewaySuffix: String = "limo",
        remoteRuntimeBaseURL: URL? = nil,
        afmServices: AFMServiceEndpointConfiguration = .local,
        openMindMemory: OpenMindMemoryEndpointConfiguration = .disabled,
        llmRouter: LLMRouterEndpointConfiguration = .local,
        bitcoinLightClient: BitcoinLightClientEndpointConfiguration = .disabled,
        evmLightClient: EVMLightClientEndpointConfiguration = .disabled,
        solanaLightClient: SolanaLightClientEndpointConfiguration = .disabled,
        cosmosLightClient: CosmosLightClientEndpointConfiguration = .disabled,
        substrateLightClient: SubstrateLightClientEndpointConfiguration = .disabled,
        avalancheLightClient: AvalancheLightClientEndpointConfiguration = .disabled,
        tronLightClient: TronLightClientEndpointConfiguration = .disabled,
        xrplLightClient: XRPLLightClientEndpointConfiguration = .disabled,
        suiMoveLightClient: MoveLightClientEndpointConfiguration = .disabled(chain: .suiMainnet),
        aptosMoveLightClient: MoveLightClientEndpointConfiguration = .disabled(chain: .aptosMainnet),
        chainTrustRegistry: ChainTrustRegistry = .defaultRegistry,
        mcpServers: [MCPServerConfiguration] = MCPServerConfiguration.defaultServers
    ) {
        self.decentralizedGatewayHost = decentralizedGatewayHost
        self.ensGatewaySuffix = ensGatewaySuffix
        self.remoteRuntimeBaseURL = remoteRuntimeBaseURL
        self.afmServices = afmServices
        self.openMindMemory = openMindMemory
        self.llmRouter = llmRouter
        self.bitcoinLightClient = bitcoinLightClient
        self.evmLightClient = evmLightClient
        self.solanaLightClient = solanaLightClient
        self.cosmosLightClient = cosmosLightClient
        self.substrateLightClient = substrateLightClient
        self.avalancheLightClient = avalancheLightClient
        self.tronLightClient = tronLightClient
        self.xrplLightClient = xrplLightClient
        self.suiMoveLightClient = suiMoveLightClient
        self.aptosMoveLightClient = aptosMoveLightClient
        self.chainTrustRegistry = chainTrustRegistry
        self.mcpServers = mcpServers
    }
}

enum RuntimeResolutionSource: String, Equatable {
    case web
    case ipfsGateway
    case ipnsGateway
    case ensGateway
    case remoteRuntime
    case unsupported
}

struct RuntimeBridgeResolution: Equatable {
    let originalInput: String
    let resolvedURLString: String?
    let source: RuntimeResolutionSource
    let message: String?
}

struct CopilotRunRequest: Equatable {
    var prompt: String
    var pageURLString: String?
    var pageSnapshot: PageSnapshot?
    var preferredAFMPackID: String?
    var preferredModelID: String?
    var conversationID: UUID?
    var runID: UUID?
    var renderedConversationContext: LLMRenderedConversationContext?
    var memoryRecall: OpenMindMemoryRecallResult?

    init(
        prompt: String,
        pageURLString: String? = nil,
        pageSnapshot: PageSnapshot? = nil,
        preferredAFMPackID: String? = nil,
        preferredModelID: String? = nil,
        conversationID: UUID? = nil,
        runID: UUID? = nil,
        renderedConversationContext: LLMRenderedConversationContext? = nil,
        memoryRecall: OpenMindMemoryRecallResult? = nil
    ) {
        self.prompt = prompt
        self.pageURLString = pageURLString
        self.pageSnapshot = pageSnapshot
        self.preferredAFMPackID = preferredAFMPackID
        self.preferredModelID = preferredModelID
        self.conversationID = conversationID
        self.runID = runID
        self.renderedConversationContext = renderedConversationContext
        self.memoryRecall = memoryRecall
    }
}

struct CopilotRunResult: Equatable, Identifiable {
    let id: UUID
    let title: String
    let summary: String
    let suggestions: [String]
    let ranAt: Date
    let mode: RuntimeBridgeMode
    let afmInstall: AFMNodeInstallResult?
    let afmNodeTask: AFMNodeTaskResult?
    let llmRouterResponse: LLMRouterCompletionResponse?
    let chainTrustUpdate: ChainTrustStatus?
    let usageProviderKey: String?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        suggestions: [String],
        ranAt: Date = Date(),
        mode: RuntimeBridgeMode,
        afmInstall: AFMNodeInstallResult? = nil,
        afmNodeTask: AFMNodeTaskResult? = nil,
        llmRouterResponse: LLMRouterCompletionResponse? = nil,
        chainTrustUpdate: ChainTrustStatus? = nil,
        usageProviderKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.suggestions = suggestions
        self.ranAt = ranAt
        self.mode = mode
        self.afmInstall = afmInstall
        self.afmNodeTask = afmNodeTask
        self.llmRouterResponse = llmRouterResponse
        self.chainTrustUpdate = chainTrustUpdate
        self.usageProviderKey = usageProviderKey
    }
}

struct WalletBridgeInfo: Equatable {
    var isConnected: Bool
    var address: String?
    var network: String
    var policy: String
    var activeChainRef: String
    var explorerURLString: String?
    var productionSigningStatus: String

    static let disconnected = WalletBridgeInfo(
        isConnected: false,
        address: nil,
        network: "iOS local policy",
        policy: "Connect a wallet before signing or spending.",
        activeChainRef: "ethereum-mainnet",
        explorerURLString: nil,
        productionSigningStatus: "Production signing adapters are not configured."
    )
}

struct WalletSpendRequest: Equatable {
    var amount: Decimal
    var currency: String
    var destination: String
    var reason: String
}

struct WalletSpendDecision: Equatable {
    enum Status: String, Equatable {
        case approved
        case needsApproval
        case rejected
    }

    var status: Status
    var reason: String
}

struct DownloadBridgeItem: Equatable, Identifiable {
    enum State: String, Equatable {
        case queued
        case downloading
        case completed
        case cancelled
        case failed
    }

    let id: UUID
    var urlString: String
    var fileName: String
    var state: State
    var progress: Double
    var localURL: URL?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        urlString: String,
        fileName: String,
        state: State,
        progress: Double = 0,
        localURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.urlString = urlString
        self.fileName = fileName
        self.state = state
        self.progress = progress
        self.localURL = localURL
        self.errorMessage = errorMessage
    }
}

@MainActor
protocol RuntimeBridge: AnyObject {
    var featureStates: [RuntimeFeatureState] { get }
    var walletInfo: WalletBridgeInfo { get }
    var walletPortfolio: WalletPortfolioSnapshot { get }
    var downloadItems: [DownloadBridgeItem] { get }
    var mcpServers: [MCPServerConfiguration] { get }

    func refreshStatus() async -> [RuntimeFeatureState]
    func resolve(_ rawInput: String) async -> RuntimeBridgeResolution
    func runCopilot(_ request: CopilotRunRequest) async -> CopilotRunResult
    func connectWallet() async -> WalletBridgeInfo
    func disconnectWallet() async -> WalletBridgeInfo
    func switchWalletNetwork(_ chainRef: String) async -> WalletBridgeInfo
    func evaluateSpend(_ request: WalletSpendRequest) async -> WalletSpendDecision
    func previewWalletTransfer(_ request: WalletTransferRequest) async -> WalletTransferPreview
    func signWalletTransfer(_ request: WalletTransferRequest) async -> WalletTransferReceipt
    func explorerURL(for target: BlockchainExplorerTarget) -> URL?
    func updateMCPServer(_ server: MCPServerConfiguration) async -> [MCPServerConfiguration]
    func addMCPServer(transport: MCPServerTransport) async -> MCPServerConfiguration
    func removeMCPServer(_ id: String) async -> [MCPServerConfiguration]
    func connectMCPServer(_ id: String) async -> MCPServerConfiguration?
    func disconnectMCPServer(_ id: String) async -> MCPServerConfiguration?
    func startDownload(_ url: URL, autoStart: Bool) async -> DownloadBridgeItem
    func cancelDownload(_ id: UUID) async -> DownloadBridgeItem?
}

@MainActor
final class MobileRuntimeBridge: ObservableObject, RuntimeBridge {
    @Published private(set) var featureStates: [RuntimeFeatureState]
    @Published private(set) var walletInfo: WalletBridgeInfo
    @Published private(set) var walletPortfolio: WalletPortfolioSnapshot = .disconnected
    @Published private(set) var downloadItems: [DownloadBridgeItem] = []
    @Published private(set) var mcpServers: [MCPServerConfiguration]

    private let configuration: RuntimeBridgeConfiguration
    private let explorerCatalog: BlockchainExplorerCatalog = .default
    private let afmServicesClient: AFMServicesClient
    private let llmRouterServiceClient: LLMRouterServiceClient
    private let bitcoinLightClientServiceClient: BitcoinLightClientServiceClient
    private let evmLightClientServiceClient: EVMLightClientServiceClient
    private let solanaLightClientServiceClient: SolanaLightClientServiceClient
    private let cosmosLightClientServiceClient: CosmosLightClientServiceClient
    private let substrateLightClientServiceClient: SubstrateLightClientServiceClient
    private let avalancheLightClientServiceClient: AvalancheLightClientServiceClient
    private let tronLightClientServiceClient: TronLightClientServiceClient
    private let xrplLightClientServiceClient: XRPLLightClientServiceClient
    private let suiMoveLightClientServiceClient: MoveLightClientServiceClient
    private let aptosMoveLightClientServiceClient: MoveLightClientServiceClient
    @Published private(set) var afmServiceSnapshot: AFMServiceSnapshot = .unknown
    @Published private(set) var llmRouterServiceSnapshot: LLMRouterServiceSnapshot = .unknown
    @Published private(set) var bitcoinLightClientSnapshot: BitcoinLightClientServiceSnapshot = .fallback(
        network: .mainnet,
        lastError: "Bitcoin light-client service not checked yet."
    )
    @Published private(set) var evmLightClientSnapshot: EVMLightClientServiceSnapshot = .fallback(
        chain: .ethereumMainnet,
        lastError: "Ethereum/EVM light-client service not checked yet."
    )
    @Published private(set) var solanaLightClientSnapshot: SolanaLightClientServiceSnapshot = .fallback(
        cluster: .mainnetBeta,
        lastError: "Solana light-client service not checked yet."
    )
    @Published private(set) var cosmosLightClientSnapshot: CosmosLightClientServiceSnapshot = .fallback(
        chain: .cosmosHub,
        lastError: "Cosmos/Tendermint light-client service not checked yet."
    )
    @Published private(set) var substrateLightClientSnapshot: SubstrateLightClientServiceSnapshot = .fallback(
        chain: .polkadot,
        lastError: "Polkadot/Substrate light-client service not checked yet."
    )
    @Published private(set) var avalancheLightClientSnapshot: AvalancheLightClientServiceSnapshot = .fallback(
        network: .cChain,
        lastError: "Avalanche light-client service not checked yet."
    )
    @Published private(set) var tronLightClientSnapshot: TronLightClientServiceSnapshot = .fallback(
        network: .mainnet,
        lastError: "TRON light-client service not checked yet."
    )
    @Published private(set) var xrplLightClientSnapshot: XRPLLightClientServiceSnapshot = .fallback(
        network: .mainnet,
        lastError: "XRPL light-client service not checked yet."
    )
    @Published private(set) var suiMoveLightClientSnapshot: MoveLightClientServiceSnapshot = .fallback(
        chain: .suiMainnet,
        lastError: "Sui Move light-client service not checked yet."
    )
    @Published private(set) var aptosMoveLightClientSnapshot: MoveLightClientServiceSnapshot = .fallback(
        chain: .aptosMainnet,
        lastError: "Aptos Move light-client service not checked yet."
    )
    @Published private(set) var chainTrustSnapshot: ChainTrustRegistry
    private var retainedWalletSeed: String?
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]

    convenience init() {
        self.init(configuration: RuntimeBridgeConfiguration())
    }

    init(
        configuration: RuntimeBridgeConfiguration,
        afmServicesClient: AFMServicesClient? = nil,
        llmRouterServiceClient: LLMRouterServiceClient? = nil,
        bitcoinLightClientServiceClient: BitcoinLightClientServiceClient? = nil,
        evmLightClientServiceClient: EVMLightClientServiceClient? = nil,
        solanaLightClientServiceClient: SolanaLightClientServiceClient? = nil,
        cosmosLightClientServiceClient: CosmosLightClientServiceClient? = nil,
        substrateLightClientServiceClient: SubstrateLightClientServiceClient? = nil,
        avalancheLightClientServiceClient: AvalancheLightClientServiceClient? = nil,
        tronLightClientServiceClient: TronLightClientServiceClient? = nil,
        xrplLightClientServiceClient: XRPLLightClientServiceClient? = nil,
        suiMoveLightClientServiceClient: MoveLightClientServiceClient? = nil,
        aptosMoveLightClientServiceClient: MoveLightClientServiceClient? = nil
    ) {
        self.configuration = configuration
        self.afmServicesClient = afmServicesClient ?? AFMServicesClient(configuration: configuration.afmServices)
        self.llmRouterServiceClient = llmRouterServiceClient ?? LLMRouterServiceClient(configuration: configuration.llmRouter)
        self.bitcoinLightClientServiceClient = bitcoinLightClientServiceClient ?? BitcoinLightClientServiceClient(configuration: configuration.bitcoinLightClient)
        self.evmLightClientServiceClient = evmLightClientServiceClient ?? EVMLightClientServiceClient(configuration: configuration.evmLightClient)
        self.solanaLightClientServiceClient = solanaLightClientServiceClient ?? SolanaLightClientServiceClient(configuration: configuration.solanaLightClient)
        self.cosmosLightClientServiceClient = cosmosLightClientServiceClient ?? CosmosLightClientServiceClient(configuration: configuration.cosmosLightClient)
        self.substrateLightClientServiceClient = substrateLightClientServiceClient ?? SubstrateLightClientServiceClient(configuration: configuration.substrateLightClient)
        self.avalancheLightClientServiceClient = avalancheLightClientServiceClient ?? AvalancheLightClientServiceClient(configuration: configuration.avalancheLightClient)
        self.tronLightClientServiceClient = tronLightClientServiceClient ?? TronLightClientServiceClient(configuration: configuration.tronLightClient)
        self.xrplLightClientServiceClient = xrplLightClientServiceClient ?? XRPLLightClientServiceClient(configuration: configuration.xrplLightClient)
        self.suiMoveLightClientServiceClient = suiMoveLightClientServiceClient ?? MoveLightClientServiceClient(configuration: configuration.suiMoveLightClient)
        self.aptosMoveLightClientServiceClient = aptosMoveLightClientServiceClient ?? MoveLightClientServiceClient(configuration: configuration.aptosMoveLightClient)
        let initialMCPServers = configuration.mcpServers.map(\.sanitizedForSave)
        self.chainTrustSnapshot = configuration.chainTrustRegistry
        self.mcpServers = initialMCPServers
        self.bitcoinLightClientSnapshot = .fallback(
            network: configuration.bitcoinLightClient.network,
            lastError: "Bitcoin light-client service not checked yet."
        )
        self.evmLightClientSnapshot = .fallback(
            chain: configuration.evmLightClient.chain,
            lastError: "Ethereum/EVM light-client service not checked yet."
        )
        self.solanaLightClientSnapshot = .fallback(
            cluster: configuration.solanaLightClient.cluster,
            lastError: "Solana light-client service not checked yet."
        )
        self.cosmosLightClientSnapshot = .fallback(
            chain: configuration.cosmosLightClient.chain,
            lastError: "Cosmos/Tendermint light-client service not checked yet."
        )
        self.substrateLightClientSnapshot = .fallback(
            chain: configuration.substrateLightClient.chain,
            lastError: "Polkadot/Substrate light-client service not checked yet."
        )
        self.avalancheLightClientSnapshot = .fallback(
            network: configuration.avalancheLightClient.network,
            lastError: "Avalanche light-client service not checked yet."
        )
        self.tronLightClientSnapshot = .fallback(
            network: configuration.tronLightClient.network,
            lastError: "TRON light-client service not checked yet."
        )
        self.xrplLightClientSnapshot = .fallback(
            network: configuration.xrplLightClient.network,
            lastError: "XRPL light-client service not checked yet."
        )
        self.suiMoveLightClientSnapshot = .fallback(
            chain: configuration.suiMoveLightClient.chain,
            lastError: "Sui Move light-client service not checked yet."
        )
        self.aptosMoveLightClientSnapshot = .fallback(
            chain: configuration.aptosMoveLightClient.chain,
            lastError: "Aptos Move light-client service not checked yet."
        )
        self.featureStates = Self.makeFeatureStates(
            configuration: configuration,
            afmSnapshot: .unknown,
            llmRouterSnapshot: .unknown,
            chainTrustSnapshot: configuration.chainTrustRegistry,
            mcpServers: initialMCPServers
        )
        self.walletInfo = .disconnected
        self.walletPortfolio = .disconnected.withChainTrust(configuration.chainTrustRegistry)
    }

    func refreshStatus() async -> [RuntimeFeatureState] {
        async let afmSnapshot = afmServicesClient.snapshot()
        async let llmRouterSnapshot = llmRouterServiceClient.snapshot()
        async let bitcoinSnapshot = bitcoinLightClientServiceClient.snapshot()
        async let evmSnapshot = evmLightClientServiceClient.snapshot()
        async let solanaSnapshot = solanaLightClientServiceClient.snapshot()
        async let cosmosSnapshot = cosmosLightClientServiceClient.snapshot()
        async let substrateSnapshot = substrateLightClientServiceClient.snapshot()
        async let avalancheSnapshot = avalancheLightClientServiceClient.snapshot()
        async let tronSnapshot = tronLightClientServiceClient.snapshot()
        async let xrplSnapshot = xrplLightClientServiceClient.snapshot()
        async let suiMoveSnapshot = suiMoveLightClientServiceClient.snapshot()
        async let aptosMoveSnapshot = aptosMoveLightClientServiceClient.snapshot()
        afmServiceSnapshot = await afmSnapshot
        llmRouterServiceSnapshot = await llmRouterSnapshot
        bitcoinLightClientSnapshot = await bitcoinSnapshot
        evmLightClientSnapshot = await evmSnapshot
        solanaLightClientSnapshot = await solanaSnapshot
        cosmosLightClientSnapshot = await cosmosSnapshot
        substrateLightClientSnapshot = await substrateSnapshot
        avalancheLightClientSnapshot = await avalancheSnapshot
        tronLightClientSnapshot = await tronSnapshot
        xrplLightClientSnapshot = await xrplSnapshot
        suiMoveLightClientSnapshot = await suiMoveSnapshot
        aptosMoveLightClientSnapshot = await aptosMoveSnapshot
        _ = chainTrustSnapshot.recordBitcoinLightClientSnapshot(bitcoinLightClientSnapshot)
        _ = chainTrustSnapshot.recordEVMLightClientSnapshot(evmLightClientSnapshot)
        _ = chainTrustSnapshot.recordSolanaLightClientSnapshot(solanaLightClientSnapshot)
        _ = chainTrustSnapshot.recordCosmosLightClientSnapshot(cosmosLightClientSnapshot)
        _ = chainTrustSnapshot.recordSubstrateLightClientSnapshot(substrateLightClientSnapshot)
        _ = chainTrustSnapshot.recordAvalancheLightClientSnapshot(avalancheLightClientSnapshot)
        _ = chainTrustSnapshot.recordTronLightClientSnapshot(tronLightClientSnapshot)
        _ = chainTrustSnapshot.recordXRPLLightClientSnapshot(xrplLightClientSnapshot)
        _ = chainTrustSnapshot.recordMoveLightClientSnapshot(suiMoveLightClientSnapshot)
        _ = chainTrustSnapshot.recordMoveLightClientSnapshot(aptosMoveLightClientSnapshot)
        walletPortfolio = walletPortfolio.withChainTrust(chainTrustSnapshot)
        featureStates = Self.makeFeatureStates(
            configuration: configuration,
            afmSnapshot: afmServiceSnapshot,
            llmRouterSnapshot: llmRouterServiceSnapshot,
            chainTrustSnapshot: chainTrustSnapshot,
            mcpServers: mcpServers
        )
        return featureStates
    }

    func resolve(_ rawInput: String) async -> RuntimeBridgeResolution {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return RuntimeBridgeResolution(
                originalInput: rawInput,
                resolvedURLString: nil,
                source: .unsupported,
                message: "Enter an address before asking the runtime bridge to resolve it."
            )
        }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return RuntimeBridgeResolution(
                    originalInput: input,
                    resolvedURLString: url.absoluteString,
                    source: .web,
                    message: nil
                )
            case "ipfs":
                return decentralizedResolution(namespace: "ipfs", url: url, originalInput: input)
            case "ipns":
                return decentralizedResolution(namespace: "ipns", url: url, originalInput: input)
            case "ens":
                return ensResolution(url: url, originalInput: input)
            default:
                return RuntimeBridgeResolution(
                    originalInput: input,
                    resolvedURLString: nil,
                    source: .unsupported,
                    message: "No iOS runtime bridge is registered for \(scheme):// addresses."
                )
            }
        }

        if Self.isDecentralizedName(input), let resolvedURL = ensGatewayURL(name: input) {
            return RuntimeBridgeResolution(
                originalInput: input,
                resolvedURLString: resolvedURL.absoluteString,
                source: .ensGateway,
                message: "Resolved ENS-compatible name through the iOS gateway bridge."
            )
        }

        return RuntimeBridgeResolution(
            originalInput: input,
            resolvedURLString: nil,
            source: .unsupported,
            message: "The runtime bridge only handles web, IPFS, IPNS, ENS, Copilot, wallet, and download actions."
        )
    }

    func runCopilot(_ request: CopilotRunRequest) async -> CopilotRunResult {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = request.pageURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = target?.isEmpty == false ? target! : "the active page"
        let task = prompt.isEmpty ? "Assist with the current browsing task." : prompt
        let adapterPrompt = request.renderedConversationContext?.prompt ?? task
        let snapshotContext = request.pageSnapshot.map { snapshot in
            " Snapshot includes \(snapshot.visibleText.count) text characters, \(snapshot.links.count) links, and \(snapshot.formControls.count) form controls."
        } ?? ""
        let conversationContext = request.renderedConversationContext.map { rendered in
            let compression = rendered.wasCompressed ? " with compressed prior context" : ""
            return " Conversation \(request.conversationID?.uuidString ?? "context") rendered \(rendered.estimatedPromptTokens) prompt tokens\(compression)."
        } ?? ""
        let memoryIDs = request.memoryRecall?.memories.map(\.id) ?? []
        let memoryContext = request.memoryRecall.map { recall in
            recall.memories.isEmpty ? " No governed memory context was approved." : " OpenMind approved \(recall.memories.count) governed memory item\(recall.memories.count == 1 ? "" : "s")."
        } ?? ""
        let snapshotCommitment = OpenMindMemoryClient.snapshotCommitment(for: request.pageSnapshot)
        var llmRouterFailureMessage: String?

        if request.preferredModelID == LLMModelRegistry.llmRouterAppleFoundationID {
            do {
                let routerSnapshot = await llmRouterServiceClient.snapshot()
                llmRouterServiceSnapshot = routerSnapshot
                featureStates = Self.makeFeatureStates(
                    configuration: configuration,
                    afmSnapshot: afmServiceSnapshot,
                    llmRouterSnapshot: routerSnapshot,
                    chainTrustSnapshot: chainTrustSnapshot,
                    mcpServers: mcpServers
                )
                guard routerSnapshot.isModelAvailable(provider: .appleFoundation) else {
                    throw LLMRouterServiceClientError.invalidResponse
                }

                let completionRequest = llmRouterServiceClient.completionRequest(
                    prompt: task,
                    conversationID: request.conversationID,
                    runID: request.runID,
                    preferredModelID: request.preferredModelID,
                    pageURLString: target,
                    renderedContext: request.renderedConversationContext,
                    memoryRecall: request.memoryRecall
                )
                let response = try await llmRouterServiceClient.complete(completionRequest)
                var suggestions = [
                    "LLM router completed with \(response.provider.rawValue) for \(page).",
                    "Router policy stayed local-first with no-egress enabled.",
                    request.renderedConversationContext == nil ? "Router received the current prompt without rendered conversation context." : "Router received rendered conversation context with \(request.renderedConversationContext?.estimatedPromptTokens ?? 0) estimated prompt tokens.",
                    memoryIDs.isEmpty ? "No governed memory IDs were sent to the router." : "Router received approved memory IDs: \(memoryIDs.joined(separator: ", "))."
                ]
                if let usage = response.usage {
                    suggestions.append("Router usage: \(usage.promptTokens ?? 0) prompt, \(usage.completionTokens ?? 0) completion, \(usage.totalTokens ?? 0) total tokens.")
                }
                if response.toolCalls.isEmpty {
                    suggestions.append("Router proposed no tool calls.")
                } else {
                    suggestions.append("Router proposed \(response.toolCalls.count) tool call\(response.toolCalls.count == 1 ? "" : "s") for approval review.")
                    suggestions.append(contentsOf: response.toolCalls.map { "Proposed tool \($0.name) remains approval-gated." })
                }
                return CopilotRunResult(
                    title: "LLM Router Copilot",
                    summary: response.text,
                    suggestions: suggestions,
                    mode: .service,
                    llmRouterResponse: response,
                    usageProviderKey: "llm_router"
                )
            } catch {
                llmRouterFailureMessage = "LLM router unavailable for selected model: \(error.localizedDescription)."
            }
        }

        do {
            let snapshot = await afmServicesClient.snapshot()
            afmServiceSnapshot = snapshot
            featureStates = Self.makeFeatureStates(
                configuration: configuration,
                afmSnapshot: snapshot,
                llmRouterSnapshot: llmRouterServiceSnapshot,
                chainTrustSnapshot: chainTrustSnapshot,
                mcpServers: mcpServers
            )

            let route = try await afmServicesClient.route(
                skill: "summarize",
                prompt: adapterPrompt,
                pageURLString: target,
                preferredPackID: request.preferredAFMPackID,
                pageSnapshotCommitment: snapshotCommitment,
                memoryContextIDs: memoryIDs
            )
            let selectedPackID = route.selection?.id ?? request.preferredAFMPackID
            let selectedPack = route.selection?.displayName
                ?? route.primary.map { "AFMarket node \($0.nodeID)" }
                ?? request.preferredAFMPackID
                ?? "AFM router default"
            let job = try await afmServicesClient.enqueueCopilotJob(
                prompt: adapterPrompt,
                pageURLString: target,
                selectedPackID: selectedPackID,
                preferredPackID: request.preferredAFMPackID,
                pageSnapshotCommitment: snapshotCommitment,
                memoryContextIDs: memoryIDs
            )
            var summary = "Routed \(page) through \(selectedPack) and queued pipelines job \(job.id).\(snapshotContext)\(conversationContext)\(memoryContext)"
            if let routeRequest = route.request {
                summary += " Route contract \(route.contract) used \(routeRequest.reward) \(routeRequest.rewardToken) on \(routeRequest.chainRef)."
            }
            if let primary = route.primary {
                summary += " Lease \(primary.leaseID) assigned \(primary.nodeID)"
                if let ttl = route.leaseTTLMS {
                    summary += " for \(ttl) ms"
                }
                summary += "."
            }
            let marketplaceSummary = snapshot.marketplaceAvailable == nil
                ? ""
                : " Marketplace has \(snapshot.marketplacePacks.count) runner pack\(snapshot.marketplacePacks.count == 1 ? "" : "s")."
            var suggestions = [
                route.primary.map { "AFMarket v1 primary lease \($0.leaseID) on \($0.nodeID)." } ?? "Router selected \(selectedPack) for \(route.requestedSkill ?? "summarize").",
                "Registry has \(snapshot.registryPacks.count) pack\(snapshot.registryPacks.count == 1 ? "" : "s"), \(snapshot.registryBundles.count) bundle\(snapshot.registryBundles.count == 1 ? "" : "s"), and \(snapshot.registryExperts.count) expert\(snapshot.registryExperts.count == 1 ? "" : "s") available to the Swift shell.\(marketplaceSummary)",
                request.preferredAFMPackID.map { "Copilot requested runner pack \($0)." } ?? "Router chose the runner pack.",
                "Pipelines accepted job \(job.id) with status \(job.status)."
            ]
            if let llmRouterFailureMessage {
                suggestions.insert(llmRouterFailureMessage, at: 0)
            }
            if let routeRequest = route.request {
                suggestions.append("Route \(route.contract) used chain \(routeRequest.chainRef), reward \(routeRequest.reward) \(routeRequest.rewardToken), SLA \(routeRequest.sla.maxLatencyMS.map { "\($0) ms" } ?? "default").")
            }
            if !route.backups.isEmpty {
                suggestions.append("AFMarket retained \(route.backups.count) backup lease\(route.backups.count == 1 ? "" : "s").")
            }
            var installResult: AFMNodeInstallResult?
            var nodeTaskResult: AFMNodeTaskResult?
            var chainTrustUpdate: ChainTrustStatus?

            if snapshot.nodeAvailable, let selectedPackID {
                do {
                    let selectedPackSummary = snapshot.availablePacks.first { $0.id == selectedPackID }
                    let install = try await afmServicesClient.installPack(
                        packID: selectedPackID,
                        checksum: selectedPackSummary?.checksum,
                        bundleURL: selectedPackSummary?.bundleURL
                    )
                    let nodeTask = try await afmServicesClient.dispatchTask(
                        prompt: adapterPrompt,
                        pageURLString: target,
                        selectedPackID: selectedPackID,
                        pageSnapshotCommitment: snapshotCommitment,
                        memoryContextIDs: memoryIDs
                    )
                    installResult = install
                    nodeTaskResult = nodeTask
                    let verificationReport = nodeTask.verificationReport
                    chainTrustUpdate = recordChainTrustEvidence(from: verificationReport)
                    summary += " Node \(nodeTask.taskID) completed with \(nodeTask.attestation.mode) attestation, \(nodeTask.proof.status) proof, and \(nodeTask.settlement.status) settlement. \(verificationReport.summary)"
                    suggestions.append("Node installed \(selectedPackID) with \(install.status) status (\(install.mode)).")
                    suggestions.append("Node dispatched \(nodeTask.taskID) with \(nodeTask.attestation.mode) attestation.")
                    suggestions.append("Proof \(nodeTask.proof.proofID ?? nodeTask.proof.id ?? "local") is \(nodeTask.proof.status); settlement is \(nodeTask.settlement.status) on \(nodeTask.settlement.chainRef ?? "local-devnet").")
                    suggestions.append("Verification \(verificationReport.state.title): \(verificationReport.summary)")
                    if let chainTrustUpdate {
                        suggestions.append("Chain trust \(chainTrustUpdate.state.title): \(chainTrustUpdate.displaySummary)")
                    }
                    for check in verificationReport.checks where check.status != .passed {
                        suggestions.append("Verification check \(check.id): \(check.message)")
                    }
                } catch {
                    suggestions.append("Node agent failed install/dispatch: \(error.localizedDescription).")
                }
            } else if snapshot.nodeAvailable {
                suggestions.append("Node agent is online, but no runner pack was selected for install/dispatch.")
            } else {
                suggestions.append("Node agent unavailable; install, attestation, proof, and settlement stayed offline.")
            }

            return CopilotRunResult(
                title: "AFM service Copilot",
                summary: summary,
                suggestions: suggestions,
                mode: .service,
                afmInstall: installResult,
                afmNodeTask: nodeTaskResult,
                chainTrustUpdate: chainTrustUpdate
            )
        } catch {
            featureStates = Self.makeFeatureStates(
                configuration: configuration,
                afmSnapshot: afmServiceSnapshot,
                llmRouterSnapshot: llmRouterServiceSnapshot,
                chainTrustSnapshot: chainTrustSnapshot,
                mcpServers: mcpServers
            )
        }

        return CopilotRunResult(
            title: "Local Copilot bridge",
            summary: "Prepared a mobile Copilot run for \(page): \(task)\(snapshotContext)\(conversationContext)\(memoryContext)",
            suggestions: [
                llmRouterFailureMessage,
                request.renderedConversationContext == nil ? "Attach page text from WKWebView before model execution." : "Use the rendered conversation ledger as local model context.",
                request.memoryRecall?.decision.status == .allowed ? "Use only the approved OpenMind memory context." : "Continue without personal memory unless OpenMind grants access.",
                "Send the prepared run to the desktop or cloud runtime when configured.",
                "Keep wallet and download actions behind explicit approval."
            ].compactMap { $0 },
            mode: .local
        )
    }

    func connectWallet() async -> WalletBridgeInfo {
        let seed = retainedWalletSeed ?? UUID().uuidString
        retainedWalletSeed = seed
        let activeChainRef = walletPortfolio.activeChainRef
        let networks = WalletNetwork.defaultNetworks(catalog: explorerCatalog)
        let accounts = WalletPolicyEngine.makeAccounts(seed: seed, networks: networks)
        walletPortfolio = WalletPortfolioSnapshot(
            isConnected: true,
            activeChainRef: activeChainRef,
            networks: networks,
            accounts: accounts,
            recentReceipts: walletPortfolio.recentReceipts,
            policySummary: "Auto-approve transfer previews up to 25 native units; require approval above the local policy limit.",
            productionSigningStatus: "Local policy receipts only. Secure Enclave, WalletConnect, and chain adapters are not configured."
        ).withChainTrust(chainTrustSnapshot)
        walletInfo = walletInfo(from: walletPortfolio)
        refreshWalletFeatureState()
        return walletInfo
    }

    func disconnectWallet() async -> WalletBridgeInfo {
        walletPortfolio = WalletPortfolioSnapshot.disconnected.withChainTrust(chainTrustSnapshot)
        walletInfo = walletInfo(from: walletPortfolio)
        refreshWalletFeatureState()
        return walletInfo
    }

    func switchWalletNetwork(_ chainRef: String) async -> WalletBridgeInfo {
        let normalized = ChainTrustStatus.normalized(chainRef)
        guard walletPortfolio.network(forChainRef: normalized) != nil else {
            return walletInfo
        }
        walletPortfolio.activeChainRef = normalized
        walletInfo = walletInfo(from: walletPortfolio)
        refreshWalletFeatureState()
        return walletInfo
    }

    func evaluateSpend(_ request: WalletSpendRequest) async -> WalletSpendDecision {
        let preview = await previewWalletTransfer(
            WalletTransferRequest(
                chainRef: walletPortfolio.activeChainRef,
                amount: request.amount,
                asset: request.currency,
                destination: request.destination,
                reason: request.reason
            )
        )
        switch preview.status {
        case .ready:
            return WalletSpendDecision(
                status: .approved,
                reason: preview.reason
            )
        case .needsApproval:
            return WalletSpendDecision(status: .needsApproval, reason: preview.reason)
        case .rejected:
            return WalletSpendDecision(status: .rejected, reason: preview.reason)
        }
    }

    func previewWalletTransfer(_ request: WalletTransferRequest) async -> WalletTransferPreview {
        WalletPolicyEngine.preview(
            request: request,
            portfolio: walletPortfolio,
            chainTrust: chainTrustSnapshot
        )
    }

    func signWalletTransfer(_ request: WalletTransferRequest) async -> WalletTransferReceipt {
        let preview = await previewWalletTransfer(request)
        let receipt = WalletPolicyEngine.receipt(request: request, preview: preview)
        walletPortfolio.recentReceipts.insert(receipt, at: 0)
        if walletPortfolio.recentReceipts.count > 50 {
            walletPortfolio.recentReceipts.removeLast(walletPortfolio.recentReceipts.count - 50)
        }
        walletInfo = walletInfo(from: walletPortfolio)
        return receipt
    }

    func explorerURL(for target: BlockchainExplorerTarget) -> URL? {
        explorerCatalog.url(for: target)
    }

    func updateMCPServer(_ server: MCPServerConfiguration) async -> [MCPServerConfiguration] {
        let sanitized = server.sanitizedForSave
        guard let index = mcpServers.firstIndex(where: { $0.id == sanitized.id }) else {
            mcpServers.append(sanitized)
            refreshMCPFeatureState()
            return mcpServers
        }
        mcpServers[index] = sanitized
        refreshMCPFeatureState()
        return mcpServers
    }

    func addMCPServer(transport: MCPServerTransport) async -> MCPServerConfiguration {
        let server = MCPServerConfiguration.newServer(transport: transport)
        mcpServers.append(server)
        refreshMCPFeatureState()
        return server
    }

    func removeMCPServer(_ id: String) async -> [MCPServerConfiguration] {
        mcpServers.removeAll { $0.id == id }
        refreshMCPFeatureState()
        return mcpServers
    }

    func connectMCPServer(_ id: String) async -> MCPServerConfiguration? {
        guard let index = mcpServers.firstIndex(where: { $0.id == id }) else { return nil }
        var server = mcpServers[index].sanitizedForSave
        if let validationError = server.validationError() {
            server.status = MCPServerConfiguration.failedStatus(validationError)
        } else {
            server.status = server.connectedStatus()
        }
        mcpServers[index] = server
        refreshMCPFeatureState()
        return server
    }

    func disconnectMCPServer(_ id: String) async -> MCPServerConfiguration? {
        guard let index = mcpServers.firstIndex(where: { $0.id == id }) else { return nil }
        var server = mcpServers[index]
        server.status = server.enabled ? MCPServerConfiguration.disconnectedStatus() : .disabled
        mcpServers[index] = server
        refreshMCPFeatureState()
        return server
    }

    @discardableResult
    func startDownload(_ url: URL, autoStart: Bool = true) async -> DownloadBridgeItem {
        let item = DownloadBridgeItem(
            urlString: url.absoluteString,
            fileName: Self.fileName(for: url),
            state: autoStart ? .downloading : .queued,
            progress: autoStart ? 0.05 : 0
        )
        downloadItems.insert(item, at: 0)

        guard autoStart else {
            return item
        }

        let task = Task { [weak self] in
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: url)
                guard !Task.isCancelled else {
                    self?.markDownloadCancelled(item.id)
                    return
                }

                let fileName = response.suggestedFilename ?? Self.fileName(for: url)
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                self?.completeDownload(item.id, localURL: destination, fileName: fileName)
            } catch is CancellationError {
                self?.markDownloadCancelled(item.id)
            } catch {
                self?.failDownload(item.id, message: error.localizedDescription)
            }
        }
        downloadTasks[item.id] = task
        return item
    }

    @discardableResult
    func cancelDownload(_ id: UUID) async -> DownloadBridgeItem? {
        downloadTasks[id]?.cancel()
        downloadTasks[id] = nil
        return markDownloadCancelled(id)
    }

    private static func makeFeatureStates(
        configuration: RuntimeBridgeConfiguration,
        afmSnapshot: AFMServiceSnapshot,
        llmRouterSnapshot: LLMRouterServiceSnapshot,
        chainTrustSnapshot: ChainTrustRegistry,
        mcpServers: [MCPServerConfiguration]
    ) -> [RuntimeFeatureState] {
        let copilotStatus: String
        let copilotMode: RuntimeBridgeMode
        if llmRouterSnapshot.isModelAvailable(provider: .appleFoundation) {
            copilotStatus = "LLM router + local-first provider"
            copilotMode = .service
        } else if afmSnapshot.coreCopilotServicesAvailable {
            copilotStatus = "AFM router + pipelines"
            copilotMode = .service
        } else {
            copilotStatus = "Local fallback bridge"
            copilotMode = .local
        }
        let chainTrustMode: RuntimeBridgeMode = {
            switch chainTrustSnapshot.strongestState {
            case .verified:
                return .local
            case .proofChecked, .syncing, .stale:
                return .service
            case .rpcFallback:
                return .gateway
            case .failed, .unavailable:
                return .unavailable
            }
        }()
        let chainTrustAvailable = chainTrustSnapshot.strongestState != .unavailable
            && chainTrustSnapshot.strongestState != .failed
        let mcpInventory = MCPServerInventory(servers: mcpServers)
        let mcpMode: RuntimeBridgeMode = mcpInventory.connectedCount > 0 ? .service : .local

        return [
            RuntimeFeatureState(feature: .webBrowsing, mode: .native, isAvailable: true, status: "WKWebView"),
            RuntimeFeatureState(feature: .tabs, mode: .native, isAvailable: true, status: "Swift state"),
            RuntimeFeatureState(
                feature: .decentralizedProtocols,
                mode: configuration.remoteRuntimeBaseURL == nil ? .gateway : .remote,
                isAvailable: true,
                status: configuration.remoteRuntimeBaseURL == nil ? "IPFS/IPNS/ENS gateway bridge" : "Remote runtime bridge"
            ),
            RuntimeFeatureState(
                feature: .architectureOverview,
                mode: .gateway,
                isAvailable: true,
                status: "Light clients + AF Market + ZeroK + LLM Gateway"
            ),
            RuntimeFeatureState(
                feature: .chainTrust,
                mode: chainTrustMode,
                isAvailable: chainTrustAvailable,
                status: chainTrustSnapshot.runtimeStatusText
            ),
            RuntimeFeatureState(
                feature: .mcpServers,
                mode: mcpMode,
                isAvailable: true,
                status: mcpInventory.summary
            ),
            RuntimeFeatureState(
                feature: .afmServices,
                mode: afmSnapshot.allServicesAvailable ? .service : .unavailable,
                isAvailable: afmSnapshot.allServicesAvailable,
                status: afmSnapshot.serviceStatusText
            ),
            RuntimeFeatureState(
                feature: .copilot,
                mode: copilotMode,
                isAvailable: true,
                status: copilotStatus
            ),
            RuntimeFeatureState(feature: .wallet, mode: .local, isAvailable: true, status: "Local policy bridge"),
            RuntimeFeatureState(feature: .downloads, mode: .native, isAvailable: true, status: "URLSession bridge")
        ]
    }

    private func recordChainTrustEvidence(from report: AFMNodeVerificationReport) -> ChainTrustStatus? {
        let update = chainTrustSnapshot.recordAFMarketVerification(report)
        featureStates = Self.makeFeatureStates(
            configuration: configuration,
            afmSnapshot: afmServiceSnapshot,
            llmRouterSnapshot: llmRouterServiceSnapshot,
            chainTrustSnapshot: chainTrustSnapshot,
            mcpServers: mcpServers
        )
        return update
    }

    private func decentralizedResolution(
        namespace: String,
        url: URL,
        originalInput: String
    ) -> RuntimeBridgeResolution {
        guard let resolvedURL = decentralizedGatewayURL(namespace: namespace, url: url) else {
            return RuntimeBridgeResolution(
                originalInput: originalInput,
                resolvedURLString: nil,
                source: .unsupported,
                message: "The \(namespace.uppercased()) address is missing a content identifier."
            )
        }

        return RuntimeBridgeResolution(
            originalInput: originalInput,
            resolvedURLString: resolvedURL.absoluteString,
            source: namespace == "ipfs" ? .ipfsGateway : .ipnsGateway,
            message: "Resolved \(namespace.uppercased()) through the iOS gateway bridge."
        )
    }

    private func ensResolution(url: URL, originalInput: String) -> RuntimeBridgeResolution {
        let rawName = url.host?.isEmpty == false ? url.host! : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let resolvedURL = ensGatewayURL(name: rawName, path: url.host == nil ? "" : url.path, query: url.query, fragment: url.fragment) else {
            return RuntimeBridgeResolution(
                originalInput: originalInput,
                resolvedURLString: nil,
                source: .unsupported,
                message: "The ENS address is missing a name."
            )
        }

        return RuntimeBridgeResolution(
            originalInput: originalInput,
            resolvedURLString: resolvedURL.absoluteString,
            source: .ensGateway,
            message: "Resolved ENS through the iOS gateway bridge."
        )
    }

    private func decentralizedGatewayURL(namespace: String, url: URL) -> URL? {
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

        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.decentralizedGatewayHost
        components.path = "/\(namespace)/\(root)\(path)"
        components.query = url.query
        components.fragment = url.fragment
        return components.url
    }

    private func ensGatewayURL(name: String, path: String = "", query: String? = nil, fragment: String? = nil) -> URL? {
        let trimmedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        guard Self.isDecentralizedName(trimmedName) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(trimmedName).\(configuration.ensGatewaySuffix)"
        components.path = path
        components.query = query
        components.fragment = fragment
        return components.url
    }

    private func completeDownload(_ id: UUID, localURL: URL, fileName: String) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }
        downloadItems[index].fileName = fileName
        downloadItems[index].state = .completed
        downloadItems[index].progress = 1
        downloadItems[index].localURL = localURL
        downloadItems[index].errorMessage = nil
        downloadTasks[id] = nil
    }

    private func failDownload(_ id: UUID, message: String) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }
        downloadItems[index].state = .failed
        downloadItems[index].errorMessage = message
        downloadTasks[id] = nil
    }

    @discardableResult
    private func markDownloadCancelled(_ id: UUID) -> DownloadBridgeItem? {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return nil }
        downloadItems[index].state = .cancelled
        downloadItems[index].progress = 0
        downloadTasks[id] = nil
        return downloadItems[index]
    }

    private func walletInfo(from portfolio: WalletPortfolioSnapshot) -> WalletBridgeInfo {
        let account = portfolio.activeAccount
        let network = portfolio.activeNetwork
        return WalletBridgeInfo(
            isConnected: portfolio.isConnected,
            address: account?.address,
            network: network?.displayName ?? "iOS local policy",
            policy: portfolio.policySummary,
            activeChainRef: portfolio.activeChainRef,
            explorerURLString: account?.explorerURL(in: explorerCatalog)?.absoluteString,
            productionSigningStatus: portfolio.productionSigningStatus
        )
    }

    private func refreshWalletFeatureState() {
        guard let index = featureStates.firstIndex(where: { $0.feature == .wallet }) else { return }
        featureStates[index].status = walletPortfolio.isConnected
            ? "\(walletPortfolio.activeNetwork?.displayName ?? "Wallet") policy receipt"
            : "Local policy bridge"
        featureStates[index].mode = .local
        featureStates[index].isAvailable = true
    }

    private func refreshMCPFeatureState() {
        guard let index = featureStates.firstIndex(where: { $0.feature == .mcpServers }) else { return }
        let inventory = MCPServerInventory(servers: mcpServers)
        featureStates[index].status = inventory.summary
        featureStates[index].mode = inventory.connectedCount > 0 ? .service : .local
        featureStates[index].isAvailable = true
    }

    private static func isDecentralizedName(_ input: String) -> Bool {
        let lowercased = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty, !lowercased.contains(" ") else {
            return false
        }

        return [".eth", ".crypto", ".blockchain"].contains { lowercased.hasSuffix($0) }
    }

    private static func fileName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? "download" : lastPathComponent
    }

}
