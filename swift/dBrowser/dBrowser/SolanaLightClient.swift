import CryptoKit
import Foundation

enum SolanaCluster: String, Codable, Equatable, CaseIterable {
    case mainnetBeta = "mainnet-beta"
    case devnet
    case testnet
    case localnet

    nonisolated var chainRef: String {
        switch self {
        case .mainnetBeta: "solana-mainnet"
        case .devnet: "solana-devnet"
        case .testnet: "solana-testnet"
        case .localnet: "solana-localnet"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .mainnetBeta: "Solana"
        case .devnet: "Solana Devnet"
        case .testnet: "Solana Testnet"
        case .localnet: "Solana Localnet"
        }
    }

    nonisolated var supportedProofTypes: [String] {
        ["slot-root", "vote-root-quorum", "optimistic-confirmation", "transaction-status", "account-proof"]
    }

    nonisolated static func known(from value: String) -> SolanaCluster? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "solana", "solana-mainnet", "mainnet", "mainnet-beta":
            return .mainnetBeta
        case "solana-devnet", "devnet":
            return .devnet
        case "solana-testnet", "testnet":
            return .testnet
        case "solana-localnet", "localnet":
            return .localnet
        default:
            return nil
        }
    }
}

enum SolanaCommitment: String, Codable, Equatable, CaseIterable {
    case processed
    case confirmed
    case finalized
}

enum SolanaLightClientSyncState: String, Codable, Equatable, CaseIterable {
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

struct SolanaLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var cluster: SolanaCluster

    nonisolated static let local = SolanaLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        cluster: .mainnetBeta
    )

    nonisolated static let disabled = SolanaLightClientEndpointConfiguration(
        baseURL: nil,
        cluster: .mainnetBeta
    )
}

enum SolanaFixtureProofKind: String, Codable, Equatable, CaseIterable {
    case account
    case transactionStatus = "transaction_status"
}

enum SolanaProofWitnessPosition: String, Codable, Equatable {
    case left
    case right
}

struct SolanaProofWitness: Codable, Equatable {
    var hash: String
    var position: SolanaProofWitnessPosition

    nonisolated init(hash: String, position: SolanaProofWitnessPosition) {
        self.hash = hash
        self.position = position
    }
}

struct SolanaSlotRootSnapshot: Codable, Equatable, Identifiable {
    var id: String { "\(cluster.chainRef)-\(slot)" }

