import CryptoKit
import Foundation

enum AvalancheNetwork: String, Codable, Equatable, CaseIterable {
    case cChain = "avalanche-c"
    case fujiCChain = "avalanche-fuji-c"
    case localCChain = "avalanche-local-c"

    nonisolated var chainRef: String {
        rawValue
    }

    nonisolated var chainID: Int {
        switch self {
        case .cChain: 43_114
        case .fujiCChain: 43_113
        case .localCChain: 43_112
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .cChain: "Avalanche C-Chain"
        case .fujiCChain: "Avalanche Fuji C-Chain"
        case .localCChain: "Avalanche Local C-Chain"
        }
    }

    nonisolated var subnetID: String {
        switch self {
        case .cChain, .fujiCChain:
            return "11111111111111111111111111111111LpoYY"
        case .localCChain:
            return "local-primary-network"
        }
    }

    nonisolated var vmID: String {
        switch self {
        case .cChain, .fujiCChain:
            return "mgj786NP7uDwBCcq6NQ6wW4SnoR14HVoE8Bv7E4s34wToZr3N"
        case .localCChain:
            return "local-c-chain-vm"
        }
    }

    nonisolated var evmChain: EVMChain? {
        switch self {
        case .cChain:
            return .avalancheCChain
        case .fujiCChain, .localCChain:
            return nil
        }
    }

    nonisolated var supportedProofTypes: [String] {
        ["snowman-accepted-finality", "validator-weight", "evm-account-proof", "evm-storage-proof", "evm-receipt-proof"]
    }

    nonisolated var limitations: [String] {
        switch self {
        case .cChain:
            return ["Ed25519 accepted-finality checks are fixture-sourced and do not yet replace a production AvalancheGo light client."]
        case .fujiCChain:
            return ["Fuji is modeled for routing and fallback; production local verification is not enabled."]
        case .localCChain:
            return ["Local C-Chain routes require a caller-provided validator set and accepted-block source."]
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let network = Self.known(from: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown Avalanche network: \(value)")
        }
        self = network
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(chainRef)
    }

    nonisolated static func known(from value: String) -> AvalancheNetwork? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "avalanche", "avalanche-c", "avalanche-c-chain", "avax", "c-chain", "43114":
            return .cChain
        case "fuji", "avalanche-fuji", "avalanche-fuji-c", "fuji-c-chain", "43113":
            return .fujiCChain
        case "local", "local-c-chain", "avalanche-local-c", "43112":
            return .localCChain
        default:
            return nil
        }
    }
}

enum AvalancheFinalityModel: String, Codable, Equatable, CaseIterable {
    case snowmanAccepted = "snowman-accepted"
    case rpcFallback = "rpc-fallback"

    nonisolated var title: String {
        switch self {
        case .snowmanAccepted: "Snowman accepted"
        case .rpcFallback: "RPC fallback"
        }
    }
}

enum AvalancheLightClientSyncState: String, Codable, Equatable, CaseIterable {
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

struct AvalancheLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var network: AvalancheNetwork

    nonisolated static let local = AvalancheLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        network: .cChain
    )

    nonisolated static let disabled = AvalancheLightClientEndpointConfiguration(
        baseURL: nil,
        network: .cChain
    )
}

struct AvalancheAcceptedBlockSnapshot: Codable, Equatable, Identifiable {
    var id: String { "\(network.chainRef)-\(height)" }

