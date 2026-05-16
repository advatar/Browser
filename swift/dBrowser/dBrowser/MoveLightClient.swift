import CryptoKit
import Foundation

enum MoveChainKind: String, Codable, Equatable, CaseIterable {
    case sui
    case aptos
}

enum MoveChain: String, Codable, Equatable, CaseIterable {
    case suiMainnet = "sui-mainnet"
    case suiTestnet = "sui-testnet"
    case suiDevnet = "sui-devnet"
    case suiLocalnet = "sui-localnet"
    case aptosMainnet = "aptos-mainnet"
    case aptosTestnet = "aptos-testnet"
    case aptosDevnet = "aptos-devnet"
    case aptosLocalnet = "aptos-localnet"

    nonisolated var chainRef: String {
        rawValue
    }

    nonisolated var chainID: String {
        switch self {
        case .suiMainnet: "sui-mainnet"
        case .suiTestnet: "sui-testnet"
        case .suiDevnet: "sui-devnet"
        case .suiLocalnet: "sui-localnet"
        case .aptosMainnet: "aptos-mainnet"
        case .aptosTestnet: "aptos-testnet"
        case .aptosDevnet: "aptos-devnet"
        case .aptosLocalnet: "aptos-localnet"
        }
    }

    nonisolated var kind: MoveChainKind {
        switch self {
        case .suiMainnet, .suiTestnet, .suiDevnet, .suiLocalnet:
            return .sui
        case .aptosMainnet, .aptosTestnet, .aptosDevnet, .aptosLocalnet:
            return .aptos
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .suiMainnet: "Sui"
        case .suiTestnet: "Sui Testnet"
        case .suiDevnet: "Sui Devnet"
        case .suiLocalnet: "Sui Localnet"
        case .aptosMainnet: "Aptos"
        case .aptosTestnet: "Aptos Testnet"
        case .aptosDevnet: "Aptos Devnet"
        case .aptosLocalnet: "Aptos Localnet"
        }
    }

    nonisolated var supportedProofTypes: [String] {
        switch kind {
        case .sui:
            return ["checkpoint-committee-quorum", "object-state-proof", "transaction-effects-proof"]
        case .aptos:
            return ["ledger-info-validator-quorum", "account-state-proof", "transaction-proof"]
        }
    }

    nonisolated var limitations: [String] {
        switch self {
        case .suiMainnet:
            return ["Fixture-backed Sui checkpoint quorum checks do not yet replace a production Sui light client."]
        case .suiTestnet, .suiDevnet:
            return ["Sui non-mainnet routes are modeled for explicit fallback and fixture checks only."]
        case .suiLocalnet:
            return ["Local Sui routes require caller-provided committee and checkpoint evidence."]
        case .aptosMainnet:
            return ["Fixture-backed Aptos ledger-info quorum checks do not yet replace a production Aptos light client."]
        case .aptosTestnet, .aptosDevnet:
            return ["Aptos non-mainnet routes are modeled for explicit fallback and fixture checks only."]
        case .aptosLocalnet:
            return ["Local Aptos routes require caller-provided validator and ledger-info evidence."]
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let chain = Self.known(from: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown Move chain: \(value)")
        }
        self = chain
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(chainRef)
    }

    nonisolated static func known(from value: String) -> MoveChain? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "sui", "sui-mainnet", "mainnet-sui":
            return .suiMainnet
        case "sui-testnet", "testnet-sui":
            return .suiTestnet
        case "sui-devnet", "devnet-sui":
            return .suiDevnet
        case "sui-localnet", "local-sui":
            return .suiLocalnet
        case "aptos", "aptos-mainnet", "mainnet-aptos":
            return .aptosMainnet
        case "aptos-testnet", "testnet-aptos":
            return .aptosTestnet
        case "aptos-devnet", "devnet-aptos":
            return .aptosDevnet
        case "aptos-localnet", "local-aptos":
            return .aptosLocalnet
        default:
            return nil
        }
    }
}

enum MoveLightClientSyncState: String, Codable, Equatable, CaseIterable {
    case unavailable
    case syncing
    case checkpointed
    case verified
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
        case .checkpointed, .verified:
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

struct MoveLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var chain: MoveChain

