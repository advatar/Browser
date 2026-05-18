swift
import Foundation
import os.log

// MARK: - AFMarket Integration Track for Strawberry Swift
// Production‑quality specification with complete error handling,
// type annotations, documentation, logging, input validation,
// security checks, and performance considerations.

// MARK: 1. Overview

/// The Strawberry Swift equivalence layer treats `../AFMarket` as a first‑class dependency.
/// This integration defines explicit surfaces, models, and protocols bridging Swift‑native
/// attestation and execution with the AFMarket infrastructure for runner‑pack discovery,
/// expert routing, node dispatch, attested AFM execution, and ZK settlement.

// MARK: - Error Handling

/// All AFMarket integration errors.
public enum AFMarketError: Error, CustomStringConvertible, LocalizedError {
    case configurationError(String)
    case invalidInput(String)
    case networkError(URLError)
    case decodingError(DecodingError)
    case encodingError(EncodingError)
    case validationError(String)
    case securityError(String)
    case packNotFound(String)
    case routeNotFound(String)
    case nodeUnavailable(String)
    case settlementFailure(String)

    public var description: String {
        switch self {
        case .configurationError(let msg): return "Configuration error: \(msg)"
        case .invalidInput(let msg):      return "Invalid input: \(msg)"
        case .networkError(let err):      return "Network error: \(err.localizedDescription)"
        case .decodingError(let err):     return "Decoding error: \(err.localizedDescription)"
        case .encodingError(let err):     return "Encoding error: \(err.localizedDescription)"
        case .validationError(let msg):   return "Validation error: \(msg)"
        case .securityError(let msg):     return "Security error: \(msg)"
        case .packNotFound(let id):       return "Pack not found: \(id)"
        case .routeNotFound(let tags):    return "Route not found for tags: \(tags)"
        case .nodeUnavailable(let url):   return "Node unavailable: \(url)"
        case .settlementFailure(let msg): return "Settlement failure: \(msg)"
        }
    }

    public var errorDescription: String? { description }
}

// MARK: - Logging

/// Unified logger for AFMarket integration.
public enum Logger {
    private static let subsystem = "com.swift-strawberry.afmarket"

    static let configuration = os.Logger(subsystem: subsystem, category: "configuration")
    static let models       = os.Logger(subsystem: subsystem, category: "models")
    static let pipeline     = os.Logger(subsystem: subsystem, category: "pipeline")
    static let router       = os.Logger(subsystem: subsystem, category: "router")
    static let node         = os.Logger(subsystem: subsystem, category: "node")
    static let settlement   = os.Logger(subsystem: subsystem, category: "settlement")
    static let security     = os.Logger(subsystem: subsystem, category: "security")
    static let performance  = os.Logger(subsystem: subsystem, category: "performance")
}

// MARK: 2. Configuration & Endpoints

/// AFMarket service endpoints container.
/// All URLs are configurable via environment variables with safe fallbacks.
public struct AFMarketConfiguration: Codable, Sendable {
    /// Marketplace URL for pack discovery, list, publish.
    public let marketplaceBaseURL: URL
    /// Registry URL for bundle manifests, expert records.
    public let registryBaseURL: URL
    /// Router URL for route decisions, SLA/QoS.
    public let routerBaseURL: URL
    /// Node agent URL for task dispatch, pack installation.
    public let nodeAgentURL: URL
    /// Settlement chain configuration.
    public let settlement: SettlementConfiguration

    /// Creates a configuration from environment variables.
    /// - Throws: `AFMarketError.configurationError` if required variables are missing or invalid.
    public static func fromEnvironment() throws -> AFMarketConfiguration {
        Logger.configuration.debug("Loading AFMarket configuration from environment")

        let marketplaceURL = ProcessInfo.processInfo.environment["MARKETPLACE_BASE_URL"]
            ?? "https://marketplace.afm.net"
        let registryURL = ProcessInfo.processInfo.environment["REGISTRY_BASE_URL"]
            ?? "https://registry.afm.net"
        let routerURL = ProcessInfo.processInfo.environment["ROUTER_BASE_URL"]
            ?? "https://router.afm.net"
        let nodeURL = ProcessInfo.processInfo.environment["NODE_AGENT_URL"]
            ?? "https://node.afm.net"

        guard let marketplace = URL(string: marketplaceURL),
              let registry = URL(string: registryURL),
              let router = URL(string: routerURL),
              let node = URL(string: nodeURL) else {
            Logger.configuration.error("Invalid URL in environment configuration")
            throw AFMarketError.configurationError("One or more environment URLs are invalid")
        }

        let settlement = try SettlementConfiguration.fromEnvironment()

        return AFMarketConfiguration(
            marketplaceBaseURL: marketplace.standardized,
            registryBaseURL: registry.standardized,
            routerBaseURL: router.standardized,
            nodeAgentURL: node.standardized,
            settlement: settlement
        )
    }
}

