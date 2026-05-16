import Foundation

struct AFMServiceEndpointConfiguration: Equatable {
    var routerBaseURL: URL
    var registryBaseURL: URL
    var pipelinesBaseURL: URL
    var nodeBaseURL: URL
    var marketplaceBaseURL: URL?
    var routeDefaults: AFMRouteDefaults = .afMarketV1

    nonisolated static let local = AFMServiceEndpointConfiguration(
        routerBaseURL: URL(string: "http://127.0.0.1:4810")!,
        registryBaseURL: URL(string: "http://127.0.0.1:4820")!,
        pipelinesBaseURL: URL(string: "http://127.0.0.1:4830")!,
        nodeBaseURL: URL(string: "http://127.0.0.1:4840")!,
        marketplaceBaseURL: nil
    )
}

struct AFMServiceSnapshot: Equatable {
    var routerAvailable: Bool
    var registryAvailable: Bool
    var pipelinesAvailable: Bool
    var nodeAvailable: Bool
    var marketplaceAvailable: Bool?
    var routerPacks: [AFMPackSummary]
    var registryPacks: [AFMPackSummary]
    var marketplacePacks: [AFMRunnerPack]
    var registryExperts: [AFMExpertRecord]
    var registryBundles: [AFMBundleRecord]

    static let unknown = AFMServiceSnapshot(
        routerAvailable: true,
        registryAvailable: true,
        pipelinesAvailable: true,
        nodeAvailable: true,
        marketplaceAvailable: nil,
        routerPacks: [],
        registryPacks: [],
        marketplacePacks: [],
        registryExperts: [],
        registryBundles: []
    )

    var allServicesAvailable: Bool {
        routerAvailable && registryAvailable && pipelinesAvailable && nodeAvailable
    }

    var coreCopilotServicesAvailable: Bool {
        routerAvailable && pipelinesAvailable
    }

    var serviceStatusText: String {
        var states = [
            "router \(routerAvailable ? "online" : "offline")",
            "registry \(registryAvailable ? "online" : "offline")",
            "pipelines \(pipelinesAvailable ? "online" : "offline")",
            "node \(nodeAvailable ? "online" : "offline")"
        ]
        if let marketplaceAvailable {
            states.append("marketplace \(marketplaceAvailable ? "online" : "offline")")
        }
        return states.joined(separator: ", ")
    }

    var availablePacks: [AFMPackSummary] {
        var packsByID: [String: AFMPackSummary] = [:]
        for pack in routerPacks + registryPacks + registryBundles.map(\.packSummary) + marketplacePacks.map(\.packSummary) {
            packsByID[pack.id] = packsByID[pack.id]?.merged(with: pack) ?? pack
        }
        return packsByID.values.sorted { $0.displayName < $1.displayName }
    }
}

struct AFMPackSummary: Codable, Equatable, Identifiable {
    var id: String
    var name: String?
    var maintainer: String?
    var version: String?
    var checksum: String?
    var skills: [String]?
    var status: String?
    var bundleURL: String?
    var runnerRoot: String?
    var modelID: String?
    var allowedDomains: [String]? = nil
    var maxContext: Int? = nil
    var creatorRoyaltyBPS: Int? = nil
    var dataRoyaltyBPS: Int? = nil
    var signature: String? = nil
    var ownerID: String? = nil
    var createdAtMillis: Int? = nil

    var displayName: String {
        name ?? id
    }

    func merged(with other: AFMPackSummary) -> AFMPackSummary {
        AFMPackSummary(
            id: id,
            name: name ?? other.name,
            maintainer: maintainer ?? other.maintainer,
            version: version ?? other.version,
            checksum: checksum ?? other.checksum,
            skills: skills ?? other.skills,
            status: status ?? other.status,
            bundleURL: bundleURL ?? other.bundleURL,
            runnerRoot: runnerRoot ?? other.runnerRoot,
            modelID: modelID ?? other.modelID,
            allowedDomains: allowedDomains ?? other.allowedDomains,
            maxContext: maxContext ?? other.maxContext,
            creatorRoyaltyBPS: creatorRoyaltyBPS ?? other.creatorRoyaltyBPS,
            dataRoyaltyBPS: dataRoyaltyBPS ?? other.dataRoyaltyBPS,
            signature: signature ?? other.signature,
            ownerID: ownerID ?? other.ownerID,
            createdAtMillis: createdAtMillis ?? other.createdAtMillis
        )
    }
}

