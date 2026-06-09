import CryptoKit
import Foundation

enum SubstrateChain: String, Codable, Equatable, CaseIterable {
    case polkadot
    case kusama
    case westend
    case assetHubPolkadot = "asset-hub-polkadot"
    case localnet = "substrate-localnet"

    nonisolated var chainSpecID: String {
        switch self {
        case .polkadot: "polkadot"
        case .kusama: "kusama"
        case .westend: "westend"
        case .assetHubPolkadot: "asset-hub-polkadot"
        case .localnet: "substrate-localnet"
        }
    }

    nonisolated var chainRef: String {
        switch self {
        case .polkadot: "polkadot"
        case .kusama: "kusama"
        case .westend: "westend"
        case .assetHubPolkadot: "asset-hub-polkadot"
        case .localnet: "substrate-localnet"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .polkadot: "Polkadot"
        case .kusama: "Kusama"
        case .westend: "Westend"
        case .assetHubPolkadot: "Asset Hub Polkadot"
        case .localnet: "Substrate Localnet"
        }
    }

    nonisolated var relayChain: SubstrateChain? {
        switch self {
        case .assetHubPolkadot: .polkadot
        case .polkadot, .kusama, .westend, .localnet: nil
        }
    }

    nonisolated var ss58Prefix: Int {
        switch self {
        case .polkadot, .assetHubPolkadot: 0
        case .kusama: 2
        case .westend: 42
        case .localnet: 42
        }
    }

    nonisolated var supportedProofTypes: [String] {
        ["grandpa-finality", "authority-set", "storage-proof", "chain-spec"]
    }

    nonisolated static func known(from value: String) -> SubstrateChain? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "polkadot", "dot", "polkadot-relay":
            return .polkadot
        case "kusama", "ksm":
            return .kusama
        case "westend":
            return .westend
        case "asset-hub-polkadot", "statemint", "polkadot-asset-hub":
            return .assetHubPolkadot
        case "substrate-localnet", "localnet":
            return .localnet
        default:
            return nil
        }
    }
}

enum SubstrateLightClientSyncState: String, Codable, Equatable, CaseIterable {
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

struct SubstrateLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var chain: SubstrateChain

    nonisolated static let local = SubstrateLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        chain: .polkadot
    )

    nonisolated static let disabled = SubstrateLightClientEndpointConfiguration(
        baseURL: nil,
        chain: .polkadot
    )
}

struct SubstrateHeaderSnapshot: Codable, Equatable, Identifiable {
    var id: String { "\(chain.chainRef)-\(number)" }

    var chain: SubstrateChain
    var number: Int
    var hash: String
    var parentHash: String
    var stateRoot: String
    var extrinsicsRoot: String
    var digestLogs: [String]
    var finalized: Bool
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case chain
        case chainRef = "chain_ref"
        case chainSpecID = "chain_spec_id"
        case number
        case hash
        case parentHash = "parent_hash"
        case stateRoot = "state_root"
        case extrinsicsRoot = "extrinsics_root"
        case digestLogs = "digest_logs"
        case finalized
        case source
    }

    nonisolated init(
        chain: SubstrateChain,
        number: Int,
        hash: String,
        parentHash: String,
        stateRoot: String,
        extrinsicsRoot: String,
        digestLogs: [String] = [],
        finalized: Bool,
        source: String? = nil
    ) {
        self.chain = chain
        self.number = number
        self.hash = SubstrateHex.normalized(hash)
        self.parentHash = SubstrateHex.normalized(parentHash)
        self.stateRoot = SubstrateHex.normalized(stateRoot)
        self.extrinsicsRoot = SubstrateHex.normalized(extrinsicsRoot)
        self.digestLogs = digestLogs
        self.finalized = finalized
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let chain = try container.decodeIfPresent(SubstrateChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = SubstrateChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainSpecID = try container.decodeIfPresent(String.self, forKey: .chainSpecID),
                  let chain = SubstrateChain.known(from: chainSpecID) {
            self.chain = chain
        } else {
            self.chain = .polkadot
        }
        self.number = try container.decode(Int.self, forKey: .number)
        self.hash = SubstrateHex.normalized(try container.decode(String.self, forKey: .hash))
        self.parentHash = SubstrateHex.normalized(try container.decode(String.self, forKey: .parentHash))
        self.stateRoot = SubstrateHex.normalized(try container.decode(String.self, forKey: .stateRoot))
        self.extrinsicsRoot = SubstrateHex.normalized(try container.decode(String.self, forKey: .extrinsicsRoot))
        self.digestLogs = try container.decodeIfPresent([String].self, forKey: .digestLogs) ?? []
        self.finalized = try container.decodeIfPresent(Bool.self, forKey: .finalized) ?? false
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainSpecID, forKey: .chainSpecID)
        try container.encode(number, forKey: .number)
        try container.encode(hash, forKey: .hash)
        try container.encode(parentHash, forKey: .parentHash)
        try container.encode(stateRoot, forKey: .stateRoot)
        try container.encode(extrinsicsRoot, forKey: .extrinsicsRoot)
        try container.encode(digestLogs, forKey: .digestLogs)
        try container.encode(finalized, forKey: .finalized)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: number,
            blockHash: hash,
            checkpointID: "\(chain.chainRef)-finalized-\(number)",
            updatedAt: Date()
        )
    }
}