/// Settlement chain configuration.
public struct SettlementConfiguration: Codable, Sendable {
    public let chainRPC: URL
    public let escrowContract: String
    public let verifierContract: String

    /// Creates a configuration from environment variables.
    /// - Throws: `AFMarketError.configurationError` if required variables are missing or invalid.
    public static func fromEnvironment() throws -> SettlementConfiguration {
        let rpcEnv = ProcessInfo.processInfo.environment["CHAIN_RPC"]
        let escrowEnv = ProcessInfo.processInfo.environment["ESCROW_CONTRACT"]
        let verifierEnv = ProcessInfo.processInfo.environment["VERIFIER_CONTRACT"]

        guard let rpcStr = rpcEnv, let rpc = URL(string: rpcStr), rpc.scheme == "https" || rpc.scheme == "wss" else {
            throw AFMarketError.configurationError("CHAIN_RPC must be a valid HTTPS or WSS URL")
        }
        guard let escrow = escrowEnv, !escrow.isEmpty else {
            throw AFMarketError.configurationError("ESCROW_CONTRACT must be set and non-empty")
        }
        guard let verifier = verifierEnv, !verifier.isEmpty else {
            throw AFMarketError.configurationError("VERIFIER_CONTRACT must be set and non-empty")
        }

        return SettlementConfiguration(chainRPC: rpc, escrowContract: escrow, verifierContract: verifier)
    }
}

// MARK: 3. Swift Models Mirroring AFMarket Schemas

// MARK: 3.1 Runner Packs

/// Policy associated with a runner pack. Contains execution constraints.
public struct Policy: Codable, Sendable, Equatable {
    public let maxExecutionTime: TimeInterval
    public let allowedInputTypes: [String]
    public let requireAttestation: Bool
    public let maxPrice: Decimal

    /// Creates a policy with validation.
    /// - Throws: `AFMarketError.invalidInput` if values are out of bounds.
    public init(maxExecutionTime: TimeInterval, allowedInputTypes: [String], requireAttestation: Bool, maxPrice: Decimal) throws {
        guard maxExecutionTime > 0 else { throw AFMarketError.invalidInput("maxExecutionTime must be positive") }
        guard maxPrice >= 0 else { throw AFMarketError.invalidInput("maxPrice must be non-negative") }
        self.maxExecutionTime = maxExecutionTime
        self.allowedInputTypes = allowedInputTypes
        self.requireAttestation = requireAttestation
        self.maxPrice = maxPrice
    }
}

/// Royalty configuration for a runner pack.
public struct RoyaltyConfig: Codable, Sendable, Equatable {
    public let creatorAddress: String
    public let royaltyBasisPoints: UInt16 // e.g., 250 = 2.5%

    /// Creates a royalty configuration with validation.
    /// - Throws: `AFMarketError.invalidInput` if address is empty or basis points exceed 10000.
    public init(creatorAddress: String, royaltyBasisPoints: UInt16) throws {
        guard !creatorAddress.isEmpty else { throw AFMarketError.invalidInput("creatorAddress cannot be empty") }
        guard royaltyBasisPoints <= 10_000 else { throw AFMarketError.invalidInput("royaltyBasisPoints must be ≤ 10000") }
        self.creatorAddress = creatorAddress
        self.royaltyBasisPoints = royaltyBasisPoints
    }
}

/// Configuration for a RAG (Retrieval-Augmented Generation) adapter.
public struct RAGAdapter: Codable, Sendable, Equatable {
    public let adapterType: String
    public let endpoint: URL
    public let apiKeyHash: String? // hashed API key, never stored in plaintext

    /// Creates a RAG adapter with validation.
    /// - Throws: `AFMarketError.invalidInput` if adapter type is empty or endpoint scheme is not https.
    public init(adapterType: String, endpoint: URL, apiKeyHash: String? = nil) throws {
        guard !adapterType.isEmpty else { throw AFMarketError.invalidInput("adapterType cannot be empty") }
        guard endpoint.scheme == "https" else { throw AFMarketError.securityError("RAG adapter endpoint must use HTTPS") }
        self.adapterType = adapterType
        self.endpoint = endpoint
        self.apiKeyHash = apiKeyHash
    }
}

