import CryptoKit
import Foundation

enum CosmosChain: String, Codable, Equatable, CaseIterable {
    case cosmosHub = "cosmoshub-4"
    case osmosis = "osmosis-1"
    case juno = "juno-1"
    case localnet = "cosmos-localnet"

    nonisolated var chainID: String { rawValue }

    nonisolated var chainRef: String {
        switch self {
        case .cosmosHub: "cosmos-hub"
        case .osmosis: "osmosis"
        case .juno: "juno"
        case .localnet: "cosmos-localnet"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .cosmosHub: "Cosmos Hub"
        case .osmosis: "Osmosis"
        case .juno: "Juno"
        case .localnet: "Cosmos Localnet"
        }
    }

    nonisolated var bech32Prefix: String {
        switch self {
        case .cosmosHub: "cosmos"
        case .osmosis: "osmo"
        case .juno: "juno"
        case .localnet: "cosmos"
        }
    }

    nonisolated var trustPeriodSeconds: Int {
        switch self {
        case .cosmosHub, .osmosis, .juno: 1_209_600
        case .localnet: 86_400
        }
    }

    nonisolated var supportedProofTypes: [String] {
        ["tendermint-header", "validator-set", "commit-signature", "ics23-query-proof"]
    }

    nonisolated static func known(from value: String) -> CosmosChain? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "cosmos", "cosmoshub", "cosmoshub-4", "cosmos-hub", "cosmos-mainnet":
            return .cosmosHub
        case "osmosis", "osmosis-1", "osmo":
            return .osmosis
        case "juno", "juno-1":
            return .juno
        case "cosmos-localnet", "localnet":
            return .localnet
        default:
            return nil
        }
    }
}

enum TendermintLightClientSyncState: String, Codable, Equatable, CaseIterable {
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

struct CosmosLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var chain: CosmosChain

    nonisolated static let local = CosmosLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        chain: .cosmosHub
    )

    nonisolated static let disabled = CosmosLightClientEndpointConfiguration(
        baseURL: nil,
        chain: .cosmosHub
    )
}

struct TendermintValidator: Codable, Equatable, Identifiable {
    var id: String { address }

    var address: String
    var publicKey: String?
    var votingPower: Int
    var name: String?

    private enum CodingKeys: String, CodingKey {
        case address
        case publicKey = "public_key"
        case votingPower = "voting_power"
        case name
    }

    nonisolated init(
        address: String,
        publicKey: String? = nil,
        votingPower: Int,
        name: String? = nil
    ) {
        self.address = TendermintHex.normalized(address)
        self.publicKey = publicKey
        self.votingPower = votingPower
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.address = TendermintHex.normalized(try container.decode(String.self, forKey: .address))
        self.publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)
        self.votingPower = try container.decode(Int.self, forKey: .votingPower)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct TendermintValidatorSet: Codable, Equatable, Identifiable {
    var id: String { "\(chain.chainRef)-validators-\(height)" }

    var chain: CosmosChain
    var height: Int
    var validators: [TendermintValidator]
    var hash: String
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case chain
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case height
        case validators
        case hash
        case source
    }