    nonisolated static let localSui = MoveLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        chain: .suiMainnet
    )

    nonisolated static let localAptos = MoveLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        chain: .aptosMainnet
    )

    nonisolated static func disabled(chain: MoveChain = .suiMainnet) -> MoveLightClientEndpointConfiguration {
        MoveLightClientEndpointConfiguration(baseURL: nil, chain: chain)
    }
}

struct MoveCheckpointSnapshot: Codable, Equatable, Identifiable {
    var id: String { digest }

    var chain: MoveChain
    var sequenceNumber: Int
    var epoch: Int
    var digest: String
    var previousDigest: String
    var stateRoot: String
    var transactionEffectsRoot: String
    var timestamp: UInt64
    var finalized: Bool
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case chain
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case sequenceNumber = "sequence_number"
        case ledgerVersion = "ledger_version"
        case version
        case epoch
        case digest
        case ledgerInfoHash = "ledger_info_hash"
        case previousDigest = "previous_digest"
        case stateRoot = "state_root"
        case transactionEffectsRoot = "transaction_effects_root"
        case transactionAccumulatorRoot = "transaction_accumulator_root"
        case timestamp
        case finalized
        case source
    }

    nonisolated init(
        chain: MoveChain,
        sequenceNumber: Int,
        epoch: Int,
        digest: String,
        previousDigest: String,
        stateRoot: String,
        transactionEffectsRoot: String,
        timestamp: UInt64,
        finalized: Bool,
        source: String? = nil
    ) {
        self.chain = chain
        self.sequenceNumber = sequenceNumber
        self.epoch = epoch
        self.digest = MoveHash.normalized(digest)
        self.previousDigest = MoveHash.normalized(previousDigest)
        self.stateRoot = MoveHash.normalized(stateRoot)
        self.transactionEffectsRoot = MoveHash.normalized(transactionEffectsRoot)
        self.timestamp = timestamp
        self.finalized = finalized
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let chain = try container.decodeIfPresent(MoveChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = MoveChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainID = try container.decodeIfPresent(String.self, forKey: .chainID),
                  let chain = MoveChain.known(from: chainID) {
            self.chain = chain
        } else {
            self.chain = .suiMainnet
        }
        self.sequenceNumber = try container.decodeIfPresent(Int.self, forKey: .sequenceNumber)
            ?? container.decodeIfPresent(Int.self, forKey: .ledgerVersion)
            ?? container.decodeIfPresent(Int.self, forKey: .version)
            ?? 0
        self.epoch = try container.decodeIfPresent(Int.self, forKey: .epoch) ?? 0
        self.digest = MoveHash.normalized(
            try container.decodeIfPresent(String.self, forKey: .digest)
                ?? container.decode(String.self, forKey: .ledgerInfoHash)
        )
        self.previousDigest = MoveHash.normalized(try container.decodeIfPresent(String.self, forKey: .previousDigest) ?? "")
        self.stateRoot = MoveHash.normalized(try container.decode(String.self, forKey: .stateRoot))
        self.transactionEffectsRoot = MoveHash.normalized(
            try container.decodeIfPresent(String.self, forKey: .transactionEffectsRoot)
                ?? container.decode(String.self, forKey: .transactionAccumulatorRoot)
        )
        self.timestamp = try container.decodeIfPresent(UInt64.self, forKey: .timestamp) ?? 0
        self.finalized = try container.decodeIfPresent(Bool.self, forKey: .finalized) ?? false
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainID, forKey: .chainID)
        try container.encode(sequenceNumber, forKey: .sequenceNumber)
        try container.encode(epoch, forKey: .epoch)
        try container.encode(digest, forKey: .digest)
        try container.encode(previousDigest, forKey: .previousDigest)
        try container.encode(stateRoot, forKey: .stateRoot)
        try container.encode(transactionEffectsRoot, forKey: .transactionEffectsRoot)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(finalized, forKey: .finalized)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: sequenceNumber,
            blockHash: digest,
            checkpointID: "\(chain.chainRef)-checkpoint-\(sequenceNumber)",
            updatedAt: Date(timeIntervalSince1970: TimeInterval(timestamp))
        )
    }

    func expectedRoot(for kind: MoveLocalProofKind) -> String {
        switch kind {
        case .suiObject, .aptosAccount:
            return stateRoot
        case .suiTransactionEffects, .aptosTransaction:
            return transactionEffectsRoot
        }
    }
}