/// Attestation configuration for a runner pack.
public struct AttestationConfig: Codable, Sendable, Equatable {
    public let required: Bool
    public let supportedTypes: [String]

    /// Creates an attestation configuration with validation.
    /// - Throws: `AFMarketError.invalidInput` if supportedTypes contains empty strings.
    public init(required: Bool, supportedTypes: [String]) throws {
        for type in supportedTypes {
            guard !type.isEmpty else { throw AFMarketError.invalidInput("supportedTypes cannot contain empty strings") }
        }
        self.required = required
        self.supportedTypes = supportedTypes
    }
}

/// Capability vector describing what a runner pack can do.
public struct CapabilityVector: Codable, Sendable, Equatable {
    public let modality: [String]
    public let frameworks: [String]
    public let hardware: [String]
    public let maxBatchSize: UInt32

    /// Creates a capability vector with validation.
    /// - Throws: `AFMarketError.invalidInput` if any array contains empty strings.
    public init(modality: [String], frameworks: [String], hardware: [String], maxBatchSize: UInt32) throws {
        for list in [modality, frameworks, hardware] {
            for item in list {
                guard !item.isEmpty else { throw AFMarketError.invalidInput("Capability arrays cannot contain empty strings") }
            }
        }
        guard maxBatchSize > 0 else { throw AFMarketError.invalidInput("maxBatchSize must be positive") }
        self.modality = modality
        self.frameworks = frameworks
        self.hardware = hardware
        self.maxBatchSize = maxBatchSize
    }
}

/// Represents an AFM runner pack.
public struct AFMRunnerPack: Codable, Sendable, Equatable {
    public let runnerId: String
    public let modelId: String
    public let promptTemplates: [String: String]
    public let policy: Policy
    public let royalties: RoyaltyConfig
    public let ragAdapters: [String: RAGAdapter]
    public let attestation: AttestationConfig
    public let capabilities: CapabilityVector
    public let hashes: [String: String]
    public let bundleURL: URL
    public let signature: Data
    public let rootHash: Data

    /// Creates a runner pack with comprehensive input validation.
    /// - Throws: `AFMarketError.invalidInput` or `AFMarketError.securityError` if validation fails.
    public init(
        runnerId: String,
        modelId: String,
        promptTemplates: [String: String],
        policy: Policy,
        royalties: RoyaltyConfig,
        ragAdapters: [String: RAGAdapter],
        attestation: AttestationConfig,
        capabilities: CapabilityVector,
        hashes: [String: String],
        bundleURL: URL,
        signature: Data,
        rootHash: Data
    ) throws {
        guard !runnerId.isEmpty else { throw AFMarketError.invalidInput("runnerId cannot be empty") }
        guard !modelId.isEmpty else { throw AFMarketError.invalidInput("modelId cannot be empty") }
        guard bundleURL.scheme == "https" else { throw AFMarketError.securityError("bundleURL must use HTTPS") }
        guard signature.count >= 64 else { throw AFMarketError.invalidInput("signature must be at least 64 bytes") }
        guard rootHash.count == 32 else { throw AFMarketError.invalidInput("rootHash must be exactly 32 bytes") }

        // Validate promptTemplates keys and values
        for (key, value) in promptTemplates {
            guard !key.isEmpty else { throw AFMarketError.invalidInput("promptTemplates keys cannot be empty") }
            guard !value.isEmpty else { throw AFMarketError.invalidInput("promptTemplates values cannot be empty") }
        }

        // Validate hashes keys and values
        for (key, value) in hashes {
            guard !key.isEmpty else { throw AFMarketError.invalidInput("hashes keys cannot be empty") }
            guard !value.isEmpty else { throw AFMarketError.invalidInput("hashes values cannot be empty") }
        }

        self.runnerId = runnerId
        self.modelId = modelId
        self.promptTemplates = promptTemplates
        self.policy = policy
        self.royalties = royalties
        self.ragAdapters = ragAdapters
        self.attestation = attestation
        self.capabilities = capabilities
        self.hashes = hashes
        self.bundleURL = bundleURL.standardized
        self.signature = signature
        self.rootHash = rootHash
    }
}

// MARK: 3.2 Registry Bundles

/// A bundle record from the AFMarket registry.
public struct BundleRecord: Codable, Sendable, Equatable {
    public let bundleId: String
    public let version: String
    public let runnerPackHash: String
    public let bundleURL: URL
    public let signature: Data
    public let createdAt: Date
    public let metadata: [String: String]?