    nonisolated init(
        chain: CosmosChain,
        height: Int,
        validators: [TendermintValidator],
        hash: String? = nil,
        source: String? = nil
    ) {
        self.chain = chain
        self.height = height
        self.validators = validators
        self.hash = TendermintHex.normalized(hash ?? Self.computeHash(validators: validators))
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let chain = try container.decodeIfPresent(CosmosChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = CosmosChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainID = try container.decodeIfPresent(String.self, forKey: .chainID),
                  let chain = CosmosChain.known(from: chainID) {
            self.chain = chain
        } else {
            self.chain = .cosmosHub
        }
        self.height = try container.decode(Int.self, forKey: .height)
        self.validators = try container.decode([TendermintValidator].self, forKey: .validators)
        self.hash = TendermintHex.normalized(try container.decodeIfPresent(String.self, forKey: .hash) ?? Self.computeHash(validators: validators))
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainID, forKey: .chainID)
        try container.encode(height, forKey: .height)
        try container.encode(validators, forKey: .validators)
        try container.encode(hash, forKey: .hash)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var totalVotingPower: Int {
        validators.reduce(0) { $0 + max(0, $1.votingPower) }
    }

    var validatesHash: Bool {
        hash == Self.computeHash(validators: validators)
    }

    func signedVotingPower(addresses: Set<String>) -> Int {
        validators.reduce(0) { partial, validator in
            addresses.contains(TendermintHex.normalized(validator.address)) ? partial + max(0, validator.votingPower) : partial
        }
    }

    func hasTwoThirdsPower(addresses: Set<String>) -> Bool {
        let signedPower = signedVotingPower(addresses: addresses)
        return signedPower * 3 > totalVotingPower * 2
    }

    nonisolated static func computeHash(validators: [TendermintValidator]) -> String {
        let payload = validators
            .map { "\(TendermintHex.normalized($0.address)):\($0.votingPower)" }
            .sorted()
            .joined(separator: "|")
        return TendermintHex.sha256Hex(payload)
    }
}

struct TendermintHeader: Codable, Equatable, Identifiable {
    var id: String { "\(chain.chainRef)-\(height)" }

    var chain: CosmosChain
    var height: Int
    var timeUnixSeconds: Int
    var lastBlockIDHash: String
    var validatorsHash: String
    var nextValidatorsHash: String
    var appHash: String
    var dataHash: String?
    var evidenceHash: String?
    var proposerAddress: String
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case chain
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case height
        case timeUnixSeconds = "time_unix_seconds"
        case lastBlockIDHash = "last_block_id_hash"
        case validatorsHash = "validators_hash"
        case nextValidatorsHash = "next_validators_hash"
        case appHash = "app_hash"
        case dataHash = "data_hash"
        case evidenceHash = "evidence_hash"
        case proposerAddress = "proposer_address"
        case source
    }

    nonisolated init(
        chain: CosmosChain,
        height: Int,
        timeUnixSeconds: Int,
        lastBlockIDHash: String,
        validatorsHash: String,
        nextValidatorsHash: String,
        appHash: String,
        dataHash: String? = nil,
        evidenceHash: String? = nil,
        proposerAddress: String,
        source: String? = nil
    ) {
        self.chain = chain
        self.height = height
        self.timeUnixSeconds = timeUnixSeconds
        self.lastBlockIDHash = TendermintHex.normalized(lastBlockIDHash)
        self.validatorsHash = TendermintHex.normalized(validatorsHash)
        self.nextValidatorsHash = TendermintHex.normalized(nextValidatorsHash)
        self.appHash = TendermintHex.normalized(appHash)
        self.dataHash = dataHash.map(TendermintHex.normalized)
        self.evidenceHash = evidenceHash.map(TendermintHex.normalized)
        self.proposerAddress = TendermintHex.normalized(proposerAddress)
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let chain = try container.decodeIfPresent(CosmosChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = CosmosChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainID = try container.decodeIfPresent(String.self, forKey: .chainID),
                  let chain = CosmosChain.known(from: chainID) {
            self.chain = chain
        } else {
            self.chain = .cosmosHub
        }
        self.height = try container.decode(Int.self, forKey: .height)
        self.timeUnixSeconds = try container.decode(Int.self, forKey: .timeUnixSeconds)
        self.lastBlockIDHash = TendermintHex.normalized(try container.decode(String.self, forKey: .lastBlockIDHash))
        self.validatorsHash = TendermintHex.normalized(try container.decode(String.self, forKey: .validatorsHash))
        self.nextValidatorsHash = TendermintHex.normalized(try container.decode(String.self, forKey: .nextValidatorsHash))
        self.appHash = TendermintHex.normalized(try container.decode(String.self, forKey: .appHash))
        self.dataHash = try container.decodeIfPresent(String.self, forKey: .dataHash).map(TendermintHex.normalized)
        self.evidenceHash = try container.decodeIfPresent(String.self, forKey: .evidenceHash).map(TendermintHex.normalized)
        self.proposerAddress = TendermintHex.normalized(try container.decode(String.self, forKey: .proposerAddress))
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainID, forKey: .chainID)
        try container.encode(height, forKey: .height)
        try container.encode(timeUnixSeconds, forKey: .timeUnixSeconds)
        try container.encode(lastBlockIDHash, forKey: .lastBlockIDHash)
        try container.encode(validatorsHash, forKey: .validatorsHash)
        try container.encode(nextValidatorsHash, forKey: .nextValidatorsHash)
        try container.encode(appHash, forKey: .appHash)
        try container.encodeIfPresent(dataHash, forKey: .dataHash)
        try container.encodeIfPresent(evidenceHash, forKey: .evidenceHash)
        try container.encode(proposerAddress, forKey: .proposerAddress)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var hash: String {
        Self.computeHash(
            chainID: chain.chainID,
            height: height,
            timeUnixSeconds: timeUnixSeconds,
            lastBlockIDHash: lastBlockIDHash,
            validatorsHash: validatorsHash,
            nextValidatorsHash: nextValidatorsHash,
            appHash: appHash,
            dataHash: dataHash,
            evidenceHash: evidenceHash,
            proposerAddress: proposerAddress
        )
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: height,
            blockHash: hash,
            checkpointID: "\(chain.chainRef)-height-\(height)",
            updatedAt: Date(timeIntervalSince1970: TimeInterval(timeUnixSeconds))
        )
    }

