import CryptoKit
import Foundation

enum XRPLNetwork: String, Codable, Equatable, CaseIterable {
    case mainnet = "xrp-ledger"
    case testnet = "xrp-testnet"
    case devnet = "xrp-devnet"
    case localnet = "xrp-localnet"

    nonisolated var chainRef: String {
        rawValue
    }

    nonisolated var networkID: String {
        switch self {
        case .mainnet: "mainnet"
        case .testnet: "testnet"
        case .devnet: "devnet"
        case .localnet: "localnet"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .mainnet: "XRP Ledger"
        case .testnet: "XRP Ledger Testnet"
        case .devnet: "XRP Ledger Devnet"
        case .localnet: "XRP Ledger Localnet"
        }
    }

    nonisolated var supportedProofTypes: [String] {
        ["validated-ledger", "unl-quorum", "account-state-proof", "trust-line-proof", "payment-metadata-proof"]
    }

    nonisolated var limitations: [String] {
        switch self {
        case .mainnet:
            return ["Fixture-backed UNL quorum checks do not yet replace a production XRPL validator or rippled verification path."]
        case .testnet, .devnet:
            return ["XRPL test networks are modeled for explicit fallback and fixture checks only."]
        case .localnet:
            return ["Local XRPL routes require caller-provided UNL validators and validated-ledger evidence."]
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let network = Self.known(from: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown XRPL network: \(value)")
        }
        self = network
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(chainRef)
    }

    nonisolated static func known(from value: String) -> XRPLNetwork? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "xrpl", "xrp", "mainnet", "xrp-ledger", "xrpl-mainnet":
            return .mainnet
        case "testnet", "xrp-testnet", "xrpl-testnet":
            return .testnet
        case "devnet", "xrp-devnet", "xrpl-devnet":
            return .devnet
        case "localnet", "xrp-localnet", "local":
            return .localnet
        default:
            return nil
        }
    }
}

enum XRPLLightClientSyncState: String, Codable, Equatable, CaseIterable {
    case unavailable
    case syncing
    case validated
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
        case .validated:
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

struct XRPLLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var network: XRPLNetwork

    nonisolated static let local = XRPLLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        network: .mainnet
    )

    nonisolated static let disabled = XRPLLightClientEndpointConfiguration(
        baseURL: nil,
        network: .mainnet
    )
}

struct XRPLValidatedLedgerSnapshot: Codable, Equatable, Identifiable {
    var id: String { ledgerHash }

