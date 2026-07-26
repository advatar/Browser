import Foundation
import CryptoKit

/// The pinned, network-disabled ActiveChain Phase 1 compatibility boundary.
///
/// This is deliberately a semantic fixture surface. It does not open sockets,
/// start a node, sign, broadcast, spend, or claim network finality.
struct ActiveChainSandboxConfiguration: Codable, Equatable {
    static let supportedVerifierABIRevision: UInt32 = 1
    static let supportedVerifierSchemaRevision: UInt32 = 1
    static let supportedWalletABIRevision: UInt32 = 2
    static let supportedRPCSchemaRevision: UInt32 = 1
    static let supportedLightClientSchemaRevision: UInt32 = 1
    static let supportedProtocolRevisions: [UInt64] = [1]

    static let current = ActiveChainSandboxConfiguration(
        protocolVersion: "activechain-v1-dev",
        sourceRevision: "2befc06bcd1693dffe9a60cd103d6d9139a710b8",
        vectors: [
            "principal-v1",
            "credential-v1",
            "authority-v1",
            "apl-v1",
            "state-tree-v1",
            "devnet-block-v1",
            "dbrowser-wallet-abi-v1",
            "dbrowser-verifier-sdk-v1",
            "dbrowser-development-rpc-v1",
            "finalized-block-v1",
            "light-client-v1",
            "external-anchor-v1"
        ],
        vectorSourceSHA256: [
            "dbrowser-wallet-abi-v1": "ca3af1e9b97823f74687be5900e766a34243a8c49541d58ce37a102c0ebc59a2",
            "dbrowser-verifier-sdk-v1": "434b39f4579af807e69fffb1e439d13c83bb93580576bff72b7f48142fc17340",
            "dbrowser-development-rpc-v1": "8570e146682ed02640f0f75561128bfae777aad80a2e9080845b4b4038423320",
            "finalized-block-v1": "7df74d4bbe8f449afad7c7db5ed8f30ca39da4f76c84272d4b9aa75a93515d1a",
            "light-client-v1": "a75871a6b8a0cf37c8b4e850643111cb1758f2a8acfa4f92d71dc5c1c86a26d5",
            "external-anchor-v1": "5bc58aeff5b1a0baf16467a1fb0dbf37f705ec49abc9681e844485b6aea501d9"
        ]
    )

    let protocolVersion: String
    let sourceRevision: String
    let vectors: [String]
    let walletABIRevision: UInt32
    let verifierABIRevision: UInt32
    let verifierSchemaRevision: UInt32
    let rpcSchemaRevision: UInt32
    let lightClientSchemaRevision: UInt32
    let supportedProtocolRevisions: [UInt64]
    let productionCertified: Bool
    let independentlyAudited: Bool
    let artifactLinked: Bool
    let vectorSourceSHA256: [String: String]

    /// Hashes cover the canonical `envelope_hex` bytes from the pinned fixture
    /// snapshot. They are intentionally data-only until ActiveChain exposes a
    /// stable packaged verifier API.
    let vectorSHA256: [String: String]

    init(
        protocolVersion: String,
        sourceRevision: String,
        vectors: [String],
        vectorSHA256: [String: String] = [:],
        vectorSourceSHA256: [String: String] = [:],
        walletABIRevision: UInt32 = ActiveChainSandboxConfiguration.supportedWalletABIRevision,
        verifierABIRevision: UInt32 = ActiveChainSandboxConfiguration.supportedVerifierABIRevision,
        verifierSchemaRevision: UInt32 = ActiveChainSandboxConfiguration.supportedVerifierSchemaRevision,
        rpcSchemaRevision: UInt32 = ActiveChainSandboxConfiguration.supportedRPCSchemaRevision,
        lightClientSchemaRevision: UInt32 = ActiveChainSandboxConfiguration.supportedLightClientSchemaRevision,
        supportedProtocolRevisions: [UInt64] = ActiveChainSandboxConfiguration.supportedProtocolRevisions,
        productionCertified: Bool = false,
        independentlyAudited: Bool = false,
        artifactLinked: Bool = false
    ) {
        self.protocolVersion = protocolVersion
        self.sourceRevision = sourceRevision
        self.vectors = vectors
        self.vectorSHA256 = vectorSHA256
        self.vectorSourceSHA256 = vectorSourceSHA256
        self.walletABIRevision = walletABIRevision
        self.verifierABIRevision = verifierABIRevision
        self.verifierSchemaRevision = verifierSchemaRevision
        self.rpcSchemaRevision = rpcSchemaRevision
        self.lightClientSchemaRevision = lightClientSchemaRevision
        self.supportedProtocolRevisions = supportedProtocolRevisions
        self.productionCertified = productionCertified
        self.independentlyAudited = independentlyAudited
        self.artifactLinked = artifactLinked
    }