struct GRANDPAAuthority: Codable, Equatable, Identifiable {
    var id: String { authorityID }

    var authorityID: String
    var weight: Int

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case weight
    }

    nonisolated init(authorityID: String, weight: Int) {
        self.authorityID = SubstrateHex.normalized(authorityID)
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.authorityID = SubstrateHex.normalized(try container.decode(String.self, forKey: .authorityID))
        self.weight = try container.decode(Int.self, forKey: .weight)
    }
}

struct GRANDPAAuthoritySet: Codable, Equatable, Identifiable {
    var id: String { "\(chain.chainRef)-grandpa-\(setID)" }

    var chain: SubstrateChain
    var setID: Int
    var authorities: [GRANDPAAuthority]
    var hash: String
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case chain
        case chainRef = "chain_ref"
        case chainSpecID = "chain_spec_id"
        case setID = "set_id"
        case authorities
        case hash
        case source
    }

    nonisolated init(
        chain: SubstrateChain,
        setID: Int,
        authorities: [GRANDPAAuthority],
        hash: String? = nil,
        source: String? = nil
    ) {
        self.chain = chain
        self.setID = setID
        self.authorities = authorities
        self.hash = SubstrateHex.normalized(hash ?? Self.computeHash(authorities: authorities))
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let chain = try container.decodeIfPresent(SubstrateChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = SubstrateChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainSpecID = try container.decodeIfPresent(String.self, forKey: .chainSpecID),
                  let chain = SubstrateChain.known(from: chainSpecID) {
            self.chain = chain
        } else {
            self.chain = .polkadot
        }
        self.setID = try container.decode(Int.self, forKey: .setID)
        self.authorities = try container.decode([GRANDPAAuthority].self, forKey: .authorities)
        self.hash = SubstrateHex.normalized(try container.decodeIfPresent(String.self, forKey: .hash) ?? Self.computeHash(authorities: authorities))
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainSpecID, forKey: .chainSpecID)
        try container.encode(setID, forKey: .setID)
        try container.encode(authorities, forKey: .authorities)
        try container.encode(hash, forKey: .hash)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var totalWeight: Int {
        authorities.reduce(0) { $0 + max(0, $1.weight) }
    }

    var validatesHash: Bool {
        hash == Self.computeHash(authorities: authorities)
    }

    func signedWeight(authorityIDs: Set<String>) -> Int {
        authorities.reduce(0) { partial, authority in
            authorityIDs.contains(SubstrateHex.normalized(authority.authorityID)) ? partial + max(0, authority.weight) : partial
        }
    }

    func hasTwoThirdsWeight(authorityIDs: Set<String>) -> Bool {
        signedWeight(authorityIDs: authorityIDs) * 3 > totalWeight * 2
    }

    nonisolated static func computeHash(authorities: [GRANDPAAuthority]) -> String {
        let payload = authorities
            .map { "\(SubstrateHex.normalized($0.authorityID)):\($0.weight)" }
            .sorted()
            .joined(separator: "|")
        return SubstrateHex.sha256Hex(payload)
    }
}

