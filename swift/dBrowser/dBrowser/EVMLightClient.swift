import CryptoKit
import Foundation

enum EVMChain: Equatable, CaseIterable, Codable {
    case ethereumMainnet
    case baseMainnet
    case baseSepolia
    case arbitrumOne
    case optimismMainnet
    case polygonMainnet
    case bnbSmartChain
    case avalancheCChain

    nonisolated var chainID: Int {
        switch self {
        case .ethereumMainnet: 1
        case .baseMainnet: 8453
        case .baseSepolia: 84532
        case .arbitrumOne: 42161
        case .optimismMainnet: 10
        case .polygonMainnet: 137
        case .bnbSmartChain: 56
        case .avalancheCChain: 43114
        }
    }

    nonisolated var chainRef: String {
        switch self {
        case .ethereumMainnet: "ethereum-mainnet"
        case .baseMainnet: "base-mainnet"
        case .baseSepolia: "base-sepolia"
        case .arbitrumOne: "arbitrum-one"
        case .optimismMainnet: "optimism-mainnet"
        case .polygonMainnet: "polygon-mainnet"
        case .bnbSmartChain: "bnb-smart-chain"
        case .avalancheCChain: "avalanche-c"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .ethereumMainnet: "Ethereum Mainnet"
        case .baseMainnet: "Base"
        case .baseSepolia: "Base Sepolia"
        case .arbitrumOne: "Arbitrum One"
        case .optimismMainnet: "Optimism"
        case .polygonMainnet: "Polygon PoS"
        case .bnbSmartChain: "BNB Smart Chain"
        case .avalancheCChain: "Avalanche C-Chain"
        }
    }

    nonisolated var family: ChainTrustFamily {
        switch self {
        case .ethereumMainnet:
            return .ethereum
        case .avalancheCChain:
            return .avalanche
        case .baseMainnet, .baseSepolia, .arbitrumOne, .optimismMainnet, .polygonMainnet, .bnbSmartChain:
            return .evmLayer2
        }
    }

    nonisolated var finalityModel: EVMFinalityModel {
        switch self {
        case .ethereumMainnet:
            return .proofOfStakeFinalized
        case .baseMainnet, .baseSepolia, .arbitrumOne, .optimismMainnet:
            return .rollupSettlement
        case .polygonMainnet, .bnbSmartChain:
            return .validatorFinality
        case .avalancheCChain:
            return .snowmanFinality
        }
    }

    nonisolated var supportedProofTypes: [String] {
        switch self {
        case .ethereumMainnet:
            return ["sync-committee", "execution-proof", "account-proof", "storage-proof", "receipt-proof"]
        case .baseMainnet, .baseSepolia, .arbitrumOne, .optimismMainnet:
            return ["rollup-state-root", "settlement-finality", "evm-receipt", "escrow-event"]
        case .polygonMainnet, .bnbSmartChain:
            return ["validator-finality", "evm-receipt", "account-proof", "storage-proof"]
        case .avalancheCChain:
            return ["snowman-finality", "evm-receipt", "account-proof", "storage-proof"]
        }
    }