    func validates(expectedRevision: String) -> Bool {
        sourceRevision == expectedRevision && !protocolVersion.isEmpty && !vectors.isEmpty
    }
}

struct ActiveChainCompatibilitySchema: Codable, Equatable {
    let name: String
    let typeTag: String
    let schemaRevision: UInt16
}

struct ActiveChainCompatibilityArtifact: Codable, Equatable {
    let path: String
    let sha256: String
}

struct ActiveChainCompatibilityManifest: Codable, Equatable {
    let format: String
    let sourceRevision: String
    let releaseStatus: String
    let independentlyAudited: Bool
    let verifierABIRevision: UInt32
    let verifierSchemaRevision: UInt32
    let walletABIRevision: UInt32
    let rpcSchemaRevision: UInt32
    let lightClientSchemaRevision: UInt32
    let minimumProtocolRevision: UInt64
    let supportedProtocolRevisions: [UInt64]
    let schemas: [ActiveChainCompatibilitySchema]
    let appleSlices: [String]
    let upgradePolicy: String
    let artifacts: [ActiveChainCompatibilityArtifact]

    enum CodingKeys: String, CodingKey {
        case format
        case sourceRevision = "source_revision"
        case releaseStatus = "release_status"
        case independentlyAudited = "independently_audited"
        case verifierABIRevision = "verifier_abi_revision"
        case verifierSchemaRevision = "verifier_schema_revision"
        case walletABIRevision = "wallet_abi_revision"
        case rpcSchemaRevision = "rpc_schema_revision"
        case lightClientSchemaRevision = "light_client_schema_revision"
        case minimumProtocolRevision = "minimum_protocol_revision"
        case supportedProtocolRevisions = "supported_protocol_revisions"
        case schemas
        case appleSlices = "apple_slices"
        case upgradePolicy = "upgrade_policy"
        case artifacts
    }
}

enum ActiveChainCompatibilityError: Error, Equatable {
    case incompatibleFormat
    case unsupportedSourceRevision
    case unsupportedReleaseStatus
    case auditClaimUnsupported
    case unsupportedVerifierABI(UInt32)
    case unsupportedVerifierSchema(UInt32)
    case unsupportedWalletABI(UInt32)
    case unsupportedRPCSchema(UInt32)
    case unsupportedLightClientSchema(UInt32)
    case unsupportedProtocolRevision
    case unsupportedSchemas
    case unsupportedAppleSlices
    case unsupportedUpgradePolicy
    case invalidArtifacts
}

struct ActiveChainCompatibilityPolicy {
    static let expectedSchemas = [
        ActiveChainCompatibilitySchema(name: "Principal", typeTag: "0x0020", schemaRevision: 1),
        ActiveChainCompatibilitySchema(name: "CapabilityGrant", typeTag: "0x0030", schemaRevision: 1),
        ActiveChainCompatibilitySchema(name: "PolicyDecision", typeTag: "0x0042", schemaRevision: 1),
        ActiveChainCompatibilitySchema(name: "StateProof", typeTag: "0x0055", schemaRevision: 1),
        ActiveChainCompatibilitySchema(name: "StateCommitment", typeTag: "0x0056", schemaRevision: 1),
        ActiveChainCompatibilitySchema(name: "BlockReceipt", typeTag: "0x0074", schemaRevision: 1),
        ActiveChainCompatibilitySchema(name: "FinalityCertificateBundle", typeTag: "0x007a", schemaRevision: 1),
        ActiveChainCompatibilitySchema(name: "CashAuthorizationRequestV1", typeTag: "0x008a", schemaRevision: 1),
        ActiveChainCompatibilitySchema(name: "AuthorizedCashTransferV1", typeTag: "0x008b", schemaRevision: 1)
    ]

