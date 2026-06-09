import CryptoKit
import Foundation

enum TronNetwork: String, Codable, Equatable, CaseIterable {
    case mainnet = "tron-mainnet"
    case nile = "tron-nile"
    case shasta = "tron-shasta"
    case localnet = "tron-localnet"

    nonisolated var chainRef: String {
        rawValue
    }

    nonisolated var networkID: String {
        switch self {
        case .mainnet: "mainnet"
        case .nile: "nile"
        case .shasta: "shasta"
        case .localnet: "localnet"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .mainnet: "TRON"
        case .nile: "TRON Nile"
        case .shasta: "TRON Shasta"
        case .localnet: "TRON Localnet"
        }
    }

    nonisolated var supportedProofTypes: [String] {
        ["solid-block", "witness-quorum", "account-proof", "trc20-state-proof", "transaction-receipt"]
    }

    nonisolated var limitations: [String] {
        switch self {
        case .mainnet:
            return ["Fixture-backed witness quorum checks do not yet replace a production TRON full-node light client."]
        case .nile, .shasta:
            return ["TRON testnet routes are modeled for explicit fallback and fixture checks only."]
        case .localnet:
            return ["Local TRON routes require a caller-provided witness set and block source."]
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let network = Self.known(from: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown TRON network: \(value)")
        }
        self = network
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(chainRef)
    }

    nonisolated static func known(from value: String) -> TronNetwork? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "tron", "mainnet", "tron-mainnet":
            return .mainnet
        case "nile", "tron-nile":
            return .nile
        case "shasta", "tron-shasta":
            return .shasta
        case "localnet", "tron-localnet", "local":
            return .localnet
        default:
            return nil
        }
    }
}

enum TronLightClientSyncState: String, Codable, Equatable, CaseIterable {
    case unavailable
    case syncing
    case synced
    case proofChecked = "proof_checked"
    case apiFallback = "api_fallback"
    case stale
    case failed

    nonisolated var chainTrustState: ChainTrustState {
        switch self {
        case .unavailable, .apiFallback:
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

struct TronLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var network: TronNetwork

    nonisolated static let local = TronLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        network: .mainnet
    )

    nonisolated static let disabled = TronLightClientEndpointConfiguration(
        baseURL: nil,
        network: .mainnet
    )
}

struct TronBlockHeaderSnapshot: Codable, Equatable, Identifiable {
    var id: String { blockID }

    var network: TronNetwork
    var number: Int
    var blockID: String
    var parentHash: String
    var witnessAddress: String
    var timestamp: UInt64
    var accountStateRoot: String
    var receiptRoot: String
    var solid: Bool
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case network
        case chainRef = "chain_ref"
        case number
        case blockID = "block_id"
        case parentHash = "parent_hash"
        case witnessAddress = "witness_address"
        case timestamp
        case accountStateRoot = "account_state_root"
        case receiptRoot = "receipt_root"
        case solid
        case source
    }

    nonisolated init(
        network: TronNetwork,
        number: Int,
        blockID: String,
        parentHash: String,
        witnessAddress: String,
        timestamp: UInt64,
        accountStateRoot: String,
        receiptRoot: String,
        solid: Bool,
        source: String? = nil
    ) {
        self.network = network
        self.number = number
        self.blockID = TronHex.normalized(blockID)
        self.parentHash = TronHex.normalized(parentHash)
        self.witnessAddress = TronHex.normalizedAddress(witnessAddress)
        self.timestamp = timestamp
        self.accountStateRoot = TronHex.normalized(accountStateRoot)
        self.receiptRoot = TronHex.normalized(receiptRoot)
        self.solid = solid
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let network = try container.decodeIfPresent(TronNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = TronNetwork.known(from: chainRef) {
            self.network = network
        } else {
            self.network = .mainnet
        }
        self.number = try container.decode(Int.self, forKey: .number)
        self.blockID = TronHex.normalized(try container.decode(String.self, forKey: .blockID))
        self.parentHash = TronHex.normalized(try container.decode(String.self, forKey: .parentHash))
        self.witnessAddress = TronHex.normalizedAddress(try container.decode(String.self, forKey: .witnessAddress))
        self.timestamp = try container.decode(UInt64.self, forKey: .timestamp)
        self.accountStateRoot = TronHex.normalized(try container.decode(String.self, forKey: .accountStateRoot))
        self.receiptRoot = TronHex.normalized(try container.decode(String.self, forKey: .receiptRoot))
        self.solid = try container.decodeIfPresent(Bool.self, forKey: .solid) ?? false
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(number, forKey: .number)
        try container.encode(blockID, forKey: .blockID)
        try container.encode(parentHash, forKey: .parentHash)
        try container.encode(witnessAddress, forKey: .witnessAddress)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(accountStateRoot, forKey: .accountStateRoot)
        try container.encode(receiptRoot, forKey: .receiptRoot)
        try container.encode(solid, forKey: .solid)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: number,
            blockHash: blockID,
            checkpointID: "\(network.chainRef)-solid-\(number)",
            updatedAt: Date(timeIntervalSince1970: TimeInterval(timestamp))
        )
    }