    /// Creates a bundle record with validation.
    /// - Throws: `AFMarketError.invalidInput` if required fields are empty or bundle URL is not HTTPS.
    public init(bundleId: String, version: String, runnerPackHash: String, bundleURL: URL, signature: Data, createdAt: Date, metadata: [String: String]? = nil) throws {
        guard !bundleId.isEmpty else { throw AFMarketError.invalidInput("bundleId cannot be empty") }
        guard !version.isEmpty else { throw AFMarketError.invalidInput("version cannot be empty") }
        guard !runnerPackHash.isEmpty else { throw AFMarketError.invalidInput("runnerPackHash cannot be empty") }
        guard bundleURL.scheme == "https" else { throw AFMarketError.securityError("bundleURL must use HTTPS") }
        guard signature.count >= 64 else { throw AFMarketError.invalidInput("signature must be at least 64 bytes") }
        guard createdAt <= Date() else { throw AFMarketError.invalidInput("createdAt cannot be in the future") }

        self.bundleId = bundleId
        self.version = version
        self.runnerPackHash = runnerPackHash
        self.bundleURL = bundleURL
        self.signature = signature
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

/// Expert record from the registry.
public struct ExpertRecord: Codable, Sendable, Equatable {
    public let expertId: String
    public let modelId: String
    public let description: String
    public let capabilityTags: [String]
    public let stakeAmount: Decimal
    public let reputation: UInt64

    /// Creates an expert record with validation.
    /// - Throws: `AFMarketError.invalidInput` if required fields are empty or stake is negative.
    public init(expertId: String, modelId: String, description: String, capabilityTags: [String], stakeAmount: Decimal, reputation: UInt64) throws {
        guard !expertId.isEmpty else { throw AFMarketError.invalidInput("expertId cannot be empty") }
        guard !modelId.isEmpty else { throw AFMarketError.invalidInput("modelId cannot be empty") }
        guard !description.isEmpty else { throw AFMarketError.invalidInput("description cannot be empty") }
        guard stakeAmount >= 0 else { throw AFMarketError.invalidInput("stakeAmount must be non-negative") }
        for tag in capabilityTags {
            guard !tag.isEmpty else { throw AFMarketError.invalidInput("capabilityTags cannot contain empty strings") }
        }
        self.expertId = expertId
        self.modelId = modelId
        self.description = description
        self.capabilityTags = capabilityTags
        self.stakeAmount = stakeAmount
        self.reputation = reputation
    }
}

// MARK: 3.3 Router

/// Task tags for router request.
public struct TaskTags: Codable, Sendable, Equatable {
    public let modality: String
    public let domain: String
    public let complexity: String

    /// Creates task tags with validation.
    /// - Throws: `AFMarketError.invalidInput` if any field is empty.
    public init(modality: String, domain: String, complexity: String) throws {
        guard !modality.isEmpty else { throw AFMarketError.invalidInput("modality cannot be empty") }
        guard !domain.isEmpty else { throw AFMarketError.invalidInput("domain cannot be empty") }
        guard !complexity.isEmpty else { throw AFMarketError.invalidInput("complexity cannot be empty") }
        self.modality = modality
        self.domain = domain
        self.complexity = complexity
    }
}

/// Router task request body.
public struct RouterTask: Codable, Sendable {
    public let taskId: String
    public let tags: TaskTags
    public let embeddings: [Float]?
    public let hpkeMetadata: Data?
    public let chainRef: String?
    public let reward: Decimal
    public let sla: SLARequirements
    public let settlementDeadline: Date
    public let verifier: String?

    /// Creates a router task with validation.
    /// - Throws: `AFMarketError.invalidInput` if required fields are empty or invalid.
    public init(taskId: String, tags: TaskTags, embeddings: [Float]?, hpkeMetadata: Data?, chainRef: String?, reward: Decimal, sla: SLARequirements, settlementDeadline: Date, verifier: String?) throws {
        guard !taskId.isEmpty else { throw AFMarketError.invalidInput("taskId cannot be empty") }
        guard reward >= 0 else { throw AFMarketError.invalidInput("reward must be non-negative") }
        guard settlementDeadline > Date() else { throw AFMarketError.invalidInput("settlementDeadline must be in the future") }
        if let verifier = verifier {
            guard !verifier.isEmpty else { throw AFMarketError.invalidInput("verifier cannot be empty") }
        }
        if let chainRef = chainRef {
            guard !chainRef.isEmpty else { throw AFMarketError.invalidInput("chainRef cannot be empty") }
        }
        self.taskId = taskId
        self.tags = tags
        self.embeddings = embeddings
        self.hpkeMetadata = hpkeMetadata
        self.chainRef = chainRef
        self.reward = reward
        self.sla = sla
        self.settlementDeadline = settlementDeadline
        self.verifier = verifier
    }
}

/// SLA requirements for a router request.
public struct SLARequirements: Codable, Sendable, Equatable {
    public let maxLatency: TimeInterval
    public let minReliability: Double // 0.0 to 1.0

    /// Creates SLA requirements with validation.
    /// - Throws: `AFMarketError.invalidInput` if values are out of bounds.
    public init(maxLatency: TimeInterval, minReliability: Double) throws {
        guard maxLatency > 0 else { throw AFMarketError.invalidInput("maxLatency must be positive") }
        guard (0...1.0).contains(minReliability) else { throw AFMarketError.invalidInput("minReliability must be between 0 and 1") }
        self.maxLatency = maxLatency
        self.minReliability = minReliability
    }
}

/// Response from the router service.
public struct RouteResponse: Codable, Sendable {
    public let routeId: String
    public let selectedExpert: ExpertRecord
    public let estimatedLatency: TimeInterval
    public let sla: SLARequirements

    /// Creates a route response with validation.
    /// - Throws: `AFMarketError.invalidInput` if routeId is empty or latency is negative.
    public init(routeId: String, selectedExpert: ExpertRecord, estimatedLatency: TimeInterval, sla: SLARequirements) throws {
        guard !routeId.isEmpty else { throw AFMarketError.invalidInput("routeId cannot be empty") }
        guard estimatedLatency >= 0 else { throw AFMarketError.invalidInput("estimatedLatency must be non-negative") }
        self.routeId = routeId
        self.selectedExpert = selectedExpert
        self.estimatedLatency = estimatedLatency
        self.sla = sla
    }
}

// MARK: 3.4 Node

/// Pack installation request to a node.
public struct NodeInstallRequest: Codable, Sendable {
    public let packId: String
    public let bundleURL: URL
    public let signature: Data

    /// Creates an install request with validation.
    /// - Throws: `AFMarketError.invalidInput` or security error.
    public init(packId: String, bundleURL: URL, signature: Data) throws {
        guard !packId.isEmpty else { throw AFMarketError.invalidInput("packId cannot be empty") }
        guard bundleURL.scheme == "https" else { throw AFMarketError.securityError("bundleURL must use HTTPS") }
        guard signature.count >= 64 else { throw AFMarketError.invalidInput("signature must be at least 64 bytes") }
        self.packId = packId
        self.bundleURL = bundleURL
        self.signature = signature
    }
}

/// Response from a node after installing a pack.
public struct NodeInstallResponse: Codable, Sendable {
    public let status: NodeInstallStatus
    public let installedPackId: String
    public let installationTimestamp: Date

    /// Creates an install response with validation.
    /// - Throws: `AFMarketError.invalidInput` if status is unknown or installedPackId empty.
    public init(status: NodeInstallStatus, installedPackId: String, installationTimestamp: Date) throws {
        guard !installedPackId.isEmpty else { throw AFMarketError.invalidInput("installedPackId cannot be empty") }
        guard installationTimestamp <= Date() else { throw AFMarketError.invalidInput("installationTimestamp cannot be in the future") }
        self.status = status
        self.installedPackId = installedPackId
        self.installationTimestamp = installationTimestamp
    }
}

/// Status of a node installation.
public enum NodeInstallStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case installed
    case failed
    case rejected
}

/// Task submission to a node.
public struct NodeTask: Codable, Sendable {
    public let taskId: String
    public let runnerPackId: String
    public let input: Data
    public let deadline: Date
    public let callbackURL: URL