    var network: XRPLNetwork
    var ledgerIndex: Int
    var ledgerHash: String
    var parentHash: String
    var accountStateRoot: String
    var transactionMetadataRoot: String
    var closeTime: UInt64
    var validated: Bool
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case network
        case chainRef = "chain_ref"
        case ledgerIndex = "ledger_index"
        case ledgerHash = "ledger_hash"
        case parentHash = "parent_hash"
        case accountStateRoot = "account_state_root"
        case transactionMetadataRoot = "transaction_metadata_root"
        case closeTime = "close_time"
        case validated
        case source
    }

    nonisolated init(
        network: XRPLNetwork,
        ledgerIndex: Int,
        ledgerHash: String,
        parentHash: String,
        accountStateRoot: String,
        transactionMetadataRoot: String,
        closeTime: UInt64,
        validated: Bool,
        source: String? = nil
    ) {
        self.network = network
        self.ledgerIndex = ledgerIndex
        self.ledgerHash = XRPLHash.normalized(ledgerHash)
        self.parentHash = XRPLHash.normalized(parentHash)
        self.accountStateRoot = XRPLHash.normalized(accountStateRoot)
        self.transactionMetadataRoot = XRPLHash.normalized(transactionMetadataRoot)
        self.closeTime = closeTime
        self.validated = validated
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let network = try container.decodeIfPresent(XRPLNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = XRPLNetwork.known(from: chainRef) {
            self.network = network
        } else {
            self.network = .mainnet
        }
        self.ledgerIndex = try container.decode(Int.self, forKey: .ledgerIndex)
        self.ledgerHash = XRPLHash.normalized(try container.decode(String.self, forKey: .ledgerHash))
        self.parentHash = XRPLHash.normalized(try container.decode(String.self, forKey: .parentHash))
        self.accountStateRoot = XRPLHash.normalized(try container.decode(String.self, forKey: .accountStateRoot))
        self.transactionMetadataRoot = XRPLHash.normalized(try container.decode(String.self, forKey: .transactionMetadataRoot))
        self.closeTime = try container.decode(UInt64.self, forKey: .closeTime)
        self.validated = try container.decodeIfPresent(Bool.self, forKey: .validated) ?? false
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(ledgerIndex, forKey: .ledgerIndex)
        try container.encode(ledgerHash, forKey: .ledgerHash)
        try container.encode(parentHash, forKey: .parentHash)
        try container.encode(accountStateRoot, forKey: .accountStateRoot)
        try container.encode(transactionMetadataRoot, forKey: .transactionMetadataRoot)
        try container.encode(closeTime, forKey: .closeTime)
        try container.encode(validated, forKey: .validated)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: ledgerIndex,
            blockHash: ledgerHash,
            checkpointID: "\(network.chainRef)-validated-\(ledgerIndex)",
            updatedAt: Date(timeIntervalSince1970: TimeInterval(closeTime))
        )
    }

    func expectedRoot(for kind: XRPLLocalProofKind) -> String {
        switch kind {
        case .account, .trustLine:
            return accountStateRoot
        case .payment:
            return transactionMetadataRoot
        }
    }
}

struct XRPLUNLValidator: Codable, Equatable, Identifiable {
    var id: String { validatorPublicKey }

    var validatorPublicKey: String
    var weight: Int
    var domain: String?
    var disabled: Bool

    private enum CodingKeys: String, CodingKey {
        case validatorPublicKey = "validator_public_key"
        case weight
        case domain
        case disabled
    }

    nonisolated init(
        validatorPublicKey: String,
        weight: Int = 1,
        domain: String? = nil,
        disabled: Bool = false
    ) {
        self.validatorPublicKey = XRPLHash.normalizedID(validatorPublicKey)
        self.weight = weight
        self.domain = domain
        self.disabled = disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.validatorPublicKey = XRPLHash.normalizedID(try container.decode(String.self, forKey: .validatorPublicKey))
        self.weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        self.domain = try container.decodeIfPresent(String.self, forKey: .domain)
        self.disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    }
}

struct XRPLUNLSet: Codable, Equatable, Identifiable {
    var id: String { "\(network.chainRef)-unl-\(listID)" }

