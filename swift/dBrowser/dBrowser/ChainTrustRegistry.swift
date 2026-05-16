import Foundation

enum ChainTrustFamily: String, Codable, Equatable, CaseIterable {
    case bitcoin
    case ethereum
    case evmLayer2
    case solana
    case cosmosTendermint
    case polkadotSubstrate
    case avalanche
    case tron
    case xrpLedger
    case sui
    case aptos
    case unknown

    var title: String {
        switch self {
        case .bitcoin: "Bitcoin"
        case .ethereum: "Ethereum/EVM"
        case .evmLayer2: "EVM L2s"
        case .solana: "Solana"
        case .cosmosTendermint: "Cosmos/Tendermint"
        case .polkadotSubstrate: "Polkadot/Substrate"
        case .avalanche: "Avalanche"
        case .tron: "TRON"
        case .xrpLedger: "XRP Ledger"
        case .sui: "Sui"
        case .aptos: "Aptos"
        case .unknown: "Unknown chain"
        }
    }
}

enum ChainTrustState: String, Codable, Equatable, CaseIterable {
    case unavailable
    case syncing
    case verified
    case proofChecked
    case rpcFallback
    case stale
    case failed

    var title: String {
        switch self {
        case .unavailable: "Unavailable"
        case .syncing: "Syncing"
        case .verified: "Light-client verified"
        case .proofChecked: "Proof checked"
        case .rpcFallback: "Gateway/RPC fallback"
        case .stale: "Stale"
        case .failed: "Failed"
        }
    }

    var isProductionEvidence: Bool {
        self == .verified || self == .proofChecked
    }
}

enum ChainTrustSource: String, Codable, Equatable {
    case embeddedLightClient
    case localProof
    case afMarketSettlement
    case gatewayRPCFallback
    case remoteRuntime
    case unavailable

    var title: String {
        switch self {
        case .embeddedLightClient: "Embedded light client"
        case .localProof: "Local proof"
        case .afMarketSettlement: "AFMarket settlement"
        case .gatewayRPCFallback: "Gateway/RPC fallback"
        case .remoteRuntime: "Remote runtime"
        case .unavailable: "Unavailable"
        }
    }
}

struct ChainTrustCheckpoint: Codable, Equatable {
    var height: Int?
    var blockHash: String?
    var checkpointID: String?
    var updatedAt: Date?

    nonisolated init(
        height: Int? = nil,
        blockHash: String? = nil,
        checkpointID: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.height = height
        self.blockHash = blockHash
        self.checkpointID = checkpointID
        self.updatedAt = updatedAt
    }

    var summary: String {
        if let height, let blockHash {
            return "height \(height), block \(blockHash)"
        }
        if let height {
            return "height \(height)"
        }
        if let blockHash {
            return "block \(blockHash)"
        }
        return checkpointID ?? "no checkpoint"
    }
}

struct ChainTrustEvidence: Codable, Equatable, Identifiable {
    var id: String
    var source: ChainTrustSource
    var summary: String
    var taskID: String?
    var proofID: String?
    var escrowID: String?
    var escrowContract: String?
    var transactionHash: String?
    var blockNumber: Int?
    var recordedAt: Date?

    nonisolated init(
        id: String,
        source: ChainTrustSource,
        summary: String,
        taskID: String? = nil,
        proofID: String? = nil,
        escrowID: String? = nil,
        escrowContract: String? = nil,
        transactionHash: String? = nil,
        blockNumber: Int? = nil,
        recordedAt: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.summary = summary
        self.taskID = taskID
        self.proofID = proofID
        self.escrowID = escrowID
        self.escrowContract = escrowContract
        self.transactionHash = transactionHash
        self.blockNumber = blockNumber
        self.recordedAt = recordedAt
    }
}

struct ChainTrustStatus: Codable, Equatable, Identifiable {
    var id: String { chainID }

    var chainID: String
    var chainRef: String
    var displayName: String
    var family: ChainTrustFamily
    var state: ChainTrustState
    var trustSource: ChainTrustSource
    var supportedProofTypes: [String]
    var latestCheckpoint: ChainTrustCheckpoint?
    var lastVerificationError: String?
    var evidence: [ChainTrustEvidence]
    var lastUpdated: Date?

    nonisolated init(
        chainID: String,
        chainRef: String,
        displayName: String,
        family: ChainTrustFamily,
        state: ChainTrustState = .rpcFallback,
        trustSource: ChainTrustSource = .gatewayRPCFallback,
        supportedProofTypes: [String],
        latestCheckpoint: ChainTrustCheckpoint? = nil,
        lastVerificationError: String? = nil,
        evidence: [ChainTrustEvidence] = [],
        lastUpdated: Date? = nil
    ) {
        self.chainID = chainID
        self.chainRef = chainRef
        self.displayName = displayName
        self.family = family
        self.state = state
        self.trustSource = trustSource
        self.supportedProofTypes = supportedProofTypes
        self.latestCheckpoint = latestCheckpoint
        self.lastVerificationError = lastVerificationError
        self.evidence = evidence
        self.lastUpdated = lastUpdated
    }