struct GRANDPAJustificationSignature: Codable, Equatable, Identifiable {
    var id: String { authorityID }

    var authorityID: String
    var blockHash: String
    var signed: Bool
    var signature: String?

    private enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case blockHash = "block_hash"
        case signed
        case signature
    }

    nonisolated init(
        authorityID: String,
        blockHash: String,
        signed: Bool = true,
        signature: String? = nil
    ) {
        self.authorityID = SubstrateHex.normalized(authorityID)
        self.blockHash = SubstrateHex.normalized(blockHash)
        self.signed = signed
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.authorityID = SubstrateHex.normalized(try container.decode(String.self, forKey: .authorityID))
        self.blockHash = SubstrateHex.normalized(try container.decode(String.self, forKey: .blockHash))
        self.signed = try container.decodeIfPresent(Bool.self, forKey: .signed) ?? true
        self.signature = try container.decodeIfPresent(String.self, forKey: .signature)
    }
}

struct GRANDPAFinalityJustification: Codable, Equatable {
    var round: Int
    var setID: Int
    var targetHash: String
    var targetNumber: Int
    var signatures: [GRANDPAJustificationSignature]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case round
        case setID = "set_id"
        case targetHash = "target_hash"
        case targetNumber = "target_number"
        case signatures
        case source
    }

    nonisolated init(
        round: Int,
        setID: Int,
        targetHash: String,
        targetNumber: Int,
        signatures: [GRANDPAJustificationSignature],
        source: String? = nil
    ) {
        self.round = round
        self.setID = setID
        self.targetHash = SubstrateHex.normalized(targetHash)
        self.targetNumber = targetNumber
        self.signatures = signatures
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.round = try container.decodeIfPresent(Int.self, forKey: .round) ?? 0
        self.setID = try container.decode(Int.self, forKey: .setID)
        self.targetHash = SubstrateHex.normalized(try container.decode(String.self, forKey: .targetHash))
        self.targetNumber = try container.decode(Int.self, forKey: .targetNumber)
        self.signatures = try container.decode([GRANDPAJustificationSignature].self, forKey: .signatures)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    var signedAuthorityIDs: Set<String> {
        Set(signatures.filter(\.signed).map { SubstrateHex.normalized($0.authorityID) })
    }

    /// Canonical GRANDPA vote bytes both signer and verifier agree on (dBrowser encoding pending
    /// exact SCALE-encoded GRANDPA message alignment).
    static func canonicalVote(setID: Int, round: Int, blockHash: String) -> Data {
        Data("grandpa-vote|\(setID)|\(round)|\(SubstrateHex.normalized(blockHash))".utf8)
    }

    /// Authority IDs whose Ed25519 signature cryptographically verifies (the authority ID is the
    /// Ed25519 public key). A `signed` flag without a verifiable signature does not count.
    var verifiedAuthorityIDs: Set<String> {
        var verified = Set<String>()
        for signature in signatures where signature.signed {
            let message = Self.canonicalVote(setID: setID, round: round, blockHash: signature.blockHash)
            if Ed25519QuorumVerifier.isValidSignature(
                signatureBase64: signature.signature,
                publicKeyHex: signature.authorityID,
                message: message
            ) {
                verified.insert(SubstrateHex.normalized(signature.authorityID))
            }
        }
        return verified
    }
}

enum SubstrateProofWitnessPosition: String, Codable, Equatable {
    case left
    case right
}

struct SubstrateProofWitness: Codable, Equatable {
    var hash: String
    var position: SubstrateProofWitnessPosition

    nonisolated init(hash: String, position: SubstrateProofWitnessPosition) {
        self.hash = SubstrateHex.normalized(hash)
        self.position = position
    }
}

struct SubstrateStorageProof: Codable, Equatable, Identifiable {
    var id: String { proofID }