    nonisolated var l2SettlementSummary: String? {
        switch self {
        case .baseMainnet, .baseSepolia:
            return "OP Stack rollup data is sequencer-originated until settlement/finality evidence is checked on Ethereum."
        case .arbitrumOne:
            return "Arbitrum sequencer data needs rollup assertion and dispute-window context before final trust."
        case .optimismMainnet:
            return "Optimism sequencer data needs OP Stack settlement evidence before final trust."
        case .polygonMainnet:
            return "Polygon PoS uses validator/checkpoint finality, not Ethereum mainnet finality."
        case .bnbSmartChain:
            return "BNB Smart Chain uses validator finality, not Ethereum mainnet finality."
        case .avalancheCChain:
            return "Avalanche C-Chain uses Snowman finality, not Ethereum mainnet finality."
        case .ethereumMainnet:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let chain = Self.known(from: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown EVM chain: \(value)")
        }
        self = chain
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(chainRef)
    }

    nonisolated static func known(from value: String) -> EVMChain? {
        let normalized = normalize(value)
        switch normalized {
        case "ethereum", "mainnet":
            return .ethereumMainnet
        case "base":
            return .baseMainnet
        case "arbitrum":
            return .arbitrumOne
        case "optimism":
            return .optimismMainnet
        case "polygon":
            return .polygonMainnet
        case "bnb", "bsc":
            return .bnbSmartChain
        case "avalanche":
            return .avalancheCChain
        default:
            break
        }
        if let numeric = Int(normalized), let byChainID = allCases.first(where: { $0.chainID == numeric }) {
            return byChainID
        }
        return allCases.first {
            normalize($0.chainRef) == normalized
                || normalize($0.displayName) == normalized
                || normalize(String($0.chainID)) == normalized
        }
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

enum EVMFinalityModel: String, Codable, Equatable, CaseIterable {
    case proofOfStakeFinalized = "proof-of-stake-finalized"
    case rollupSettlement = "rollup-settlement"
    case validatorFinality = "validator-finality"
    case snowmanFinality = "snowman-finality"
    case rpcFallback = "rpc-fallback"

    nonisolated var title: String {
        switch self {
        case .proofOfStakeFinalized: "Proof-of-stake finalized"
        case .rollupSettlement: "Rollup settlement"
        case .validatorFinality: "Validator finality"
        case .snowmanFinality: "Snowman finality"
        case .rpcFallback: "RPC fallback"
        }
    }
}

enum EVMLightClientSyncState: String, Codable, Equatable, CaseIterable {
    case unavailable
    case syncing
    case synced
    case proofChecked = "proof_checked"
    case rpcFallback = "rpc_fallback"
    case stale
    case failed

    nonisolated var chainTrustState: ChainTrustState {
        switch self {
        case .unavailable, .rpcFallback:
            return .rpcFallback
        case .syncing:
            return .syncing
        case .synced:
            return .verified
        case .proofChecked:
            return .proofChecked
        case .stale:
            return .stale
        case .failed:
            return .failed
        }
    }
}

struct EVMLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var chain: EVMChain

    nonisolated static let local = EVMLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        chain: .ethereumMainnet
    )

    nonisolated static let disabled = EVMLightClientEndpointConfiguration(
        baseURL: nil,
        chain: .ethereumMainnet
    )
}

enum EVMLocalProofKind: String, Codable, Equatable, CaseIterable {
    case account
    case storage
    case receipt
    case log

    nonisolated var rootFieldName: String {
        switch self {
        case .account, .storage:
            return "state root"
        case .receipt, .log:
            return "receipts root"
        }
    }
}

enum EVMProofWitnessPosition: String, Codable, Equatable {
    case left
    case right
}

struct EVMProofWitness: Codable, Equatable {
    var hash: String
    var position: EVMProofWitnessPosition

    nonisolated init(hash: String, position: EVMProofWitnessPosition) {
        self.hash = hash
        self.position = position
    }
}

struct EVMExecutionHeaderSnapshot: Codable, Equatable, Identifiable {
    var id: String { EVMHex.normalized(hash) }

    var chain: EVMChain
    var number: Int
    var hash: String
    var parentHash: String?
    var stateRoot: String
    var receiptsRoot: String
    var transactionsRoot: String?
    var timestamp: UInt64?
    var finalized: Bool
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case chain
        case chainRef = "chain_ref"
        case number
        case hash
        case parentHash = "parent_hash"
        case stateRoot = "state_root"
        case receiptsRoot = "receipts_root"
        case transactionsRoot = "transactions_root"
        case timestamp
        case finalized
        case source
    }

