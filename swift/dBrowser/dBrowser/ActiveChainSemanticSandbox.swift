import Foundation
import CryptoKit

/// The pinned, network-disabled ActiveChain Phase 1 compatibility boundary.
///
/// This is deliberately a semantic fixture surface. It does not open sockets,
/// start a node, sign, broadcast, spend, or claim network finality.
struct ActiveChainSandboxConfiguration: Codable, Equatable {
    static let current = ActiveChainSandboxConfiguration(
        protocolVersion: "activechain-v1-dev",
        sourceRevision: "aacea4a",
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

    /// Hashes cover the canonical `envelope_hex` bytes from the pinned fixture
    /// snapshot. They are intentionally data-only until ActiveChain exposes a
    /// stable packaged verifier API.
    let vectorSHA256: [String: String]

    init(protocolVersion: String, sourceRevision: String, vectors: [String], vectorSHA256: [String: String] = [:]) {
        self.protocolVersion = protocolVersion
        self.sourceRevision = sourceRevision
        self.vectors = vectors
        self.vectorSHA256 = vectorSHA256
    }

    func validates(expectedRevision: String) -> Bool {
        sourceRevision == expectedRevision && !protocolVersion.isEmpty && !vectors.isEmpty
    }
}

struct ActiveChainCanonicalVector: Equatable {
    let id: String
    let typeTag: UInt16
    let schemaVersion: UInt16
    let envelope: Data
}

enum ActiveChainVectorError: Error, Equatable {
    case missingField(String)
    case invalidHex
    case invalidEnvelope
    case unsupportedVersion
    case trailingBytes
    case hashMismatch
}

extension ActiveChainVectorError {
    var statusMessage: String {
        switch self {
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
        guard envelope.count >= 8 else { throw ActiveChainVectorError.invalidEnvelope }
        guard envelope[0] == UInt8(typeTag >> 8), envelope[1] == UInt8(typeTag & 0xff),
              envelope[2] == UInt8(schemaVersion >> 8), envelope[3] == UInt8(schemaVersion & 0xff) else {
            throw ActiveChainVectorError.unsupportedVersion
        }
        if let expectedTypeTag, expectedTypeTag != typeTag { throw ActiveChainVectorError.unsupportedVersion }
        if let expectedSchemaVersion, expectedSchemaVersion != schemaVersion { throw ActiveChainVectorError.unsupportedVersion }
        let bodyLength = Int(envelope[4]) << 24 | Int(envelope[5]) << 16 | Int(envelope[6]) << 8 | Int(envelope[7])
        guard envelope.count == bodyLength + 8 else { throw ActiveChainVectorError.trailingBytes }
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

    static var verifierStatus: String {
        "local canonical verifier ready; strict version/length/hash checks; failures are fail-closed"
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