    nonisolated static func computeHash(
        chainID: String,
        height: Int,
        timeUnixSeconds: Int,
        lastBlockIDHash: String,
        validatorsHash: String,
        nextValidatorsHash: String,
        appHash: String,
        dataHash: String?,
        evidenceHash: String?,
        proposerAddress: String
    ) -> String {
        TendermintHex.sha256Hex([
            chainID,
            "\(height)",
            "\(timeUnixSeconds)",
            TendermintHex.normalized(lastBlockIDHash),
            TendermintHex.normalized(validatorsHash),
            TendermintHex.normalized(nextValidatorsHash),
            TendermintHex.normalized(appHash),
            dataHash.map(TendermintHex.normalized) ?? "",
            evidenceHash.map(TendermintHex.normalized) ?? "",
            TendermintHex.normalized(proposerAddress)
        ].joined(separator: "|"))
    }
}

struct TendermintCommitSignature: Codable, Equatable, Identifiable {
    var id: String { validatorAddress }

    var validatorAddress: String
    var blockIDHash: String
    var signed: Bool
    var signature: String?

    private enum CodingKeys: String, CodingKey {
        case validatorAddress = "validator_address"
        case blockIDHash = "block_id_hash"
        case signed
        case signature
    }

    nonisolated init(
        validatorAddress: String,
        blockIDHash: String,
        signed: Bool = true,
        signature: String? = nil
    ) {
        self.validatorAddress = TendermintHex.normalized(validatorAddress)
        self.blockIDHash = TendermintHex.normalized(blockIDHash)
        self.signed = signed
        self.signature = signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.validatorAddress = TendermintHex.normalized(try container.decode(String.self, forKey: .validatorAddress))
        self.blockIDHash = TendermintHex.normalized(try container.decode(String.self, forKey: .blockIDHash))
        self.signed = try container.decodeIfPresent(Bool.self, forKey: .signed) ?? true
        self.signature = try container.decodeIfPresent(String.self, forKey: .signature)
    }
}

