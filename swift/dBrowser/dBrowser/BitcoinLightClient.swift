import CryptoKit
import Foundation

enum BitcoinNetwork: String, Codable, Equatable, CaseIterable {
    case mainnet
    case testnet
    case signet
    case regtest

    var title: String {
        switch self {
        case .mainnet: "Bitcoin"
        case .testnet: "Bitcoin Testnet"
        case .signet: "Bitcoin Signet"
        case .regtest: "Bitcoin Regtest"
        }
    }

    var chainRef: String {
        switch self {
        case .mainnet: "bitcoin-mainnet"
        case .testnet: "bitcoin-testnet"
        case .signet: "bitcoin-signet"
        case .regtest: "bitcoin-regtest"
        }
    }
}

enum BitcoinLightClientSyncState: String, Codable, Equatable, CaseIterable {
    case unavailable
    case syncing
    case synced
    case stale
    case reorg
    case failed

    var chainTrustState: ChainTrustState {
        switch self {
        case .unavailable:
            return .rpcFallback
        case .syncing, .reorg:
            return .syncing
        case .synced:
            return .verified
        case .stale:
            return .stale
        case .failed:
            return .failed
        }
    }
}

enum BitcoinHeaderSyncTransition: String, Codable, Equatable {
    case accepted
    case duplicate
    case orphan
    case stale
    case reorg
    case rejected
}

enum BitcoinMerkleSiblingPosition: String, Codable, Equatable {
    case left
    case right
}

struct BitcoinLightClientEndpointConfiguration: Equatable {
    var baseURL: URL?
    var network: BitcoinNetwork

    nonisolated static let local = BitcoinLightClientEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4870")!,
        network: .mainnet
    )

    nonisolated static let disabled = BitcoinLightClientEndpointConfiguration(
        baseURL: nil,
        network: .mainnet
    )
}

struct BitcoinBlockHeader: Codable, Equatable, Identifiable {
    var id: String { validatedHash }

    var height: Int
    var version: Int32
    var previousBlockHash: String
    var merkleRoot: String
    var timestamp: UInt32
    var bits: UInt32
    var nonce: UInt32
    var hash: String?
    var chainWork: String?
    var source: String?

    private enum CodingKeys: String, CodingKey {
        case height
        case version
        case previousBlockHash = "previous_block_hash"
        case merkleRoot = "merkle_root"
        case timestamp
        case bits
        case nonce
        case hash
        case chainWork = "chain_work"
        case source
    }

    nonisolated init(
        height: Int,
        version: Int32,
        previousBlockHash: String,
        merkleRoot: String,
        timestamp: UInt32,
        bits: UInt32,
        nonce: UInt32,
        hash: String? = nil,
        chainWork: String? = nil,
        source: String? = nil
    ) {
        self.height = height
        self.version = version
        self.previousBlockHash = previousBlockHash
        self.merkleRoot = merkleRoot
        self.timestamp = timestamp
        self.bits = bits
        self.nonce = nonce
        self.hash = hash
        self.chainWork = chainWork
        self.source = source
    }

    var computedHash: String {
        let digest = Self.doubleSHA256(serializedHeader)
        return BitcoinHex.displayHex(fromLittleEndianData: digest)
    }

    var validatedHash: String {
        BitcoinHex.normalized(hash ?? computedHash)
    }

    var checkpoint: ChainTrustCheckpoint {
        ChainTrustCheckpoint(
            height: height,
            blockHash: validatedHash,
            checkpointID: "bitcoin-header-\(height)",
            updatedAt: Date(timeIntervalSince1970: TimeInterval(timestamp))
        )
    }

    var validatesAdvertisedHash: Bool {
        guard let hash else { return true }
        return BitcoinHex.normalized(hash) == computedHash
    }