struct MoveValidator: Codable, Equatable, Identifiable {
    var id: String { validatorID }

    var validatorID: String
    var weight: Int
    var name: String?
    var disabled: Bool

    private enum CodingKeys: String, CodingKey {
        case validatorID = "validator_id"
        case weight
        case name
        case disabled
    }

    nonisolated init(
        validatorID: String,
        weight: Int,
        name: String? = nil,
        disabled: Bool = false
    ) {
        self.validatorID = MoveHash.normalizedID(validatorID)
        self.weight = weight
        self.name = name
        self.disabled = disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.validatorID = MoveHash.normalizedID(try container.decode(String.self, forKey: .validatorID))
        self.weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    }
}

struct MoveValidatorSet: Codable, Equatable, Identifiable {
    var id: String { "\(chain.chainRef)-validators-\(epoch)" }

    var chain: MoveChain
    var epoch: Int
    var validators: [MoveValidator]
    var quorumNumerator: Int
    var quorumDenominator: Int
    var hash: String
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case chain
        case chainRef = "chain_ref"
        case epoch
        case validators
        case quorumNumerator = "quorum_numerator"
        case quorumDenominator = "quorum_denominator"
        case hash
        case source
    }

    nonisolated init(
        chain: MoveChain,
        epoch: Int,
        validators: [MoveValidator],
        quorumNumerator: Int = 2,
        quorumDenominator: Int = 3,
        hash: String? = nil,
        source: String? = nil
    ) {
        self.chain = chain
        self.epoch = epoch
        self.validators = validators
        self.quorumNumerator = quorumNumerator
        self.quorumDenominator = quorumDenominator
        self.hash = MoveHash.normalized(hash ?? Self.computeHash(validators: validators))
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let chain = try container.decodeIfPresent(MoveChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = MoveChain.known(from: chainRef) {
            self.chain = chain
        } else {
            self.chain = .suiMainnet
        }
        self.epoch = try container.decodeIfPresent(Int.self, forKey: .epoch) ?? 0
        self.validators = try container.decode([MoveValidator].self, forKey: .validators)
        self.quorumNumerator = try container.decodeIfPresent(Int.self, forKey: .quorumNumerator) ?? 2
        self.quorumDenominator = try container.decodeIfPresent(Int.self, forKey: .quorumDenominator) ?? 3
        self.hash = MoveHash.normalized(try container.decodeIfPresent(String.self, forKey: .hash) ?? Self.computeHash(validators: validators))
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(epoch, forKey: .epoch)
        try container.encode(validators, forKey: .validators)
        try container.encode(quorumNumerator, forKey: .quorumNumerator)
        try container.encode(quorumDenominator, forKey: .quorumDenominator)
        try container.encode(hash, forKey: .hash)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var configuredWeight: Int {
        validators.reduce(0) { $0 + max(0, $1.weight) }
    }

    var effectiveWeight: Int {
        validators.reduce(0) { partial, validator in
            validator.disabled ? partial : partial + max(0, validator.weight)
        }
    }

    var requiredQuorumWeight: Int {
        guard effectiveWeight > 0, quorumDenominator > 0 else { return 0 }
        return Self.ceilDivide(effectiveWeight * quorumNumerator, by: quorumDenominator)
    }

    var validatesHash: Bool {
        hash == Self.computeHash(validators: validators)
    }

    func signedWeight(validatorIDs: Set<String>) -> Int {
        validators.reduce(0) { partial, validator in
            !validator.disabled && validatorIDs.contains(MoveHash.normalizedID(validator.validatorID))
                ? partial + max(0, validator.weight)
                : partial
        }
    }

    func hasQuorum(validatorIDs: Set<String>) -> Bool {
        let required = requiredQuorumWeight
        guard required > 0 else { return false }
        return signedWeight(validatorIDs: validatorIDs) >= required
    }

    nonisolated static func computeHash(validators: [MoveValidator]) -> String {
        let payload = validators
            .map { "\(MoveHash.normalizedID($0.validatorID)):\($0.weight):\($0.disabled ? "disabled" : "active")" }
            .sorted()
            .joined(separator: "|")
        return MoveHash.sha256Hex(payload)
    }

    nonisolated private static func ceilDivide(_ value: Int, by denominator: Int) -> Int {
        guard denominator > 0 else { return 0 }
        return (value + denominator - 1) / denominator
    }
}

struct MoveValidatorSignature: Codable, Equatable, Identifiable {
    var id: String { validatorID }

    var validatorID: String
    var checkpointDigest: String
    var sequenceNumber: Int
    var signed: Bool
    var signature: String?

    private enum CodingKeys: String, CodingKey {
        case validatorID = "validator_id"
        case checkpointDigest = "checkpoint_digest"
        case ledgerInfoHash = "ledger_info_hash"
        case targetDigest = "target_digest"
        case sequenceNumber = "sequence_number"
        case ledgerVersion = "ledger_version"
        case signed
        case signature
    }

    nonisolated init(
        validatorID: String,
        checkpointDigest: String,
        sequenceNumber: Int,
        signed: Bool = true,
        signature: String? = nil
    ) {
        self.validatorID = MoveHash.normalizedID(validatorID)
        self.checkpointDigest = MoveHash.normalized(checkpointDigest)
        self.sequenceNumber = sequenceNumber
        self.signed = signed
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.validatorID = MoveHash.normalizedID(try container.decode(String.self, forKey: .validatorID))
        self.checkpointDigest = MoveHash.normalized(
            try container.decodeIfPresent(String.self, forKey: .checkpointDigest)
                ?? container.decodeIfPresent(String.self, forKey: .ledgerInfoHash)
                ?? container.decode(String.self, forKey: .targetDigest)
        )
        self.sequenceNumber = try container.decodeIfPresent(Int.self, forKey: .sequenceNumber)
            ?? container.decodeIfPresent(Int.self, forKey: .ledgerVersion)
            ?? 0
        self.signed = try container.decodeIfPresent(Bool.self, forKey: .signed) ?? true
        self.signature = try container.decodeIfPresent(String.self, forKey: .signature)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(validatorID, forKey: .validatorID)
        try container.encode(checkpointDigest, forKey: .checkpointDigest)
        try container.encode(sequenceNumber, forKey: .sequenceNumber)
        try container.encode(signed, forKey: .signed)
        try container.encodeIfPresent(signature, forKey: .signature)
    }
}

struct MoveFinalityProof: Codable, Equatable {
    var epoch: Int
    var targetDigest: String
    var targetSequenceNumber: Int
    var signatures: [MoveValidatorSignature]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case epoch
        case targetDigest = "target_digest"
        case targetSequenceNumber = "target_sequence_number"
        case signatures
        case source
    }

    nonisolated init(
        epoch: Int,
        targetDigest: String,
        targetSequenceNumber: Int,
        signatures: [MoveValidatorSignature],
        source: String? = nil
    ) {
        self.epoch = epoch
        self.targetDigest = MoveHash.normalized(targetDigest)
        self.targetSequenceNumber = targetSequenceNumber
        self.signatures = signatures
        self.source = source
    }

    func signedValidatorIDs(targetDigest: String, targetSequenceNumber: Int) -> Set<String> {
        let normalizedTarget = MoveHash.normalized(targetDigest)
        return Set(signatures.filter {
            $0.signed
                && $0.sequenceNumber == targetSequenceNumber
                && MoveHash.normalized($0.checkpointDigest) == normalizedTarget
        }.map { MoveHash.normalizedID($0.validatorID) })
    }
}