    func expectedRoot(for kind: TronLocalProofKind) -> String {
        switch kind {
        case .account, .token:
            return accountStateRoot
        case .receipt:
            return receiptRoot
        }
    }
}

struct TronWitness: Codable, Equatable, Identifiable {
    var id: String { address }

    var address: String
    var weight: Int
    var name: String?

    private enum CodingKeys: String, CodingKey {
        case address
        case weight
        case name
    }

    nonisolated init(address: String, weight: Int, name: String? = nil) {
        self.address = TronHex.normalizedAddress(address)
        self.weight = weight
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.address = TronHex.normalizedAddress(try container.decode(String.self, forKey: .address))
        self.weight = try container.decode(Int.self, forKey: .weight)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct TronWitnessSet: Codable, Equatable, Identifiable {
    var id: String { "\(network.chainRef)-witness-\(epoch)" }

    var network: TronNetwork
    var epoch: Int
    var witnesses: [TronWitness]
    var hash: String
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case network
        case chainRef = "chain_ref"
        case epoch
        case witnesses
        case hash
        case source
    }

    nonisolated init(
        network: TronNetwork,
        epoch: Int,
        witnesses: [TronWitness],
        hash: String? = nil,
        source: String? = nil
    ) {
        self.network = network
        self.epoch = epoch
        self.witnesses = witnesses
        self.hash = TronHex.normalized(hash ?? Self.computeHash(witnesses: witnesses))
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let network = try container.decodeIfPresent(TronNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = TronNetwork.known(from: chainRef) {
            self.network = network
        } else {
            self.network = .mainnet
        }
        self.epoch = try container.decode(Int.self, forKey: .epoch)
        self.witnesses = try container.decode([TronWitness].self, forKey: .witnesses)
        self.hash = TronHex.normalized(try container.decodeIfPresent(String.self, forKey: .hash) ?? Self.computeHash(witnesses: witnesses))
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(epoch, forKey: .epoch)
        try container.encode(witnesses, forKey: .witnesses)
        try container.encode(hash, forKey: .hash)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var totalWeight: Int {
        witnesses.reduce(0) { $0 + max(0, $1.weight) }
    }

    var validatesHash: Bool {
        hash == Self.computeHash(witnesses: witnesses)
    }

    func signedWeight(addresses: Set<String>) -> Int {
        witnesses.reduce(0) { partial, witness in
            addresses.contains(TronHex.normalizedAddress(witness.address)) ? partial + max(0, witness.weight) : partial
        }
    }

    func hasQuorum(addresses: Set<String>) -> Bool {
        let total = totalWeight
        guard total > 0 else { return false }
        if total >= 27 {
            return signedWeight(addresses: addresses) >= 19
        }
        return signedWeight(addresses: addresses) * 3 > total * 2
    }

    nonisolated static func computeHash(witnesses: [TronWitness]) -> String {
        let payload = witnesses
            .map { "\(TronHex.normalizedAddress($0.address)):\($0.weight)" }
            .sorted()
            .joined(separator: "|")
        return TronHex.sha256Hex(payload)
    }
}

struct TronFinalitySignature: Codable, Equatable, Identifiable {
    var id: String { witnessAddress }

    var witnessAddress: String
    var blockID: String
    var signed: Bool
    var signature: String?
    /// The witness's Ed25519 public key (hex), required for real signature verification.
    var publicKey: String?

    private enum CodingKeys: String, CodingKey {
        case witnessAddress = "witness_address"
        case blockID = "block_id"
        case signed
        case signature
        case publicKey = "public_key"
    }

    nonisolated init(
        witnessAddress: String,
        blockID: String,
        signed: Bool = true,
        signature: String? = nil,
        publicKey: String? = nil
    ) {
        self.witnessAddress = TronHex.normalizedAddress(witnessAddress)
        self.blockID = TronHex.normalized(blockID)
        self.signed = signed
        self.signature = signature
        self.publicKey = publicKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.witnessAddress = TronHex.normalizedAddress(try container.decode(String.self, forKey: .witnessAddress))
        self.blockID = TronHex.normalized(try container.decode(String.self, forKey: .blockID))
        self.signed = try container.decodeIfPresent(Bool.self, forKey: .signed) ?? true
        self.signature = try container.decodeIfPresent(String.self, forKey: .signature)
        self.publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)
    }
}

struct TronFinalityProof: Codable, Equatable {
    var epoch: Int
    var targetBlockID: String
    var targetNumber: Int
    var signatures: [TronFinalitySignature]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case epoch
        case targetBlockID = "target_block_id"
        case targetNumber = "target_number"
        case signatures
        case source
    }

    nonisolated init(
        epoch: Int,
        targetBlockID: String,
        targetNumber: Int,
        signatures: [TronFinalitySignature],
        source: String? = nil
    ) {
        self.epoch = epoch
        self.targetBlockID = TronHex.normalized(targetBlockID)
        self.targetNumber = targetNumber
        self.signatures = signatures
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.epoch = try container.decode(Int.self, forKey: .epoch)
        self.targetBlockID = TronHex.normalized(try container.decode(String.self, forKey: .targetBlockID))
        self.targetNumber = try container.decode(Int.self, forKey: .targetNumber)
        self.signatures = try container.decode([TronFinalitySignature].self, forKey: .signatures)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    var signedWitnessAddresses: Set<String> {
        Set(signatures.filter(\.signed).map { TronHex.normalizedAddress($0.witnessAddress) })
    }

    static func canonicalVote(epoch: Int, blockID: String) -> Data {
        Data("tron-finality|\(epoch)|\(TronHex.normalized(blockID))".utf8)
    }

    /// Witness addresses whose Ed25519 signature cryptographically verifies; a `signed` flag
    /// without a verifiable signature does not count toward the quorum.
    var verifiedWitnessAddresses: Set<String> {
        var verified = Set<String>()
        for signature in signatures where signature.signed {
            guard let publicKey = signature.publicKey else { continue }
            let message = Self.canonicalVote(epoch: epoch, blockID: signature.blockID)
            if Ed25519QuorumVerifier.isValidSignature(signatureBase64: signature.signature, publicKeyHex: publicKey, message: message) {
                verified.insert(TronHex.normalizedAddress(signature.witnessAddress))
            }
        }
        return verified
    }
}

enum TronLocalProofKind: String, Codable, Equatable, CaseIterable {
    case account
    case token
    case receipt
}

enum TronProofWitnessPosition: String, Codable, Equatable {
    case left
    case right
}

struct TronProofWitness: Codable, Equatable {
    var hash: String
    var position: TronProofWitnessPosition

    nonisolated init(hash: String, position: TronProofWitnessPosition) {
        self.hash = TronHex.normalized(hash)
        self.position = position
    }
}

struct TronLocalProof: Codable, Equatable, Identifiable {
    var id: String { proofID }

    var proofID: String
    var kind: TronLocalProofKind
    var network: TronNetwork
    var subject: String
    var tokenID: String?
    var expectedValueHash: String
    var blockID: String
    var blockNumber: Int
    var expectedRoot: String
    var leafHash: String
    var witnesses: [TronProofWitness]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case proofID = "proof_id"
        case kind
        case network
        case chainRef = "chain_ref"
        case subject
        case tokenID = "token_id"
        case expectedValueHash = "expected_value_hash"
        case blockID = "block_id"
        case blockNumber = "block_number"
        case expectedRoot = "expected_root"
        case leafHash = "leaf_hash"
        case witnesses
        case source
    }

    nonisolated init(
        proofID: String,
        kind: TronLocalProofKind,
        network: TronNetwork,
        subject: String,
        tokenID: String? = nil,
        expectedValueHash: String,
        blockID: String,
        blockNumber: Int,
        expectedRoot: String,
        leafHash: String,
        witnesses: [TronProofWitness],
        source: String? = nil
    ) {
        self.proofID = proofID
        self.kind = kind
        self.network = network
        self.subject = subject
        self.tokenID = tokenID
        self.expectedValueHash = TronHex.normalized(expectedValueHash)
        self.blockID = TronHex.normalized(blockID)
        self.blockNumber = blockNumber
        self.expectedRoot = TronHex.normalized(expectedRoot)
        self.leafHash = TronHex.normalized(leafHash)
        self.witnesses = witnesses
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.proofID = try container.decodeIfPresent(String.self, forKey: .proofID) ?? UUID().uuidString
        self.kind = try container.decode(TronLocalProofKind.self, forKey: .kind)
        if let network = try container.decodeIfPresent(TronNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = TronNetwork.known(from: chainRef) {
            self.network = network
        } else {
            self.network = .mainnet
        }
        self.subject = try container.decode(String.self, forKey: .subject)
        self.tokenID = try container.decodeIfPresent(String.self, forKey: .tokenID)
        self.expectedValueHash = TronHex.normalized(try container.decode(String.self, forKey: .expectedValueHash))
        self.blockID = TronHex.normalized(try container.decode(String.self, forKey: .blockID))
        self.blockNumber = try container.decode(Int.self, forKey: .blockNumber)
        self.expectedRoot = TronHex.normalized(try container.decode(String.self, forKey: .expectedRoot))
        self.leafHash = TronHex.normalized(try container.decode(String.self, forKey: .leafHash))
        self.witnesses = try container.decodeIfPresent([TronProofWitness].self, forKey: .witnesses) ?? []
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proofID, forKey: .proofID)
        try container.encode(kind, forKey: .kind)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(subject, forKey: .subject)
        try container.encodeIfPresent(tokenID, forKey: .tokenID)
        try container.encode(expectedValueHash, forKey: .expectedValueHash)
        try container.encode(blockID, forKey: .blockID)
        try container.encode(blockNumber, forKey: .blockNumber)
        try container.encode(expectedRoot, forKey: .expectedRoot)
        try container.encode(leafHash, forKey: .leafHash)
        try container.encode(witnesses, forKey: .witnesses)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var computedRoot: String? {
        Self.computeRoot(leafHash: leafHash, witnesses: witnesses)
    }

    nonisolated static func computeRoot(leafHash: String, witnesses: [TronProofWitness]) -> String? {
        guard var node = TronHex.data(from: leafHash) else { return nil }
        for witness in witnesses {
            guard let sibling = TronHex.data(from: witness.hash) else { return nil }
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
        return TronHex.hex(from: node)
    }

    nonisolated static func fixtureLeafHash(kind: TronLocalProofKind, subject: String, tokenID: String? = nil, valueHash: String) -> String {
        TronHex.sha256Hex([
            kind.rawValue,
            subject.lowercased(),
            tokenID?.lowercased() ?? "",
            TronHex.normalized(valueHash)
        ].joined(separator: "|"))
    }
}

struct TronProofVerificationBundle: Codable, Equatable {
    var header: TronBlockHeaderSnapshot
    var witnessSet: TronWitnessSet
    var finalityProof: TronFinalityProof
    var proof: TronLocalProof?

    private enum CodingKeys: String, CodingKey {
        case header
        case witnessSet = "witness_set"
        case finalityProof = "finality_proof"
        case proof
    }

    nonisolated init(
        header: TronBlockHeaderSnapshot,
        witnessSet: TronWitnessSet,
        finalityProof: TronFinalityProof,
        proof: TronLocalProof? = nil
    ) {
        self.header = header
        self.witnessSet = witnessSet
        self.finalityProof = finalityProof
        self.proof = proof
    }

    func verify() -> TronProofVerificationResult {
        guard header.network == witnessSet.network else {
            return failure("TRON block network does not match witness set.")
        }
        guard header.solid else {
            return failure("TRON block is not marked solid; API/RPC data must remain fallback-labeled.")
        }
        guard finalityProof.epoch == witnessSet.epoch else {
            return failure("TRON finality proof uses a different witness epoch.")
        }
        guard finalityProof.targetNumber == header.number,
              TronHex.normalized(finalityProof.targetBlockID) == TronHex.normalized(header.blockID) else {
            return failure("TRON finality proof targets a different solid block.")
        }
        guard witnessSet.validatesHash else {
            return failure("TRON witness set hash is invalid.")
        }
        guard witnessSet.hasQuorum(addresses: finalityProof.verifiedWitnessAddresses) else {
            return failure("TRON finality proof did not reach the witness quorum.")
        }
        if let proof {
            guard proof.network == header.network,
                  TronHex.normalized(proof.blockID) == TronHex.normalized(header.blockID),
                  proof.blockNumber == header.number else {
                return failure("TRON proof references a different network or block.")
            }
            guard TronHex.normalized(proof.expectedRoot) == header.expectedRoot(for: proof.kind) else {
                return failure("TRON \(proof.kind.rawValue) proof expected root does not match the solid block root.")
            }
            guard proof.computedRoot == TronHex.normalized(proof.expectedRoot) else {
                return failure("TRON \(proof.kind.rawValue) proof did not resolve to the expected root.")
            }
        }

        return TronProofVerificationResult(
            verified: true,
            state: .proofChecked,
            chainRef: header.network.chainRef,
            blockNumber: header.number,
            blockID: header.blockID,
            proofID: proof?.proofID,
            kind: proof?.kind,
            summary: proof == nil
                ? "TRON solid block \(header.number) checked with fixture witness quorum."
                : "TRON \(proof?.kind.rawValue ?? "state") proof checked against solid block \(header.number)."
        )
    }

    private func failure(_ summary: String) -> TronProofVerificationResult {
        TronProofVerificationResult(
            verified: false,
            state: .failed,
            chainRef: header.network.chainRef,
            blockNumber: header.number,
            blockID: header.blockID,
            proofID: proof?.proofID,
            kind: proof?.kind,
            summary: summary
        )
    }
}

struct TronProofVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: TronLightClientSyncState
    var chainRef: String
    var blockNumber: Int?
    var blockID: String?
    var proofID: String?
    var kind: TronLocalProofKind?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case chainRef = "chain_ref"
        case blockNumber = "block_number"
        case blockID = "block_id"
        case proofID = "proof_id"
        case kind
        case summary
    }
}

struct TronLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var network: TronNetwork
    var syncState: TronLightClientSyncState
    var source: String
    var latestSolidBlock: TronBlockHeaderSnapshot?
    var witnessSet: TronWitnessSet?
    var peerCount: Int?
    var proofSource: String?
    var stale: Bool
    var limitations: [String]
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case serviceAvailable = "service_available"
        case network
        case chainRef = "chain_ref"
        case syncState = "sync_state"
        case source
        case latestSolidBlock = "latest_solid_block"
        case witnessSet = "witness_set"
        case peerCount = "peer_count"
        case proofSource = "proof_source"
        case stale
        case limitations
        case lastError = "last_error"
    }

    nonisolated init(
        serviceAvailable: Bool,
        network: TronNetwork,
        syncState: TronLightClientSyncState,
        source: String,
        latestSolidBlock: TronBlockHeaderSnapshot? = nil,
        witnessSet: TronWitnessSet? = nil,
        peerCount: Int? = nil,
        proofSource: String? = nil,
        stale: Bool = false,
        limitations: [String]? = nil,
        lastError: String? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.network = network
        self.syncState = syncState
        self.source = source
        self.latestSolidBlock = latestSolidBlock
        self.witnessSet = witnessSet
        self.peerCount = peerCount
        self.proofSource = proofSource
        self.stale = stale
        self.limitations = limitations ?? network.limitations
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? true
        if let network = try container.decodeIfPresent(TronNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = TronNetwork.known(from: chainRef) {
            self.network = network
        } else {
            self.network = .mainnet
        }
        self.syncState = try container.decodeIfPresent(TronLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "tron-light-client"
        self.latestSolidBlock = try container.decodeIfPresent(TronBlockHeaderSnapshot.self, forKey: .latestSolidBlock)
        self.witnessSet = try container.decodeIfPresent(TronWitnessSet.self, forKey: .witnessSet)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.proofSource = try container.decodeIfPresent(String.self, forKey: .proofSource)
        self.stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        self.limitations = try container.decodeIfPresent([String].self, forKey: .limitations) ?? network.limitations
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        if stale && self.syncState == .proofChecked {
            self.syncState = .stale
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceAvailable, forKey: .serviceAvailable)
        try container.encode(serviceAvailable, forKey: .ok)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(latestSolidBlock, forKey: .latestSolidBlock)
        try container.encodeIfPresent(witnessSet, forKey: .witnessSet)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(proofSource, forKey: .proofSource)
        try container.encode(stale, forKey: .stale)
        try container.encode(limitations, forKey: .limitations)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    static func fallback(network: TronNetwork, lastError: String?) -> TronLightClientServiceSnapshot {
        TronLightClientServiceSnapshot(
            serviceAvailable: false,
            network: network,
            syncState: .unavailable,
            source: "api-rpc-fallback",
            limitations: network.limitations,
            lastError: lastError
        )
    }

    var statusSummary: String {
        switch syncState {
        case .synced:
            return "\(network.displayName) solid-block witness verifier is synced at block \(latestSolidBlock?.number.description ?? "unknown")."
        case .proofChecked:
            return "\(network.displayName) witness quorum and proof evidence are locally checked; production TRON light-client verification is not claimed."
        case .syncing:
            return "\(network.displayName) TRON chain evidence is syncing."
        case .stale:
            return "\(network.displayName) solid-block evidence is stale; API/RPC fallback remains labeled."
        case .failed:
            return "\(network.displayName) verification failed: \(lastError ?? "unknown error")."
        case .apiFallback, .unavailable:
            return "\(network.displayName) light-client service is unavailable; API/RPC fallback remains labeled."
        }
    }

    var chainTrustStatus: ChainTrustStatus {
        let state = syncState.chainTrustState
        let evidence: [ChainTrustEvidence] = state.isProductionEvidence ? [
            ChainTrustEvidence(
                id: "\(network.chainRef)-tron-\(latestSolidBlock?.number ?? 0)",
                source: state == .verified ? .embeddedLightClient : .localProof,
                summary: statusSummary,
                blockNumber: latestSolidBlock?.number,
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
            family: .tron,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: network.supportedProofTypes,
            latestCheckpoint: latestSolidBlock?.checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

/// Trust boundary (goal: minimize remote trust). A client for a remote light-client/RPC service.
/// Witness-quorum checks are fixture-backed and do not yet replace a production TRON full-node
/// light client; live state is served via RPC fallback (`.rpcFallback`), not local verification.
final class TronLightClientServiceClient {
    private let configuration: TronLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: TronLightClientEndpointConfiguration = .disabled,
        session: URLSession = TronLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> TronLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(network: configuration.network, lastError: "TRON light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/tron/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/tron/status")
            } catch {
                return .fallback(network: configuration.network, lastError: error.localizedDescription)
            }
        }
    }

    func verifyProof(_ bundle: TronProofVerificationBundle) -> TronProofVerificationResult {
        bundle.verify()
    }

    func verifyProofViaService(_ bundle: TronProofVerificationBundle) async throws -> TronProofVerificationResult {
        do {
            return try await post(path: "/v1/tron/verify-proof", body: bundle)
        } catch {
            return try await post(path: "/tron/verify-proof", body: bundle)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> TronLightClientServiceSnapshot {
        var snapshot: TronLightClientServiceSnapshot = try await get(path: path)
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

enum TronHex {
    nonisolated static func normalized(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("0x") {
            normalized.removeFirst(2)
        }
        return normalized
    }

    nonisolated static func normalizedAddress(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