struct AFMRunnerPackAFM: Decodable, Equatable {
    var modelID: String

    private enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
    }
}

struct AFMRunnerPackPromptParams: Decodable, Equatable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int

    private enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }
}

struct AFMRunnerPackPrompting: Decodable, Equatable {
    var system: String
    var template: String
    var params: AFMRunnerPackPromptParams
}

struct AFMRunnerPackPolicy: Decodable, Equatable {
    var allowedDomains: [String]
    var maxContext: Int

    private enum CodingKeys: String, CodingKey {
        case allowedDomains = "allowed_domains"
        case maxContext = "max_context"
    }
}

struct AFMRunnerPackRoyalties: Decodable, Equatable {
    var creatorBPS: Int
    var dataBPS: Int?

    private enum CodingKeys: String, CodingKey {
        case creatorBPS = "creator_bps"
        case dataBPS = "data_bps"
    }
}

struct AFMRunnerPackHashes: Decodable, Equatable {
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    var values: [String: String]

    var preferredChecksum: String? {
        values["bundle"] ?? values["manifest"] ?? values["runner_root"] ?? values.values.sorted().first
    }

    init(values: [String: String] = [:]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: String] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                values[key.stringValue] = value
            } else if let value = try? container.decode(Int.self, forKey: key) {
                values[key.stringValue] = "\(value)"
            } else if let value = try? container.decode(Double.self, forKey: key) {
                values[key.stringValue] = "\(value)"
            } else if let value = try? container.decode(Bool.self, forKey: key) {
                values[key.stringValue] = value ? "true" : "false"
            }
        }
        self.values = values
    }
}

struct AFMRunnerPack: Decodable, Equatable, Identifiable {
    var runnerID: String
    var afm: AFMRunnerPackAFM
    var prompting: AFMRunnerPackPrompting
    var policy: AFMRunnerPackPolicy
    var royalties: AFMRunnerPackRoyalties
    var attestation: [String]?
    var capabilityVector: [Double]?
    var hashes: AFMRunnerPackHashes?
    var bundleURL: String?
    var signature: String?
    var runnerRoot: String?
    var ownerID: String?
    var createdAt: Int?

    var id: String { runnerID }