    var cluster: SolanaCluster
    var slot: UInt64
    var rootSlot: UInt64
    var blockhash: String
    var parentSlot: UInt64?
    var commitment: SolanaCommitment
    var accountRoot: String?
    var transactionStatusRoot: String?
    var observedAt: Date?
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case cluster
        case chainRef = "chain_ref"
        case slot
        case rootSlot = "root_slot"
        case blockhash
        case parentSlot = "parent_slot"
        case commitment
        case accountRoot = "account_root"
        case transactionStatusRoot = "transaction_status_root"
        case observedAt = "observed_at"
        case source
    }

    nonisolated init(
        cluster: SolanaCluster,
        slot: UInt64,
        rootSlot: UInt64,
        blockhash: String,
        parentSlot: UInt64? = nil,
        commitment: SolanaCommitment,
        accountRoot: String? = nil,
        transactionStatusRoot: String? = nil,
        observedAt: Date? = nil,
        source: String? = nil
    ) {
        self.cluster = cluster
        self.slot = slot
        self.rootSlot = rootSlot
        self.blockhash = blockhash
        self.parentSlot = parentSlot
        self.commitment = commitment
        self.accountRoot = accountRoot.map(SolanaHex.normalized)
        self.transactionStatusRoot = transactionStatusRoot.map(SolanaHex.normalized)
        self.observedAt = observedAt
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let cluster = try container.decodeIfPresent(SolanaCluster.self, forKey: .cluster) {
            self.cluster = cluster
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let cluster = SolanaCluster.known(from: chainRef) {
            self.cluster = cluster
        } else {
            self.cluster = .mainnetBeta
        }
        self.slot = try container.decode(UInt64.self, forKey: .slot)
        self.rootSlot = try container.decode(UInt64.self, forKey: .rootSlot)
        self.blockhash = try container.decode(String.self, forKey: .blockhash)
        self.parentSlot = try container.decodeIfPresent(UInt64.self, forKey: .parentSlot)
        self.commitment = try container.decodeIfPresent(SolanaCommitment.self, forKey: .commitment) ?? .confirmed
        self.accountRoot = try container.decodeIfPresent(String.self, forKey: .accountRoot).map(SolanaHex.normalized)
        self.transactionStatusRoot = try container.decodeIfPresent(String.self, forKey: .transactionStatusRoot).map(SolanaHex.normalized)
        self.observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cluster, forKey: .cluster)
        try container.encode(cluster.chainRef, forKey: .chainRef)
        try container.encode(slot, forKey: .slot)
        try container.encode(rootSlot, forKey: .rootSlot)
        try container.encode(blockhash, forKey: .blockhash)
        try container.encodeIfPresent(parentSlot, forKey: .parentSlot)
        try container.encode(commitment, forKey: .commitment)
        try container.encodeIfPresent(accountRoot, forKey: .accountRoot)
        try container.encodeIfPresent(transactionStatusRoot, forKey: .transactionStatusRoot)
        try container.encodeIfPresent(observedAt, forKey: .observedAt)
        try container.encodeIfPresent(source, forKey: .source)
    }

    nonisolated func rootLag() -> UInt64 {
        slot >= rootSlot ? slot - rootSlot : 0
    }

    nonisolated func isStale(maxRootLag: UInt64) -> Bool {
        commitment != .finalized || rootLag() > maxRootLag
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: Int(rootSlot),
            blockHash: blockhash,
            checkpointID: "\(cluster.chainRef)-root-\(rootSlot)",
            updatedAt: observedAt
        )
    }

    func expectedRoot(for kind: SolanaFixtureProofKind) -> String? {
        switch kind {
        case .account:
            return accountRoot
        case .transactionStatus:
            return transactionStatusRoot
        }
    }
}

struct SolanaValidator: Codable, Equatable, Identifiable {
    var id: String { voteAccount }

    var voteAccount: String
    var stake: Int
    var publicKey: String
    var name: String?
    var disabled: Bool

    private enum CodingKeys: String, CodingKey {
        case voteAccount = "vote_account"
        case stake
        case publicKey = "public_key"
        case name
        case disabled
    }

    nonisolated init(
        voteAccount: String,
        stake: Int,
        publicKey: String,
        name: String? = nil,
        disabled: Bool = false
    ) {
        self.voteAccount = SolanaHex.normalizedID(voteAccount)
        self.stake = stake
        self.publicKey = SolanaHex.normalized(publicKey)
        self.name = name
        self.disabled = disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.voteAccount = SolanaHex.normalizedID(try container.decode(String.self, forKey: .voteAccount))
        self.stake = try container.decode(Int.self, forKey: .stake)
        self.publicKey = SolanaHex.normalized(try container.decode(String.self, forKey: .publicKey))
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    }
}

struct SolanaValidatorSet: Codable, Equatable, Identifiable {
    var id: String { "\(cluster.chainRef)-validators-\(epoch)" }