    private var serializedHeader: Data {
        var data = Data()
        var littleEndianVersion = UInt32(bitPattern: version).littleEndian
        withUnsafeBytes(of: &littleEndianVersion) { data.append(contentsOf: $0) }
        if let previous = BitcoinHex.littleEndianData(fromDisplayHex: previousBlockHash) {
            data.append(previous)
        }
        if let merkle = BitcoinHex.littleEndianData(fromDisplayHex: merkleRoot) {
            data.append(merkle)
        }
        var littleEndianTimestamp = timestamp.littleEndian
        withUnsafeBytes(of: &littleEndianTimestamp) { data.append(contentsOf: $0) }
        var littleEndianBits = bits.littleEndian
        withUnsafeBytes(of: &littleEndianBits) { data.append(contentsOf: $0) }
        var littleEndianNonce = nonce.littleEndian
        withUnsafeBytes(of: &littleEndianNonce) { data.append(contentsOf: $0) }
        return data
    }

    nonisolated static var mainnetGenesis: BitcoinBlockHeader {
        BitcoinBlockHeader(
            height: 0,
            version: 1,
            previousBlockHash: String(repeating: "0", count: 64),
            merkleRoot: "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
            timestamp: 1_231_006_505,
            bits: 0x1d00ffff,
            nonce: 2_083_236_893,
            hash: "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
            chainWork: "0000000000000000000000000000000000000000000000000000000100010001",
            source: "fixture"
        )
    }

    static func doubleSHA256(_ data: Data) -> Data {
        let first = Data(SHA256.hash(data: data))
        return Data(SHA256.hash(data: first))
    }
}

struct BitcoinMerkleProofSibling: Codable, Equatable {
    var hash: String
    var position: BitcoinMerkleSiblingPosition
}

struct BitcoinMerkleProof: Codable, Equatable {
    var transactionID: String
    var blockHash: String
    var merkleRoot: String
    var transactionIndex: Int
    var siblings: [BitcoinMerkleProofSibling]

    private enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case blockHash = "block_hash"
        case merkleRoot = "merkle_root"
        case transactionIndex = "transaction_index"
        case siblings
    }

    nonisolated init(
        transactionID: String,
        blockHash: String,
        merkleRoot: String,
        transactionIndex: Int,
        siblings: [BitcoinMerkleProofSibling]
    ) {
        self.transactionID = transactionID
        self.blockHash = blockHash
        self.merkleRoot = merkleRoot
        self.transactionIndex = transactionIndex
        self.siblings = siblings
    }

    var computedMerkleRoot: String? {
        guard var node = BitcoinHex.littleEndianData(fromDisplayHex: transactionID) else { return nil }

        for sibling in siblings {
            guard let siblingHash = BitcoinHex.littleEndianData(fromDisplayHex: sibling.hash) else { return nil }
            var pair = Data()
            switch sibling.position {
            case .left:
                pair.append(siblingHash)
                pair.append(node)
            case .right:
                pair.append(node)
                pair.append(siblingHash)
            }
            node = BitcoinBlockHeader.doubleSHA256(pair)
        }

        return BitcoinHex.displayHex(fromLittleEndianData: node)
    }

    var verifiesMerkleRoot: Bool {
        computedMerkleRoot == BitcoinHex.normalized(merkleRoot)
    }
}

struct BitcoinTransactionInclusionProof: Codable, Equatable {
    var header: BitcoinBlockHeader
    var proof: BitcoinMerkleProof

    func verify() -> BitcoinTransactionVerificationResult {
        guard header.validatesAdvertisedHash else {
            return BitcoinTransactionVerificationResult(
                verified: false,
                state: .failed,
                transactionID: proof.transactionID,
                blockHash: proof.blockHash,
                height: header.height,
                summary: "Bitcoin header hash does not match its serialized header."
            )
        }

        guard BitcoinHex.normalized(proof.blockHash) == header.validatedHash else {
            return BitcoinTransactionVerificationResult(
                verified: false,
                state: .failed,
                transactionID: proof.transactionID,
                blockHash: proof.blockHash,
                height: header.height,
                summary: "Bitcoin Merkle proof references a different block hash."
            )
        }

        guard BitcoinHex.normalized(proof.merkleRoot) == BitcoinHex.normalized(header.merkleRoot),
              proof.verifiesMerkleRoot else {
            return BitcoinTransactionVerificationResult(
                verified: false,
                state: .failed,
                transactionID: proof.transactionID,
                blockHash: proof.blockHash,
                height: header.height,
                summary: "Bitcoin Merkle proof did not resolve to the header Merkle root."
            )
        }

        return BitcoinTransactionVerificationResult(
            verified: true,
            state: .synced,
            transactionID: proof.transactionID,
            blockHash: header.validatedHash,
            height: header.height,
            summary: "Bitcoin transaction inclusion verified against header \(header.height)."
        )
    }
}