struct TendermintCommit: Codable, Equatable {
    var height: Int
    var round: Int
    var blockIDHash: String
    var signatures: [TendermintCommitSignature]
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case height
        case round
        case blockIDHash = "block_id_hash"
        case signatures
        case source
    }

    nonisolated init(
        height: Int,
        round: Int,
        blockIDHash: String,
        signatures: [TendermintCommitSignature],
        source: String? = nil
    ) {
        self.height = height
        self.round = round
        self.blockIDHash = TendermintHex.normalized(blockIDHash)
        self.signatures = signatures
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.height = try container.decode(Int.self, forKey: .height)
        self.round = try container.decodeIfPresent(Int.self, forKey: .round) ?? 0
        self.blockIDHash = TendermintHex.normalized(try container.decode(String.self, forKey: .blockIDHash))
        self.signatures = try container.decode([TendermintCommitSignature].self, forKey: .signatures)
        self.source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    var signedAddresses: Set<String> {
        Set(signatures.filter(\.signed).map { TendermintHex.normalized($0.validatorAddress) })
    }
}

struct TendermintTrustPolicy: Codable, Equatable {
    var trustedHeight: Int
    var trustedTimeUnixSeconds: Int
    var trustPeriodSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case trustedHeight = "trusted_height"
        case trustedTimeUnixSeconds = "trusted_time_unix_seconds"
        case trustPeriodSeconds = "trust_period_seconds"
    }

    nonisolated init(
        trustedHeight: Int,
        trustedTimeUnixSeconds: Int,
        trustPeriodSeconds: Int
    ) {
        self.trustedHeight = trustedHeight
        self.trustedTimeUnixSeconds = trustedTimeUnixSeconds
        self.trustPeriodSeconds = trustPeriodSeconds
    }

    nonisolated func isExpired(at nowUnixSeconds: Int) -> Bool {
        nowUnixSeconds > trustedTimeUnixSeconds + trustPeriodSeconds
    }
}

struct TendermintHeaderVerificationBundle: Codable, Equatable {
    var header: TendermintHeader
    var validatorSet: TendermintValidatorSet
    var commit: TendermintCommit
    var trustPolicy: TendermintTrustPolicy
    var conflictingCommit: TendermintCommit?

    private enum CodingKeys: String, CodingKey {
        case header
        case validatorSet = "validator_set"
        case commit
        case trustPolicy = "trust_policy"
        case conflictingCommit = "conflicting_commit"
    }

    func verify(nowUnixSeconds: Int) -> CosmosHeaderVerificationResult {
        guard header.chain == validatorSet.chain else {
            return failure("Tendermint header chain does not match validator set chain.")
        }
        guard header.height == commit.height else {
            return failure("Tendermint commit height does not match the header height.")
        }
        guard TendermintHex.normalized(commit.blockIDHash) == header.hash else {
            return failure("Tendermint commit signed a different block ID.")
        }
        guard TendermintHex.normalized(header.validatorsHash) == TendermintHex.normalized(validatorSet.hash),
              validatorSet.validatesHash else {
            return failure("Tendermint validator set hash does not match the header.")
        }
        if trustPolicy.isExpired(at: nowUnixSeconds) {
            return CosmosHeaderVerificationResult(
                verified: false,
                state: .stale,
                chainRef: header.chain.chainRef,
                chainID: header.chain.chainID,
                height: header.height,
                blockHash: header.hash,
                validatorSetHash: validatorSet.hash,
                summary: "Tendermint trusted period expired before this header could be verified."
            )
        }
        if let conflictingCommit,
           conflictingCommit.height == commit.height,
           TendermintHex.normalized(conflictingCommit.blockIDHash) != TendermintHex.normalized(commit.blockIDHash),
           validatorSet.hasTwoThirdsPower(addresses: conflictingCommit.signedAddresses) {
            return CosmosHeaderVerificationResult(
                verified: false,
                state: .failed,
                chainRef: header.chain.chainRef,
                chainID: header.chain.chainID,
                height: header.height,
                blockHash: header.hash,
                validatorSetHash: validatorSet.hash,
                summary: "Conflicting Tendermint commits both reached the voting-power threshold."
            )
        }
        guard validatorSet.hasTwoThirdsPower(addresses: commit.signedAddresses) else {
            return failure("Tendermint commit did not reach the two-thirds voting-power threshold.")
        }

        return CosmosHeaderVerificationResult(
            verified: true,
            state: .synced,
            chainRef: header.chain.chainRef,
            chainID: header.chain.chainID,
            height: header.height,
            blockHash: header.hash,
            validatorSetHash: validatorSet.hash,
            summary: "Tendermint header \(header.height) verified with two-thirds validator power."
        )
    }