    nonisolated init(
        chain: EVMChain,
        number: Int,
        hash: String,
        parentHash: String? = nil,
        stateRoot: String,
        receiptsRoot: String,
        transactionsRoot: String? = nil,
        timestamp: UInt64? = nil,
        finalized: Bool = false,
        source: String? = nil
    ) {
        self.chain = chain
        self.number = number
        self.hash = EVMHex.normalized(hash)
        self.parentHash = parentHash.map(EVMHex.normalized)
        self.stateRoot = EVMHex.normalized(stateRoot)
        self.receiptsRoot = EVMHex.normalized(receiptsRoot)
        self.transactionsRoot = transactionsRoot.map(EVMHex.normalized)
        self.timestamp = timestamp
        self.finalized = finalized
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let chain = try container.decodeIfPresent(EVMChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = EVMChain.known(from: chainRef) {
            self.chain = chain
        } else {
            self.chain = .ethereumMainnet
        }
        self.number = try container.decode(Int.self, forKey: .number)
        self.hash = EVMHex.normalized(try container.decode(String.self, forKey: .hash))
        self.parentHash = try container.decodeIfPresent(String.self, forKey: .parentHash).map(EVMHex.normalized)
        self.stateRoot = EVMHex.normalized(try container.decode(String.self, forKey: .stateRoot))
        self.receiptsRoot = EVMHex.normalized(try container.decode(String.self, forKey: .receiptsRoot))
        self.transactionsRoot = try container.decodeIfPresent(String.self, forKey: .transactionsRoot).map(EVMHex.normalized)
        self.timestamp = try container.decodeIfPresent(UInt64.self, forKey: .timestamp)
        self.finalized = try container.decodeIfPresent(Bool.self, forKey: .finalized) ?? false
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(number, forKey: .number)
        try container.encode(hash, forKey: .hash)
        try container.encodeIfPresent(parentHash, forKey: .parentHash)
        try container.encode(stateRoot, forKey: .stateRoot)
        try container.encode(receiptsRoot, forKey: .receiptsRoot)
        try container.encodeIfPresent(transactionsRoot, forKey: .transactionsRoot)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(finalized, forKey: .finalized)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: number,
            blockHash: EVMHex.normalized(hash),
            checkpointID: "\(chain.chainRef)-execution-\(number)",
            updatedAt: timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    func expectedRoot(for kind: EVMLocalProofKind) -> String {
        switch kind {
        case .account, .storage:
            return EVMHex.normalized(stateRoot)
        case .receipt, .log:
            return EVMHex.normalized(receiptsRoot)
        }
    }
}

struct EVMLocalProof: Codable, Equatable, Identifiable {
    var id: String { proofID }

    var proofID: String
    var kind: EVMLocalProofKind
    var chain: EVMChain
    var subject: String
    var storageKey: String?
    var expectedValue: String?
    var blockHash: String
    var blockNumber: Int
    var expectedRoot: String
    var leafHash: String
    var witnesses: [EVMProofWitness]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case proofID = "proof_id"
        case kind
        case chain
        case chainRef = "chain_ref"
        case subject
        case storageKey = "storage_key"
        case expectedValue = "expected_value"
        case blockHash = "block_hash"
        case blockNumber = "block_number"
        case expectedRoot = "expected_root"
        case leafHash = "leaf_hash"
        case witnesses
        case source
    }

    nonisolated init(
        proofID: String,
        kind: EVMLocalProofKind,
        chain: EVMChain,
        subject: String,
        storageKey: String? = nil,
        expectedValue: String? = nil,
        blockHash: String,
        blockNumber: Int,
        expectedRoot: String,
        leafHash: String,
        witnesses: [EVMProofWitness],
        source: String? = nil
    ) {
        self.proofID = proofID
        self.kind = kind
        self.chain = chain
        self.subject = subject
        self.storageKey = storageKey
        self.expectedValue = expectedValue
        self.blockHash = EVMHex.normalized(blockHash)
        self.blockNumber = blockNumber
        self.expectedRoot = EVMHex.normalized(expectedRoot)
        self.leafHash = EVMHex.normalized(leafHash)
        self.witnesses = witnesses
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.proofID = try container.decodeIfPresent(String.self, forKey: .proofID) ?? UUID().uuidString
        self.kind = try container.decode(EVMLocalProofKind.self, forKey: .kind)
        if let chain = try container.decodeIfPresent(EVMChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = EVMChain.known(from: chainRef) {
            self.chain = chain
        } else {
            self.chain = .ethereumMainnet
        }
        self.subject = try container.decode(String.self, forKey: .subject)
        self.storageKey = try container.decodeIfPresent(String.self, forKey: .storageKey)
        self.expectedValue = try container.decodeIfPresent(String.self, forKey: .expectedValue)
        self.blockHash = EVMHex.normalized(try container.decode(String.self, forKey: .blockHash))
        self.blockNumber = try container.decode(Int.self, forKey: .blockNumber)
        self.expectedRoot = EVMHex.normalized(try container.decode(String.self, forKey: .expectedRoot))
        self.leafHash = EVMHex.normalized(try container.decode(String.self, forKey: .leafHash))
        self.witnesses = try container.decodeIfPresent([EVMProofWitness].self, forKey: .witnesses) ?? []
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proofID, forKey: .proofID)
        try container.encode(kind, forKey: .kind)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(subject, forKey: .subject)
        try container.encodeIfPresent(storageKey, forKey: .storageKey)
        try container.encodeIfPresent(expectedValue, forKey: .expectedValue)
        try container.encode(blockHash, forKey: .blockHash)
        try container.encode(blockNumber, forKey: .blockNumber)
        try container.encode(expectedRoot, forKey: .expectedRoot)
        try container.encode(leafHash, forKey: .leafHash)
        try container.encode(witnesses, forKey: .witnesses)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var computedRoot: String? {
        Self.computeRoot(leafHash: leafHash, witnesses: witnesses)
    }

    var verifiesExpectedRoot: Bool {
        computedRoot == EVMHex.normalized(expectedRoot)
    }

    static func computeRoot(leafHash: String, witnesses: [EVMProofWitness]) -> String? {
        guard var node = EVMHex.data(from: leafHash) else { return nil }
        for witness in witnesses {
            guard let sibling = EVMHex.data(from: witness.hash) else { return nil }
            var pair = Data()
            switch witness.position {
            case .left:
                pair.append(sibling)
                pair.append(node)
            case .right:
                pair.append(node)
                pair.append(sibling)
            }
            node = Data(SHA256.hash(data: pair))
        }
        return EVMHex.hex(from: node)
    }

    static func fixtureLeafHash(kind: EVMLocalProofKind, subject: String, key: String? = nil, value: String) -> String {
        let payload = [
            kind.rawValue,
            subject.lowercased(),
            key?.lowercased() ?? "",
            value.lowercased()
        ].joined(separator: "|")
        return EVMHex.sha256Hex(payload)
    }
}

struct EVMLocalProofBundle: Codable, Equatable {
    var header: EVMExecutionHeaderSnapshot
    var proof: EVMLocalProof

    nonisolated init(header: EVMExecutionHeaderSnapshot, proof: EVMLocalProof) {
        self.header = header
        self.proof = proof
    }

    func verify() -> EVMProofVerificationResult {
        guard proof.chain == header.chain else {
            return failure("EVM proof chain \(proof.chain.chainRef) does not match header chain \(header.chain.chainRef).")
        }

        guard EVMHex.normalized(proof.blockHash) == EVMHex.normalized(header.hash),
              proof.blockNumber == header.number else {
            return failure("EVM proof references a different execution block.")
        }

        let expectedHeaderRoot = header.expectedRoot(for: proof.kind)
        guard EVMHex.normalized(proof.expectedRoot) == expectedHeaderRoot else {
            return failure("EVM \(proof.kind.rawValue) proof expected root does not match the header \(proof.kind.rootFieldName).")
        }

        guard proof.verifiesExpectedRoot else {
            return failure("EVM \(proof.kind.rawValue) proof did not resolve to the expected \(proof.kind.rootFieldName).")
        }

        return EVMProofVerificationResult(
            verified: true,
            state: header.finalized && header.chain == .ethereumMainnet ? .synced : .proofChecked,
            proofID: proof.proofID,
            kind: proof.kind,
            chainRef: header.chain.chainRef,
            blockHash: header.hash,
            blockNumber: header.number,
            summary: "EVM \(proof.kind.rawValue) fixture proof checked for \(header.chain.displayName) block \(header.number)."
        )
    }

    private func failure(_ summary: String) -> EVMProofVerificationResult {
        EVMProofVerificationResult(
            verified: false,
            state: .failed,
            proofID: proof.proofID,
            kind: proof.kind,
            chainRef: proof.chain.chainRef,
            blockHash: proof.blockHash,
            blockNumber: proof.blockNumber,
            summary: summary
        )
    }
}

struct EVMProofVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: EVMLightClientSyncState
    var proofID: String
    var kind: EVMLocalProofKind
    var chainRef: String
    var blockHash: String
    var blockNumber: Int?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case proofID = "proof_id"
        case kind
        case chainRef = "chain_ref"
        case blockHash = "block_hash"
        case blockNumber = "block_number"
        case summary
    }
}

