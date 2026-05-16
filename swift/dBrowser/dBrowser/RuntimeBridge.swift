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

    nonisolated init(
        decentralizedGatewayHost: String = "dweb.link",
        ensGatewaySuffix: String = "limo",
        remoteRuntimeBaseURL: URL? = nil,
        afmServices: AFMServiceEndpointConfiguration = .local,
        openMindMemory: OpenMindMemoryEndpointConfiguration = .disabled
    ) {
        self.decentralizedGatewayHost = decentralizedGatewayHost
        self.ensGatewaySuffix = ensGatewaySuffix
        self.remoteRuntimeBaseURL = remoteRuntimeBaseURL
        self.afmServices = afmServices
        self.openMindMemory = openMindMemory
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
    var renderedConversationContext: LLMRenderedConversationContext?
    var memoryRecall: OpenMindMemoryRecallResult?

    init(
        prompt: String,
        pageURLString: String? = nil,
        pageSnapshot: PageSnapshot? = nil,
        preferredAFMPackID: String? = nil,
        preferredModelID: String? = nil,
        conversationID: UUID? = nil,
        renderedConversationContext: LLMRenderedConversationContext? = nil,
        memoryRecall: OpenMindMemoryRecallResult? = nil
    ) {
        self.prompt = prompt
        self.pageURLString = pageURLString
        self.pageSnapshot = pageSnapshot
        self.preferredAFMPackID = preferredAFMPackID
        self.preferredModelID = preferredModelID
        self.conversationID = conversationID
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

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        suggestions: [String],
        ranAt: Date = Date(),
        mode: RuntimeBridgeMode,
        afmInstall: AFMNodeInstallResult? = nil,
        afmNodeTask: AFMNodeTaskResult? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.suggestions = suggestions
        self.ranAt = ranAt
        self.mode = mode
        self.afmInstall = afmInstall
        self.afmNodeTask = afmNodeTask
    }
}

struct WalletBridgeInfo: Equatable {
    var isConnected: Bool
    var address: String?
    var network: String
    var policy: String

    static let disconnected = WalletBridgeInfo(
        isConnected: false,
        address: nil,
        network: "iOS local policy",
        policy: "Connect a wallet before signing or spending."
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
    var downloadItems: [DownloadBridgeItem] { get }

    func refreshStatus() async -> [RuntimeFeatureState]
    func resolve(_ rawInput: String) async -> RuntimeBridgeResolution
    func runCopilot(_ request: CopilotRunRequest) async -> CopilotRunResult
    func connectWallet() async -> WalletBridgeInfo
    func disconnectWallet() async -> WalletBridgeInfo
    func evaluateSpend(_ request: WalletSpendRequest) async -> WalletSpendDecision
    func startDownload(_ url: URL, autoStart: Bool) async -> DownloadBridgeItem
    func cancelDownload(_ id: UUID) async -> DownloadBridgeItem?
}

@MainActor
final class MobileRuntimeBridge: ObservableObject, RuntimeBridge {
    @Published private(set) var featureStates: [RuntimeFeatureState]
    @Published private(set) var walletInfo: WalletBridgeInfo
    @Published private(set) var downloadItems: [DownloadBridgeItem] = []

    private let configuration: RuntimeBridgeConfiguration
    private let afmServicesClient: AFMServicesClient
    @Published private(set) var afmServiceSnapshot: AFMServiceSnapshot = .unknown
    private var retainedWalletAddress: String?
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]

    convenience init() {
        self.init(configuration: RuntimeBridgeConfiguration())
    }

    init(configuration: RuntimeBridgeConfiguration, afmServicesClient: AFMServicesClient? = nil) {
        self.configuration = configuration
        self.afmServicesClient = afmServicesClient ?? AFMServicesClient(configuration: configuration.afmServices)
        self.featureStates = Self.makeFeatureStates(configuration: configuration, afmSnapshot: .unknown)
        self.walletInfo = .disconnected
    }