struct BitcoinTransactionVerificationResult: Codable, Equatable {
    var verified: Bool
    var state: BitcoinLightClientSyncState
    var transactionID: String
    var blockHash: String
    var height: Int?
    var summary: String

    private enum CodingKeys: String, CodingKey {
        case verified
        case state
        case transactionID = "transaction_id"
        case blockHash = "block_hash"
        case height
        case summary
    }
}

struct BitcoinHeaderSyncResult: Equatable {
    var transition: BitcoinHeaderSyncTransition
    var state: BitcoinLightClientSyncState
    var activeTip: BitcoinBlockHeader?
    var reorgDepth: Int
    var message: String
}

struct BitcoinHeaderChainTracker: Equatable {
    private(set) var headersByHash: [String: BitcoinBlockHeader]
    private(set) var activeTip: BitcoinBlockHeader?

    init(anchor: BitcoinBlockHeader? = nil) {
        if let anchor {
            self.headersByHash = [anchor.validatedHash: anchor]
            self.activeTip = anchor
        } else {
            self.headersByHash = [:]
            self.activeTip = nil
        }
    }

    mutating func apply(_ header: BitcoinBlockHeader) -> BitcoinHeaderSyncResult {
        guard header.validatesAdvertisedHash else {
            return BitcoinHeaderSyncResult(
                transition: .rejected,
                state: .failed,
                activeTip: activeTip,
                reorgDepth: 0,
                message: "Rejected Bitcoin header \(header.height) because its advertised hash is invalid."
            )
        }

        let headerHash = header.validatedHash
        if headersByHash[headerHash] != nil {
            return BitcoinHeaderSyncResult(
                transition: .duplicate,
                state: .synced,
                activeTip: activeTip,
                reorgDepth: 0,
                message: "Ignored duplicate Bitcoin header \(header.height)."
            )
        }
        headersByHash[headerHash] = header

        guard let activeTip else {
            self.activeTip = header
            return BitcoinHeaderSyncResult(
                transition: .accepted,
                state: .synced,
                activeTip: header,
                reorgDepth: 0,
                message: "Accepted Bitcoin header \(header.height) as the active tip."
            )
        }

        if BitcoinHex.normalized(header.previousBlockHash) == activeTip.validatedHash {
            self.activeTip = header
            return BitcoinHeaderSyncResult(
                transition: .accepted,
                state: .synced,
                activeTip: header,
                reorgDepth: 0,
                message: "Extended Bitcoin active chain to height \(header.height)."
            )
        }

        guard let previousHeader = headersByHash[BitcoinHex.normalized(header.previousBlockHash)] else {
            return BitcoinHeaderSyncResult(
                transition: .orphan,
                state: .syncing,
                activeTip: activeTip,
                reorgDepth: 0,
                message: "Stored Bitcoin orphan header \(header.height) while waiting for parent \(header.previousBlockHash)."
            )
        }

        if Self.header(header, isStrongerThan: activeTip) {
            self.activeTip = header
            let reorgDepth = max(1, activeTip.height - previousHeader.height)
            return BitcoinHeaderSyncResult(
                transition: .reorg,
                state: .reorg,
                activeTip: header,
                reorgDepth: reorgDepth,
                message: "Bitcoin active chain reorged by \(reorgDepth) block\(reorgDepth == 1 ? "" : "s")."
            )
        }

        return BitcoinHeaderSyncResult(
            transition: .stale,
            state: .stale,
            activeTip: activeTip,
            reorgDepth: 0,
            message: "Stored stale Bitcoin header \(header.height) without changing the active tip."
        )
    }

    private static func header(_ lhs: BitcoinBlockHeader, isStrongerThan rhs: BitcoinBlockHeader) -> Bool {
        if let lhsWork = lhs.chainWork, let rhsWork = rhs.chainWork {
            let comparison = BitcoinHex.compareMagnitude(lhsWork, rhsWork)
            if comparison != .orderedSame {
                return comparison == .orderedDescending
            }
        }
        return lhs.height > rhs.height
    }
}