    var network: AvalancheNetwork
    var height: Int
    var blockHash: String
    var parentHash: String
    var stateRoot: String
    var receiptsRoot: String
    var timestamp: UInt64?
    var accepted: Bool
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case network
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case subnetID = "subnet_id"
        case vmID = "vm_id"
        case height
        case blockHash = "block_hash"
        case parentHash = "parent_hash"
        case stateRoot = "state_root"
        case receiptsRoot = "receipts_root"
        case timestamp
        case accepted
        case source
    }

    nonisolated init(
        network: AvalancheNetwork,
        height: Int,
        blockHash: String,
        parentHash: String,
        stateRoot: String,
        receiptsRoot: String,
        timestamp: UInt64? = nil,
        accepted: Bool,
        source: String? = nil
    ) {
        self.network = network
        self.height = height
        self.blockHash = AvalancheHex.normalized(blockHash)
        self.parentHash = AvalancheHex.normalized(parentHash)
        self.stateRoot = AvalancheHex.normalized(stateRoot)
        self.receiptsRoot = AvalancheHex.normalized(receiptsRoot)
        self.timestamp = timestamp
        self.accepted = accepted
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let network = try container.decodeIfPresent(AvalancheNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = AvalancheNetwork.known(from: chainRef) {
            self.network = network
        } else if let chainID = try container.decodeIfPresent(Int.self, forKey: .chainID),
                  let network = AvalancheNetwork.known(from: String(chainID)) {
            self.network = network
        } else {
            self.network = .cChain
        }
        self.height = try container.decode(Int.self, forKey: .height)
        self.blockHash = AvalancheHex.normalized(try container.decode(String.self, forKey: .blockHash))
        self.parentHash = AvalancheHex.normalized(try container.decode(String.self, forKey: .parentHash))
        self.stateRoot = AvalancheHex.normalized(try container.decode(String.self, forKey: .stateRoot))
        self.receiptsRoot = AvalancheHex.normalized(try container.decode(String.self, forKey: .receiptsRoot))
        self.timestamp = try container.decodeIfPresent(UInt64.self, forKey: .timestamp)
        self.accepted = try container.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(network.chainID, forKey: .chainID)
        try container.encode(network.subnetID, forKey: .subnetID)
        try container.encode(network.vmID, forKey: .vmID)
        try container.encode(height, forKey: .height)
        try container.encode(blockHash, forKey: .blockHash)
        try container.encode(parentHash, forKey: .parentHash)
        try container.encode(stateRoot, forKey: .stateRoot)
        try container.encode(receiptsRoot, forKey: .receiptsRoot)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(accepted, forKey: .accepted)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: height,
            blockHash: blockHash,
            checkpointID: "\(network.chainRef)-accepted-\(height)",
            updatedAt: timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    var executionHeader: EVMExecutionHeaderSnapshot? {
        guard let evmChain = network.evmChain else { return nil }
        return EVMExecutionHeaderSnapshot(
            chain: evmChain,
            number: height,
            hash: blockHash,
            parentHash: parentHash,
            stateRoot: stateRoot,
            receiptsRoot: receiptsRoot,
            timestamp: timestamp,
            finalized: false,
            source: source
        )
    }
}

struct AvalancheValidator: Codable, Equatable, Identifiable {
    var id: String { nodeID }

    var nodeID: String
    var weight: Int
    var publicKey: String?

    private enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case weight
        case publicKey = "public_key"
    }

    nonisolated init(nodeID: String, weight: Int, publicKey: String? = nil) {
        self.nodeID = AvalancheHex.normalizedID(nodeID)
        self.weight = weight
        self.publicKey = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nodeID = AvalancheHex.normalizedID(try container.decode(String.self, forKey: .nodeID))
        self.weight = try container.decode(Int.self, forKey: .weight)
        self.publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct AvalancheValidatorSet: Codable, Equatable, Identifiable {
    var id: String { "\(network.chainRef)-validators-\(setID)" }

    var network: AvalancheNetwork
    var setID: Int
    var validators: [AvalancheValidator]
    var hash: String
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case network
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case setID = "set_id"
        case validators
        case hash
        case source
    }

    nonisolated init(
        network: AvalancheNetwork,
        setID: Int,
        validators: [AvalancheValidator],
        hash: String? = nil,
        source: String? = nil
    ) {
        self.network = network
        self.setID = setID
        self.validators = validators
        self.hash = AvalancheHex.normalized(hash ?? Self.computeHash(validators: validators))
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let network = try container.decodeIfPresent(AvalancheNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = AvalancheNetwork.known(from: chainRef) {
            self.network = network
        } else if let chainID = try container.decodeIfPresent(Int.self, forKey: .chainID),
                  let network = AvalancheNetwork.known(from: String(chainID)) {
            self.network = network
        } else {
            self.network = .cChain
        }
        self.setID = try container.decode(Int.self, forKey: .setID)
        self.validators = try container.decode([AvalancheValidator].self, forKey: .validators)
        self.hash = AvalancheHex.normalized(try container.decodeIfPresent(String.self, forKey: .hash) ?? Self.computeHash(validators: validators))
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(network.chainID, forKey: .chainID)
        try container.encode(setID, forKey: .setID)
        try container.encode(validators, forKey: .validators)
        try container.encode(hash, forKey: .hash)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var totalWeight: Int {
        validators.reduce(0) { $0 + max(0, $1.weight) }
    }

    var validatesHash: Bool {
        hash == Self.computeHash(validators: validators)
    }

    func signedWeight(validatorIDs: Set<String>) -> Int {
        validators.reduce(0) { partial, validator in
            validatorIDs.contains(AvalancheHex.normalizedID(validator.nodeID)) ? partial + max(0, validator.weight) : partial
        }
    }

    func hasAcceptedQuorum(validatorIDs: Set<String>) -> Bool {
        let total = totalWeight
        guard total > 0 else { return false }
        return signedWeight(validatorIDs: validatorIDs) * 5 >= total * 4
    }

    nonisolated static func computeHash(validators: [AvalancheValidator]) -> String {
        let payload = validators
            .map {
                let publicKey = $0.publicKey?.lowercased() ?? ""
                return "\(AvalancheHex.normalizedID($0.nodeID)):\($0.weight):\(publicKey)"
            }
            .sorted()
            .joined(separator: "|")
        return AvalancheHex.sha256Hex(payload)
    }
}

struct AvalancheFinalitySignature: Codable, Equatable, Identifiable {
    var id: String { nodeID }

    var nodeID: String
    var blockHash: String
    var signed: Bool
    var signature: String?

    private enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case blockHash = "block_hash"
        case signed
        case signature
    }

    nonisolated init(
        nodeID: String,
        blockHash: String,
        signed: Bool = true,
        signature: String? = nil
    ) {
        self.nodeID = AvalancheHex.normalizedID(nodeID)
        self.blockHash = AvalancheHex.normalized(blockHash)
        self.signed = signed
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nodeID = AvalancheHex.normalizedID(try container.decode(String.self, forKey: .nodeID))
        self.blockHash = AvalancheHex.normalized(try container.decode(String.self, forKey: .blockHash))
        self.signed = try container.decodeIfPresent(Bool.self, forKey: .signed) ?? true
        self.signature = try container.decodeIfPresent(String.self, forKey: .signature)
    }
}

struct AvalancheFinalityEvidence: Codable, Equatable {
    var setID: Int
    var targetHash: String
    var targetHeight: Int
    var signatures: [AvalancheFinalitySignature]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case setID = "set_id"
        case targetHash = "target_hash"
        case targetHeight = "target_height"
        case signatures
        case source
    }

    nonisolated init(
        setID: Int,
        targetHash: String,
        targetHeight: Int,
        signatures: [AvalancheFinalitySignature],
        source: String? = nil
    ) {
        self.setID = setID
        self.targetHash = AvalancheHex.normalized(targetHash)
        self.targetHeight = targetHeight
        self.signatures = signatures
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.setID = try container.decode(Int.self, forKey: .setID)
        self.targetHash = AvalancheHex.normalized(try container.decode(String.self, forKey: .targetHash))
        self.targetHeight = try container.decode(Int.self, forKey: .targetHeight)
        self.signatures = try container.decode([AvalancheFinalitySignature].self, forKey: .signatures)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    static func canonicalVote(setID: Int, targetHeight: Int, blockHash: String) -> Data {
        let normalizedHash = AvalancheHex.normalized(blockHash)
        return Data("avalanche-snowman-accepted-v1|\(setID)|\(targetHeight)|\(normalizedHash)".utf8)
    }

    func verifiedValidatorIDs(validators: [AvalancheValidator]) -> Set<String> {
        let publicKeysByID = Dictionary(
            uniqueKeysWithValues: validators.compactMap { validator -> (String, String)? in
                guard let publicKey = validator.publicKey else {
                    return nil
                }
                return (AvalancheHex.normalizedID(validator.nodeID), publicKey)
            }
        )
        let normalizedTarget = AvalancheHex.normalized(targetHash)
        var verified = Set<String>()

        for signature in signatures where signature.signed {
            let validatorID = AvalancheHex.normalizedID(signature.nodeID)
            guard
                AvalancheHex.normalized(signature.blockHash) == normalizedTarget,
                let publicKey = publicKeysByID[validatorID]
            else {
                continue
            }

            let message = Self.canonicalVote(
                setID: setID,
                targetHeight: targetHeight,
                blockHash: signature.blockHash
            )
            if Ed25519QuorumVerifier.isValidSignature(
                signatureBase64: signature.signature,
                publicKeyHex: publicKey,
                message: message
            ) {
                verified.insert(validatorID)
            }
        }

        return verified
    }
}

struct AvalancheStateVerificationBundle: Codable, Equatable {
    var acceptedBlock: AvalancheAcceptedBlockSnapshot
    var validatorSet: AvalancheValidatorSet
    var finalityEvidence: AvalancheFinalityEvidence
    var evmProof: EVMLocalProofBundle?
    var conflictingEvidence: AvalancheFinalityEvidence?

    private enum CodingKeys: String, CodingKey {
        case acceptedBlock = "accepted_block"
        case validatorSet = "validator_set"
        case finalityEvidence = "finality_evidence"
        case evmProof = "evm_proof"
        case conflictingEvidence = "conflicting_evidence"
    }

    nonisolated init(
        acceptedBlock: AvalancheAcceptedBlockSnapshot,
        validatorSet: AvalancheValidatorSet,
        finalityEvidence: AvalancheFinalityEvidence,
        evmProof: EVMLocalProofBundle? = nil,
        conflictingEvidence: AvalancheFinalityEvidence? = nil
    ) {
        self.acceptedBlock = acceptedBlock
        self.validatorSet = validatorSet
        self.finalityEvidence = finalityEvidence
        self.evmProof = evmProof
        self.conflictingEvidence = conflictingEvidence
    }

    func verify() -> AvalancheProofVerificationResult {
        guard acceptedBlock.network == validatorSet.network else {
            return failure("Avalanche accepted block network does not match the validator set.")
        }
        guard acceptedBlock.accepted else {
            return failure("Avalanche block is not marked accepted by Snowman finality evidence.")
        }
        guard finalityEvidence.setID == validatorSet.setID else {
            return failure("Avalanche finality evidence uses a different validator set.")
        }
        guard finalityEvidence.targetHeight == acceptedBlock.height,
              AvalancheHex.normalized(finalityEvidence.targetHash) == AvalancheHex.normalized(acceptedBlock.blockHash) else {
            return failure("Avalanche finality evidence targets a different accepted block.")
        }
        guard validatorSet.validatesHash else {
            return failure("Avalanche validator set hash is invalid.")
        }
        if let conflictingEvidence,
           conflictingEvidence.targetHeight == finalityEvidence.targetHeight,
           AvalancheHex.normalized(conflictingEvidence.targetHash) != AvalancheHex.normalized(finalityEvidence.targetHash),
           validatorSet.hasAcceptedQuorum(validatorIDs: conflictingEvidence.verifiedValidatorIDs(validators: validatorSet.validators)) {
            return failure("Conflicting Avalanche accepted-block evidence reached validator quorum.")
        }
        guard validatorSet.hasAcceptedQuorum(validatorIDs: finalityEvidence.verifiedValidatorIDs(validators: validatorSet.validators)) else {
            return failure("Avalanche accepted-finality evidence did not reach the validator-weight quorum.")
        }

        if let evmProof {
            guard let executionHeader = acceptedBlock.executionHeader else {
                return failure("Avalanche network does not expose a supported C-Chain EVM proof bridge.")
            }
            guard evmProof.header.chain == .avalancheCChain,
                  evmProof.header.chain == executionHeader.chain else {
                return failure("C-Chain EVM proof must be Avalanche-specific and must not use Ethereum mainnet finality.")
            }
            guard evmProof.header.number == acceptedBlock.height,
                  AvalancheHex.normalized(evmProof.header.hash) == AvalancheHex.normalized(acceptedBlock.blockHash),
                  AvalancheHex.normalized(evmProof.header.stateRoot) == AvalancheHex.normalized(acceptedBlock.stateRoot),
                  AvalancheHex.normalized(evmProof.header.receiptsRoot) == AvalancheHex.normalized(acceptedBlock.receiptsRoot) else {
                return failure("C-Chain EVM proof header is not bound to the accepted Avalanche block.")
            }
            let evmResult = evmProof.verify()
            guard evmResult.verified else {
                return failure(evmResult.summary)
            }
        }

        return AvalancheProofVerificationResult(
            verified: true,
            state: .proofChecked,
            chainRef: acceptedBlock.network.chainRef,
            blockNumber: acceptedBlock.height,
            blockHash: acceptedBlock.blockHash,
            proofID: evmProof?.proof.proofID,
            summary: evmProof == nil
                ? "Avalanche Snowman accepted block \(acceptedBlock.height) checked with Ed25519 validator quorum."
                : "Avalanche Snowman accepted block \(acceptedBlock.height) checked with C-Chain EVM proof evidence."
        )
    }

    private func failure(_ summary: String) -> AvalancheProofVerificationResult {
        AvalancheProofVerificationResult(
            verified: false,
            state: .failed,
            chainRef: acceptedBlock.network.chainRef,
            blockNumber: acceptedBlock.height,
            blockHash: acceptedBlock.blockHash,
            proofID: evmProof?.proof.proofID,
            summary: summary
        )
    }
}

struct AvalancheProofVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: AvalancheLightClientSyncState
    var chainRef: String
    var blockNumber: Int?
    var blockHash: String?
    var proofID: String?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case chainRef = "chain_ref"
        case blockNumber = "block_number"
        case blockHash = "block_hash"
        case proofID = "proof_id"
        case summary
    }
}