struct EVMLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var chain: EVMChain
    var syncState: EVMLightClientSyncState
    var source: String
    var finalityModel: EVMFinalityModel
    var finalizedCheckpoint: EVMExecutionHeaderSnapshot?
    var head: EVMExecutionHeaderSnapshot?
    var peerCount: Int?
    var proofSource: String?
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case serviceAvailable = "service_available"
        case chain
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case syncState = "sync_state"
        case source
        case finalityModel = "finality_model"
        case finalizedCheckpoint = "finalized_checkpoint"
        case head
        case peerCount = "peer_count"
        case proofSource = "proof_source"
        case lastError = "last_error"
    }

    nonisolated init(
        serviceAvailable: Bool,
        chain: EVMChain,
        syncState: EVMLightClientSyncState,
        source: String,
        finalityModel: EVMFinalityModel? = nil,
        finalizedCheckpoint: EVMExecutionHeaderSnapshot? = nil,
        head: EVMExecutionHeaderSnapshot? = nil,
        peerCount: Int? = nil,
        proofSource: String? = nil,
        lastError: String? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.chain = chain
        self.syncState = syncState
        self.source = source
        self.finalityModel = finalityModel ?? chain.finalityModel
        self.finalizedCheckpoint = finalizedCheckpoint
        self.head = head
        self.peerCount = peerCount
        self.proofSource = proofSource
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? true
        if let chain = try container.decodeIfPresent(EVMChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = EVMChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainID = try container.decodeIfPresent(Int.self, forKey: .chainID),
                  let chain = EVMChain.known(from: String(chainID)) {
            self.chain = chain
        } else {
            self.chain = .ethereumMainnet
        }
        self.syncState = try container.decodeIfPresent(EVMLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "evm-light-client"
        self.finalityModel = try container.decodeIfPresent(EVMFinalityModel.self, forKey: .finalityModel) ?? chain.finalityModel
        self.finalizedCheckpoint = try container.decodeIfPresent(EVMExecutionHeaderSnapshot.self, forKey: .finalizedCheckpoint)
        self.head = try container.decodeIfPresent(EVMExecutionHeaderSnapshot.self, forKey: .head)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.proofSource = try container.decodeIfPresent(String.self, forKey: .proofSource)
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceAvailable, forKey: .serviceAvailable)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainID, forKey: .chainID)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(source, forKey: .source)
        try container.encode(finalityModel, forKey: .finalityModel)
        try container.encodeIfPresent(finalizedCheckpoint, forKey: .finalizedCheckpoint)
        try container.encodeIfPresent(head, forKey: .head)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(proofSource, forKey: .proofSource)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    static func fallback(chain: EVMChain, lastError: String?) -> EVMLightClientServiceSnapshot {
        EVMLightClientServiceSnapshot(
            serviceAvailable: false,
            chain: chain,
            syncState: .unavailable,
            source: "gateway-rpc-fallback",
            finalityModel: .rpcFallback,
            lastError: lastError
        )
    }

    var bestHeader: EVMExecutionHeaderSnapshot? {
        finalizedCheckpoint ?? head
    }

    var statusSummary: String {
        switch syncState {
        case .synced:
            return "\(chain.displayName) light-client finalized checkpoint is synced at block \(bestHeader?.number.description ?? "unknown")."
        case .proofChecked:
            let settlement = chain.l2SettlementSummary.map { " \($0)" } ?? ""
            return "\(chain.displayName) proof evidence is locally checked.\(settlement)"
        case .syncing:
            return "\(chain.displayName) light-client evidence is syncing."
        case .stale:
            return "\(chain.displayName) light-client data is stale."
        case .failed:
            return "\(chain.displayName) light-client verification failed: \(lastError ?? "unknown error")."
        case .rpcFallback, .unavailable:
            return "\(chain.displayName) light-client service is unavailable; Gateway/RPC fallback remains labeled."
        }
    }

    var chainTrustStatus: ChainTrustStatus {
        let state = syncState.chainTrustState
        let header = bestHeader
        let checkpoint = header?.checkpoint ?? ChainTrustCheckpoint(
            height: nil,
            blockHash: nil,
            checkpointID: "\(chain.chainRef)-light-client",
            updatedAt: nil
        )
        let evidence: [ChainTrustEvidence] = state.isProductionEvidence ? [
            ChainTrustEvidence(
                id: "\(chain.chainRef)-evm-light-client-\(checkpoint.blockHash ?? "unknown")",
                source: state == .verified ? .embeddedLightClient : .localProof,
                summary: statusSummary,
                blockNumber: checkpoint.height,
                recordedAt: Date()
            )
        ] : []
        let trustSource: ChainTrustSource
        switch state {
        case .verified:
            trustSource = .embeddedLightClient
        case .proofChecked:
            trustSource = .localProof
        case .syncing, .stale:
            trustSource = .embeddedLightClient
        case .failed:
            trustSource = .unavailable
        case .rpcFallback, .unavailable:
            trustSource = .gatewayRPCFallback
        }

        return ChainTrustStatus(
            chainID: chain.chainRef,
            chainRef: chain.chainRef,
            displayName: chain.displayName,
            family: chain.family,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: chain.supportedProofTypes,
            latestCheckpoint: checkpoint.height == nil && checkpoint.blockHash == nil ? nil : checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

final class EVMLightClientServiceClient {
    private let configuration: EVMLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: EVMLightClientEndpointConfiguration = .disabled,
        session: URLSession = EVMLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> EVMLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(chain: configuration.chain, lastError: "Ethereum/EVM light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/evm/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/evm/status")
            } catch {
                return .fallback(chain: configuration.chain, lastError: error.localizedDescription)
            }
        }
    }

    func verifyProof(_ proof: EVMLocalProofBundle) -> EVMProofVerificationResult {
        proof.verify()
    }

    func verifyProofViaService(_ proof: EVMLocalProofBundle) async throws -> EVMProofVerificationResult {
        do {
            return try await post(path: "/v1/evm/verify-proof", body: proof)
        } catch {
            return try await post(path: "/evm/verify-proof", body: proof)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> EVMLightClientServiceSnapshot {
        var snapshot: EVMLightClientServiceSnapshot = try await get(path: path)
        if snapshot.chain != configuration.chain {
            snapshot.chain = configuration.chain
            snapshot.finalityModel = configuration.chain.finalityModel
        }
        return snapshot
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let baseURL = configuration.baseURL else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: Self.url(
            baseURL: baseURL,
            path: path,
            queryItems: [URLQueryItem(name: "chain", value: configuration.chain.chainRef)]
        ))
        try validate(response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, U: Encodable>(path: String, body: U) async throws -> T {
        guard let baseURL = configuration.baseURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: Self.url(baseURL: baseURL, path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func url(baseURL: URL, path: String, queryItems: [URLQueryItem] = []) -> URL {
        let pathURL = path.split(separator: "/").reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
        guard !queryItems.isEmpty,
              var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            return pathURL
        }
        components.queryItems = queryItems
        return components.url ?? pathURL
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2.0
        return URLSession(configuration: configuration)
    }
}

enum EVMHex {
    nonisolated static func normalized(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("0x") {
            normalized.removeFirst(2)
        }
        return normalized
    }

    nonisolated static func data(from hex: String) -> Data? {
        let normalized = normalized(hex)
        guard normalized.count % 2 == 0 else { return nil }
        var data = Data()
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    nonisolated static func hex(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func sha256Hex(_ value: String) -> String {
        hex(from: Data(SHA256.hash(data: Data(value.utf8))))
    }
}