struct BitcoinLightClientServiceSnapshot: Codable, Equatable {
    var serviceAvailable: Bool
    var network: BitcoinNetwork
    var syncState: BitcoinLightClientSyncState
    var source: String
    var bestHeight: Int?
    var bestBlockHash: String?
    var bestHeader: BitcoinBlockHeader?
    var peerCount: Int?
    var filterSource: String?
    var lastError: String?
    var reorgDepth: Int?

    private enum CodingKeys: String, CodingKey {
        case ok
        case serviceAvailable = "service_available"
        case network
        case syncState = "sync_state"
        case source
        case bestHeight = "best_height"
        case bestBlockHash = "best_block_hash"
        case bestHeader = "best_header"
        case peerCount = "peer_count"
        case filterSource = "filter_source"
        case lastError = "last_error"
        case reorgDepth = "reorg_depth"
    }

    nonisolated init(
        serviceAvailable: Bool,
        network: BitcoinNetwork,
        syncState: BitcoinLightClientSyncState,
        source: String,
        bestHeight: Int? = nil,
        bestBlockHash: String? = nil,
        bestHeader: BitcoinBlockHeader? = nil,
        peerCount: Int? = nil,
        filterSource: String? = nil,
        lastError: String? = nil,
        reorgDepth: Int? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.network = network
        self.syncState = syncState
        self.source = source
        self.bestHeight = bestHeight
        self.bestBlockHash = bestBlockHash
        self.bestHeader = bestHeader
        self.peerCount = peerCount
        self.filterSource = filterSource
        self.lastError = lastError
        self.reorgDepth = reorgDepth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
            ?? container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? true
        self.network = try container.decodeIfPresent(BitcoinNetwork.self, forKey: .network) ?? .mainnet
        self.syncState = try container.decodeIfPresent(BitcoinLightClientSyncState.self, forKey: .syncState) ?? .syncing
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "bitcoin-light-client"
        self.bestHeight = try container.decodeIfPresent(Int.self, forKey: .bestHeight)
        self.bestBlockHash = try container.decodeIfPresent(String.self, forKey: .bestBlockHash)
        self.bestHeader = try container.decodeIfPresent(BitcoinBlockHeader.self, forKey: .bestHeader)
        self.peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount)
        self.filterSource = try container.decodeIfPresent(String.self, forKey: .filterSource)
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        self.reorgDepth = try container.decodeIfPresent(Int.self, forKey: .reorgDepth)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serviceAvailable, forKey: .serviceAvailable)
        try container.encode(network, forKey: .network)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(bestHeight, forKey: .bestHeight)
        try container.encodeIfPresent(bestBlockHash, forKey: .bestBlockHash)
        try container.encodeIfPresent(bestHeader, forKey: .bestHeader)
        try container.encodeIfPresent(peerCount, forKey: .peerCount)
        try container.encodeIfPresent(filterSource, forKey: .filterSource)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encodeIfPresent(reorgDepth, forKey: .reorgDepth)
    }

    static func fallback(network: BitcoinNetwork, lastError: String?) -> BitcoinLightClientServiceSnapshot {
        BitcoinLightClientServiceSnapshot(
            serviceAvailable: false,
            network: network,
            syncState: .unavailable,
            source: "gateway-rpc-fallback",
            lastError: lastError
        )
    }

    var statusSummary: String {
        switch syncState {
        case .synced:
            return "\(network.title) light-client header chain is synced at height \(bestHeight.map(String.init) ?? "unknown")."
        case .syncing:
            return "\(network.title) light-client header chain is syncing."
        case .reorg:
            return "\(network.title) light-client detected a reorg of \(reorgDepth ?? 0) block\(reorgDepth == 1 ? "" : "s")."
        case .stale:
            return "\(network.title) light-client data is stale."
        case .failed:
            return "\(network.title) light-client verification failed: \(lastError ?? "unknown error")."
        case .unavailable:
            return "\(network.title) light-client service is unavailable; Gateway/RPC fallback remains labeled."
        }
    }

    var chainTrustStatus: ChainTrustStatus {
        let state = syncState.chainTrustState
        let checkpoint = ChainTrustCheckpoint(
            height: bestHeight ?? bestHeader?.height,
            blockHash: bestBlockHash ?? bestHeader?.validatedHash,
            checkpointID: "\(network.chainRef)-light-client",
            updatedAt: nil
        )
        let evidence: [ChainTrustEvidence] = state == .verified ? [
            ChainTrustEvidence(
                id: "\(network.chainRef)-light-client-\(checkpoint.blockHash ?? "unknown")",
                source: .embeddedLightClient,
                summary: statusSummary,
                blockNumber: checkpoint.height,
                recordedAt: Date()
            )
        ] : []
        let trustSource: ChainTrustSource
        if state == .verified || state == .syncing || state == .stale {
            trustSource = .embeddedLightClient
        } else if state == .failed {
            trustSource = .unavailable
        } else {
            trustSource = .gatewayRPCFallback
        }

        return ChainTrustStatus(
            chainID: network.chainRef,
            chainRef: network.chainRef,
            displayName: network.title,
            family: .bitcoin,
            state: state,
            trustSource: trustSource,
            supportedProofTypes: ["spv", "compact-filter", "merkle-inclusion"],
            latestCheckpoint: checkpoint.height == nil && checkpoint.blockHash == nil ? nil : checkpoint,
            lastVerificationError: state == .failed ? lastError : nil,
            evidence: evidence,
            lastUpdated: Date()
        )
    }
}