    var network: XRPLNetwork
    var listID: String
    var validators: [XRPLUNLValidator]
    var negativeUNL: [String]
    var quorumNumerator: Int
    var quorumDenominator: Int
    var hash: String
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case network
        case chainRef = "chain_ref"
        case listID = "list_id"
        case validators
        case negativeUNL = "negative_unl"
        case quorumNumerator = "quorum_numerator"
        case quorumDenominator = "quorum_denominator"
        case hash
        case source
    }

    nonisolated init(
        network: XRPLNetwork,
        listID: String,
        validators: [XRPLUNLValidator],
        negativeUNL: [String] = [],
        quorumNumerator: Int = 4,
        quorumDenominator: Int = 5,
        hash: String? = nil,
        source: String? = nil
    ) {
        self.network = network
        self.listID = listID
        self.validators = validators
        self.negativeUNL = negativeUNL.map(XRPLHash.normalizedID).sorted()
        self.quorumNumerator = quorumNumerator
        self.quorumDenominator = quorumDenominator
        self.hash = XRPLHash.normalized(hash ?? Self.computeHash(validators: validators, negativeUNL: self.negativeUNL))
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let network = try container.decodeIfPresent(XRPLNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = XRPLNetwork.known(from: chainRef) {
            self.network = network
        } else {
            self.network = .mainnet
        }
        self.listID = try container.decodeIfPresent(String.self, forKey: .listID) ?? "default-unl"
        self.validators = try container.decode([XRPLUNLValidator].self, forKey: .validators)
        self.negativeUNL = (try container.decodeIfPresent([String].self, forKey: .negativeUNL) ?? [])
            .map(XRPLHash.normalizedID)
            .sorted()
        self.quorumNumerator = try container.decodeIfPresent(Int.self, forKey: .quorumNumerator) ?? 4
        self.quorumDenominator = try container.decodeIfPresent(Int.self, forKey: .quorumDenominator) ?? 5
        self.hash = XRPLHash.normalized(try container.decodeIfPresent(String.self, forKey: .hash) ?? Self.computeHash(validators: validators, negativeUNL: negativeUNL))
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(listID, forKey: .listID)
        try container.encode(validators, forKey: .validators)
        try container.encode(negativeUNL, forKey: .negativeUNL)
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
            isEffective(validator) ? partial + max(0, validator.weight) : partial
        }
    }

    var requiredQuorumWeight: Int {
        guard effectiveWeight > 0, quorumDenominator > 0 else { return 0 }
        let effectiveQuorum = Self.ceilDivide(effectiveWeight * quorumNumerator, by: quorumDenominator)
        let hardMinimum = Self.ceilDivide(configuredWeight * 3, by: 5)
        return max(effectiveQuorum, hardMinimum)
    }

    var validatesHash: Bool {
        hash == Self.computeHash(validators: validators, negativeUNL: negativeUNL)
    }

    func signedWeight(validatorPublicKeys: Set<String>) -> Int {
        validators.reduce(0) { partial, validator in
            isEffective(validator) && validatorPublicKeys.contains(XRPLHash.normalizedID(validator.validatorPublicKey))
                ? partial + max(0, validator.weight)
                : partial
        }
    }

    func hasQuorum(validatorPublicKeys: Set<String>) -> Bool {
        let required = requiredQuorumWeight
        guard required > 0 else { return false }
        return signedWeight(validatorPublicKeys: validatorPublicKeys) >= required
    }

    private func isEffective(_ validator: XRPLUNLValidator) -> Bool {
        !validator.disabled && !negativeUNL.contains(XRPLHash.normalizedID(validator.validatorPublicKey))
    }

    nonisolated static func computeHash(validators: [XRPLUNLValidator], negativeUNL: [String]) -> String {
        let validatorPayload = validators
            .map { "\(XRPLHash.normalizedID($0.validatorPublicKey)):\($0.weight):\($0.disabled ? "disabled" : "active")" }
            .sorted()
            .joined(separator: "|")
        let negativePayload = negativeUNL.map(XRPLHash.normalizedID).sorted().joined(separator: "|")
        return XRPLHash.sha256Hex("\(validatorPayload)#negative:\(negativePayload)")
    }

    nonisolated private static func ceilDivide(_ value: Int, by denominator: Int) -> Int {
        guard denominator > 0 else { return 0 }
        return (value + denominator - 1) / denominator
    }
}

struct XRPLValidationVote: Codable, Equatable, Identifiable {
    var id: String { validatorPublicKey }

    var validatorPublicKey: String
    var ledgerHash: String
    var ledgerIndex: Int
    var signed: Bool
    var signature: String?

    private enum CodingKeys: String, CodingKey {
        case validatorPublicKey = "validator_public_key"
        case ledgerHash = "ledger_hash"
        case ledgerIndex = "ledger_index"
        case signed
        case signature
    }

    nonisolated init(
        validatorPublicKey: String,
        ledgerHash: String,
        ledgerIndex: Int,
        signed: Bool = true,
        signature: String? = nil
    ) {
        self.validatorPublicKey = XRPLHash.normalizedID(validatorPublicKey)
        self.ledgerHash = XRPLHash.normalized(ledgerHash)
        self.ledgerIndex = ledgerIndex
        self.signed = signed
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.validatorPublicKey = XRPLHash.normalizedID(try container.decode(String.self, forKey: .validatorPublicKey))
        self.ledgerHash = XRPLHash.normalized(try container.decode(String.self, forKey: .ledgerHash))
        self.ledgerIndex = try container.decode(Int.self, forKey: .ledgerIndex)
        self.signed = try container.decodeIfPresent(Bool.self, forKey: .signed) ?? true
        self.signature = try container.decodeIfPresent(String.self, forKey: .signature)
    }
}