    var proofID: String
    var chain: SubstrateChain
    var blockHash: String
    var storageKey: String
    var expectedValueHash: String
    var leafHash: String
    var witnesses: [SubstrateProofWitness]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case proofID = "proof_id"
        case chain
        case chainRef = "chain_ref"
        case chainSpecID = "chain_spec_id"
        case blockHash = "block_hash"
        case storageKey = "storage_key"
        case expectedValueHash = "expected_value_hash"
        case leafHash = "leaf_hash"
        case witnesses
        case source
    }

    nonisolated init(
        proofID: String,
        chain: SubstrateChain,
        blockHash: String,
        storageKey: String,
        expectedValueHash: String,
        leafHash: String,
        witnesses: [SubstrateProofWitness],
        source: String? = nil
    ) {
        self.proofID = proofID
        self.chain = chain
        self.blockHash = SubstrateHex.normalized(blockHash)
        self.storageKey = storageKey
        self.expectedValueHash = SubstrateHex.normalized(expectedValueHash)
        self.leafHash = SubstrateHex.normalized(leafHash)
        self.witnesses = witnesses
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.proofID = try container.decodeIfPresent(String.self, forKey: .proofID) ?? UUID().uuidString
        if let chain = try container.decodeIfPresent(SubstrateChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = SubstrateChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainSpecID = try container.decodeIfPresent(String.self, forKey: .chainSpecID),
                  let chain = SubstrateChain.known(from: chainSpecID) {
            self.chain = chain
        } else {
            self.chain = .polkadot
        }
        self.blockHash = SubstrateHex.normalized(try container.decode(String.self, forKey: .blockHash))
        self.storageKey = try container.decode(String.self, forKey: .storageKey)
        self.expectedValueHash = SubstrateHex.normalized(try container.decode(String.self, forKey: .expectedValueHash))
        self.leafHash = SubstrateHex.normalized(try container.decode(String.self, forKey: .leafHash))
        self.witnesses = try container.decodeIfPresent([SubstrateProofWitness].self, forKey: .witnesses) ?? []
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proofID, forKey: .proofID)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainSpecID, forKey: .chainSpecID)
        try container.encode(blockHash, forKey: .blockHash)
        try container.encode(storageKey, forKey: .storageKey)
        try container.encode(expectedValueHash, forKey: .expectedValueHash)
        try container.encode(leafHash, forKey: .leafHash)
        try container.encode(witnesses, forKey: .witnesses)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var computedRoot: String? {
        Self.computeRoot(leafHash: leafHash, witnesses: witnesses)
    }

    nonisolated static func computeRoot(leafHash: String, witnesses: [SubstrateProofWitness]) -> String? {
        guard var node = SubstrateHex.data(from: leafHash) else { return nil }
        for witness in witnesses {
            guard let sibling = SubstrateHex.data(from: witness.hash) else { return nil }
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
        return SubstrateHex.hex(from: node)
    }

    nonisolated static func fixtureLeafHash(storageKey: String, valueHash: String) -> String {
        SubstrateHex.sha256Hex([storageKey.lowercased(), SubstrateHex.normalized(valueHash)].joined(separator: "|"))
    }
}

struct SubstrateProofVerificationBundle: Codable, Equatable {
    var header: SubstrateHeaderSnapshot
    var authoritySet: GRANDPAAuthoritySet
    var justification: GRANDPAFinalityJustification
    var storageProof: SubstrateStorageProof?
    var conflictingJustification: GRANDPAFinalityJustification?

    private enum CodingKeys: String, CodingKey {
        case header
        case authoritySet = "authority_set"
        case justification
        case storageProof = "storage_proof"
        case conflictingJustification = "conflicting_justification"
    }