/// Trust boundary (goal: minimize remote trust). Despite the "light client" name, this is a
/// client for a remote light-client/RPC service, not a full node. It DOES validate supplied
/// block-header proof-of-work and hash linkage locally, but it does not yet fetch or prove a
/// header chain to tip itself, so unproven state is labeled `.rpcFallback`/`.gatewayRPCFallback`
/// rather than presented as local consensus verification. Target: end-to-end SPV that removes the
/// RPC fallback.
final class BitcoinLightClientServiceClient {
    private let configuration: BitcoinLightClientEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: BitcoinLightClientEndpointConfiguration = .disabled,
        session: URLSession = BitcoinLightClientServiceClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> BitcoinLightClientServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .fallback(network: configuration.network, lastError: "Bitcoin light-client service is disabled.")
        }

        do {
            return try await normalizedSnapshot(path: "/v1/bitcoin/status")
        } catch {
            do {
                return try await normalizedSnapshot(path: "/bitcoin/status")
            } catch {
                return .fallback(network: configuration.network, lastError: error.localizedDescription)
            }
        }
    }

    func verifyTransactionInclusion(_ proof: BitcoinTransactionInclusionProof) -> BitcoinTransactionVerificationResult {
        proof.verify()
    }

    func verifyTransactionInclusionViaService(
        _ proof: BitcoinTransactionInclusionProof
    ) async throws -> BitcoinTransactionVerificationResult {
        do {
            return try await post(path: "/v1/bitcoin/verify-transaction", body: proof)
        } catch {
            return try await post(path: "/bitcoin/verify-transaction", body: proof)
        }
    }

    private func normalizedSnapshot(path: String) async throws -> BitcoinLightClientServiceSnapshot {
        var snapshot: BitcoinLightClientServiceSnapshot = try await get(path: path)
        if snapshot.network != configuration.network {
            snapshot.network = configuration.network
        }
        return snapshot
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let baseURL = configuration.baseURL else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: Self.url(baseURL: baseURL, path: path))
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

    private static func url(baseURL: URL, path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2.0
        return URLSession(configuration: configuration)
    }
}

private enum BitcoinHex {
    static func normalized(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("0x") {
            normalized.removeFirst(2)
        }
        return normalized
    }

    static func littleEndianData(fromDisplayHex hex: String) -> Data? {
        guard let data = data(from: hex) else { return nil }
        return Data(data.reversed())
    }

    static func displayHex(fromLittleEndianData data: Data) -> String {
        Data(data.reversed()).map { String(format: "%02x", $0) }.joined()
    }

    static func compareMagnitude(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = trimmedMagnitude(lhs)
        let right = trimmedMagnitude(rhs)
        if left.count < right.count { return .orderedAscending }
        if left.count > right.count { return .orderedDescending }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    private static func data(from hex: String) -> Data? {
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

    private static func trimmedMagnitude(_ value: String) -> String {
        let trimmed = normalized(value).drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}