    var packSummary: AFMPackSummary {
        AFMPackSummary(
            id: runnerID,
            name: runnerID,
            maintainer: ownerID,
            version: nil,
            checksum: hashes?.preferredChecksum,
            skills: policy.allowedDomains,
            status: "marketplace",
            bundleURL: bundleURL,
            runnerRoot: runnerRoot,
            modelID: afm.modelID,
            allowedDomains: policy.allowedDomains,
            maxContext: policy.maxContext,
            creatorRoyaltyBPS: royalties.creatorBPS,
            dataRoyaltyBPS: royalties.dataBPS,
            signature: signature,
            ownerID: ownerID,
            createdAtMillis: createdAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case runnerID = "runner_id"
        case afm
        case prompting
        case policy
        case royalties
        case attestation
        case capabilityVector = "capability_vector"
        case hashes
        case bundleURL = "bundle_url"
        case signature
        case runnerRoot = "runner_root"
        case ownerID = "owner_id"
        case createdAt = "created_at"
    }
}

struct AFMExpertRecord: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var payoutAddress: String?
    var nodePublicKey: String?
    var capability: [Double]
    var pricePer1K: Double?
    var latencyP50: Double?
    var tags: [String]
    var baseModel: String?
    var coverage: Double?
    var reputation: Double?
    var stake: Double?
    var attestation: String?
    var ingestURLString: String?
    var profileSignature: String?
    var createdAt: String?
    var updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case payoutAddress = "payoutAddr"
        case nodePublicKey = "nodePub"
        case capability
        case pricePer1K = "pricePer1k"
        case latencyP50
        case tags
        case baseModel
        case coverage
        case reputation
        case stake
        case attestation
        case ingestURLString = "ingestUrl"
        case profileSignature = "profileSig"
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        self.payoutAddress = try container.decodeIfPresent(String.self, forKey: .payoutAddress)
        self.nodePublicKey = try container.decodeIfPresent(String.self, forKey: .nodePublicKey)
        self.capability = try container.decodeIfPresent([Double].self, forKey: .capability) ?? []
        self.pricePer1K = try container.decodeIfPresent(Double.self, forKey: .pricePer1K)
        self.latencyP50 = try container.decodeIfPresent(Double.self, forKey: .latencyP50)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.baseModel = try container.decodeIfPresent(String.self, forKey: .baseModel)
        self.coverage = try container.decodeIfPresent(Double.self, forKey: .coverage)
        self.reputation = try container.decodeIfPresent(Double.self, forKey: .reputation)
        self.stake = try container.decodeIfPresent(Double.self, forKey: .stake)
        self.attestation = try container.decodeIfPresent(String.self, forKey: .attestation)
        self.ingestURLString = try container.decodeIfPresent(String.self, forKey: .ingestURLString)
        self.profileSignature = try container.decodeIfPresent(String.self, forKey: .profileSignature)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct AFMBundleHashes: Codable, Equatable {
    var manifest: String? = nil
    var rag: String? = nil
    var adapter: String? = nil
    var merkle: String? = nil
    var bundle: String? = nil
}

struct AFMBundleRecord: Codable, Equatable, Identifiable {
    var recordID: String?
    var runnerID: String
    var version: String
    var capability: [Double]
    var hashes: AFMBundleHashes
    var attestation: [String]
    var bundleURL: String?
    var runnerRoot: String?
    var bundleSignature: String?
    var createdAt: String?
    var updatedAt: String?

    var id: String { recordID ?? runnerID }

    var packSummary: AFMPackSummary {
        AFMPackSummary(
            id: runnerID,
            name: nil,
            maintainer: nil,
            version: version,
            checksum: hashes.bundle ?? hashes.manifest,
            skills: nil,
            status: "bundle",
            bundleURL: bundleURL,
            runnerRoot: runnerRoot,
            modelID: nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case recordID = "id"
        case runnerID = "runnerId"
        case version
        case capability
        case hashes
        case attestation
        case bundleURL = "bundleUrl"
        case runnerRoot = "runner_root"
        case bundleSignature = "bundleSig"
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.recordID = try container.decodeIfPresent(String.self, forKey: .recordID)
        self.runnerID = try container.decode(String.self, forKey: .runnerID)
        self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? "default"
        self.capability = try container.decodeIfPresent([Double].self, forKey: .capability) ?? []
        self.hashes = try container.decodeIfPresent(AFMBundleHashes.self, forKey: .hashes) ?? AFMBundleHashes()
        self.attestation = try container.decodeIfPresent([String].self, forKey: .attestation) ?? []
        self.bundleURL = try container.decodeIfPresent(String.self, forKey: .bundleURL)
        self.runnerRoot = try container.decodeIfPresent(String.self, forKey: .runnerRoot)
        self.bundleSignature = try container.decodeIfPresent(String.self, forKey: .bundleSignature)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct AFMRouteSLA: Codable, Equatable {
    var maxLatencyMS: Int?
    var minCoverage: Double?

    private enum CodingKeys: String, CodingKey {
        case maxLatencyMS = "max_latency_ms"
        case minCoverage = "min_coverage"
    }
}

struct AFMRouteSettlementPolicy: Codable, Equatable {
    var deadline: Int?
    var escrowContract: String?
    var verifier: String?

    private enum CodingKeys: String, CodingKey {
        case deadline
        case escrowContract = "escrow_contract"
        case verifier
    }
}

struct AFMRouteDefaults: Equatable {
    var modelID: String
    var modelVersion: String
    var capabilityVector: [Double]
    var taskTags: [String]
    var maxPrice: Double?
    var reward: Double
    var rewardToken: String
    var sla: AFMRouteSLA
    var chainRef: String
    var settlement: AFMRouteSettlementPolicy?

    nonisolated static let afMarketV1 = AFMRouteDefaults(
        modelID: "apple.afm.demo",
        modelVersion: "1.0.0",
        capabilityVector: [0.12, 0.01, 0.75],
        taskTags: ["summarize"],
        maxPrice: 3.0,
        reward: 0.01,
        rewardToken: "native",
        sla: AFMRouteSLA(maxLatencyMS: 12_000, minCoverage: nil),
        chainRef: "base-sepolia",
        settlement: nil
    )
}

struct AFMRouteRequestMetadata: Codable, Equatable {
    var taskID: String
    var modelID: String
    var modelVersion: String
    var taskTags: [String]
    var inputCommitment: String
    var reward: Double
    var rewardToken: String
    var sla: AFMRouteSLA
    var chainRef: String
    var settlement: AFMRouteSettlementPolicy?
}

struct AFMRouteDispatchState: Codable, Equatable {
    var status: String?
    var httpStatus: Int?

    private enum CodingKeys: String, CodingKey {
        case status
        case httpStatus = "http_status"
    }
}

struct AFMRoutePrimaryLease: Codable, Equatable {
    var nodeID: String
    var leaseID: String
    var verifier: String?
    var payoutAddress: String?
    var dispatch: AFMRouteDispatchState?

    private enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case leaseID = "lease_id"
        case verifier
        case payoutAddress = "payout_address"
        case dispatch
    }
}

struct AFMRouteBackupLease: Codable, Equatable {
    var nodeID: String
    var leaseID: String

    private enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case leaseID = "lease_id"
    }
}

struct AFMRouteExplainRow: Codable, Equatable {
    var expertID: String
    var score: Double?
    var vrfRatio: Double?
    var rendezvous: Double?