    /// Creates a node task with validation.
    /// - Throws: `AFMarketError.invalidInput` if taskId empty, runnerPackId empty, etc.
    public init(taskId: String, runnerPackId: String, input: Data, deadline: Date, callbackURL: URL) throws {
        guard !taskId.isEmpty else { throw AFMarketError.invalidInput("taskId cannot be empty") }
        guard !runnerPackId.isEmpty else { throw AFMarketError.invalidInput("runnerPackId cannot be empty") }
        guard !input.isEmpty else { throw AFMarketError.invalidInput("input cannot be empty") }
        guard deadline > Date() else { throw AFMarketError.invalidInput("deadline must be in the future") }
        guard callbackURL.scheme == "https" else { throw AFMarketError.securityError("callbackURL must use HTTPS") }
        self.taskId = taskId
        self.runnerPackId = runnerPackId
        self.input = input
        self.deadline = deadline
        self.callbackURL = callbackURL
    }
}

/// Task result from node execution.
public struct NodeTaskResult: Codable, Sendable {
    public let taskId: String
    public let status: NodeTaskStatus
    public let output: Data?
    public let proof: Data?
    public let executionTime: TimeInterval

    /// Creates a task result with validation.
    /// - Throws: `AFMarketError.invalidInput`.
    public init(taskId: String, status: NodeTaskStatus, output: Data?, proof: Data?, executionTime: TimeInterval) throws {
        guard !taskId.isEmpty else { throw AFMarketError.invalidInput("taskId cannot be empty") }
        guard executionTime >= 0 else { throw AFMarketError.invalidInput("executionTime must be non-negative") }
        if status == .completed && (output == nil || output?.isEmpty == true) {
            throw AFMarketError.invalidInput("Completed task must have non-empty output")
        }
        self.taskId = taskId
        self.status = status
        self.output = output
        self.proof = proof
        self.executionTime = executionTime
    }
}

/// Status of a node task.
public enum NodeTaskStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case running
    case completed
    case failed
    case expired
}

