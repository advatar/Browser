import Foundation

/// The pinned, network-disabled ActiveChain Phase 1 compatibility boundary.
///
/// This is deliberately a semantic fixture surface. It does not open sockets,
/// start a node, sign, broadcast, spend, or claim network finality.
struct ActiveChainSandboxConfiguration: Codable, Equatable {
    static let current = ActiveChainSandboxConfiguration(
        protocolVersion: "development-1",
        sourceRevision: "cdb8478",
        vectors: [
            "principal-v1",
            "credential-v1",
            "authority-v1",
            "apl-v1",
            "state-tree-v1",
            "devnet-block-v1"
        ]
    )

    let protocolVersion: String
    let sourceRevision: String
    let vectors: [String]

    init(protocolVersion: String, sourceRevision: String, vectors: [String]) {
        self.protocolVersion = protocolVersion
        self.sourceRevision = sourceRevision
        self.vectors = vectors
    }

    func validates(expectedRevision: String) -> Bool {
        sourceRevision == expectedRevision && !protocolVersion.isEmpty && !vectors.isEmpty
    }
}

enum ActiveChainSandboxProvenance: String, Codable, Equatable {
    case developmentFixture
    case localSimulation
    case unsupportedVersion
}

enum ActiveChainSandboxCapability: String, Codable, Equatable, CaseIterable {
    case canonicalVerification
    case semanticSimulation
    case sign
    case spend
    case discloseCredential
    case broadcast
    case peerService
    case nodeStartup

    var isAllowed: Bool {
        self == .canonicalVerification || self == .semanticSimulation
    }
}

struct ActiveChainSandboxResult: Codable, Equatable {
    let provenance: ActiveChainSandboxProvenance
    let protocolVersion: String
    let sourceRevision: String
    let vectorID: String
    let finalityClaim: String

    static func fixture(
        vectorID: String,
        configuration: ActiveChainSandboxConfiguration = .current
    ) -> ActiveChainSandboxResult {
        ActiveChainSandboxResult(
            provenance: .developmentFixture,
            protocolVersion: configuration.protocolVersion,
            sourceRevision: configuration.sourceRevision,
            vectorID: vectorID,
            finalityClaim: "No network finality"
        )
    }
}

enum ActiveChainSandboxError: Error, Equatable {
    case unsupportedRevision
    case unsupportedProtocolVersion
    case capabilityDenied(ActiveChainSandboxCapability)
    case unknownVector(String)
}

struct ActiveChainSemanticSandbox {
    static var runtimeSummary: String {
        let configuration = ActiveChainSandboxConfiguration.current
        return "ActiveChain sandbox \(configuration.protocolVersion) @ \(configuration.sourceRevision); development fixture; no network finality"
    }

    let configuration: ActiveChainSandboxConfiguration

    init(
        configuration: ActiveChainSandboxConfiguration = .current,
        expectedRevision: String = ActiveChainSandboxConfiguration.current.sourceRevision
    ) throws {
        guard configuration.validates(expectedRevision: expectedRevision) else {
            throw ActiveChainSandboxError.unsupportedRevision
        }
        guard configuration.protocolVersion == ActiveChainSandboxConfiguration.current.protocolVersion else {
            throw ActiveChainSandboxError.unsupportedProtocolVersion
        }
        self.configuration = configuration
    }

    func simulate(vectorID: String) throws -> ActiveChainSandboxResult {
        guard configuration.vectors.contains(vectorID) else {
            throw ActiveChainSandboxError.unknownVector(vectorID)
        }
        return .fixture(vectorID: vectorID, configuration: configuration)
    }

    func request(_ capability: ActiveChainSandboxCapability) throws {
        guard capability.isAllowed else {
            throw ActiveChainSandboxError.capabilityDenied(capability)
        }
    }
}