    private enum CodingKeys: String, CodingKey {
        case expertID = "expert_id"
        case score
        case vrfRatio = "vrf_ratio"
        case rendezvous
    }
}

struct AFMRouteResult: Codable, Equatable {
    var selection: AFMPackSummary?
    var requestedSkill: String?
    var contract: String
    var primary: AFMRoutePrimaryLease?
    var backups: [AFMRouteBackupLease]
    var leaseTTLMS: Int?
    var explain: [AFMRouteExplainRow]
    var request: AFMRouteRequestMetadata?

    private enum CodingKeys: String, CodingKey {
        case selection
        case requestedSkill
        case contract
        case primary
        case backups
        case leaseTTLMS = "lease_ttl_ms"
        case explain
        case request
    }

    init(
        selection: AFMPackSummary?,
        requestedSkill: String?,
        contract: String = "local",
        primary: AFMRoutePrimaryLease? = nil,
        backups: [AFMRouteBackupLease] = [],
        leaseTTLMS: Int? = nil,
        explain: [AFMRouteExplainRow] = [],
        request: AFMRouteRequestMetadata? = nil
    ) {
        self.selection = selection
        self.requestedSkill = requestedSkill
        self.contract = contract
        self.primary = primary
        self.backups = backups
        self.leaseTTLMS = leaseTTLMS
        self.explain = explain
        self.request = request
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selection = try container.decodeIfPresent(AFMPackSummary.self, forKey: .selection)
        self.requestedSkill = try container.decodeIfPresent(String.self, forKey: .requestedSkill)
        self.contract = try container.decodeIfPresent(String.self, forKey: .contract) ?? "local"
        self.primary = try container.decodeIfPresent(AFMRoutePrimaryLease.self, forKey: .primary)
        self.backups = try container.decodeIfPresent([AFMRouteBackupLease].self, forKey: .backups) ?? []
        self.leaseTTLMS = try container.decodeIfPresent(Int.self, forKey: .leaseTTLMS)
        self.explain = try container.decodeIfPresent([AFMRouteExplainRow].self, forKey: .explain) ?? []
        self.request = try container.decodeIfPresent(AFMRouteRequestMetadata.self, forKey: .request)
    }
}

struct AFMPipelineJobResult: Codable, Equatable {
    var ok: Bool
    var id: String
    var status: String
}

struct AFMNodeInstallReceipt: Codable, Equatable {
    var mode: String
    var installCommitment: String
    var verifier: String
}

struct AFMNodeInstallResult: Codable, Equatable, Identifiable {
    var ok: Bool?
    var id: String
    var packID: String
    var checksum: String?
    var bundleURL: String?
    var requestedBy: String?
    var status: String
    var mode: String
    var installedAt: String?
    var receipt: AFMNodeInstallReceipt?
}

struct AFMNodeTaskOutput: Codable, Equatable {
    var summary: String
    var outputCommitment: String
    var completedAt: String?
}

struct AFMAttestedRun: Codable, Equatable {
    var mode: String
    var taskID: String
    var outputCommitment: String
    var nonce: String
    var tokenCount: Int
    var contextPassages: Int
    var attestationToken: String?
}

struct AFMProofState: Codable, Equatable {
    var id: String?
    var proofID: String?
    var status: String
    var verifier: String
    var publicInputs: [String: String]?
}

struct AFMSettlementState: Codable, Equatable {
    var id: String?
    var status: String
    var chainRef: String?
    var escrowID: String?
    var verifier: String?
    var mode: String?
    var settledAt: String?
}

struct AFMNodeTaskResult: Codable, Equatable, Identifiable {
    var ok: Bool?
    var id: String
    var taskID: String
    var packID: String
    var installID: String?
    var status: String
    var mode: String
    var result: AFMNodeTaskOutput
    var attestation: AFMAttestedRun
    var proof: AFMProofState
    var settlement: AFMSettlementState
}

enum AFMServicesClientError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "AFM service returned an invalid response."
        case .httpStatus(let status):
            return "AFM service returned HTTP \(status)."
        }
    }
}