    var displaySummary: String {
        switch state {
        case .verified:
            return "\(displayName) is locally verified by \(trustSource.title)."
        case .proofChecked:
            return "\(displayName) has proof-checked evidence from \(trustSource.title)."
        case .rpcFallback:
            return "\(displayName) is using Gateway/RPC fallback; no local chain verification is claimed."
        case .syncing:
            return "\(displayName) is waiting for chain evidence."
        case .stale:
            return "\(displayName) has stale verification data."
        case .failed:
            return "\(displayName) verification failed: \(lastVerificationError ?? "unknown error")."
        case .unavailable:
            return "\(displayName) verification is unavailable."
        }
    }

    var proofTypeSummary: String {
        supportedProofTypes.isEmpty ? "No proof types configured" : supportedProofTypes.joined(separator: ", ")
    }

    func matches(chainRef candidate: String) -> Bool {
        let normalizedCandidate = Self.normalized(candidate)
        return normalizedCandidate == Self.normalized(chainRef)
            || normalizedCandidate == Self.normalized(chainID)
            || normalizedCandidate == Self.normalized(displayName)
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    nonisolated static var defaultStatuses: [ChainTrustStatus] {
        [
            ChainTrustStatus(
                chainID: "bitcoin-mainnet",
                chainRef: "bitcoin-mainnet",
                displayName: "Bitcoin",
                family: .bitcoin,
                supportedProofTypes: ["spv", "compact-filter"]
            ),
            ChainTrustStatus(
                chainID: "ethereum-mainnet",
                chainRef: "ethereum-mainnet",
                displayName: "Ethereum Mainnet",
                family: .ethereum,
                supportedProofTypes: ["sync-committee", "execution-proof", "receipt-proof"]
            ),
            ChainTrustStatus(
                chainID: "base-sepolia",
                chainRef: "base-sepolia",
                displayName: "Base Sepolia",
                family: .evmLayer2,
                supportedProofTypes: ["evm-receipt", "escrow-event", "settlement-transaction"]
            ),
            ChainTrustStatus(
                chainID: "evm-l2",
                chainRef: "evm-l2",
                displayName: "EVM L2s",
                family: .evmLayer2,
                supportedProofTypes: ["rollup-state-root", "evm-receipt"]
            ),
            ChainTrustStatus(
                chainID: "solana-mainnet",
                chainRef: "solana-mainnet",
                displayName: "Solana",
                family: .solana,
                supportedProofTypes: ["optimistic-confirmation", "transaction-status"]
            ),
            ChainTrustStatus(
                chainID: "cosmos-hub",
                chainRef: "cosmos-hub",
                displayName: "Cosmos/Tendermint",
                family: .cosmosTendermint,
                supportedProofTypes: ["tendermint-header", "ics23"]
            ),
            ChainTrustStatus(
                chainID: "polkadot",
                chainRef: "polkadot",
                displayName: "Polkadot/Substrate",
                family: .polkadotSubstrate,
                supportedProofTypes: ["grandpa-finality", "mmr-proof"]
            ),
            ChainTrustStatus(
                chainID: "avalanche-c",
                chainRef: "avalanche-c",
                displayName: "Avalanche C-Chain",
                family: .avalanche,
                supportedProofTypes: ["snowman-finality", "evm-receipt"]
            ),
            ChainTrustStatus(
                chainID: "tron-mainnet",
                chainRef: "tron-mainnet",
                displayName: "TRON",
                family: .tron,
                supportedProofTypes: ["sr-block-header", "transaction-receipt"]
            ),
            ChainTrustStatus(
                chainID: "xrp-ledger",
                chainRef: "xrp-ledger",
                displayName: "XRP Ledger",
                family: .xrpLedger,
                supportedProofTypes: ["ledger-header", "transaction-proof"]
            ),
            ChainTrustStatus(
                chainID: "sui-mainnet",
                chainRef: "sui-mainnet",
                displayName: "Sui",
                family: .sui,
                supportedProofTypes: ["checkpoint", "object-proof"]
            ),
            ChainTrustStatus(
                chainID: "aptos-mainnet",
                chainRef: "aptos-mainnet",
                displayName: "Aptos",
                family: .aptos,
                supportedProofTypes: ["ledger-info", "state-proof"]
            )
        ]
    }
}

struct ChainTrustRegistry: Codable, Equatable {
    var statuses: [ChainTrustStatus]

    nonisolated init(statuses: [ChainTrustStatus] = ChainTrustStatus.defaultStatuses) {
        self.statuses = statuses
    }

    nonisolated static var defaultRegistry: ChainTrustRegistry {
        ChainTrustRegistry()
    }

    var supportedFamilyCount: Int {
        Set(statuses.map(\.family)).subtracting([.unknown]).count
    }