enum MoveLocalProofKind: String, Codable, Equatable, CaseIterable {
    case suiObject = "sui_object"
    case suiTransactionEffects = "sui_transaction_effects"
    case aptosAccount = "aptos_account"
    case aptosTransaction = "aptos_transaction"

    nonisolated var chainKind: MoveChainKind {
        switch self {
        case .suiObject, .suiTransactionEffects:
            return .sui
        case .aptosAccount, .aptosTransaction:
            return .aptos
        }
    }
}

enum MoveProofWitnessPosition: String, Codable, Equatable {
    case left
    case right
}

struct MoveProofWitness: Codable, Equatable {
    var hash: String
    var position: MoveProofWitnessPosition

    nonisolated init(hash: String, position: MoveProofWitnessPosition) {
        self.hash = MoveHash.normalized(hash)
        self.position = position
    }
}

struct MoveLocalProof: Codable, Equatable, Identifiable {
    var id: String { proofID }

    var proofID: String
    var kind: MoveLocalProofKind
    var chain: MoveChain
    var subject: String
    var objectID: String?
    var accountAddress: String?
    var transactionDigest: String?
    var expectedValueHash: String
    var checkpointDigest: String
    var sequenceNumber: Int
    var expectedRoot: String
    var leafHash: String
    var witnesses: [MoveProofWitness]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case proofID = "proof_id"
        case kind
        case chain
        case chainRef = "chain_ref"
        case subject
        case objectID = "object_id"
        case accountAddress = "account_address"
        case transactionDigest = "transaction_digest"
        case expectedValueHash = "expected_value_hash"
        case checkpointDigest = "checkpoint_digest"
        case ledgerInfoHash = "ledger_info_hash"
        case sequenceNumber = "sequence_number"
        case ledgerVersion = "ledger_version"
        case expectedRoot = "expected_root"
        case leafHash = "leaf_hash"
        case witnesses
        case source
    }

    nonisolated init(
        proofID: String,
        kind: MoveLocalProofKind,
        chain: MoveChain,
        subject: String,
        objectID: String? = nil,
        accountAddress: String? = nil,
        transactionDigest: String? = nil,
        expectedValueHash: String,
        checkpointDigest: String,
        sequenceNumber: Int,
        expectedRoot: String,
        leafHash: String,
        witnesses: [MoveProofWitness],
        source: String? = nil
    ) {
        self.proofID = proofID
        self.kind = kind
        self.chain = chain
        self.subject = subject
        self.objectID = objectID.map(MoveHash.normalizedID)
        self.accountAddress = accountAddress.map(MoveHash.normalizedID)
        self.transactionDigest = transactionDigest.map(MoveHash.normalized)
        self.expectedValueHash = MoveHash.normalized(expectedValueHash)
        self.checkpointDigest = MoveHash.normalized(checkpointDigest)
        self.sequenceNumber = sequenceNumber
        self.expectedRoot = MoveHash.normalized(expectedRoot)
        self.leafHash = MoveHash.normalized(leafHash)
        self.witnesses = witnesses
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.proofID = try container.decodeIfPresent(String.self, forKey: .proofID) ?? UUID().uuidString
        self.kind = try container.decode(MoveLocalProofKind.self, forKey: .kind)
        if let chain = try container.decodeIfPresent(MoveChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = MoveChain.known(from: chainRef) {
            self.chain = chain
        } else {
            self.chain = kind.chainKind == .sui ? .suiMainnet : .aptosMainnet
        }
        self.subject = try container.decode(String.self, forKey: .subject)
        self.objectID = try container.decodeIfPresent(String.self, forKey: .objectID).map(MoveHash.normalizedID)
        self.accountAddress = try container.decodeIfPresent(String.self, forKey: .accountAddress).map(MoveHash.normalizedID)
        self.transactionDigest = try container.decodeIfPresent(String.self, forKey: .transactionDigest).map(MoveHash.normalized)
        self.expectedValueHash = MoveHash.normalized(try container.decode(String.self, forKey: .expectedValueHash))
        self.checkpointDigest = MoveHash.normalized(
            try container.decodeIfPresent(String.self, forKey: .checkpointDigest)
                ?? container.decode(String.self, forKey: .ledgerInfoHash)
        )
        self.sequenceNumber = try container.decodeIfPresent(Int.self, forKey: .sequenceNumber)
            ?? container.decodeIfPresent(Int.self, forKey: .ledgerVersion)
            ?? 0
        self.expectedRoot = MoveHash.normalized(try container.decode(String.self, forKey: .expectedRoot))
        self.leafHash = MoveHash.normalized(try container.decode(String.self, forKey: .leafHash))
        self.witnesses = try container.decodeIfPresent([MoveProofWitness].self, forKey: .witnesses) ?? []
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proofID, forKey: .proofID)
        try container.encode(kind, forKey: .kind)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(subject, forKey: .subject)
        try container.encodeIfPresent(objectID, forKey: .objectID)
        try container.encodeIfPresent(accountAddress, forKey: .accountAddress)
        try container.encodeIfPresent(transactionDigest, forKey: .transactionDigest)
        try container.encode(expectedValueHash, forKey: .expectedValueHash)
        try container.encode(checkpointDigest, forKey: .checkpointDigest)
        try container.encode(sequenceNumber, forKey: .sequenceNumber)
        try container.encode(expectedRoot, forKey: .expectedRoot)
        try container.encode(leafHash, forKey: .leafHash)
        try container.encode(witnesses, forKey: .witnesses)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var computedRoot: String? {
        Self.computeRoot(leafHash: leafHash, witnesses: witnesses)
    }

    nonisolated static func computeRoot(leafHash: String, witnesses: [MoveProofWitness]) -> String? {
        guard var node = MoveHash.data(from: leafHash) else { return nil }
        for witness in witnesses {
            guard let sibling = MoveHash.data(from: witness.hash) else { return nil }
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
        return MoveHash.hex(from: node)
    }

    nonisolated static func fixtureLeafHash(
        kind: MoveLocalProofKind,
        subject: String,
        objectID: String? = nil,
        accountAddress: String? = nil,
        transactionDigest: String? = nil,
        valueHash: String
    ) -> String {
        MoveHash.sha256Hex([
            kind.rawValue,
            subject.lowercased(),
            objectID?.lowercased() ?? "",
            accountAddress?.lowercased() ?? "",
            transactionDigest.map(MoveHash.normalized) ?? "",
            MoveHash.normalized(valueHash)
        ].joined(separator: "|"))
    }
}

struct MoveProofVerificationBundle: Codable, Equatable {
    var checkpoint: MoveCheckpointSnapshot
    var validatorSet: MoveValidatorSet
    var finalityProof: MoveFinalityProof
    var proof: MoveLocalProof?

    private enum CodingKeys: String, CodingKey {
        case checkpoint
        case validatorSet = "validator_set"
        case finalityProof = "finality_proof"
        case proof
    }

    nonisolated init(
        checkpoint: MoveCheckpointSnapshot,
        validatorSet: MoveValidatorSet,
        finalityProof: MoveFinalityProof,
        proof: MoveLocalProof? = nil
    ) {
        self.checkpoint = checkpoint
        self.validatorSet = validatorSet
        self.finalityProof = finalityProof
        self.proof = proof
    }

    func verify() -> MoveProofVerificationResult {
        guard checkpoint.chain == validatorSet.chain else {
            return failure("Move checkpoint chain does not match validator set.")
        }
        guard checkpoint.finalized else {
            return failure("Move checkpoint or ledger info is not marked finalized; API/RPC data must remain fallback-labeled.")
        }
        guard finalityProof.epoch == validatorSet.epoch,
              finalityProof.targetSequenceNumber == checkpoint.sequenceNumber,
              MoveHash.normalized(finalityProof.targetDigest) == MoveHash.normalized(checkpoint.digest) else {
            return failure("Move finality proof targets a different checkpoint, ledger version, or epoch.")
        }
        guard validatorSet.validatesHash else {
            return failure("Move validator set hash is invalid.")
        }
        let signedValidators = finalityProof.signedValidatorIDs(
            targetDigest: checkpoint.digest,
            targetSequenceNumber: checkpoint.sequenceNumber
        )
        guard validatorSet.hasQuorum(validatorIDs: signedValidators) else {
            return failure("Move finality proof did not reach the validator quorum.")
        }
        if let proof {
            guard proof.kind.chainKind == checkpoint.chain.kind else {
                return failure("Move proof kind does not match the selected chain family.")
            }
            guard proof.chain == checkpoint.chain,
                  proof.sequenceNumber == checkpoint.sequenceNumber,
                  MoveHash.normalized(proof.checkpointDigest) == MoveHash.normalized(checkpoint.digest) else {
                return failure("Move proof references a different chain checkpoint or ledger info.")
            }
            guard MoveHash.normalized(proof.expectedRoot) == checkpoint.expectedRoot(for: proof.kind) else {
                return failure("Move \(proof.kind.rawValue) proof expected root does not match checkpoint roots.")
            }
            guard proof.computedRoot == MoveHash.normalized(proof.expectedRoot) else {
                return failure("Move \(proof.kind.rawValue) proof did not resolve to the expected root.")
            }
        }

        return MoveProofVerificationResult(
            verified: true,
            state: .proofChecked,
            chainRef: checkpoint.chain.chainRef,
            sequenceNumber: checkpoint.sequenceNumber,
            checkpointDigest: checkpoint.digest,
            proofID: proof?.proofID,
            kind: proof?.kind,
            summary: proof == nil
                ? "\(checkpoint.chain.displayName) checkpoint \(checkpoint.sequenceNumber) checked with fixture validator quorum."
                : "\(checkpoint.chain.displayName) \(proof?.kind.rawValue ?? "state") proof checked against checkpoint \(checkpoint.sequenceNumber)."
        )
    }

    private func failure(_ summary: String) -> MoveProofVerificationResult {
        MoveProofVerificationResult(
            verified: false,
            state: .failed,
            chainRef: checkpoint.chain.chainRef,
            sequenceNumber: checkpoint.sequenceNumber,
            checkpointDigest: checkpoint.digest,
            proofID: proof?.proofID,
            kind: proof?.kind,
            summary: summary
        )
    }
}

struct MoveProofVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: MoveLightClientSyncState
    var chainRef: String
    var sequenceNumber: Int?
    var checkpointDigest: String?
    var proofID: String?
    var kind: MoveLocalProofKind?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case chainRef = "chain_ref"
        case sequenceNumber = "sequence_number"
        case checkpointDigest = "checkpoint_digest"
        case proofID = "proof_id"
        case kind
        case summary
    }
}