final class AFMServicesClient {
    private struct HealthResponse: Decodable {
        let ok: Bool
    }

    private struct PacksResponse: Decodable {
        let data: [AFMPackSummary]
    }

    private struct MarketplacePacksResponse: Decodable {
        let packs: [AFMRunnerPack]

        private enum CodingKeys: String, CodingKey {
            case packs
            case data
            case bundles
        }

        init(from decoder: Decoder) throws {
            if var container = try? decoder.unkeyedContainer() {
                var packs: [AFMRunnerPack] = []
                while !container.isAtEnd {
                    packs.append(try container.decode(AFMRunnerPack.self))
                }
                self.packs = packs
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let packs = try container.decodeIfPresent([AFMRunnerPack].self, forKey: .packs) {
                self.packs = packs
            } else if let packs = try container.decodeIfPresent([AFMRunnerPack].self, forKey: .data) {
                self.packs = packs
            } else if let packs = try container.decodeIfPresent([AFMRunnerPack].self, forKey: .bundles) {
                self.packs = packs
            } else {
                self.packs = []
            }
        }
    }

    private struct ExpertsResponse: Decodable {
        let experts: [AFMExpertRecord]
    }

    private struct BundlesResponse: Decodable {
        let bundles: [AFMBundleRecord]
    }

    private struct RouteRequest: Encodable {
        let skill: String
        let prompt: String
        let pageURLString: String?
        let preferredPackID: String?
        let pageSnapshotCommitment: String?
        let memoryContextIDs: [String]
    }

    private struct RouteV1Constraints: Encodable {
        let maxPrice: Double?
        let geo: String?

        private enum CodingKeys: String, CodingKey {
            case maxPrice = "max_price"
            case geo
        }
    }

    private struct RouteV1HPKEInfo: Encodable {
        let kem: String
        let kdf: String
        let aead: String
        let ciphertext: String
        let epk: String
        let aad: String?
        let version: String
    }

    private struct RouteV1Request: Encodable {
        let taskID: String
        let modelID: String
        let modelVersion: String
        let qEmbed: [Double]
        let taskTags: [String]
        let inputCommitment: String
        let policy: [String: String]
        let constraints: RouteV1Constraints
        let reward: Double
        let rewardToken: String
        let sla: AFMRouteSLA
        let clientPublicKey: String
        let hpkeInfo: RouteV1HPKEInfo
        let chainRef: String
        let settlement: AFMRouteSettlementPolicy?