struct AvalancheLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var network: AvalancheNetwork
    var syncState: AvalancheLightClientSyncState
    var source: String
    var finalityModel: AvalancheFinalityModel
    var acceptedBlock: AvalancheAcceptedBlockSnapshot?
    var validatorSet: AvalancheValidatorSet?
    var peerCount: Int?
    var proofSource: String?
    var limitations: [String]
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case serviceAvailable = "service_available"
        case network
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case syncState = "sync_state"
        case source
        case finalityModel = "finality_model"
        case acceptedBlock = "accepted_block"
        case validatorSet = "validator_set"
        case peerCount = "peer_count"
        case proofSource = "proof_source"
        case limitations
        case lastError = "last_error"
    }

    nonisolated init(
        serviceAvailable: Bool,
        network: AvalancheNetwork,
        syncState: AvalancheLightClientSyncState,
        source: String,
        finalityModel: AvalancheFinalityModel? = nil,
        acceptedBlock: AvalancheAcceptedBlockSnapshot? = nil,
        validatorSet: AvalancheValidatorSet? = nil,
        peerCount: Int? = nil,
        proofSource: String? = nil,
        limitations: [String]? = nil,
        lastError: String? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.network = network
        self.syncState = syncState
        self.source = source
        self.finalityModel = finalityModel ?? .snowmanAccepted
        self.acceptedBlock = acceptedBlock
        self.validatorSet = validatorSet
        self.peerCount = peerCount
        self.proofSource = proofSource
        self.limitations = limitations ?? network.limitations
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? true
        if let network = try container.decodeIfPresent(AvalancheNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = AvalancheNetwork.known(from: chainRef) {
            self.network = network
        } else if let chainID = try container.decodeIfPresent(Int.self, forKey: .chainID),
                  let network = AvalancheNetwork.known(from: String(chainID)) {
            self.network = network
        } else {
            self.network = .cChain
        }
        self.syncState = try container.decodeIfPresent(AvalancheLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "avalanche-light-client"
        self.finalityModel = try container.decodeIfPresent(AvalancheFinalityModel.self, forKey: .finalityModel) ?? .snowmanAccepted
        self.acceptedBlock = try container.decodeIfPresent(AvalancheAcceptedBlockSnapshot.self, forKey: .acceptedBlock)
        self.validatorSet = try container.decodeIfPresent(AvalancheValidatorSet.self, forKey: .validatorSet)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.proofSource = try container.decodeIfPresent(String.self, forKey: .proofSource)
        self.limitations = try container.decodeIfPresent([String].self, forKey: .limitations) ?? network.limitations
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceAvailable, forKey: .serviceAvailable)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(network.chainID, forKey: .chainID)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(source, forKey: .source)
        try container.encode(finalityModel, forKey: .finalityModel)
        try container.encodeIfPresent(acceptedBlock, forKey: .acceptedBlock)
        try container.encodeIfPresent(validatorSet, forKey: .validatorSet)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(proofSource, forKey: .proofSource)
        try container.encode(limitations, forKey: .limitations)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    static func fallback(network: AvalancheNetwork, lastError: String?) -> AvalancheLightClientServiceSnapshot {
        AvalancheLightClientServiceSnapshot(
            serviceAvailable: false,
            network: network,
            syncState: .unavailable,
            source: "gateway-rpc-fallback",
            finalityModel: .rpcFallback,
            limitations: network.limitations,
            lastError: lastError
        )
    }

    var statusSummary: String {
        switch syncState {
        case .synced:
            return "\(network.displayName) Snowman accepted-finality verifier is synced at block \(acceptedBlock?.height.description ?? "unknown")."
        case .proofChecked:
            return "\(network.displayName) Snowman accepted-finality and C-Chain EVM proof evidence are locally checked; this is distinct from Ethereum mainnet finality."
        case .syncing:
            return "\(network.displayName) Avalanche light-client evidence is syncing."
        case .stale:
            return "\(network.displayName) accepted-block evidence is stale."
        case .failed:
            return "\(network.displayName) Avalanche verification failed: \(lastError ?? "unknown error")."
        case .rpcFallback, .unavailable:
            return "\(network.displayName) light-client service is unavailable; Gateway/RPC fallback remains labeled."
        }
    }

    var chainTrustStatus: ChainTrustStatus {
        let state = syncState.chainTrustState
        let evidence: [ChainTrustEvidence] = state.isProductionEvidence ? [
            ChainTrustEvidence(
                id: "\(network.chainRef)-avalanche-\(acceptedBlock?.height ?? 0)",
                source: state == .verified ? .embeddedLightClient : .localProof,
                summary: statusSummary,
                blockNumber: acceptedBlock?.height,
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
            chainID: network.chainRef,
            chainRef: network.chainRef,
            displayName: network.displayName,
            family: .avalanche,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: network.supportedProofTypes,
            latestCheckpoint: acceptedBlock?.checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

/// Trust boundary (goal: minimize remote trust). A client for a remote light-client/RPC service.
/// Accepted-finality checks verify Ed25519 validator quorum evidence, but the evidence is still
/// fixture/service-sourced and does not yet replace a production AvalancheGo light client.
final class AvalancheLightClientServiceClient {
    private let configuration: AvalancheLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: AvalancheLightClientEndpointConfiguration = .disabled,
        session: URLSession = AvalancheLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> AvalancheLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(network: configuration.network, lastError: "Avalanche light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/avalanche/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/avalanche/status")
            } catch {
                return .fallback(network: configuration.network, lastError: error.localizedDescription)
            }
        }
    }

    func verifyState(_ bundle: AvalancheStateVerificationBundle) -> AvalancheProofVerificationResult {
        bundle.verify()
    }

    func verifyStateViaService(_ bundle: AvalancheStateVerificationBundle) async throws -> AvalancheProofVerificationResult {
        do {
            return try await post(path: "/v1/avalanche/verify-state", body: bundle)
        } catch {
            return try await post(path: "/avalanche/verify-state", body: bundle)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> AvalancheLightClientServiceSnapshot {
        var snapshot: AvalancheLightClientServiceSnapshot = try await get(path: path)
        if snapshot.network != configuration.network {
            snapshot.network = configuration.network
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
            queryItems: [URLQueryItem(name: "network", value: configuration.network.chainRef)]
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

enum AvalancheHex {
    nonisolated static func normalized(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("0x") {
            normalized.removeFirst(2)
        }
        return normalized
    }

    nonisolated static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func sha256Hex(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).map { String(format: "%02x", $0) }.joined()
    }
}