struct XRPLLedgerValidationProof: Codable, Equatable {
    var listID: String
    var ledgerHash: String
    var ledgerIndex: Int
    var votes: [XRPLValidationVote]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case listID = "list_id"
        case ledgerHash = "ledger_hash"
        case ledgerIndex = "ledger_index"
        case votes
        case source
    }

    nonisolated init(
        listID: String,
        ledgerHash: String,
        ledgerIndex: Int,
        votes: [XRPLValidationVote],
        source: String? = nil
    ) {
        self.listID = listID
        self.ledgerHash = XRPLHash.normalized(ledgerHash)
        self.ledgerIndex = ledgerIndex
        self.votes = votes
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.listID = try container.decodeIfPresent(String.self, forKey: .listID) ?? "default-unl"
        self.ledgerHash = XRPLHash.normalized(try container.decode(String.self, forKey: .ledgerHash))
        self.ledgerIndex = try container.decode(Int.self, forKey: .ledgerIndex)
        self.votes = try container.decode([XRPLValidationVote].self, forKey: .votes)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func signedValidatorPublicKeys(ledgerHash: String, ledgerIndex: Int) -> Set<String> {
        let normalizedLedgerHash = XRPLHash.normalized(ledgerHash)
        return Set(votes.filter {
            $0.signed
                && $0.ledgerIndex == ledgerIndex
                && XRPLHash.normalized($0.ledgerHash) == normalizedLedgerHash
        }.map { XRPLHash.normalizedID($0.validatorPublicKey) })
    }
}

enum XRPLLocalProofKind: String, Codable, Equatable, CaseIterable {
    case account
    case trustLine = "trust_line"
    case payment
}

enum XRPLProofWitnessPosition: String, Codable, Equatable {
    case left
    case right
}

struct XRPLProofWitness: Codable, Equatable {
    var hash: String
    var position: XRPLProofWitnessPosition

    nonisolated init(hash: String, position: XRPLProofWitnessPosition) {
        self.hash = XRPLHash.normalized(hash)
        self.position = position
    }
}

struct XRPLLocalProof: Codable, Equatable, Identifiable {
    var id: String { proofID }