        private enum CodingKeys: String, CodingKey {
            case taskID = "task_id"
            case modelID = "model_id"
            case modelVersion = "model_ver"
            case qEmbed = "q_embed"
            case taskTags = "task_tags"
            case inputCommitment = "input_commitment"
            case policy
            case constraints
            case reward
            case rewardToken = "reward_token"
            case sla
            case clientPublicKey = "client_pub"
            case hpkeInfo = "hpke_info"
            case chainRef = "chain_ref"
            case settlement
        }
    }

    private struct RouteV1Response: Decodable {
        let primary: AFMRoutePrimaryLease?
        let backups: [AFMRouteBackupLease]
        let leaseTTLMS: Int?
        let explain: [AFMRouteExplainRow]

        private enum CodingKeys: String, CodingKey {
            case primary
            case backups
            case leaseTTLMS = "lease_ttl_ms"
            case explain
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.primary = try container.decodeIfPresent(AFMRoutePrimaryLease.self, forKey: .primary)
            self.backups = try container.decodeIfPresent([AFMRouteBackupLease].self, forKey: .backups) ?? []
            self.leaseTTLMS = try container.decodeIfPresent(Int.self, forKey: .leaseTTLMS)
            self.explain = try container.decodeIfPresent([AFMRouteExplainRow].self, forKey: .explain) ?? []
        }
    }

    private struct PipelineJobRequest: Encodable {
        let name: String
        let payload: PipelineJobPayload
    }

    private struct PipelineJobPayload: Encodable {
        let prompt: String
        let pageURLString: String?
        let selectedPackID: String?
        let preferredPackID: String?
        let pageSnapshotCommitment: String?
        let memoryContextIDs: [String]
    }

    private struct NodeInstallRequest: Encodable {
        let packID: String
        let checksum: String?
        let bundleURL: String?
        let requestedBy: String
    }

    private struct NodeTaskRequest: Encodable {
        let prompt: String
        let pageURLString: String?
        let selectedPackID: String?
        let pageSnapshotCommitment: String?
        let memoryContextIDs: [String]
    }

    private let configuration: AFMServiceEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: AFMServiceEndpointConfiguration = .local,
        session: URLSession = AFMServicesClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> AFMServiceSnapshot {
        let routerAvailable = (try? await health(baseURL: configuration.routerBaseURL)) ?? false
        let registryAvailable = (try? await health(baseURL: configuration.registryBaseURL)) ?? false
        let pipelinesAvailable = (try? await health(baseURL: configuration.pipelinesBaseURL)) ?? false
        let nodeAvailable = (try? await health(baseURL: configuration.nodeBaseURL)) ?? false
        let routerPacks = routerAvailable ? ((try? await packs(baseURL: configuration.routerBaseURL)) ?? []) : []
        let registryPacks = registryAvailable ? ((try? await packs(baseURL: configuration.registryBaseURL)) ?? []) : []
        let registryExperts = registryAvailable ? ((try? await experts(baseURL: configuration.registryBaseURL)) ?? []) : []
        let registryBundles = registryAvailable ? ((try? await bundles(baseURL: configuration.registryBaseURL)) ?? []) : []
        let marketplaceResult = await marketplaceSnapshot()

        return AFMServiceSnapshot(
            routerAvailable: routerAvailable,
            registryAvailable: registryAvailable,
            pipelinesAvailable: pipelinesAvailable,
            nodeAvailable: nodeAvailable,
            marketplaceAvailable: marketplaceResult.available,
            routerPacks: routerPacks,
            registryPacks: registryPacks,
            marketplacePacks: marketplaceResult.packs,
            registryExperts: registryExperts,
            registryBundles: registryBundles
        )
    }