    func refreshStatus() async -> [RuntimeFeatureState] {
        afmServiceSnapshot = await afmServicesClient.snapshot()
        featureStates = Self.makeFeatureStates(configuration: configuration, afmSnapshot: afmServiceSnapshot)
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

        do {
            let snapshot = await afmServicesClient.snapshot()
            afmServiceSnapshot = snapshot
            featureStates = Self.makeFeatureStates(configuration: configuration, afmSnapshot: snapshot)

            let route = try await afmServicesClient.route(
                skill: "summarize",
                prompt: adapterPrompt,
                pageURLString: target,
                preferredPackID: request.preferredAFMPackID,
                pageSnapshotCommitment: snapshotCommitment,
                memoryContextIDs: memoryIDs
            )
            let selectedPackID = route.selection?.id ?? request.preferredAFMPackID
            let selectedPack = route.selection?.displayName ?? request.preferredAFMPackID ?? "AFM router default"
            let job = try await afmServicesClient.enqueueCopilotJob(
                prompt: adapterPrompt,
                pageURLString: target,
                selectedPackID: selectedPackID,
                preferredPackID: request.preferredAFMPackID,
                pageSnapshotCommitment: snapshotCommitment,
                memoryContextIDs: memoryIDs
            )
            var summary = "Routed \(page) through \(selectedPack) and queued pipelines job \(job.id).\(snapshotContext)\(conversationContext)\(memoryContext)"
            var suggestions = [
                "Router selected \(selectedPack) for \(route.requestedSkill ?? "summarize").",
                "Registry has \(snapshot.registryPacks.count) pack\(snapshot.registryPacks.count == 1 ? "" : "s") available to the Swift shell.",
                request.preferredAFMPackID.map { "Copilot requested runner pack \($0)." } ?? "Router chose the runner pack.",
                "Pipelines accepted job \(job.id) with status \(job.status)."
            ]
            var installResult: AFMNodeInstallResult?
            var nodeTaskResult: AFMNodeTaskResult?

            if snapshot.nodeAvailable, let selectedPackID {
                do {
                    let selectedPackSummary = snapshot.availablePacks.first { $0.id == selectedPackID }
                    let install = try await afmServicesClient.installPack(
                        packID: selectedPackID,
                        checksum: selectedPackSummary?.checksum
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
                    summary += " Node \(nodeTask.taskID) completed with \(nodeTask.attestation.mode) attestation, \(nodeTask.proof.status) proof, and \(nodeTask.settlement.status) settlement."
                    suggestions.append("Node installed \(selectedPackID) with \(install.status) status (\(install.mode)).")
                    suggestions.append("Node dispatched \(nodeTask.taskID) with \(nodeTask.attestation.mode) attestation.")
                    suggestions.append("Proof \(nodeTask.proof.proofID ?? nodeTask.proof.id ?? "local") is \(nodeTask.proof.status); settlement is \(nodeTask.settlement.status) on \(nodeTask.settlement.chainRef ?? "local-devnet").")
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
                afmNodeTask: nodeTaskResult
            )
        } catch {
            featureStates = Self.makeFeatureStates(configuration: configuration, afmSnapshot: afmServiceSnapshot)
        }

        return CopilotRunResult(
            title: "Local Copilot bridge",
            summary: "Prepared a mobile Copilot run for \(page): \(task)\(snapshotContext)\(conversationContext)\(memoryContext)",
            suggestions: [
                request.renderedConversationContext == nil ? "Attach page text from WKWebView before model execution." : "Use the rendered conversation ledger as local model context.",
                request.memoryRecall?.decision.status == .allowed ? "Use only the approved OpenMind memory context." : "Continue without personal memory unless OpenMind grants access.",
                "Send the prepared run to the desktop or cloud runtime when configured.",
                "Keep wallet and download actions behind explicit approval."
            ],
            mode: .local
        )
    }

    func connectWallet() async -> WalletBridgeInfo {
        let address = retainedWalletAddress ?? Self.makeWalletAddress()
        retainedWalletAddress = address
        walletInfo = WalletBridgeInfo(
            isConnected: true,
            address: address,
            network: "iOS local policy",
            policy: "Auto-approve low-value read-only actions; require confirmation for spend and signature requests."
        )
        return walletInfo
    }

    func disconnectWallet() async -> WalletBridgeInfo {
        walletInfo = .disconnected
        return walletInfo
    }

    func evaluateSpend(_ request: WalletSpendRequest) async -> WalletSpendDecision {
        guard walletInfo.isConnected else {
            return WalletSpendDecision(status: .rejected, reason: "Connect a wallet before evaluating spend policy.")
        }

        guard request.amount > Decimal.zero else {
            return WalletSpendDecision(status: .rejected, reason: "Spend amount must be greater than zero.")
        }

        if request.amount <= Decimal(25) {
            return WalletSpendDecision(
                status: .approved,
                reason: "Amount is within the local iOS policy limit."
            )
        }

        return WalletSpendDecision(
            status: .needsApproval,
            reason: "Amount exceeds the local iOS policy limit and needs explicit approval."
        )
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
        afmSnapshot: AFMServiceSnapshot
    ) -> [RuntimeFeatureState] {
        [
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
                feature: .afmServices,
                mode: afmSnapshot.allServicesAvailable ? .service : .unavailable,
                isAvailable: afmSnapshot.allServicesAvailable,
                status: afmSnapshot.serviceStatusText
            ),
            RuntimeFeatureState(
                feature: .copilot,
                mode: afmSnapshot.coreCopilotServicesAvailable ? .service : .local,
                isAvailable: true,
                status: afmSnapshot.coreCopilotServicesAvailable ? "AFM router + pipelines" : "Local fallback bridge"
            ),
            RuntimeFeatureState(feature: .wallet, mode: .local, isAvailable: true, status: "Local policy bridge"),
            RuntimeFeatureState(feature: .downloads, mode: .native, isAvailable: true, status: "URLSession bridge")
        ]
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

    private static func makeWalletAddress() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        if raw.count >= 40 {
            return "0x\(raw.prefix(40))"
        }
        return "0x\(raw)\(String(repeating: "0", count: 40 - raw.count))"
    }
}