    var proofID: String
    var kind: XRPLLocalProofKind
    var network: XRPLNetwork
    var subject: String
    var counterparty: String?
    var currency: String?
    var transactionHash: String?
    var expectedValueHash: String
    var ledgerHash: String
    var ledgerIndex: Int
    var expectedRoot: String
    var leafHash: String
    var witnesses: [XRPLProofWitness]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case proofID = "proof_id"
        case kind
        case network
        case chainRef = "chain_ref"
        case subject
        case counterparty
        case currency
        case transactionHash = "transaction_hash"
        case expectedValueHash = "expected_value_hash"
        case ledgerHash = "ledger_hash"
        case ledgerIndex = "ledger_index"
        case expectedRoot = "expected_root"
        case leafHash = "leaf_hash"
        case witnesses
        case source
    }

    nonisolated init(
        proofID: String,
        kind: XRPLLocalProofKind,
        network: XRPLNetwork,
        subject: String,
        counterparty: String? = nil,
        currency: String? = nil,
        transactionHash: String? = nil,
        expectedValueHash: String,
        ledgerHash: String,
        ledgerIndex: Int,
        expectedRoot: String,
        leafHash: String,
        witnesses: [XRPLProofWitness],
        source: String? = nil
    ) {
        self.proofID = proofID
        self.kind = kind
        self.network = network
        self.subject = subject
        self.counterparty = counterparty
        self.currency = currency
        self.transactionHash = transactionHash.map(XRPLHash.normalized)
        self.expectedValueHash = XRPLHash.normalized(expectedValueHash)
        self.ledgerHash = XRPLHash.normalized(ledgerHash)
        self.ledgerIndex = ledgerIndex
        self.expectedRoot = XRPLHash.normalized(expectedRoot)
        self.leafHash = XRPLHash.normalized(leafHash)
        self.witnesses = witnesses
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.proofID = try container.decodeIfPresent(String.self, forKey: .proofID) ?? UUID().uuidString
        self.kind = try container.decode(XRPLLocalProofKind.self, forKey: .kind)
        if let network = try container.decodeIfPresent(XRPLNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = XRPLNetwork.known(from: chainRef) {
            self.network = network
        } else {
            self.network = .mainnet
        }
        self.subject = try container.decode(String.self, forKey: .subject)
        self.counterparty = try container.decodeIfPresent(String.self, forKey: .counterparty)
        self.currency = try container.decodeIfPresent(String.self, forKey: .currency)
        self.transactionHash = try container.decodeIfPresent(String.self, forKey: .transactionHash).map(XRPLHash.normalized)
        self.expectedValueHash = XRPLHash.normalized(try container.decode(String.self, forKey: .expectedValueHash))
        self.ledgerHash = XRPLHash.normalized(try container.decode(String.self, forKey: .ledgerHash))
        self.ledgerIndex = try container.decode(Int.self, forKey: .ledgerIndex)
        self.expectedRoot = XRPLHash.normalized(try container.decode(String.self, forKey: .expectedRoot))
        self.leafHash = XRPLHash.normalized(try container.decode(String.self, forKey: .leafHash))
        self.witnesses = try container.decodeIfPresent([XRPLProofWitness].self, forKey: .witnesses) ?? []
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proofID, forKey: .proofID)
        try container.encode(kind, forKey: .kind)
        try container.encode(network, forKey: .network)
        try container.encode(network.chainRef, forKey: .chainRef)
        try container.encode(subject, forKey: .subject)
        try container.encodeIfPresent(counterparty, forKey: .counterparty)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(transactionHash, forKey: .transactionHash)
        try container.encode(expectedValueHash, forKey: .expectedValueHash)
        try container.encode(ledgerHash, forKey: .ledgerHash)
        try container.encode(ledgerIndex, forKey: .ledgerIndex)
        try container.encode(expectedRoot, forKey: .expectedRoot)
        try container.encode(leafHash, forKey: .leafHash)
        try container.encode(witnesses, forKey: .witnesses)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var computedRoot: String? {
        Self.computeRoot(leafHash: leafHash, witnesses: witnesses)
    }

    nonisolated static func computeRoot(leafHash: String, witnesses: [XRPLProofWitness]) -> String? {
        guard var node = XRPLHash.data(from: leafHash) else { return nil }
        for witness in witnesses {
            guard let sibling = XRPLHash.data(from: witness.hash) else { return nil }
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
        return XRPLHash.hex(from: node)
    }

    nonisolated static func fixtureLeafHash(
        kind: XRPLLocalProofKind,
        subject: String,
        counterparty: String? = nil,
        currency: String? = nil,
        transactionHash: String? = nil,
        valueHash: String
    ) -> String {
        XRPLHash.sha256Hex([
            kind.rawValue,
            subject.lowercased(),
            counterparty?.lowercased() ?? "",
            currency?.lowercased() ?? "",
            transactionHash.map(XRPLHash.normalized) ?? "",
            XRPLHash.normalized(valueHash)
        ].joined(separator: "|"))
    }
}

struct XRPLProofVerificationBundle: Codable, Equatable {
    var ledger: XRPLValidatedLedgerSnapshot
    var unlSet: XRPLUNLSet
    var validationProof: XRPLLedgerValidationProof
    var proof: XRPLLocalProof?

    private enum CodingKeys: String, CodingKey {
        case ledger
        case unlSet = "unl_set"
        case validationProof = "validation_proof"
        case proof
    }

    nonisolated init(
        ledger: XRPLValidatedLedgerSnapshot,
        unlSet: XRPLUNLSet,
        validationProof: XRPLLedgerValidationProof,
        proof: XRPLLocalProof? = nil
    ) {
        self.ledger = ledger
        self.unlSet = unlSet
        self.validationProof = validationProof
        self.proof = proof
    }

    func verify() -> XRPLProofVerificationResult {
        guard ledger.network == unlSet.network else {
            return failure("XRPL ledger network does not match the UNL trust-anchor set.")
        }
        guard ledger.validated else {
            return failure("XRPL ledger is not marked validated; API/RPC data must remain fallback-labeled.")
        }
        guard validationProof.listID == unlSet.listID,
              validationProof.ledgerIndex == ledger.ledgerIndex,
              XRPLHash.normalized(validationProof.ledgerHash) == XRPLHash.normalized(ledger.ledgerHash) else {
            return failure("XRPL validation proof targets a different ledger or UNL list.")
        }
        guard unlSet.validatesHash else {
            return failure("XRPL UNL trust-anchor hash is invalid.")
        }
        let signedValidators = validationProof.signedValidatorPublicKeys(
            ledgerHash: ledger.ledgerHash,
            ledgerIndex: ledger.ledgerIndex
        )
        guard unlSet.hasQuorum(validatorPublicKeys: signedValidators) else {
            return failure("XRPL validation proof did not reach the configured UNL quorum.")
        }
        if let proof {
            guard proof.network == ledger.network,
                  proof.ledgerIndex == ledger.ledgerIndex,
                  XRPLHash.normalized(proof.ledgerHash) == XRPLHash.normalized(ledger.ledgerHash) else {
                return failure("XRPL proof references a different network or ledger.")
            }
            guard XRPLHash.normalized(proof.expectedRoot) == ledger.expectedRoot(for: proof.kind) else {
                return failure("XRPL \(proof.kind.rawValue) proof expected root does not match the validated ledger root.")
            }
            guard proof.computedRoot == XRPLHash.normalized(proof.expectedRoot) else {
                return failure("XRPL \(proof.kind.rawValue) proof did not resolve to the expected root.")
            }
        }

        return XRPLProofVerificationResult(
            verified: true,
            state: .proofChecked,
            chainRef: ledger.network.chainRef,
            ledgerIndex: ledger.ledgerIndex,
            ledgerHash: ledger.ledgerHash,
            proofID: proof?.proofID,
            kind: proof?.kind,
            summary: proof == nil
                ? "XRPL validated ledger \(ledger.ledgerIndex) checked with fixture UNL quorum."
                : "XRPL \(proof?.kind.rawValue ?? "state") proof checked against validated ledger \(ledger.ledgerIndex)."
        )
    }

    private func failure(_ summary: String) -> XRPLProofVerificationResult {
        XRPLProofVerificationResult(
            verified: false,
            state: .failed,
            chainRef: ledger.network.chainRef,
            ledgerIndex: ledger.ledgerIndex,
            ledgerHash: ledger.ledgerHash,
            proofID: proof?.proofID,
            kind: proof?.kind,
            summary: summary
        )
    }
}

struct XRPLProofVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: XRPLLightClientSyncState
    var chainRef: String
    var ledgerIndex: Int?
    var ledgerHash: String?
    var proofID: String?
    var kind: XRPLLocalProofKind?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case chainRef = "chain_ref"
        case ledgerIndex = "ledger_index"
        case ledgerHash = "ledger_hash"
        case proofID = "proof_id"
        case kind
        case summary
    }
}