    static let expectedAppleSlices = [
        "aarch64-apple-darwin",
        "x86_64-apple-darwin",
        "aarch64-apple-ios",
        "aarch64-apple-ios-sim"
    ]

    func validateMetadata(_ manifest: ActiveChainCompatibilityManifest) throws {
        guard manifest.format == "activechain-apple-compatibility-v1" else { throw ActiveChainCompatibilityError.incompatibleFormat }
        guard manifest.sourceRevision == ActiveChainSandboxConfiguration.current.sourceRevision else { throw ActiveChainCompatibilityError.unsupportedSourceRevision }
        guard manifest.releaseStatus == "developmental-unaudited" else { throw ActiveChainCompatibilityError.unsupportedReleaseStatus }
        guard !manifest.independentlyAudited else { throw ActiveChainCompatibilityError.auditClaimUnsupported }
        guard manifest.verifierABIRevision == ActiveChainSandboxConfiguration.supportedVerifierABIRevision else { throw ActiveChainCompatibilityError.unsupportedVerifierABI(manifest.verifierABIRevision) }
        guard manifest.verifierSchemaRevision == ActiveChainSandboxConfiguration.supportedVerifierSchemaRevision else { throw ActiveChainCompatibilityError.unsupportedVerifierSchema(manifest.verifierSchemaRevision) }
        guard manifest.walletABIRevision == ActiveChainSandboxConfiguration.supportedWalletABIRevision else { throw ActiveChainCompatibilityError.unsupportedWalletABI(manifest.walletABIRevision) }
        guard manifest.rpcSchemaRevision == ActiveChainSandboxConfiguration.supportedRPCSchemaRevision else { throw ActiveChainCompatibilityError.unsupportedRPCSchema(manifest.rpcSchemaRevision) }
        guard manifest.lightClientSchemaRevision == ActiveChainSandboxConfiguration.supportedLightClientSchemaRevision else { throw ActiveChainCompatibilityError.unsupportedLightClientSchema(manifest.lightClientSchemaRevision) }
        guard manifest.minimumProtocolRevision == 1,
              manifest.supportedProtocolRevisions == ActiveChainSandboxConfiguration.supportedProtocolRevisions else { throw ActiveChainCompatibilityError.unsupportedProtocolRevision }
        guard manifest.schemas == Self.expectedSchemas else { throw ActiveChainCompatibilityError.unsupportedSchemas }
        guard manifest.appleSlices == Self.expectedAppleSlices else { throw ActiveChainCompatibilityError.unsupportedAppleSlices }
        guard manifest.upgradePolicy == "reject-unknown-abi-schema-or-protocol-revision" else { throw ActiveChainCompatibilityError.unsupportedUpgradePolicy }
        guard !manifest.artifacts.isEmpty,
              zip(manifest.artifacts, manifest.artifacts.dropFirst()).allSatisfy({ $0.0.path < $0.1.path }),
              manifest.artifacts.allSatisfy({ !$0.path.isEmpty && $0.sha256.isLowercaseHex(count: 64) }) else {
            throw ActiveChainCompatibilityError.invalidArtifacts
        }
    }
}

enum ActiveChainVerifierDisposition: String, Codable, Equatable {
    case verified
    case invalid
    case unsupported
    case unavailable
}

struct ActiveChainVerifierOutcome: Codable, Equatable {
    let disposition: ActiveChainVerifierDisposition
    let chainID: String
    let genesisCommitment: String
    let protocolRevision: UInt64
    let verifierRevision: UInt32
    let finalizedHeight: UInt64?
    let verifiedCommitment: String?

    func isAccepted(expectedChainID: String, expectedGenesis: String) -> Bool {
        disposition == .verified
            && chainID == expectedChainID
            && genesisCommitment == expectedGenesis
            && protocolRevision == 1
            && verifierRevision == ActiveChainSandboxConfiguration.supportedVerifierABIRevision
            && finalizedHeight != nil
            && verifiedCommitment?.isLowercaseHex(count: 96) == true
    }
}