    func route(
        skill: String,
        prompt: String,
        pageURLString: String?,
        preferredPackID: String? = nil,
        pageSnapshotCommitment: String? = nil,
        memoryContextIDs: [String] = []
    ) async throws -> AFMRouteResult {
        let metadata = Self.routeMetadata(
            defaults: configuration.routeDefaults,
            skill: skill,
            prompt: prompt,
            pageURLString: pageURLString,
            pageSnapshotCommitment: pageSnapshotCommitment
        )
        let routeV1Request = RouteV1Request(
            taskID: metadata.taskID,
            modelID: metadata.modelID,
            modelVersion: metadata.modelVersion,
            qEmbed: configuration.routeDefaults.capabilityVector,
            taskTags: metadata.taskTags,
            inputCommitment: metadata.inputCommitment,
            policy: [:],
            constraints: RouteV1Constraints(maxPrice: configuration.routeDefaults.maxPrice, geo: nil),
            reward: metadata.reward,
            rewardToken: metadata.rewardToken,
            sla: metadata.sla,
            clientPublicKey: Self.clientPublicKey(for: metadata.taskID),
            hpkeInfo: Self.hpkeInfo(for: metadata, prompt: prompt, memoryContextIDs: memoryContextIDs),
            chainRef: metadata.chainRef,
            settlement: metadata.settlement
        )
        do {
            let response: RouteV1Response = try await send(
                method: "POST",
                baseURL: configuration.routerBaseURL,
                path: "/v1/route",
                body: routeV1Request
            )
            return AFMRouteResult(
                selection: nil,
                requestedSkill: skill,
                contract: "afmarket-v1",
                primary: response.primary,
                backups: response.backups,
                leaseTTLMS: response.leaseTTLMS,
                explain: response.explain,
                request: metadata
            )
        } catch AFMServicesClientError.httpStatus(let status) where status == 404 {
            return try await routeLegacy(
                skill: skill,
                prompt: prompt,
                pageURLString: pageURLString,
                preferredPackID: preferredPackID,
                pageSnapshotCommitment: pageSnapshotCommitment,
                memoryContextIDs: memoryContextIDs,
                metadata: metadata
            )
        }
    }

    private func routeLegacy(
        skill: String,
        prompt: String,
        pageURLString: String?,
        preferredPackID: String?,
        pageSnapshotCommitment: String?,
        memoryContextIDs: [String],
        metadata: AFMRouteRequestMetadata
    ) async throws -> AFMRouteResult {
        let body = RouteRequest(
            skill: skill,
            prompt: prompt,
            pageURLString: pageURLString,
            preferredPackID: preferredPackID,
            pageSnapshotCommitment: pageSnapshotCommitment,
            memoryContextIDs: memoryContextIDs
        )
        var result: AFMRouteResult = try await send(
            method: "POST",
            baseURL: configuration.routerBaseURL,
            path: "/route",
            body: body
        )
        result.contract = "local"
        result.request = metadata
        return result
    }

    func enqueueCopilotJob(
        prompt: String,
        pageURLString: String?,
        selectedPackID: String?,
        preferredPackID: String? = nil,
        pageSnapshotCommitment: String? = nil,
        memoryContextIDs: [String] = []
    ) async throws -> AFMPipelineJobResult {
        let body = PipelineJobRequest(
            name: "swift-copilot",
            payload: PipelineJobPayload(
                prompt: prompt,
                pageURLString: pageURLString,
                selectedPackID: selectedPackID,
                preferredPackID: preferredPackID,
                pageSnapshotCommitment: pageSnapshotCommitment,
                memoryContextIDs: memoryContextIDs
            )
        )
        return try await send(
            method: "POST",
            baseURL: configuration.pipelinesBaseURL,
            path: "/jobs",
            body: body
        )
    }

    func installPack(
        packID: String,
        checksum: String?,
        bundleURL: String? = nil,
        requestedBy: String = "swift-copilot"
    ) async throws -> AFMNodeInstallResult {
        let body = NodeInstallRequest(
            packID: packID,
            checksum: checksum,
            bundleURL: bundleURL,
            requestedBy: requestedBy
        )
        return try await send(
            method: "POST",
            baseURL: configuration.nodeBaseURL,
            path: "/packs/install",
            body: body
        )
    }

    func dispatchTask(
        prompt: String,
        pageURLString: String?,
        selectedPackID: String?,
        pageSnapshotCommitment: String?,
        memoryContextIDs: [String] = []
    ) async throws -> AFMNodeTaskResult {
        let body = NodeTaskRequest(
            prompt: prompt,
            pageURLString: pageURLString,
            selectedPackID: selectedPackID,
            pageSnapshotCommitment: pageSnapshotCommitment,
            memoryContextIDs: memoryContextIDs
        )
        return try await send(
            method: "POST",
            baseURL: configuration.nodeBaseURL,
            path: "/tasks",
            body: body
        )
    }