    func verify() -> SubstrateProofVerificationResult {
        guard header.chain == authoritySet.chain else {
            return failure("Substrate header chain does not match the GRANDPA authority set.")
        }
        guard justification.setID == authoritySet.setID else {
            return failure("GRANDPA justification uses a different authority set.")
        }
        guard justification.targetNumber == header.number,
              SubstrateHex.normalized(justification.targetHash) == SubstrateHex.normalized(header.hash) else {
            return failure("GRANDPA justification targets a different finalized header.")
        }
        guard authoritySet.validatesHash else {
            return failure("GRANDPA authority set hash is invalid.")
        }
        if let conflictingJustification,
           conflictingJustification.targetNumber == justification.targetNumber,
           SubstrateHex.normalized(conflictingJustification.targetHash) != SubstrateHex.normalized(justification.targetHash),
           authoritySet.hasTwoThirdsWeight(authorityIDs: conflictingJustification.verifiedAuthorityIDs) {
            return failure("Conflicting GRANDPA justifications both reached the authority threshold.")
        }
        guard authoritySet.hasTwoThirdsWeight(authorityIDs: justification.verifiedAuthorityIDs) else {
            return failure("GRANDPA justification did not reach the two-thirds authority threshold.")
        }
        if let storageProof {
            guard storageProof.chain == header.chain,
                  SubstrateHex.normalized(storageProof.blockHash) == SubstrateHex.normalized(header.hash) else {
                return failure("Substrate storage proof references a different chain or block.")
            }
            guard storageProof.computedRoot == SubstrateHex.normalized(header.stateRoot) else {
                return failure("Substrate storage proof did not resolve to the finalized state root.")
            }
        }

        return SubstrateProofVerificationResult(
            verified: true,
            state: header.finalized ? .synced : .proofChecked,
            chainRef: header.chain.chainRef,
            chainSpecID: header.chain.chainSpecID,
            blockNumber: header.number,
            blockHash: header.hash,
            proofID: storageProof?.proofID,
            storageKey: storageProof?.storageKey,
            summary: storageProof == nil
                ? "GRANDPA finalized header \(header.number) verified."
                : "Substrate storage proof checked against finalized header \(header.number)."
        )
    }

    private func failure(_ summary: String) -> SubstrateProofVerificationResult {
        SubstrateProofVerificationResult(
            verified: false,
            state: .failed,
            chainRef: header.chain.chainRef,
            chainSpecID: header.chain.chainSpecID,
            blockNumber: header.number,
            blockHash: header.hash,
            proofID: storageProof?.proofID,
            storageKey: storageProof?.storageKey,
            summary: summary
        )
    }
}

struct SubstrateProofVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: SubstrateLightClientSyncState
    var chainRef: String
    var chainSpecID: String
    var blockNumber: Int?
    var blockHash: String?
    var proofID: String?
    var storageKey: String?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case chainRef = "chain_ref"
        case chainSpecID = "chain_spec_id"
        case blockNumber = "block_number"
        case blockHash = "block_hash"
        case proofID = "proof_id"
        case storageKey = "storage_key"
        case summary
    }
}