    var strongestState: ChainTrustState {
        if statuses.contains(where: { $0.state == .verified }) {
            return .verified
        }
        if statuses.contains(where: { $0.state == .proofChecked }) {
            return .proofChecked
        }
        if statuses.contains(where: { $0.state == .syncing }) {
            return .syncing
        }
        if statuses.contains(where: { $0.state == .rpcFallback }) {
            return .rpcFallback
        }
        if statuses.contains(where: { $0.state == .stale }) {
            return .stale
        }
        if statuses.contains(where: { $0.state == .failed }) {
            return .failed
        }
        return .unavailable
    }

    var runtimeStatusText: String {
        if let verified = statuses.first(where: { $0.state == .verified }) {
            return "\(verified.displayName) light-client verified; \(statuses.count) chains registered"
        }
        if let proofChecked = statuses.first(where: { $0.state == .proofChecked }) {
            return "\(proofChecked.displayName) proof checked; \(statuses.count) chains registered"
        }
        if let syncing = statuses.first(where: { $0.state == .syncing }) {
            return "\(syncing.displayName) waiting for chain evidence; gateway/RPC fallback remains labeled"
        }
        return "\(statuses.count) chains registered; gateway/RPC fallback only"
    }

    var fallbackWarning: String {
        "Gateway/RPC fallback is not local light-client verification."
    }

    func status(forChainRef chainRef: String) -> ChainTrustStatus? {
        statuses.first { $0.matches(chainRef: chainRef) }
    }

    mutating func recordAFMarketVerification(_ report: AFMNodeVerificationReport) -> ChainTrustStatus? {
        guard let rawChainRef = report.chainRef?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawChainRef.isEmpty else {
            return nil
        }
        guard let state = Self.chainTrustState(for: report.state) else {
            return nil
        }

        let evidence = ChainTrustEvidence(
            id: Self.evidenceID(for: report),
            source: .afMarketSettlement,
            summary: report.summary,
            taskID: report.taskID,
            proofID: report.proofID,
            escrowID: report.escrowID,
            escrowContract: report.escrowContract,
            transactionHash: report.transactionHash,
            blockNumber: report.blockNumber,
            recordedAt: Date()
        )
        var status = self.status(forChainRef: rawChainRef)
            ?? Self.statusForUnknownChain(chainRef: rawChainRef)
        status.state = state
        status.trustSource = .afMarketSettlement
        status.latestCheckpoint = ChainTrustCheckpoint(
            height: report.blockNumber,
            blockHash: report.transactionHash,
            checkpointID: report.escrowID,
            updatedAt: Date()
        )
        status.lastVerificationError = state == .failed ? report.summary : nil
        status.lastUpdated = Date()
        status.evidence.insert(evidence, at: 0)

        if let index = statuses.firstIndex(where: { $0.matches(chainRef: rawChainRef) }) {
            statuses[index] = status
        } else {
            statuses.append(status)
        }
        return status
    }

    private static func chainTrustState(for verificationState: AFMVerificationState) -> ChainTrustState? {
        switch verificationState {
        case .chainAnchored:
            return .proofChecked
        case .pendingChainEvidence:
            return .syncing
        case .failed:
            return .failed
        case .mock, .locallyConsistent:
            return nil
        }
    }

    private static func evidenceID(for report: AFMNodeVerificationReport) -> String {
        [
            "afmarket",
            report.taskID,
            report.transactionHash,
            report.proofID,
            report.escrowID
        ]
            .compactMap { $0 }
            .joined(separator: "-")
    }

    private static func statusForUnknownChain(chainRef: String) -> ChainTrustStatus {
        ChainTrustStatus(
            chainID: ChainTrustStatus.normalized(chainRef),
            chainRef: chainRef,
            displayName: chainRef,
            family: inferredFamily(for: chainRef),
            state: .rpcFallback,
            trustSource: .gatewayRPCFallback,
            supportedProofTypes: ["external-settlement-evidence"]
        )
    }

    private static func inferredFamily(for chainRef: String) -> ChainTrustFamily {
        let normalized = ChainTrustStatus.normalized(chainRef)
        if normalized.contains("bitcoin") || normalized.contains("btc") {
            return .bitcoin
        }
        if normalized.contains("base")
            || normalized.contains("ethereum")
            || normalized.contains("sepolia")
            || normalized.contains("polygon")
            || normalized.contains("optimism")
            || normalized.contains("arbitrum")
            || normalized.contains("evm") {
            return .evmLayer2
        }
        if normalized.contains("solana") {
            return .solana
        }
        if normalized.contains("cosmos") || normalized.contains("tendermint") {
            return .cosmosTendermint
        }
        if normalized.contains("polkadot") || normalized.contains("substrate") {
            return .polkadotSubstrate
        }
        if normalized.contains("avalanche") {
            return .avalanche
        }
        if normalized.contains("tron") {
            return .tron
        }
        if normalized.contains("xrp") {
            return .xrpLedger
        }
        if normalized.contains("sui") {
            return .sui
        }
        if normalized.contains("aptos") {
            return .aptos
        }
        return .unknown
    }
}