struct MoveLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var chain: MoveChain
    var syncState: MoveLightClientSyncState
    var source: String
    var latestCheckpoint: MoveCheckpointSnapshot?
    var validatorSet: MoveValidatorSet?
    var peerCount: Int?
    var proofSource: String?
    var stale: Bool
    var limitations: [String]
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case serviceAvailable = "service_available"
        case chain
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case syncState = "sync_state"
        case source
        case latestCheckpoint = "latest_checkpoint"
        case latestLedger = "latest_ledger"
        case validatorSet = "validator_set"
        case peerCount = "peer_count"
        case proofSource = "proof_source"
        case stale
        case limitations
        case lastError = "last_error"
    }

    nonisolated init(
        serviceAvailable: Bool,
        chain: MoveChain,
        syncState: MoveLightClientSyncState,
        source: String,
        latestCheckpoint: MoveCheckpointSnapshot? = nil,
        validatorSet: MoveValidatorSet? = nil,
        peerCount: Int? = nil,
        proofSource: String? = nil,
        stale: Bool = false,
        limitations: [String]? = nil,
        lastError: String? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.chain = chain
        self.syncState = syncState
        self.source = source
        self.latestCheckpoint = latestCheckpoint
        self.validatorSet = validatorSet
        self.peerCount = peerCount
        self.proofSource = proofSource
        self.stale = stale
        self.limitations = limitations ?? chain.limitations
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? true
        if let chain = try container.decodeIfPresent(MoveChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = MoveChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainID = try container.decodeIfPresent(String.self, forKey: .chainID),
                  let chain = MoveChain.known(from: chainID) {
            self.chain = chain
        } else {
            self.chain = .suiMainnet
        }
        self.syncState = try container.decodeIfPresent(MoveLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "move-light-client"
        self.latestCheckpoint = try container.decodeIfPresent(MoveCheckpointSnapshot.self, forKey: .latestCheckpoint)
            ?? container.decodeIfPresent(MoveCheckpointSnapshot.self, forKey: .latestLedger)
        self.validatorSet = try container.decodeIfPresent(MoveValidatorSet.self, forKey: .validatorSet)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.proofSource = try container.decodeIfPresent(String.self, forKey: .proofSource)
        self.stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        self.limitations = try container.decodeIfPresent([String].self, forKey: .limitations) ?? chain.limitations
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        if stale && (self.syncState == .checkpointed || self.syncState == .verified || self.syncState == .proofChecked) {
            self.syncState = .stale
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceAvailable, forKey: .serviceAvailable)
        try container.encode(serviceAvailable, forKey: .ok)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainID, forKey: .chainID)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(latestCheckpoint, forKey: .latestCheckpoint)
        try container.encodeIfPresent(validatorSet, forKey: .validatorSet)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(proofSource, forKey: .proofSource)
        try container.encode(stale, forKey: .stale)
        try container.encode(limitations, forKey: .limitations)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    static func fallback(chain: MoveChain, lastError: String?) -> MoveLightClientServiceSnapshot {
        MoveLightClientServiceSnapshot(
            serviceAvailable: false,
            chain: chain,
            syncState: .unavailable,
            source: "api-rpc-fallback",
            limitations: chain.limitations,
            lastError: lastError
        )
    }

    var statusSummary: String {
        switch syncState {
        case .checkpointed, .verified:
            return "\(chain.displayName) checkpoint verifier is synced at \(latestCheckpoint?.sequenceNumber.description ?? "unknown")."
        case .proofChecked:
            let noun = chain.kind == .sui ? "checkpoint committee" : "ledger-info validator"
            return "\(chain.displayName) \(noun) quorum and proof evidence are locally checked; production \(chain.displayName) verifier integration is not claimed."
        case .syncing:
            return "\(chain.displayName) Move-chain evidence is syncing."
        case .stale:
            return "\(chain.displayName) Move-chain evidence is stale; API/RPC fallback remains labeled."
        case .failed:
            return "\(chain.displayName) verification failed: \(lastError ?? "unknown error")."
        case .apiFallback, .unavailable:
            return "\(chain.displayName) light-client service is unavailable; API/RPC fallback remains labeled."
        }
    }

    var chainTrustStatus: ChainTrustStatus {
        let state = syncState.chainTrustState
        let evidence: [ChainTrustEvidence] = state.isProductionEvidence ? [
            ChainTrustEvidence(
                id: "\(chain.chainRef)-move-\(latestCheckpoint?.sequenceNumber ?? 0)",
                source: state == .verified ? .embeddedLightClient : .localProof,
                summary: statusSummary,
                blockNumber: latestCheckpoint?.sequenceNumber,
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
            chainID: chain.chainID,
            chainRef: chain.chainRef,
            displayName: chain.displayName,
            family: chain.kind == .sui ? .sui : .aptos,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: chain.supportedProofTypes,
            latestCheckpoint: latestCheckpoint?.checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

final class MoveLightClientServiceClient {
    private let configuration: MoveLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: MoveLightClientEndpointConfiguration = .disabled(),
        session: URLSession = MoveLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> MoveLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(chain: configuration.chain, lastError: "\(configuration.chain.displayName) Move light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/move/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/move/status")
            } catch {
                return .fallback(chain: configuration.chain, lastError: error.localizedDescription)
            }
        }
    }

    func verifyProof(_ bundle: MoveProofVerificationBundle) -> MoveProofVerificationResult {
        bundle.verify()
    }

    func verifyProofViaService(_ bundle: MoveProofVerificationBundle) async throws -> MoveProofVerificationResult {
        do {
            return try await post(path: "/v1/move/verify-proof", body: bundle)
        } catch {
            return try await post(path: "/move/verify-proof", body: bundle)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> MoveLightClientServiceSnapshot {
        var snapshot: MoveLightClientServiceSnapshot = try await get(path: path)
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

enum MoveHash {
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