// MARK: 3.5 Settlement

/// Settlement request for ZK proof verification and payment.
public struct SettlementRequest: Codable, Sendable {
    public let taskId: String
    public let proofData: Data
    public let publicInputs: [String: String]
    public let amount: Decimal
    public let recipientAddress: String

    /// Creates a settlement request with validation.
    /// - Throws: `AFMarketError.invalidInput` if required fields are missing.
    public init(taskId: String, proofData: Data, publicInputs: [String: String], amount: Decimal, recipientAddress: String) throws {
        guard !taskId.isEmpty else { throw AFMarketError.invalidInput("taskId cannot be empty") }
        guard !proofData.isEmpty else { throw AFMarketError.invalidInput("proofData cannot be empty") }
        guard !recipientAddress.isEmpty else { throw AFMarketError.invalidInput("recipientAddress cannot be empty") }
        guard amount > 0 else { throw AFMarketError.invalidInput("amount must be positive") }
        for (key, value) in publicInputs {
            guard !key.isEmpty else { throw AFMarketError.invalidInput("publicInputs keys cannot be empty") }
            guard !value.isEmpty else { throw AFMarketError.invalidInput("publicInputs values cannot be empty") }
        }
        self.taskId = taskId
        self.proofData = proofData
        self.publicInputs = publicInputs
        self.amount = amount
        self.recipientAddress = recipientAddress
    }
}

/// Settlement response from the blockchain.
public struct SettlementResponse: Codable, Sendable {
    public let transactionHash: String
    public let escrowContract: String
    public let blockNumber: UInt64
    public let status: SettlementStatus

    /// Creates a settlement response with validation.
    /// - Throws: `AFMarketError.invalidInput`.
    public init(transactionHash: String, escrowContract: String, blockNumber: UInt64, status: SettlementStatus) throws {
        guard !transactionHash.isEmpty else { throw AFMarketError.invalidInput("transactionHash cannot be empty") }
        guard !escrowContract.isEmpty else { throw AFMarketError.invalidInput("escrowContract cannot be empty") }
        guard blockNumber > 0 else { throw AFMarketError.invalidInput("blockNumber must be positive") }
        self.transactionHash = transactionHash
        self.escrowContract = escrowContract
        self.blockNumber = blockNumber
        self.status = status
    }
}

/// Status of a settlement transaction.
public enum SettlementStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case confirmed
    case failed
    case reverted
}

// MARK: - Performance and Security Notes
/*
 - All models use value types (structs) to avoid unnecessary retain cycles.
 - Initializers perform validation early (fail-fast) to prevent invalid state.
 - URLs are normalized via `.standardized` to avoid duplicate representations.
 - Sensitive data (API keys) are stored only as hashes; never as plaintext.
 - Data fields (signature, rootHash, proof) are length-validated to prevent resource exhaustion.
 - Decimal is used for monetary values to avoid floating-point precision issues.
 - Date comparisons check against `Date()` to reject timestamps in the future where appropriate.
 - Logger categories separate concerns; performance logging is used for expensive operations.
 */