struct ActiveChainDevelopmentRPCStatus: Codable, Equatable {
    let chainID: String
    let genesisCommitment: String
    let protocolRevision: UInt64
    let finalizedHeight: UInt64
    let finalizedBlockHash: String
    let finalizedAt: Date
    let healthy: Bool
    let supportedProofProfiles: [String]
    let verifierRevision: UInt32
}

enum ActiveChainDevelopmentRPCError: Error, Equatable {
    case wrongChain
    case wrongGenesis
    case unsupportedProtocolRevision
    case unsupportedVerifierRevision
    case unhealthy
    case stale
    case missingFinality
    case invalidProofProfiles
}

struct ActiveChainDevelopmentRPCPolicy {
    let expectedChainID: String
    let expectedGenesis: String
    let maximumStaleness: TimeInterval

    func validate(_ status: ActiveChainDevelopmentRPCStatus, now: Date = Date()) throws {
        guard status.chainID == expectedChainID else { throw ActiveChainDevelopmentRPCError.wrongChain }
        guard status.genesisCommitment == expectedGenesis else { throw ActiveChainDevelopmentRPCError.wrongGenesis }
        guard status.protocolRevision == 1 else { throw ActiveChainDevelopmentRPCError.unsupportedProtocolRevision }
        guard status.verifierRevision == ActiveChainSandboxConfiguration.supportedVerifierABIRevision else { throw ActiveChainDevelopmentRPCError.unsupportedVerifierRevision }
        guard status.healthy else { throw ActiveChainDevelopmentRPCError.unhealthy }
        guard now.timeIntervalSince(status.finalizedAt) >= 0,
              now.timeIntervalSince(status.finalizedAt) <= maximumStaleness else { throw ActiveChainDevelopmentRPCError.stale }
        guard status.finalizedHeight > 0,
              status.finalizedBlockHash.isLowercaseHex(count: 96) else { throw ActiveChainDevelopmentRPCError.missingFinality }
        guard !status.supportedProofProfiles.isEmpty,
              Set(status.supportedProofProfiles).count == status.supportedProofProfiles.count,
              status.supportedProofProfiles.allSatisfy({ !$0.isEmpty }) else { throw ActiveChainDevelopmentRPCError.invalidProofProfiles }
    }
}