struct XRPLLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var network: XRPLNetwork
    var syncState: XRPLLightClientSyncState
    var source: String
    var latestValidatedLedger: XRPLValidatedLedgerSnapshot?
    var unlSet: XRPLUNLSet?
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
        case latestValidatedLedger = "latest_validated_ledger"
        case unlSet = "unl_set"
        case peerCount = "peer_count"
        case proofSource = "proof_source"
        case stale
        case limitations
        case lastError = "last_error"
    }

    nonisolated init(
        serviceAvailable: Bool,
        network: XRPLNetwork,
        syncState: XRPLLightClientSyncState,
        source: String,
        latestValidatedLedger: XRPLValidatedLedgerSnapshot? = nil,
        unlSet: XRPLUNLSet? = nil,
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
        self.latestValidatedLedger = latestValidatedLedger
        self.unlSet = unlSet
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
        if let network = try container.decodeIfPresent(XRPLNetwork.self, forKey: .network) {
            self.network = network
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let network = XRPLNetwork.known(from: chainRef) {
            self.network = network
        } else {
            self.network = .mainnet
        }
        self.syncState = try container.decodeIfPresent(XRPLLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "xrpl-light-client"
        self.latestValidatedLedger = try container.decodeIfPresent(XRPLValidatedLedgerSnapshot.self, forKey: .latestValidatedLedger)
        self.unlSet = try container.decodeIfPresent(XRPLUNLSet.self, forKey: .unlSet)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.proofSource = try container.decodeIfPresent(String.self, forKey: .proofSource)
        self.stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        self.limitations = try container.decodeIfPresent([String].self, forKey: .limitations) ?? network.limitations
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        if stale && (self.syncState == .proofChecked || self.syncState == .validated) {
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
        try container.encodeIfPresent(latestValidatedLedger, forKey: .latestValidatedLedger)
        try container.encodeIfPresent(unlSet, forKey: .unlSet)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(proofSource, forKey: .proofSource)
        try container.encode(stale, forKey: .stale)
        try container.encode(limitations, forKey: .limitations)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    static func fallback(network: XRPLNetwork, lastError: String?) -> XRPLLightClientServiceSnapshot {
        XRPLLightClientServiceSnapshot(
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
        case .validated:
            return "\(network.displayName) validated-ledger verifier is synced at ledger \(latestValidatedLedger?.ledgerIndex.description ?? "unknown")."
        case .proofChecked:
            return "\(network.displayName) UNL quorum and proof evidence are locally checked; production XRPL verifier integration is not claimed."
        case .syncing:
            return "\(network.displayName) validated-ledger evidence is syncing."
        case .stale:
            return "\(network.displayName) validated-ledger evidence is stale; API/RPC fallback remains labeled."
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
                id: "\(network.chainRef)-xrpl-\(latestValidatedLedger?.ledgerIndex ?? 0)",
                source: state == .verified ? .embeddedLightClient : .localProof,
                summary: statusSummary,
                blockNumber: latestValidatedLedger?.ledgerIndex,
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
            family: .xrpLedger,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: network.supportedProofTypes,
            latestCheckpoint: latestValidatedLedger?.checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

/// Trust boundary (goal: minimize remote trust). A client for a remote light-client/RPC service.
/// UNL-quorum checks are fixture-backed and do not yet replace a production XRPL validator /
/// rippled verification path; live state is served via RPC fallback (`.rpcFallback`).
final class XRPLLightClientServiceClient {
    private let configuration: XRPLLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: XRPLLightClientEndpointConfiguration = .disabled,
        session: URLSession = XRPLLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> XRPLLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(network: configuration.network, lastError: "XRPL light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/xrpl/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/xrpl/status")
            } catch {
                return .fallback(network: configuration.network, lastError: error.localizedDescription)
            }
        }
    }

    func verifyProof(_ bundle: XRPLProofVerificationBundle) -> XRPLProofVerificationResult {
        bundle.verify()
    }

    func verifyProofViaService(_ bundle: XRPLProofVerificationBundle) async throws -> XRPLProofVerificationResult {
        do {
            return try await post(path: "/v1/xrpl/verify-proof", body: bundle)
        } catch {
            return try await post(path: "/xrpl/verify-proof", body: bundle)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> XRPLLightClientServiceSnapshot {
        var snapshot: XRPLLightClientServiceSnapshot = try await get(path: path)
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

enum XRPLHash {
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