    private func health(baseURL: URL) async throws -> Bool {
        let response: HealthResponse = try await send(method: "GET", baseURL: baseURL, path: "/health")
        return response.ok
    }

    private func packs(baseURL: URL) async throws -> [AFMPackSummary] {
        let response: PacksResponse = try await send(method: "GET", baseURL: baseURL, path: "/packs")
        return response.data
    }

    private func experts(baseURL: URL) async throws -> [AFMExpertRecord] {
        let response: ExpertsResponse = try await send(method: "GET", baseURL: baseURL, path: "/v1/experts")
        return response.experts
    }

    private func bundles(baseURL: URL) async throws -> [AFMBundleRecord] {
        let response: BundlesResponse = try await send(method: "GET", baseURL: baseURL, path: "/v1/bundles")
        return response.bundles
    }

    private func marketplaceSnapshot() async -> (available: Bool?, packs: [AFMRunnerPack]) {
        guard let marketplaceBaseURL = configuration.marketplaceBaseURL else {
            return (nil, [])
        }
        do {
            let response: MarketplacePacksResponse = try await send(
                method: "GET",
                baseURL: marketplaceBaseURL,
                path: "/api/packs"
            )
            return (true, response.packs)
        } catch {
            return (false, [])
        }
    }

    private static func routeMetadata(
        defaults: AFMRouteDefaults,
        skill: String,
        prompt: String,
        pageURLString: String?,
        pageSnapshotCommitment: String?
    ) -> AFMRouteRequestMetadata {
        var taskTags = defaults.taskTags
        if !taskTags.contains(skill) {
            taskTags.append(skill)
        }
        let inputCommitment = pageSnapshotCommitment ?? "fnv1a64:\(fnv1a64Hex("\(prompt)|\(pageURLString ?? "")"))"
        let taskSeed = [skill, prompt, pageURLString ?? "", inputCommitment].joined(separator: "|")
        return AFMRouteRequestMetadata(
            taskID: "swift-\(fnv1a64Hex(taskSeed))",
            modelID: defaults.modelID,
            modelVersion: defaults.modelVersion,
            taskTags: taskTags,
            inputCommitment: inputCommitment,
            reward: defaults.reward,
            rewardToken: defaults.rewardToken,
            sla: defaults.sla,
            chainRef: defaults.chainRef,
            settlement: defaults.settlement
        )
    }

    private static func hpkeInfo(
        for metadata: AFMRouteRequestMetadata,
        prompt: String,
        memoryContextIDs: [String]
    ) -> RouteV1HPKEInfo {
        let envelope = [metadata.inputCommitment, prompt, memoryContextIDs.joined(separator: ",")].joined(separator: "|")
        let ciphertext = Data(envelope.utf8).base64EncodedString()
        return RouteV1HPKEInfo(
            kem: "X25519",
            kdf: "HKDF-SHA256",
            aead: "ChaCha20Poly1305",
            ciphertext: ciphertext.isEmpty ? "metadata-only" : ciphertext,
            epk: "swift-dbrowser-epk-\(fnv1a64Hex(metadata.taskID))-000000000000",
            aad: metadata.taskID,
            version: "X25519-HKDF-SHA256/CHACHA20POLY1305-v1"
        )
    }

    private static func clientPublicKey(for taskID: String) -> String {
        "swift-dbrowser-client-pub-\(fnv1a64Hex(taskID))-000000000000"
    }

    private static func fnv1a64Hex(_ input: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private func send<Response: Decodable>(
        method: String,
        baseURL: URL,
        path: String
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(baseURL: baseURL, path: path))
        request.httpMethod = method
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        baseURL: URL,
        path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(baseURL: baseURL, path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func endpoint(baseURL: URL, path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url!
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AFMServicesClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AFMServicesClientError.httpStatus(http.statusCode)
        }
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.75
        configuration.timeoutIntervalForResource = 0.75
        return URLSession(configuration: configuration)
    }
}