    var cluster: SolanaCluster
    var epoch: UInt64
    var validators: [SolanaValidator]
    var hash: String
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case cluster
        case chainRef = "chain_ref"
        case epoch
        case validators
        case hash
        case source
    }

    nonisolated init(
        cluster: SolanaCluster,
        epoch: UInt64,
        validators: [SolanaValidator],
        hash: String? = nil,
        source: String? = nil
    ) {
        self.cluster = cluster
        self.epoch = epoch
        self.validators = validators
        self.hash = SolanaHex.normalized(hash ?? Self.computeHash(validators: validators))
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let cluster = try container.decodeIfPresent(SolanaCluster.self, forKey: .cluster) {
            self.cluster = cluster
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let cluster = SolanaCluster.known(from: chainRef) {
            self.cluster = cluster
        } else {
            self.cluster = .mainnetBeta
        }
        self.epoch = try container.decode(UInt64.self, forKey: .epoch)
        self.validators = try container.decode([SolanaValidator].self, forKey: .validators)
        self.hash = SolanaHex.normalized(try container.decodeIfPresent(String.self, forKey: .hash) ?? Self.computeHash(validators: validators))
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cluster, forKey: .cluster)
        try container.encode(cluster.chainRef, forKey: .chainRef)
        try container.encode(epoch, forKey: .epoch)
        try container.encode(validators, forKey: .validators)
        try container.encode(hash, forKey: .hash)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var effectiveStake: Int {
        validators.reduce(0) { partial, validator in
            validator.disabled ? partial : partial + max(0, validator.stake)
        }
    }

    var validatesHash: Bool {
        hash == Self.computeHash(validators: validators)
    }

    func signedStake(voteAccounts: Set<String>) -> Int {
        validators.reduce(0) { partial, validator in
            guard !validator.disabled,
                  voteAccounts.contains(SolanaHex.normalizedID(validator.voteAccount)) else {
                return partial
            }
            return partial + max(0, validator.stake)
        }
    }

    func hasRootQuorum(voteAccounts: Set<String>) -> Bool {
        let total = effectiveStake
        guard total > 0 else { return false }
        return signedStake(voteAccounts: voteAccounts) * 3 > total * 2
    }

    nonisolated static func computeHash(validators: [SolanaValidator]) -> String {
        let payload = validators
            .map { validator in
                [
                    SolanaHex.normalizedID(validator.voteAccount),
                    "\(validator.stake)",
                    SolanaHex.normalized(validator.publicKey),
                    validator.disabled ? "disabled" : "active"
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: "|")
        return SolanaHex.sha256Hex(payload)
    }
}

struct SolanaVoteRootSignature: Codable, Equatable, Identifiable {
    var id: String { voteAccount }

    var voteAccount: String
    var rootSlot: UInt64
    var blockhash: String
    var signed: Bool
    var signature: String?

    private enum CodingKeys: String, CodingKey {
        case voteAccount = "vote_account"
        case rootSlot = "root_slot"
        case blockhash
        case signed
        case signature
    }

    nonisolated init(
        voteAccount: String,
        rootSlot: UInt64,
        blockhash: String,
        signed: Bool = true,
        signature: String? = nil
    ) {
        self.voteAccount = SolanaHex.normalizedID(voteAccount)
        self.rootSlot = rootSlot
        self.blockhash = SolanaHex.normalized(blockhash)
        self.signed = signed
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.voteAccount = SolanaHex.normalizedID(try container.decode(String.self, forKey: .voteAccount))
        self.rootSlot = try container.decode(UInt64.self, forKey: .rootSlot)
        self.blockhash = SolanaHex.normalized(try container.decode(String.self, forKey: .blockhash))
        self.signed = try container.decodeIfPresent(Bool.self, forKey: .signed) ?? true
        self.signature = try container.decodeIfPresent(String.self, forKey: .signature)
    }
}

struct SolanaVoteRootEvidence: Codable, Equatable {
    var epoch: UInt64
    var cluster: SolanaCluster
    var targetRootSlot: UInt64
    var targetBlockhash: String
    var accountRoot: String?
    var transactionStatusRoot: String?
    var signatures: [SolanaVoteRootSignature]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case epoch
        case cluster
        case chainRef = "chain_ref"
        case targetRootSlot = "target_root_slot"
        case targetBlockhash = "target_blockhash"
        case accountRoot = "account_root"
        case transactionStatusRoot = "transaction_status_root"
        case signatures
        case source
    }

    nonisolated init(
        epoch: UInt64,
        cluster: SolanaCluster,
        targetRootSlot: UInt64,
        targetBlockhash: String,
        accountRoot: String?,
        transactionStatusRoot: String?,
        signatures: [SolanaVoteRootSignature],
        source: String? = nil
    ) {
        self.epoch = epoch
        self.cluster = cluster
        self.targetRootSlot = targetRootSlot
        self.targetBlockhash = SolanaHex.normalized(targetBlockhash)
        self.accountRoot = accountRoot.map(SolanaHex.normalized)
        self.transactionStatusRoot = transactionStatusRoot.map(SolanaHex.normalized)
        self.signatures = signatures
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.epoch = try container.decode(UInt64.self, forKey: .epoch)
        if let cluster = try container.decodeIfPresent(SolanaCluster.self, forKey: .cluster) {
            self.cluster = cluster
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let cluster = SolanaCluster.known(from: chainRef) {
            self.cluster = cluster
        } else {
            self.cluster = .mainnetBeta
        }
        self.targetRootSlot = try container.decode(UInt64.self, forKey: .targetRootSlot)
        self.targetBlockhash = SolanaHex.normalized(try container.decode(String.self, forKey: .targetBlockhash))
        self.accountRoot = try container.decodeIfPresent(String.self, forKey: .accountRoot).map(SolanaHex.normalized)
        self.transactionStatusRoot = try container.decodeIfPresent(String.self, forKey: .transactionStatusRoot).map(SolanaHex.normalized)
        self.signatures = try container.decode([SolanaVoteRootSignature].self, forKey: .signatures)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(epoch, forKey: .epoch)
        try container.encode(cluster, forKey: .cluster)
        try container.encode(cluster.chainRef, forKey: .chainRef)
        try container.encode(targetRootSlot, forKey: .targetRootSlot)
        try container.encode(targetBlockhash, forKey: .targetBlockhash)
        try container.encodeIfPresent(accountRoot, forKey: .accountRoot)
        try container.encodeIfPresent(transactionStatusRoot, forKey: .transactionStatusRoot)
        try container.encode(signatures, forKey: .signatures)
        try container.encodeIfPresent(source, forKey: .source)
    }

    static func canonicalVote(
        cluster: SolanaCluster,
        epoch: UInt64,
        rootSlot: UInt64,
        blockhash: String,
        accountRoot: String?,
        transactionStatusRoot: String?
    ) -> Data {
        let payload = [
            "solana-vote-root-v1",
            cluster.chainRef,
            "\(epoch)",
            "\(rootSlot)",
            SolanaHex.normalized(blockhash),
            accountRoot.map(SolanaHex.normalized) ?? "",
            transactionStatusRoot.map(SolanaHex.normalized) ?? ""
        ].joined(separator: "|")
        return Data(payload.utf8)
    }

    func verifiedVoteAccounts(validators: [SolanaValidator]) -> Set<String> {
        let publicKeysByVoteAccount = Dictionary(
            uniqueKeysWithValues: validators.filter { !$0.disabled }.map {
                (SolanaHex.normalizedID($0.voteAccount), SolanaHex.normalized($0.publicKey))
            }
        )
        let expectedMessage = Self.canonicalVote(
            cluster: cluster,
            epoch: epoch,
            rootSlot: targetRootSlot,
            blockhash: targetBlockhash,
            accountRoot: accountRoot,
            transactionStatusRoot: transactionStatusRoot
        )
        var verified = Set<String>()

        for signature in signatures where signature.signed {
            let voteAccount = SolanaHex.normalizedID(signature.voteAccount)
            guard
                signature.rootSlot == targetRootSlot,
                SolanaHex.normalized(signature.blockhash) == SolanaHex.normalized(targetBlockhash),
                let publicKey = publicKeysByVoteAccount[voteAccount],
                Ed25519QuorumVerifier.isValidSignature(
                    signatureBase64: signature.signature,
                    publicKeyHex: publicKey,
                    message: expectedMessage
                )
            else {
                continue
            }
            verified.insert(voteAccount)
        }

        return verified
    }
}

struct SolanaFixtureProof: Codable, Equatable, Identifiable {
    var id: String { proofID }

    var proofID: String
    var kind: SolanaFixtureProofKind
    var cluster: SolanaCluster
    var subject: String
    var slot: UInt64
    var expectedRoot: String
    var leafHash: String
    var witnesses: [SolanaProofWitness]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case proofID = "proof_id"
        case kind
        case cluster
        case chainRef = "chain_ref"
        case subject
        case slot
        case expectedRoot = "expected_root"
        case leafHash = "leaf_hash"
        case witnesses
        case source
    }

    nonisolated init(
        proofID: String,
        kind: SolanaFixtureProofKind,
        cluster: SolanaCluster,
        subject: String,
        slot: UInt64,
        expectedRoot: String,
        leafHash: String,
        witnesses: [SolanaProofWitness],
        source: String? = nil
    ) {
        self.proofID = proofID
        self.kind = kind
        self.cluster = cluster
        self.subject = subject
        self.slot = slot
        self.expectedRoot = SolanaHex.normalized(expectedRoot)
        self.leafHash = SolanaHex.normalized(leafHash)
        self.witnesses = witnesses
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.proofID = try container.decodeIfPresent(String.self, forKey: .proofID) ?? UUID().uuidString
        self.kind = try container.decode(SolanaFixtureProofKind.self, forKey: .kind)
        if let cluster = try container.decodeIfPresent(SolanaCluster.self, forKey: .cluster) {
            self.cluster = cluster
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let cluster = SolanaCluster.known(from: chainRef) {
            self.cluster = cluster
        } else {
            self.cluster = .mainnetBeta
        }
        self.subject = try container.decode(String.self, forKey: .subject)
        self.slot = try container.decode(UInt64.self, forKey: .slot)
        self.expectedRoot = SolanaHex.normalized(try container.decode(String.self, forKey: .expectedRoot))
        self.leafHash = SolanaHex.normalized(try container.decode(String.self, forKey: .leafHash))
        self.witnesses = try container.decodeIfPresent([SolanaProofWitness].self, forKey: .witnesses) ?? []
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proofID, forKey: .proofID)
        try container.encode(kind, forKey: .kind)
        try container.encode(cluster, forKey: .cluster)
        try container.encode(cluster.chainRef, forKey: .chainRef)
        try container.encode(subject, forKey: .subject)
        try container.encode(slot, forKey: .slot)
        try container.encode(expectedRoot, forKey: .expectedRoot)
        try container.encode(leafHash, forKey: .leafHash)
        try container.encode(witnesses, forKey: .witnesses)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var computedRoot: String? {
        Self.computeRoot(leafHash: leafHash, witnesses: witnesses)
    }

    var verifiesExpectedRoot: Bool {
        computedRoot == SolanaHex.normalized(expectedRoot)
    }

    nonisolated static func computeRoot(leafHash: String, witnesses: [SolanaProofWitness]) -> String? {
        guard var node = SolanaHex.data(from: leafHash) else { return nil }
        for witness in witnesses {
            guard let sibling = SolanaHex.data(from: witness.hash) else { return nil }
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
        return SolanaHex.hex(from: node)
    }

    nonisolated static func fixtureLeafHash(kind: SolanaFixtureProofKind, subject: String, value: String) -> String {
        SolanaHex.sha256Hex([kind.rawValue, subject.lowercased(), value.lowercased()].joined(separator: "|"))
    }
}

struct SolanaProofBundle: Codable, Equatable {
    var snapshot: SolanaSlotRootSnapshot
    var proof: SolanaFixtureProof
    var validatorSet: SolanaValidatorSet
    var voteEvidence: SolanaVoteRootEvidence

    private enum CodingKeys: String, CodingKey {
        case snapshot
        case proof
        case validatorSet = "validator_set"
        case voteEvidence = "vote_evidence"
    }

    nonisolated init(
        snapshot: SolanaSlotRootSnapshot,
        proof: SolanaFixtureProof,
        validatorSet: SolanaValidatorSet,
        voteEvidence: SolanaVoteRootEvidence
    ) {
        self.snapshot = snapshot
        self.proof = proof
        self.validatorSet = validatorSet
        self.voteEvidence = voteEvidence
    }

    func verify(maxRootLag: UInt64 = 512) -> SolanaProofVerificationResult {
        guard snapshot.cluster == proof.cluster else {
            return failure("Solana proof cluster does not match the slot/root snapshot.")
        }
        guard snapshot.cluster == validatorSet.cluster,
              snapshot.cluster == voteEvidence.cluster else {
            return failure("Solana vote-root evidence cluster does not match the slot/root snapshot.")
        }
        guard proof.slot <= snapshot.slot else {
            return failure("Solana proof references a future slot.")
        }
        guard validatorSet.validatesHash else {
            return failure("Solana validator set hash is invalid.")
        }
        guard voteEvidence.epoch == validatorSet.epoch else {
            return failure("Solana vote-root evidence uses a different validator epoch.")
        }
        guard voteEvidence.targetRootSlot == snapshot.rootSlot,
              SolanaHex.normalized(voteEvidence.targetBlockhash) == SolanaHex.normalized(snapshot.blockhash),
              voteEvidence.accountRoot == snapshot.accountRoot,
              voteEvidence.transactionStatusRoot == snapshot.transactionStatusRoot else {
            return failure("Solana vote-root evidence is not bound to the slot/root snapshot.")
        }
        guard let snapshotRoot = snapshot.expectedRoot(for: proof.kind),
              SolanaHex.normalized(proof.expectedRoot) == snapshotRoot else {
            return failure("Solana \(proof.kind.rawValue) proof expected root does not match the snapshot root.")
        }
        guard proof.verifiesExpectedRoot else {
            return failure("Solana \(proof.kind.rawValue) proof did not resolve to the expected root.")
        }
        let verifiedVoteAccounts = voteEvidence.verifiedVoteAccounts(validators: validatorSet.validators)
        guard validatorSet.hasRootQuorum(voteAccounts: verifiedVoteAccounts) else {
            return failure("Solana vote-root evidence did not reach the validator stake quorum.")
        }

        return SolanaProofVerificationResult(
            verified: true,
            state: snapshot.isStale(maxRootLag: maxRootLag) ? .proofChecked : .synced,
            proofID: proof.proofID,
            kind: proof.kind,
            chainRef: snapshot.cluster.chainRef,
            slot: proof.slot,
            rootSlot: snapshot.rootSlot,
            summary: "Solana \(proof.kind.rawValue) proof checked at slot \(proof.slot) with Ed25519 vote-root stake quorum."
        )
    }

    private func failure(_ summary: String) -> SolanaProofVerificationResult {
        SolanaProofVerificationResult(
            verified: false,
            state: .failed,
            proofID: proof.proofID,
            kind: proof.kind,
            chainRef: proof.cluster.chainRef,
            slot: proof.slot,
            rootSlot: snapshot.rootSlot,
            summary: summary
        )
    }
}

struct SolanaProofVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: SolanaLightClientSyncState
    var proofID: String
    var kind: SolanaFixtureProofKind
    var chainRef: String
    var slot: UInt64?
    var rootSlot: UInt64?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case proofID = "proof_id"
        case kind
        case chainRef = "chain_ref"
        case slot
        case rootSlot = "root_slot"
        case summary
    }
}