private extension String {
    func isLowercaseHex(count: Int) -> Bool {
        self.count == count && utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

struct ActiveChainCanonicalVector: Equatable {
    let id: String
    let typeTag: UInt16
    let schemaVersion: UInt16
    let envelope: Data
}

enum ActiveChainVectorError: Error, Equatable {
    case tooLarge
    case typeMismatch
    case missingField(String)
    case invalidHex
    case invalidEnvelope
    case unsupportedVersion
    case trailingBytes
    case hashMismatch

    var code: UInt32 {
        switch self {
        case .tooLarge: 1
        case .missingField, .invalidHex, .invalidEnvelope, .trailingBytes: 2
        case .typeMismatch: 3
        case .unsupportedVersion: 4
        case .hashMismatch: 5
        }
    }
}

extension ActiveChainVectorError {
    var statusMessage: String {
        switch self {
        case .tooLarge: "envelope too large"
        case .typeMismatch: "type mismatch"
        case .missingField(let field): "missing \(field)"
        case .invalidHex: "invalid hex"
        case .invalidEnvelope: "invalid envelope"
        case .unsupportedVersion: "unsupported version"
        case .trailingBytes: "trailing bytes"
        case .hashMismatch: "hash mismatch"
        }
    }
}

struct ActiveChainCanonicalVectorVerifier {
    let configuration: ActiveChainSandboxConfiguration

    func verify(_ text: String, expectedVectorID: String, expectedTypeTag: UInt16? = nil, expectedSchemaVersion: UInt16? = nil) throws -> ActiveChainCanonicalVector {
        let fields = text.split(whereSeparator: \.isNewline).reduce(into: [String: String]()) { result, line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { return }
            result[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        guard fields["vector"] == expectedVectorID else { throw ActiveChainVectorError.missingField("vector") }
        guard let type = fields["type_tag"], let version = fields["schema_version"],
              let envelopeHex = fields["envelope_hex"] else { throw ActiveChainVectorError.missingField("envelope") }
        guard let typeTag = UInt16(type.dropFirst(2), radix: 16), let schemaVersion = UInt16(version),
              let envelope = Data(hexString: envelopeHex) else { throw ActiveChainVectorError.invalidHex }
        guard envelope.count <= 256 * 1024 else { throw ActiveChainVectorError.tooLarge }
        guard envelope.count >= 5 else { throw ActiveChainVectorError.invalidEnvelope }
        guard envelope[0] == UInt8(typeTag >> 8), envelope[1] == UInt8(typeTag & 0xff),
              envelope[2] == UInt8(schemaVersion >> 8), envelope[3] == UInt8(schemaVersion & 0xff) else {
            throw ActiveChainVectorError.unsupportedVersion
        }
        if let expectedTypeTag, expectedTypeTag != typeTag { throw ActiveChainVectorError.typeMismatch }
        if let expectedSchemaVersion, expectedSchemaVersion != schemaVersion { throw ActiveChainVectorError.unsupportedVersion }
        var bodyLength = 0
        var shift = 0
        var cursor = 4
        while cursor < envelope.count {
            let byte = envelope[cursor]
            bodyLength |= Int(byte & 0x7f) << shift
            cursor += 1
            if byte & 0x80 == 0 { break }
            shift += 7
            if shift > 28 { throw ActiveChainVectorError.invalidEnvelope }
        }
        guard cursor + bodyLength == envelope.count else { throw ActiveChainVectorError.trailingBytes }
        if let expectedHash = configuration.vectorSHA256[expectedVectorID],
           SHA256.hash(data: envelope).hexString != expectedHash { throw ActiveChainVectorError.hashMismatch }
        return ActiveChainCanonicalVector(id: expectedVectorID, typeTag: typeTag, schemaVersion: schemaVersion, envelope: envelope)
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        self.init((0..<hexString.count / 2).compactMap { index in
            let start = hexString.index(hexString.startIndex, offsetBy: index * 2)
            return UInt8(hexString[start..<hexString.index(start, offsetBy: 2)], radix: 16)
        })
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
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
    case networkIngress
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
    case unsupportedWalletABIRevision(UInt32)
    case productionCertificationUnsupported
    case capabilityDenied(ActiveChainSandboxCapability)
    case unknownVector(String)
}

struct ActiveChainSemanticSandbox {
    static var runtimeSummary: String {
        let configuration = ActiveChainSandboxConfiguration.current
        return "ActiveChain sandbox \(configuration.protocolVersion) @ \(configuration.sourceRevision); verifier ABI/schema v\(configuration.verifierABIRevision)/v\(configuration.verifierSchemaRevision); wallet ABI v\(configuration.walletABIRevision); RPC/light-client schema v\(configuration.rpcSchemaRevision)/v\(configuration.lightClientSchemaRevision); artifact linked: \(configuration.artifactLinked); independently audited: \(configuration.independentlyAudited); development-only; production certified: \(configuration.productionCertified); no network finality"
    }

    static var verifierStatus: String {
        "downstream verifier contract ready; packaged verifier artifact not linked; local fixture checks only; failures are fail-closed"
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
        guard configuration.walletABIRevision == ActiveChainSandboxConfiguration.supportedWalletABIRevision else {
            throw ActiveChainSandboxError.unsupportedWalletABIRevision(configuration.walletABIRevision)
        }
        guard configuration.verifierABIRevision == ActiveChainSandboxConfiguration.supportedVerifierABIRevision,
              configuration.verifierSchemaRevision == ActiveChainSandboxConfiguration.supportedVerifierSchemaRevision,
              configuration.rpcSchemaRevision == ActiveChainSandboxConfiguration.supportedRPCSchemaRevision,
              configuration.lightClientSchemaRevision == ActiveChainSandboxConfiguration.supportedLightClientSchemaRevision,
              configuration.supportedProtocolRevisions == ActiveChainSandboxConfiguration.supportedProtocolRevisions else {
            throw ActiveChainSandboxError.unsupportedProtocolVersion
        }
        guard !configuration.productionCertified else {
            throw ActiveChainSandboxError.productionCertificationUnsupported
        }
        guard !configuration.independentlyAudited, !configuration.artifactLinked else {
            throw ActiveChainSandboxError.productionCertificationUnsupported
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