    private func failure(_ summary: String) -> CosmosHeaderVerificationResult {
        CosmosHeaderVerificationResult(
            verified: false,
            state: .failed,
            chainRef: header.chain.chainRef,
            chainID: header.chain.chainID,
            height: header.height,
            blockHash: header.hash,
            validatorSetHash: validatorSet.hash,
            summary: summary
        )
    }
}

struct CosmosHeaderVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: TendermintLightClientSyncState
    var chainRef: String
    var chainID: String
    var height: Int?
    var blockHash: String?
    var validatorSetHash: String?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case height
        case blockHash = "block_hash"
        case validatorSetHash = "validator_set_hash"
        case summary
    }
}

struct CosmosLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var chain: CosmosChain
    var syncState: TendermintLightClientSyncState
    var source: String
    var latestHeader: TendermintHeader?
    var validatorSet: TendermintValidatorSet?
    var peerCount: Int?
    var proofSource: String?
    var trustPeriodExpired: Bool
    var trustExpiresAtUnixSeconds: Int?
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case serviceAvailable = "service_available"
        case chain
        case chainRef = "chain_ref"
        case chainID = "chain_id"
        case syncState = "sync_state"
        case source
        case latestHeader = "latest_header"
        case validatorSet = "validator_set"
        case peerCount = "peer_count"
        case proofSource = "proof_source"
        case trustPeriodExpired = "trust_period_expired"
        case trustExpiresAtUnixSeconds = "trust_expires_at_unix_seconds"
        case lastError = "last_error"
    }

    nonisolated init(
        serviceAvailable: Bool,
        chain: CosmosChain,
        syncState: TendermintLightClientSyncState,
        source: String,
        latestHeader: TendermintHeader? = nil,
        validatorSet: TendermintValidatorSet? = nil,
        peerCount: Int? = nil,
        proofSource: String? = nil,
        trustPeriodExpired: Bool = false,
        trustExpiresAtUnixSeconds: Int? = nil,
        lastError: String? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.chain = chain
        self.syncState = trustPeriodExpired && syncState == .synced ? .stale : syncState
        self.source = source
        self.latestHeader = latestHeader
        self.validatorSet = validatorSet
        self.peerCount = peerCount
        self.proofSource = proofSource
        self.trustPeriodExpired = trustPeriodExpired
        self.trustExpiresAtUnixSeconds = trustExpiresAtUnixSeconds
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? true
        if let chain = try container.decodeIfPresent(CosmosChain.self, forKey: .chain) {
            self.chain = chain
        } else if let chainRef = try container.decodeIfPresent(String.self, forKey: .chainRef),
                  let chain = CosmosChain.known(from: chainRef) {
            self.chain = chain
        } else if let chainID = try container.decodeIfPresent(String.self, forKey: .chainID),
                  let chain = CosmosChain.known(from: chainID) {
            self.chain = chain
        } else {
            self.chain = .cosmosHub
        }
        self.syncState = try container.decodeIfPresent(TendermintLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "cosmos-tendermint-light-client"
        self.latestHeader = try container.decodeIfPresent(TendermintHeader.self, forKey: .latestHeader)
        self.validatorSet = try container.decodeIfPresent(TendermintValidatorSet.self, forKey: .validatorSet)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.proofSource = try container.decodeIfPresent(String.self, forKey: .proofSource)
        self.trustPeriodExpired = try container.decodeIfPresent(Bool.self, forKey: .trustPeriodExpired) ?? false
        self.trustExpiresAtUnixSeconds = try container.decodeIfPresent(Int.self, forKey: .trustExpiresAtUnixSeconds)
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        if trustPeriodExpired, syncState == .synced {
            self.syncState = .stale
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceAvailable, forKey: .serviceAvailable)
        try container.encode(chain, forKey: .chain)
        try container.encode(chain.chainRef, forKey: .chainRef)
        try container.encode(chain.chainID, forKey: .chainID)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(latestHeader, forKey: .latestHeader)
        try container.encodeIfPresent(validatorSet, forKey: .validatorSet)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(proofSource, forKey: .proofSource)
        try container.encode(trustPeriodExpired, forKey: .trustPeriodExpired)
        try container.encodeIfPresent(trustExpiresAtUnixSeconds, forKey: .trustExpiresAtUnixSeconds)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    static func fallback(chain: CosmosChain, lastError: String?) -> CosmosLightClientServiceSnapshot {
        CosmosLightClientServiceSnapshot(
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
            return "\(chain.displayName) Tendermint header \(latestHeader?.height.description ?? "unknown") is locally verified."
        case .proofChecked:
            return "\(chain.displayName) Tendermint fixture evidence is locally checked; production peer verification is not claimed."
        case .syncing:
            return "\(chain.displayName) Tendermint light-client evidence is syncing."
        case .stale:
            return "\(chain.displayName) Tendermint trust period is expired or stale."
        case .failed:
            return "\(chain.displayName) Tendermint verification failed: \(lastError ?? "unknown error")."
        case .rpcFallback, .unavailable:
            return "\(chain.displayName) light-client service is unavailable; trusted RPC fallback remains labeled."
        }
    }

    var chainTrustStatus: ChainTrustStatus {
        let state = syncState.chainTrustState
        let evidence: [ChainTrustEvidence] = state.isProductionEvidence ? [
            ChainTrustEvidence(
                id: "\(chain.chainRef)-tendermint-\(latestHeader?.height ?? 0)",
                source: state == .verified ? .embeddedLightClient : .localProof,
                summary: statusSummary,
                blockNumber: latestHeader?.height,
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
            family: .cosmosTendermint,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: chain.supportedProofTypes,
            latestCheckpoint: latestHeader?.checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

/// Trust boundary (goal: minimize remote trust). A client for a remote light-client/RPC service.
/// It DOES perform Tendermint header verification (trusted period + validator set) where a
/// verification bundle is supplied, but otherwise serves state via RPC fallback (`.rpcFallback`)
/// rather than local verification. Target: extend real header verification to the default path.
final class CosmosLightClientServiceClient {
    private let configuration: CosmosLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: CosmosLightClientEndpointConfiguration = .disabled,
        session: URLSession = CosmosLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> CosmosLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(chain: configuration.chain, lastError: "Cosmos/Tendermint light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/cosmos/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/cosmos/status")
            } catch {
                return .fallback(chain: configuration.chain, lastError: error.localizedDescription)
            }
        }
    }

    func verifyHeader(_ bundle: TendermintHeaderVerificationBundle, nowUnixSeconds: Int) -> CosmosHeaderVerificationResult {
        bundle.verify(nowUnixSeconds: nowUnixSeconds)
    }

    func verifyHeaderViaService(_ bundle: TendermintHeaderVerificationBundle) async throws -> CosmosHeaderVerificationResult {
        do {
            return try await post(path: "/v1/cosmos/verify-header", body: bundle)
        } catch {
            return try await post(path: "/cosmos/verify-header", body: bundle)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> CosmosLightClientServiceSnapshot {
        var snapshot: CosmosLightClientServiceSnapshot = try await get(path: path)
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
            queryItems: [URLQueryItem(name: "chain", value: configuration.chain.chainID)]
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

enum TendermintHex {
    nonisolated static func normalized(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("0x") {
            normalized.removeFirst(2)
        }
        return normalized
    }

    nonisolated static func sha256Hex(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).map { String(format: "%02x", $0) }.joined()
    }
}