struct SolanaLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var cluster: SolanaCluster
    var syncState: SolanaLightClientSyncState
    var source: String
    var slotRoot: SolanaSlotRootSnapshot?
    var peerCount: Int?
    var proofSource: String?
    var rootLag: UInt64?
    var maxRootLag: UInt64
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case serviceAvailable = "service_available"
        case cluster
        case chainRef = "chain_ref"
        case syncState = "sync_state"
        case source
        case slotRoot = "slot_root"
        case peerCount = "peer_count"
        case proofSource = "proof_source"
        case rootLag = "root_lag"
        case maxRootLag = "max_root_lag"
        case lastError = "last_error"
    }

    nonisolated init(
        serviceAvailable: Bool,
        cluster: SolanaCluster,
        syncState: SolanaLightClientSyncState,
        source: String,
        slotRoot: SolanaSlotRootSnapshot? = nil,
        peerCount: Int? = nil,
        proofSource: String? = nil,
        rootLag: UInt64? = nil,
        maxRootLag: UInt64 = 512,
        lastError: String? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.cluster = cluster
        self.syncState = syncState
        self.source = source
        self.slotRoot = slotRoot
        self.peerCount = peerCount
        self.proofSource = proofSource
        self.rootLag = rootLag
        self.maxRootLag = maxRootLag
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? true
        if let cluster = try container.decodeIfPresent(SolanaCluster.self, forKey: .cluster) {
            self.cluster = cluster
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let cluster = SolanaCluster.known(from: chainRef) {
            self.cluster = cluster
        } else {
            self.cluster = .mainnetBeta
        }
        self.syncState = try container.decodeIfPresent(SolanaLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "solana-light-client"
        self.slotRoot = try container.decodeIfPresent(SolanaSlotRootSnapshot.self, forKey: .slotRoot)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.proofSource = try container.decodeIfPresent(String.self, forKey: .proofSource)
        self.rootLag = try container.decodeIfPresent(UInt64.self, forKey: .rootLag)
        self.maxRootLag = try container.decodeIfPresent(UInt64.self, forKey: .maxRootLag) ?? 512
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        if let slotRoot, slotRoot.isStale(maxRootLag: maxRootLag), syncState == .synced {
            self.syncState = .stale
            self.rootLag = slotRoot.rootLag()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceAvailable, forKey: .serviceAvailable)
        try container.encode(cluster, forKey: .cluster)
        try container.encode(cluster.chainRef, forKey: .chainRef)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(slotRoot, forKey: .slotRoot)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(proofSource, forKey: .proofSource)
        try container.encodeIfPresent(rootLag, forKey: .rootLag)
        try container.encode(maxRootLag, forKey: .maxRootLag)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    static func fallback(cluster: SolanaCluster, lastError: String?) -> SolanaLightClientServiceSnapshot {
        SolanaLightClientServiceSnapshot(
            serviceAvailable: false,
            cluster: cluster,
            syncState: .unavailable,
            source: "trusted-rpc-fallback",
            lastError: lastError
        )
    }

    var statusSummary: String {
        switch syncState {
        case .synced:
            return "\(cluster.displayName) slot/root evidence is finalized at root \(slotRoot?.rootSlot.description ?? "unknown")."
        case .proofChecked:
            return "\(cluster.displayName) vote-root proof evidence is locally checked; production Solana consensus replay is not claimed."
        case .syncing:
            return "\(cluster.displayName) slot/root evidence is syncing."
        case .stale:
            return "\(cluster.displayName) slot/root evidence is stale by \(rootLag ?? slotRoot?.rootLag() ?? 0) slot(s)."
        case .failed:
            return "\(cluster.displayName) verification failed: \(lastError ?? "unknown error")."
        case .rpcFallback, .unavailable:
            return "\(cluster.displayName) light-client service is unavailable; trusted RPC fallback remains labeled."
        }
    }

    var chainTrustStatus: ChainTrustStatus {
        let state = syncState.chainTrustState
        let evidence: [ChainTrustEvidence] = state.isProductionEvidence ? [
            ChainTrustEvidence(
                id: "\(cluster.chainRef)-solana-light-client-\(slotRoot?.rootSlot ?? 0)",
                source: state == .verified ? .embeddedLightClient : .localProof,
                summary: statusSummary,
                blockNumber: slotRoot.flatMap { Int($0.rootSlot) },
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
            chainID: cluster.chainRef,
            chainRef: cluster.chainRef,
            displayName: cluster.displayName,
            family: .solana,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: cluster.supportedProofTypes,
            latestCheckpoint: slotRoot?.checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

/// Trust boundary (goal: minimize remote trust). A client for a remote light-client/RPC service.
/// Local Solana proof bundles verify account or transaction-status Merkle evidence against an
/// Ed25519 signed vote-root quorum; live state still uses labeled RPC fallback unless a service
/// supplies those bundles.
final class SolanaLightClientServiceClient {
    private let configuration: SolanaLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: SolanaLightClientEndpointConfiguration = .disabled,
        session: URLSession = SolanaLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> SolanaLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(cluster: configuration.cluster, lastError: "Solana light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/solana/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/solana/status")
            } catch {
                return .fallback(cluster: configuration.cluster, lastError: error.localizedDescription)
            }
        }
    }

    func verifyProof(_ proof: SolanaProofBundle) -> SolanaProofVerificationResult {
        proof.verify()
    }

    func verifyProofViaService(_ proof: SolanaProofBundle) async throws -> SolanaProofVerificationResult {
        do {
            return try await post(path: "/v1/solana/verify-proof", body: proof)
        } catch {
            return try await post(path: "/solana/verify-proof", body: proof)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> SolanaLightClientServiceSnapshot {
        var snapshot: SolanaLightClientServiceSnapshot = try await get(path: path)
        if snapshot.cluster != configuration.cluster {
            snapshot.cluster = configuration.cluster
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
            queryItems: [URLQueryItem(name: "cluster", value: configuration.cluster.rawValue)]
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

enum SolanaHex {
    nonisolated static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

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