struct SubstrateLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var chain: SubstrateChain
    var syncState: SubstrateLightClientSyncState
    var source: String
    var latestFinalizedHeader: SubstrateHeaderSnapshot?
    var authoritySet: GRANDPAAuthoritySet?
    var peerCount: Int?
    var proofSource: String?
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case serviceAvailable = "service_available"
        case chain
        case chainRef = "chain_ref"
        case chainSpecID = "chain_spec_id"
        case syncState = "sync_state"
        case source
        case latestFinalizedHeader = "latest_finalized_header"
        case authoritySet = "authority_set"
        case peerCount = "peer_count"
        case proofSource = "proof_source"
        case lastError = "last_error"
    }

    nonisolated init(
        serviceAvailable: Bool,
        chain: SubstrateChain,
        syncState: SubstrateLightClientSyncState,
        source: String,
        latestFinalizedHeader: SubstrateHeaderSnapshot? = nil,
        authoritySet: GRANDPAAuthoritySet? = nil,
        peerCount: Int? = nil,
        proofSource: String? = nil,
        lastError: String? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.chain = chain
        self.syncState = syncState
        self.source = source
        self.latestFinalizedHeader = latestFinalizedHeader
        self.authoritySet = authoritySet
        self.peerCount = peerCount
        self.proofSource = proofSource
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? true
        if let chain = try container.decodeIfPresent(SubstrateChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = SubstrateChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainSpecID = try container.decodeIfPresent(String.self, forKey: .chainSpecID),
                  let chain = SubstrateChain.known(from: chainSpecID) {
            self.chain = chain
        } else {
            self.chain = .polkadot
        }
        self.syncState = try container.decodeIfPresent(SubstrateLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "substrate-light-client"
        self.latestFinalizedHeader = try container.decodeIfPresent(SubstrateHeaderSnapshot.self, forKey: .latestFinalizedHeader)
        self.authoritySet = try container.decodeIfPresent(GRANDPAAuthoritySet.self, forKey: .authoritySet)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.proofSource = try container.decodeIfPresent(String.self, forKey: .proofSource)
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceAvailable, forKey: .serviceAvailable)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainSpecID, forKey: .chainSpecID)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(latestFinalizedHeader, forKey: .latestFinalizedHeader)
        try container.encodeIfPresent(authoritySet, forKey: .authoritySet)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(proofSource, forKey: .proofSource)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    static func fallback(chain: SubstrateChain, lastError: String?) -> SubstrateLightClientServiceSnapshot {
        SubstrateLightClientServiceSnapshot(
            serviceAvailable: false,
            chain: chain,
            syncState: .unavailable,
            source: "trusted-rpc-fallback",
            lastError: lastError
        )
    }

    var statusSummary: String {
        switch syncState {
        case .synced:
            return "\(chain.displayName) GRANDPA finalized header \(latestFinalizedHeader?.number.description ?? "unknown") is locally verified."
        case .proofChecked:
            return "\(chain.displayName) storage proof evidence is locally checked; production Substrate verification is not claimed."
        case .syncing:
            return "\(chain.displayName) Substrate light-client evidence is syncing."
        case .stale:
            return "\(chain.displayName) Substrate finalized state is stale."
        case .failed:
            return "\(chain.displayName) Substrate verification failed: \(lastError ?? "unknown error")."
        case .rpcFallback, .unavailable:
            return "\(chain.displayName) light-client service is unavailable; trusted RPC fallback remains labeled."
        }
    }

    var chainTrustStatus: ChainTrustStatus {
        let state = syncState.chainTrustState
        let evidence: [ChainTrustEvidence] = state.isProductionEvidence ? [
            ChainTrustEvidence(
                id: "\(chain.chainRef)-substrate-\(latestFinalizedHeader?.number ?? 0)",
                source: state == .verified ? .embeddedLightClient : .localProof,
                summary: statusSummary,
                blockNumber: latestFinalizedHeader?.number,
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
            family: .polkadotSubstrate,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: chain.supportedProofTypes,
            latestCheckpoint: latestFinalizedHeader?.checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

/// Trust boundary (goal: minimize remote trust). A client for a remote light-client/RPC service.
/// It models GRANDPA finality justifications (with conflicting-justification handling) but also
/// uses fixture leaf hashes, and serves state via RPC fallback (`.rpcFallback`) by default rather
/// than local verification. Target: real GRANDPA + storage-proof checks that remove the fallback.
final class SubstrateLightClientServiceClient {
    private let configuration: SubstrateLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: SubstrateLightClientEndpointConfiguration = .disabled,
        session: URLSession = SubstrateLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> SubstrateLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(chain: configuration.chain, lastError: "Polkadot/Substrate light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/substrate/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/substrate/status")
            } catch {
                return .fallback(chain: configuration.chain, lastError: error.localizedDescription)
            }
        }
    }

    func verifyStorageProof(_ bundle: SubstrateProofVerificationBundle) -> SubstrateProofVerificationResult {
        bundle.verify()
    }

    func verifyStorageProofViaService(_ bundle: SubstrateProofVerificationBundle) async throws -> SubstrateProofVerificationResult {
        do {
            return try await post(path: "/v1/substrate/verify-storage-proof", body: bundle)
        } catch {
            return try await post(path: "/substrate/verify-storage-proof", body: bundle)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> SubstrateLightClientServiceSnapshot {
        var snapshot: SubstrateLightClientServiceSnapshot = try await get(path: path)
        if snapshot.chain != configuration.chain {
            snapshot.chain = configuration.chain
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
            queryItems: [URLQueryItem(name: "chain", value: configuration.chain.chainSpecID)]
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

enum SubstrateHex {
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
