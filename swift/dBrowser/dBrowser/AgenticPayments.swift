import CryptoKit
import Foundation

enum EUDIWalletIntegrationMode: String, CaseIterable, Codable, Equatable {
    case referenceFixture
    case walletCompatibleClient
    case certifiedWalletProvider

    var title: String {
        switch self {
        case .referenceFixture: "Reference fixture"
        case .walletCompatibleClient: "Wallet-compatible client"
        case .certifiedWalletProvider: "Certified wallet provider"
        }
    }

    var canClaimCertification: Bool {
        self == .certifiedWalletProvider
    }
}

enum EUDICredentialKind: String, CaseIterable, Codable, Equatable {
    case personIdentificationData
    case mobileDrivingLicence
    case qualifiedAttribute
    case pseudonym
    case paymentAuthentication
    case verifiedEmail

    var title: String {
        switch self {
        case .personIdentificationData: "PID"
        case .mobileDrivingLicence: "mDL"
        case .qualifiedAttribute: "Qualified attribute"
        case .pseudonym: "Pseudonym"
        case .paymentAuthentication: "Payment authentication"
        case .verifiedEmail: "Verified email"
        }
    }
}

enum EUDIPresentationProtocol: String, CaseIterable, Codable, Equatable {
    case openID4VP
    case openID4VCI
    case iso18013Proximity
    case sdJWTVC
    case pseudonym

    var title: String {
        switch self {
        case .openID4VP: "OpenID4VP"
        case .openID4VCI: "OpenID4VCI"
        case .iso18013Proximity: "ISO 18013-5 proximity"
        case .sdJWTVC: "SD-JWT VC"
        case .pseudonym: "Pseudonym"
        }
    }
}

struct EUDIWalletProfile: Codable, Equatable {
    var mode: EUDIWalletIntegrationMode
    var supportedProtocols: [EUDIPresentationProtocol]
    var supportedCredentialKinds: [EUDICredentialKind]
    var usesKeychainStorage: Bool
    var usesSecureEnclave: Bool
    var certificationNote: String

    static let dbrowserReference = EUDIWalletProfile(
        mode: .walletCompatibleClient,
        supportedProtocols: [.openID4VP, .openID4VCI, .iso18013Proximity, .sdJWTVC, .pseudonym],
        supportedCredentialKinds: [.personIdentificationData, .mobileDrivingLicence, .qualifiedAttribute, .pseudonym, .paymentAuthentication, .verifiedEmail],
        usesKeychainStorage: true,
        usesSecureEnclave: true,
        certificationNote: "Wallet-compatible client and fixture support; not a certified EUDI wallet provider."
    )

    var canUseForProductionWalletProviderClaim: Bool {
        mode.canClaimCertification
    }
}

struct EUDICredentialDocument: Codable, Equatable, Identifiable {
    let id: String
    var kind: EUDICredentialKind
    var issuer: String
    var subjectHint: String
    var claims: [String: String]
    var issuedAt: Date
    var expiresAt: Date?
    var isRevoked: Bool

    var isUsable: Bool {
        !isRevoked && expiresAt.map { $0 > Date() } != false
    }
}

enum EUDIEmailCredentialSubjectType: String, Codable, Equatable {
    case user
    case agent
}

struct EUDIEmailCredentialHolderBinding: Codable, Equatable {
    var holderDID: String
    var holderPublicKeyJWK: [String: String]
    var holderJWKThumbprint: String

    enum CodingKeys: String, CodingKey {
        case holderDID = "holder_did"
        case holderPublicKeyJWK = "holder_public_key_jwk"
        case holderJWKThumbprint = "holder_jwk_thumbprint"
    }
}

struct EUDIEmailCredentialAgentBinding: Codable, Equatable {
    var agentInstanceID: String?
    var agentClass: String?
    var operatorHint: String?

    enum CodingKeys: String, CodingKey {
        case agentInstanceID = "agent_instance_id"
        case agentClass = "agent_class"
        case operatorHint = "operator_hint"
    }
}

struct EUDIEmailCredentialSubject: Codable, Equatable {
    var id: String
    var email: String
    var emailNormalized: String
    var emailVerified: Bool
    var subjectType: EUDIEmailCredentialSubjectType
    var holder: EUDIEmailCredentialHolderBinding
    var agent: EUDIEmailCredentialAgentBinding?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case emailNormalized = "email_normalized"
        case emailVerified = "email_verified"
        case subjectType = "subject_type"
        case holder
        case agent
    }
}

struct EUDIEmailCredentialEvidence: Codable, Equatable {
    var method: String
    var challengeID: String?
    var nonceHash: String?
    var emailHash: String?
    var verifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case method
        case challengeID = "challenge_id"
        case nonceHash = "nonce_hash"
        case emailHash = "email_hash"
        case verifiedAt = "verified_at"
    }

    init(method: String, challengeID: String? = nil, nonceHash: String? = nil, emailHash: String? = nil, verifiedAt: Date? = nil) {
        self.method = method
        self.challengeID = challengeID
        self.nonceHash = nonceHash
        self.emailHash = emailHash
        self.verifiedAt = verifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(String.self, forKey: .method)
        challengeID = try container.decodeIfPresent(String.self, forKey: .challengeID)
        nonceHash = try container.decodeIfPresent(String.self, forKey: .nonceHash)
        emailHash = try container.decodeIfPresent(String.self, forKey: .emailHash)
        if let verifiedAtString = try container.decodeIfPresent(String.self, forKey: .verifiedAt) {
            verifiedAt = EUDIEmailCredentialDateCoding.date(from: verifiedAtString)
        } else {
            verifiedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(challengeID, forKey: .challengeID)
        try container.encodeIfPresent(nonceHash, forKey: .nonceHash)
        try container.encodeIfPresent(emailHash, forKey: .emailHash)
        if let verifiedAt {
            try container.encode(EUDIEmailCredentialDateCoding.string(from: verifiedAt), forKey: .verifiedAt)
        }
    }
}

struct EUDIEmailAddressCredential: Codable, Equatable, Identifiable {
    let id: String
    var context: [String]
    var types: [String]
    var issuer: String
    var validFrom: Date
    var validUntil: Date
    var credentialSubject: EUDIEmailCredentialSubject
    var evidence: [EUDIEmailCredentialEvidence]

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case id
        case types = "type"
        case issuer
        case validFrom
        case validUntil
        case credentialSubject
        case evidence
    }

    init(
        id: String,
        context: [String],
        types: [String],
        issuer: String,
        validFrom: Date,
        validUntil: Date,
        credentialSubject: EUDIEmailCredentialSubject,
        evidence: [EUDIEmailCredentialEvidence]
    ) {
        self.id = id
        self.context = context
        self.types = types
        self.issuer = issuer
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.credentialSubject = credentialSubject
        self.evidence = evidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        context = try container.decode([String].self, forKey: .context)
        types = try container.decode([String].self, forKey: .types)
        issuer = try container.decode(String.self, forKey: .issuer)
        let validFromString = try container.decode(String.self, forKey: .validFrom)
        let validUntilString = try container.decode(String.self, forKey: .validUntil)
        guard let decodedValidFrom = EUDIEmailCredentialDateCoding.date(from: validFromString),
              let decodedValidUntil = EUDIEmailCredentialDateCoding.date(from: validUntilString) else {
            throw DecodingError.dataCorruptedError(forKey: .validUntil, in: container, debugDescription: "Email credential dates must be ISO 8601 strings.")
        }
        validFrom = decodedValidFrom
        validUntil = decodedValidUntil
        credentialSubject = try container.decode(EUDIEmailCredentialSubject.self, forKey: .credentialSubject)
        evidence = try container.decodeIfPresent([EUDIEmailCredentialEvidence].self, forKey: .evidence) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(context, forKey: .context)
        try container.encode(id, forKey: .id)
        try container.encode(types, forKey: .types)
        try container.encode(issuer, forKey: .issuer)
        try container.encode(EUDIEmailCredentialDateCoding.string(from: validFrom), forKey: .validFrom)
        try container.encode(EUDIEmailCredentialDateCoding.string(from: validUntil), forKey: .validUntil)
        try container.encode(credentialSubject, forKey: .credentialSubject)
        if !evidence.isEmpty {
            try container.encode(evidence, forKey: .evidence)
        }
    }

    var credentialHash: String {
        AgenticPaymentHash.stable([
            id,
            issuer,
            credentialSubject.id,
            credentialSubject.emailNormalized,
            credentialSubject.holder.holderDID,
            credentialSubject.holder.holderJWKThumbprint
        ])
    }
}

private enum EUDIEmailCredentialDateCoding {
    private static let internetFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        internetFormatter.date(from: string) ?? fractionalFormatter.date(from: string)
    }

    static func string(from date: Date) -> String {
        internetFormatter.string(from: date)
    }
}

enum EUDIEmailCredentialImportStatus: String, Codable, Equatable {
    case imported
    case unsupportedFormat
    case invalidCredential
    case unverifiedEmail
    case nonHumanSubject
    case expired
    case signatureRejected
}

struct EUDIEmailCredentialImportResult: Equatable {
    var status: EUDIEmailCredentialImportStatus
    var sourceCredential: EUDIEmailAddressCredential?
    var document: EUDICredentialDocument?
    var reasons: [String]
    var signatureTrust: EUDICredentialSignatureTrust = .unverifiedEnvelope

    var isImported: Bool {
        status == .imported && document != nil
    }

    /// True only when the credential was imported AND its issuer signature was cryptographically verified.
    var isCryptographicallyVerified: Bool {
        isImported && signatureTrust == .issuerSignatureVerified
    }
}

enum EUDIEmailCredentialImportError: Error, Equatable {
    case compactJWTRequiresVerification
    case invalidJSONEnvelope
    case missingCredentialObject
    case invalidCredentialJSON(String)
}

enum EUDIEmailCredentialEnvelopeDecoder {
    static func decodeCredential(from data: Data) throws -> EUDIEmailAddressCredential {
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.hasPrefix("{") && trimmed.split(separator: ".").count == 3 {
            throw EUDIEmailCredentialImportError.compactJWTRequiresVerification
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw EUDIEmailCredentialImportError.invalidCredentialJSON(error.localizedDescription)
        }
        guard let envelope = jsonObject as? [String: Any] else {
            throw EUDIEmailCredentialImportError.invalidJSONEnvelope
        }

        if envelope["credentialSubject"] is [String: Any] {
            return try decodeCredentialObject(data)
        }
        if let credentialObject = envelope["credential"] as? [String: Any] {
            let credentialData = try JSONSerialization.data(withJSONObject: credentialObject, options: [])
            return try decodeCredentialObject(credentialData)
        }
        if let vcJWT = envelope["vc_jwt"] as? String, !vcJWT.isEmpty {
            throw EUDIEmailCredentialImportError.compactJWTRequiresVerification
        }

        throw EUDIEmailCredentialImportError.missingCredentialObject
    }

    private static func decodeCredentialObject(_ data: Data) throws -> EUDIEmailAddressCredential {
        do {
            return try JSONDecoder().decode(EUDIEmailAddressCredential.self, from: data)
        } catch {
            throw EUDIEmailCredentialImportError.invalidCredentialJSON(error.localizedDescription)
        }
    }
}

// MARK: - EUDI issuer trust store and real VC-JWT signature verification

/// Cryptographic trust state of an imported credential. The distinction is load-bearing:
/// `issuerSignatureVerified` means an issuer signature was checked against a trusted key,
/// while `unverifiedEnvelope` means the credential arrived as a bare JSON envelope whose
/// authenticity dBrowser has NOT cryptographically verified.
enum EUDICredentialSignatureTrust: String, Codable, Equatable {
    case issuerSignatureVerified = "issuer_signature_verified"
    case unverifiedEnvelope = "unverified_envelope"

    var label: String {
        switch self {
        case .issuerSignatureVerified: return "Issuer signature verified"
        case .unverifiedEnvelope: return "Unverified envelope"
        }
    }
}

enum EUDIIssuerSignatureAlgorithm: String, Codable, Equatable {
    case es256 = "ES256" // ECDSA over P-256 with SHA-256
    case eddsa = "EdDSA" // Ed25519
}

/// A trusted issuer signing key, normally sourced from an issuer JWKS endpoint or a pinned
/// allowlist. `publicKeyRaw` is the raw key representation: 64-byte x||y for ES256 P-256,
/// 32-byte compressed point for Ed25519.
struct EUDIIssuerKey: Equatable, Identifiable {
    var keyID: String
    var algorithm: EUDIIssuerSignatureAlgorithm
    var publicKeyRaw: Data
    var id: String { keyID }
}

struct EUDIIssuerTrustStore: Equatable {
    private(set) var keysByID: [String: EUDIIssuerKey]

    init(keys: [EUDIIssuerKey] = []) {
        var map: [String: EUDIIssuerKey] = [:]
        for key in keys { map[key.keyID] = key }
        keysByID = map
    }

    func key(forID keyID: String) -> EUDIIssuerKey? { keysByID[keyID] }

    var isEmpty: Bool { keysByID.isEmpty }
}

enum EUDIVerifiableCredentialJWTError: Error, Equatable {
    case malformedJWT
    case unsupportedAlgorithm(String)
    case unknownIssuerKey(String)
    case algorithmMismatch(String)
    case signatureVerificationFailed
    case credentialDecodingFailed(String)

    var reason: String {
        switch self {
        case .malformedJWT:
            return "VC-JWT is not a well-formed compact JWS (header.payload.signature)."
        case let .unsupportedAlgorithm(alg):
            return "VC-JWT signature algorithm \(alg) is not supported; expected ES256 or EdDSA."
        case let .unknownIssuerKey(kid):
            return "VC-JWT key id \(kid) is not present in the configured issuer trust store."
        case let .algorithmMismatch(kid):
            return "VC-JWT algorithm does not match the trusted key \(kid)."
        case .signatureVerificationFailed:
            return "VC-JWT issuer signature did not verify against the trusted issuer key."
        case let .credentialDecodingFailed(detail):
            return "VC-JWT payload did not contain a decodable email credential: \(detail)."
        }
    }
}

/// Performs real issuer-signature verification of a compact VC-JWT using CryptoKit. This is the
/// anchor that makes the agent identity/delegation chain trustworthy: a forged credential with
/// `email_verified: true` but no valid issuer signature is rejected here instead of imported.
enum EUDIVerifiableCredentialJWTVerifier {
    static func verify(
        compactJWT: String,
        trustStore: EUDIIssuerTrustStore,
        now: Date = Date()
    ) -> Result<EUDIEmailAddressCredential, EUDIVerifiableCredentialJWTError> {
        let segments = compactJWT.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return .failure(.malformedJWT) }
        let headerSegment = String(segments[0])
        let payloadSegment = String(segments[1])
        let signatureSegment = String(segments[2])

        guard
            let headerData = base64URLDecode(headerSegment),
            let payloadData = base64URLDecode(payloadSegment),
            let signatureData = base64URLDecode(signatureSegment),
            let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        else {
            return .failure(.malformedJWT)
        }

        guard let algString = header["alg"] as? String else { return .failure(.malformedJWT) }
        guard let algorithm = EUDIIssuerSignatureAlgorithm(rawValue: algString) else {
            return .failure(.unsupportedAlgorithm(algString))
        }
        guard let keyID = header["kid"] as? String else { return .failure(.malformedJWT) }
        guard let issuerKey = trustStore.key(forID: keyID) else {
            return .failure(.unknownIssuerKey(keyID))
        }
        guard issuerKey.algorithm == algorithm else {
            return .failure(.algorithmMismatch(keyID))
        }

        let signingInput = Data("\(headerSegment).\(payloadSegment)".utf8)
        guard verifySignature(signatureData, over: signingInput, with: issuerKey) else {
            return .failure(.signatureVerificationFailed)
        }

        do {
            let credential = try decodeCredential(fromPayload: payloadData)
            return .success(credential)
        } catch {
            return .failure(.credentialDecodingFailed(error.localizedDescription))
        }
    }

    private static func verifySignature(
        _ signature: Data,
        over message: Data,
        with key: EUDIIssuerKey
    ) -> Bool {
        switch key.algorithm {
        case .es256:
            guard
                let publicKey = try? P256.Signing.PublicKey(rawRepresentation: key.publicKeyRaw),
                let parsedSignature = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
            else { return false }
            return publicKey.isValidSignature(parsedSignature, for: message)
        case .eddsa:
            guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key.publicKeyRaw) else {
                return false
            }
            return publicKey.isValidSignature(signature, for: message)
        }
    }

    /// Accepts either a W3C VC-JWT payload (credential under the `vc` claim) or a payload whose
    /// top level is the credential object itself.
    private static func decodeCredential(fromPayload payloadData: Data) throws -> EUDIEmailAddressCredential {
        if
            let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let vcObject = payload["vc"] as? [String: Any]
        {
            let vcData = try JSONSerialization.data(withJSONObject: vcObject, options: [])
            return try EUDIEmailCredentialEnvelopeDecoder.decodeCredential(from: vcData)
        }
        return try EUDIEmailCredentialEnvelopeDecoder.decodeCredential(from: payloadData)
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}

enum EUDIEmailCredentialImporter {
    static func importHumanVerifiedEmail(
        from data: Data,
        trustStore: EUDIIssuerTrustStore? = nil,
        now: Date = Date()
    ) -> EUDIEmailCredentialImportResult {
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let looksLikeCompactJWT = !raw.hasPrefix("{") && raw.split(separator: ".").count == 3
        if looksLikeCompactJWT {
            guard let trustStore, !trustStore.isEmpty else {
                return EUDIEmailCredentialImportResult(
                    status: .unsupportedFormat,
                    sourceCredential: nil,
                    document: nil,
                    reasons: ["Compact VC-JWT input requires a configured issuer trust store (JWKS) before import."]
                )
            }
            switch EUDIVerifiableCredentialJWTVerifier.verify(compactJWT: raw, trustStore: trustStore, now: now) {
            case let .success(credential):
                return importHumanVerifiedEmail(credential, signatureTrust: .issuerSignatureVerified, now: now)
            case let .failure(error):
                return EUDIEmailCredentialImportResult(
                    status: .signatureRejected,
                    sourceCredential: nil,
                    document: nil,
                    reasons: [error.reason]
                )
            }
        }

        do {
            let credential = try EUDIEmailCredentialEnvelopeDecoder.decodeCredential(from: data)
            return importHumanVerifiedEmail(credential, signatureTrust: .unverifiedEnvelope, now: now)
        } catch EUDIEmailCredentialImportError.compactJWTRequiresVerification {
            return EUDIEmailCredentialImportResult(
                status: .unsupportedFormat,
                sourceCredential: nil,
                document: nil,
                reasons: ["Compact VC-JWT input requires a configured issuer trust store (JWKS) before import."]
            )
        } catch {
            return EUDIEmailCredentialImportResult(
                status: .invalidCredential,
                sourceCredential: nil,
                document: nil,
                reasons: ["Email credential JSON could not be decoded: \(error.localizedDescription)"]
            )
        }
    }

    static func importHumanVerifiedEmail(
        _ credential: EUDIEmailAddressCredential,
        signatureTrust: EUDICredentialSignatureTrust = .unverifiedEnvelope,
        now: Date = Date()
    ) -> EUDIEmailCredentialImportResult {
        guard credential.types.contains("EmailAddressCredential") else {
            return EUDIEmailCredentialImportResult(
                status: .invalidCredential,
                sourceCredential: credential,
                document: nil,
                reasons: ["Credential type does not include EmailAddressCredential."]
            )
        }
        guard credential.credentialSubject.emailVerified else {
            return EUDIEmailCredentialImportResult(
                status: .unverifiedEmail,
                sourceCredential: credential,
                document: nil,
                reasons: ["Email credential is not marked as verified."]
            )
        }
        guard credential.credentialSubject.subjectType == .user else {
            return EUDIEmailCredentialImportResult(
                status: .nonHumanSubject,
                sourceCredential: credential,
                document: nil,
                reasons: ["Human wallet import requires subject_type=user."]
            )
        }
        guard credential.validUntil > now else {
            return EUDIEmailCredentialImportResult(
                status: .expired,
                sourceCredential: credential,
                document: nil,
                reasons: ["Email credential is expired."]
            )
        }
        guard credential.credentialSubject.id == credential.credentialSubject.holder.holderDID else {
            return EUDIEmailCredentialImportResult(
                status: .invalidCredential,
                sourceCredential: credential,
                document: nil,
                reasons: ["Credential subject is not bound to the holder DID."]
            )
        }

        let subject = credential.credentialSubject
        let document = EUDICredentialDocument(
            id: credential.id,
            kind: .verifiedEmail,
            issuer: credential.issuer,
            subjectHint: subject.emailNormalized,
            claims: [
                "email": subject.email,
                "email_normalized": subject.emailNormalized,
                "email_verified": subject.emailVerified ? "true" : "false",
                "holder_did": subject.holder.holderDID,
                "holder_jwk_thumbprint": subject.holder.holderJWKThumbprint,
                "source_credential_id": credential.id,
                "source_credential_hash": credential.credentialHash,
                "subject_type": subject.subjectType.rawValue,
                "signature_trust": signatureTrust.rawValue
            ],
            issuedAt: credential.validFrom,
            expiresAt: credential.validUntil,
            isRevoked: false
        )

        let trustReason: String
        switch signatureTrust {
        case .issuerSignatureVerified:
            trustReason = "Issuer VC-JWT signature verified; imported into the human identity vault."
        case .unverifiedEnvelope:
            trustReason = "Imported into the human identity vault from an unverified JSON envelope; issuer signature was not cryptographically checked."
        }

        return EUDIEmailCredentialImportResult(
            status: .imported,
            sourceCredential: credential,
            document: document,
            reasons: [trustReason],
            signatureTrust: signatureTrust
        )
    }
}

struct EUDIAttributeRequest: Codable, Equatable, Identifiable {
    let id: String
    var claimName: String
    var purpose: String
    var isRequired: Bool

    init(id: String? = nil, claimName: String, purpose: String, isRequired: Bool) {
        self.id = id ?? claimName
        self.claimName = claimName
        self.purpose = purpose
        self.isRequired = isRequired
    }
}

struct EUDIPresentationRequest: Codable, Equatable, Identifiable {
    let id: String
    var relyingPartyID: String
    var relyingPartyName: String
    var purpose: String
    var legalBasis: String
    var protocolName: EUDIPresentationProtocol
    var requestedAttributes: [EUDIAttributeRequest]
    var transactionDataHash: String?
    var expiresAt: Date

    var requestedClaimNames: Set<String> {
        Set(requestedAttributes.map(\.claimName))
    }
}

enum EUDIPresentationDecisionState: String, Codable, Equatable {
    case approved
    case denied
    case stepUpRequired
    case expired
    case missingRequiredClaims
}

struct EUDIPresentationDecision: Codable, Equatable, Identifiable {
    let id: String
    var request: EUDIPresentationRequest
    var documentIDs: [String]
    var disclosedClaims: [String: String]
    var omittedClaims: [String]
    var state: EUDIPresentationDecisionState
    var requiresUserAuthentication: Bool

    var disclosesIdentity: Bool {
        !disclosedClaims.isEmpty
    }

    var receiptHash: String {
        AgenticPaymentHash.stable([
            id,
            request.relyingPartyID,
            request.purpose,
            request.protocolName.rawValue,
            disclosedClaims.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|"),
            state.rawValue
        ])
    }
}

enum EUDIWalletDecisionEngine {
    static func decide(
        request: EUDIPresentationRequest,
        documents: [EUDICredentialDocument],
        approvedClaimNames: Set<String>,
        userAuthenticated: Bool,
        now: Date = Date()
    ) -> EUDIPresentationDecision {
        if request.expiresAt <= now {
            return EUDIPresentationDecision(
                id: "eudi-\(request.id)",
                request: request,
                documentIDs: [],
                disclosedClaims: [:],
                omittedClaims: Array(request.requestedClaimNames).sorted(),
                state: .expired,
                requiresUserAuthentication: true
            )
        }

        let usableDocuments = documents.filter(\.isUsable)
        let availableClaims = usableDocuments.reduce(into: [String: String]()) { partial, document in
            for (name, value) in document.claims where partial[name] == nil {
                partial[name] = value
            }
        }
        let missingRequiredClaims = request.requestedAttributes
            .filter { $0.isRequired && availableClaims[$0.claimName] == nil }
            .map(\.claimName)

        if !missingRequiredClaims.isEmpty {
            return EUDIPresentationDecision(
                id: "eudi-\(request.id)",
                request: request,
                documentIDs: usableDocuments.map(\.id),
                disclosedClaims: [:],
                omittedClaims: missingRequiredClaims.sorted(),
                state: .missingRequiredClaims,
                requiresUserAuthentication: true
            )
        }

        if !userAuthenticated {
            return EUDIPresentationDecision(
                id: "eudi-\(request.id)",
                request: request,
                documentIDs: usableDocuments.map(\.id),
                disclosedClaims: [:],
                omittedClaims: Array(request.requestedClaimNames).sorted(),
                state: .stepUpRequired,
                requiresUserAuthentication: true
            )
        }

        let disclosed = availableClaims.filter { approvedClaimNames.contains($0.key) }
        let omitted = request.requestedClaimNames.subtracting(disclosed.keys).sorted()
        let deniedRequired = request.requestedAttributes.contains { $0.isRequired && disclosed[$0.claimName] == nil }

        return EUDIPresentationDecision(
            id: "eudi-\(request.id)",
            request: request,
            documentIDs: usableDocuments.map(\.id),
            disclosedClaims: disclosed,
            omittedClaims: omitted,
            state: deniedRequired ? .denied : .approved,
            requiresUserAuthentication: true
        )
    }
}

enum AgenticPaymentProtocol: String, CaseIterable, Codable, Equatable {
    case visaTrustedAgent
    case agenticCommerceProtocol
    case agentPaymentsProtocol
    case x402
    case notabeneTransactionAuthorization
    case mastercardAgentPay
    case manualApproval

    var title: String {
        switch self {
        case .visaTrustedAgent: "Visa Trusted Agent Protocol"
        case .agenticCommerceProtocol: "Agentic Commerce Protocol"
        case .agentPaymentsProtocol: "Agent Payments Protocol"
        case .x402: "x402"
        case .notabeneTransactionAuthorization: "Notabene TAP"
        case .mastercardAgentPay: "Mastercard Agent Pay"
        case .manualApproval: "Manual approval"
        }
    }
}

enum AgenticPaymentRisk: String, Codable, Equatable {
    case low
    case medium
    case high
}

struct AgenticPaymentIntent: Codable, Equatable, Identifiable {
    let id: String
    var objective: String
    var merchantID: String?
    var counterpartyID: String?
    var amountMinorUnits: Int
    var currencyOrAsset: String
    var protocolName: AgenticPaymentProtocol
    var risk: AgenticPaymentRisk
    var pageSnapshotHash: String
    var expiresAt: Date
    var recurringPolicy: RecurringAgenticPaymentPolicy?

    var isExpired: Bool {
        expiresAt <= Date()
    }
}

struct RecurringAgenticPaymentPolicy: Codable, Equatable {
    var maxRuns: Int
    var usedRuns: Int
    var maxAmountMinorUnits: Int
    var cooldownHours: Int
    var merchantAllowlist: [String]
    var revokedAt: Date?

    var isRevoked: Bool {
        revokedAt != nil
    }

    func allows(intent: AgenticPaymentIntent) -> Bool {
        guard !isRevoked else { return false }
        guard usedRuns < maxRuns else { return false }
        guard intent.amountMinorUnits <= maxAmountMinorUnits else { return false }
        guard let merchantID = intent.merchantID else { return merchantAllowlist.isEmpty }
        return merchantAllowlist.isEmpty || merchantAllowlist.contains(merchantID)
    }
}

struct VisaTrustedAgentSignature: Codable, Equatable {
    var keyID: String
    var algorithm: String
    var signatureReference: String
    var signedHeaders: [String]
    var issuedAt: Date
    var expiresAt: Date
    var sessionID: String
    /// Base64-encoded signature bytes over the canonical signing base. Optional so existing
    /// reference-only requests remain valid; required for cryptographic verification.
    var signatureValue: String?

    init(
        keyID: String,
        algorithm: String,
        signatureReference: String,
        signedHeaders: [String],
        issuedAt: Date,
        expiresAt: Date,
        sessionID: String,
        signatureValue: String? = nil
    ) {
        self.keyID = keyID
        self.algorithm = algorithm
        self.signatureReference = signatureReference
        self.signedHeaders = signedHeaders
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.sessionID = sessionID
        self.signatureValue = signatureValue
    }

    var coversRequiredHeaders: Bool {
        let required = Set(["method", "target-uri", "body-digest", "created", "expires"])
        return required.isSubset(of: Set(signedHeaders))
    }
}

struct VisaTrustedAgentRequest: Codable, Equatable, Identifiable {
    let id: String
    var agentProviderID: String
    var paymentSchemeID: String
    var merchantID: String
    var method: String
    var targetURI: String
    var bodyDigest: String
    var signature: VisaTrustedAgentSignature
    var consumerIdentityHash: String?
    var paymentContainerHash: String?
}

enum VisaTrustedAgentVerificationStatus: String, Codable, Equatable {
    case verified
    case expired
    case missingRequiredHeaders
    case unknownKey
    case unsupportedAlgorithm
    case missingPaymentContext
    case missingSignatureValue
    case signatureInvalid
}

struct VisaTrustedAgentVerification: Codable, Equatable {
    var status: VisaTrustedAgentVerificationStatus
    var keyID: String
    var agentProviderID: String
    var merchantID: String

    var isVerified: Bool {
        status == .verified
    }
}

enum VisaTrustedAgentVerifier {
    static let supportedAlgorithms = Set(["ed25519", "ecdsa-p256-sha256", "rsa-pss-sha256"])

    static func verify(
        _ request: VisaTrustedAgentRequest,
        trustedKeyIDs: Set<String>,
        now: Date = Date()
    ) -> VisaTrustedAgentVerification {
        let status: VisaTrustedAgentVerificationStatus
        if request.signature.expiresAt <= now || request.signature.issuedAt > now {
            status = .expired
        } else if !request.signature.coversRequiredHeaders {
            status = .missingRequiredHeaders
        } else if !trustedKeyIDs.contains(request.signature.keyID) {
            status = .unknownKey
        } else if !supportedAlgorithms.contains(request.signature.algorithm.lowercased()) {
            status = .unsupportedAlgorithm
        } else if request.paymentContainerHash == nil {
            status = .missingPaymentContext
        } else {
            status = .verified
        }

        return VisaTrustedAgentVerification(
            status: status,
            keyID: request.signature.keyID,
            agentProviderID: request.agentProviderID,
            merchantID: request.merchantID
        )
    }

    /// Locally verifiable Visa Trusted Agent signature algorithms. RSA-PSS is intentionally
    /// excluded because CryptoKit cannot verify it without the Security framework SecKey path.
    static let locallyVerifiableAlgorithms = Set(["ed25519", "ecdsa-p256-sha256"])

    /// Canonical signing base for a request, derived from the required signed components in a
    /// deterministic order. Both signer and verifier must agree on this base. This is a dBrowser
    /// canonical base pending exact RFC 9421 signature-base alignment with Visa.
    static func canonicalSigningBase(for request: VisaTrustedAgentRequest) -> Data {
        let lines = [
            "\"@method\": \(request.method)",
            "\"@target-uri\": \(request.targetURI)",
            "\"body-digest\": \(request.bodyDigest)",
            "\"@created\": \(Int(request.signature.issuedAt.timeIntervalSince1970))",
            "\"@expires\": \(Int(request.signature.expiresAt.timeIntervalSince1970))",
            "\"@key-id\": \(request.signature.keyID)"
        ]
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// Cryptographically verifies the request signature bytes against a trusted key, in addition
    /// to the metadata checks. This is what makes a "verified" trusted-agent request real: a
    /// forged or tampered request whose signature does not validate against the trusted key is
    /// rejected instead of accepted on metadata alone.
    static func verify(
        _ request: VisaTrustedAgentRequest,
        keyStore: VisaTrustedAgentKeyStore,
        now: Date = Date()
    ) -> VisaTrustedAgentVerification {
        func result(_ status: VisaTrustedAgentVerificationStatus) -> VisaTrustedAgentVerification {
            VisaTrustedAgentVerification(
                status: status,
                keyID: request.signature.keyID,
                agentProviderID: request.agentProviderID,
                merchantID: request.merchantID
            )
        }

        // Run the same metadata pre-checks first.
        if request.signature.expiresAt <= now || request.signature.issuedAt > now {
            return result(.expired)
        }
        if !request.signature.coversRequiredHeaders {
            return result(.missingRequiredHeaders)
        }
        guard let key = keyStore.key(forID: request.signature.keyID) else {
            return result(.unknownKey)
        }
        let algorithm = request.signature.algorithm.lowercased()
        guard supportedAlgorithms.contains(algorithm) else {
            return result(.unsupportedAlgorithm)
        }
        if request.paymentContainerHash == nil {
            return result(.missingPaymentContext)
        }
        // Only algorithms dBrowser can locally verify with CryptoKit may reach `.verified`.
        guard locallyVerifiableAlgorithms.contains(algorithm), key.algorithm.lowercased() == algorithm else {
            return result(.unsupportedAlgorithm)
        }
        guard
            let signatureValue = request.signature.signatureValue,
            let signatureData = Data(base64Encoded: signatureValue)
        else {
            return result(.missingSignatureValue)
        }

        let signingBase = canonicalSigningBase(for: request)
        let signatureValid = verifySignature(signatureData, over: signingBase, key: key, algorithm: algorithm)
        return result(signatureValid ? .verified : .signatureInvalid)
    }

    private static func verifySignature(
        _ signature: Data,
        over message: Data,
        key: VisaTrustedAgentKey,
        algorithm: String
    ) -> Bool {
        switch algorithm {
        case "ecdsa-p256-sha256":
            guard
                let publicKey = try? P256.Signing.PublicKey(rawRepresentation: key.publicKeyRaw),
                let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
            else { return false }
            return publicKey.isValidSignature(parsed, for: message)
        case "ed25519":
            guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key.publicKeyRaw) else {
                return false
            }
            return publicKey.isValidSignature(signature, for: message)
        default:
            return false
        }
    }
}

/// A trusted Visa Trusted Agent signing key, normally discovered from the agent provider's key
/// directory. `publicKeyRaw` is the raw key representation: 64-byte x||y for ECDSA P-256,
/// 32-byte compressed point for Ed25519.
struct VisaTrustedAgentKey: Equatable, Identifiable {
    var keyID: String
    var algorithm: String
    var publicKeyRaw: Data
    var id: String { keyID }
}

struct VisaTrustedAgentKeyStore: Equatable {
    private(set) var keysByID: [String: VisaTrustedAgentKey]

    init(keys: [VisaTrustedAgentKey] = []) {
        var map: [String: VisaTrustedAgentKey] = [:]
        for key in keys { map[key.keyID] = key }
        keysByID = map
    }

    func key(forID keyID: String) -> VisaTrustedAgentKey? { keysByID[keyID] }

    var isEmpty: Bool { keysByID.isEmpty }
}

struct ACPLineItem: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var quantity: Int
    var unitAmountMinorUnits: Int

    var totalMinorUnits: Int {
        max(0, quantity) * max(0, unitAmountMinorUnits)
    }
}

enum ACPCheckoutStatus: String, Codable, Equatable {
    case draft
    case readyForBuyerReview
    case delegatedPaymentTokenIssued
    case completed
    case cancelled
    case refunded
}

struct ACPDelegatedPaymentTokenReference: Codable, Equatable {
    var tokenReference: String
    var merchantID: String
    var basketHash: String
    var amountMinorUnits: Int
    var currency: String
    var expiresAt: Date

    var storesRawPaymentCredential: Bool {
        false
    }
}

struct ACPCheckoutSession: Codable, Equatable, Identifiable {
    let id: String
    var merchantID: String
    var merchantName: String
    var currency: String
    var lineItems: [ACPLineItem]
    var fulfillmentOptions: [String]
    var delegatedPaymentToken: ACPDelegatedPaymentTokenReference?
    var status: ACPCheckoutStatus

    var totalMinorUnits: Int {
        lineItems.map(\.totalMinorUnits).reduce(0, +)
    }

    var basketHash: String {
        AgenticPaymentHash.stable([
            merchantID,
            currency,
            lineItems.map { "\($0.id):\($0.quantity):\($0.unitAmountMinorUnits)" }.joined(separator: "|"),
            "\(totalMinorUnits)"
        ])
    }

    var isReadyForPayment: Bool {
        status == .readyForBuyerReview || status == .delegatedPaymentTokenIssued
    }
}

enum AP2MandateKind: String, Codable, Equatable {
    case intent
    case cart
    case payment
}

struct AP2Mandate: Codable, Equatable, Identifiable {
    let id: String
    var kind: AP2MandateKind
    var signerID: String
    var subjectID: String
    var scopeHash: String
    var amountMinorUnits: Int?
    var currencyOrAsset: String?
    var priorMandateHashes: [String]
    var signatureReference: String
    var expiresAt: Date
    var revokedAt: Date?

    var mandateHash: String {
        AgenticPaymentHash.stable([
            id,
            kind.rawValue,
            signerID,
            subjectID,
            scopeHash,
            amountMinorUnits.map(String.init) ?? "",
            currencyOrAsset ?? "",
            priorMandateHashes.joined(separator: "|"),
            signatureReference
        ])
    }

    var isUsable: Bool {
        revokedAt == nil && expiresAt > Date() && !signatureReference.isEmpty
    }

    func binds(to prior: AP2Mandate) -> Bool {
        priorMandateHashes.contains(prior.mandateHash)
    }
}

struct X402PaymentRequirement: Codable, Equatable, Identifiable {
    let id: String
    var resourceURLString: String
    var amountMinorUnits: Int
    var asset: String
    var network: String
    var payTo: String
    var facilitatorURLString: String?
    var expiresAt: Date

    var requirementHash: String {
        AgenticPaymentHash.stable([
            resourceURLString,
            "\(amountMinorUnits)",
            asset,
            network,
            payTo,
            facilitatorURLString ?? ""
        ])
    }
}

struct X402PaymentPayload: Codable, Equatable {
    var requirementHash: String
    var walletAccount: String
    var transactionReference: String?
    var signatureReference: String

    var isSigned: Bool {
        !signatureReference.isEmpty
    }
}

enum NotabeneTransferAuthorizationState: String, Codable, Equatable {
    case requested
    case authorized
    case denied
    case expired
    case settled
}

struct NotabeneTransferRequest: Codable, Equatable, Identifiable {
    let id: String
    var originatorPartyID: String
    var beneficiaryPartyID: String
    var asset: String
    var network: String
    var amountMinorUnits: Int
    var destinationAddressHash: String
    var encryptedMessageReference: String?
    var state: NotabeneTransferAuthorizationState
    var expiresAt: Date

    var transferHash: String {
        AgenticPaymentHash.stable([
            originatorPartyID,
            beneficiaryPartyID,
            asset,
            network,
            "\(amountMinorUnits)",
            destinationAddressHash,
            encryptedMessageReference ?? ""
        ])
    }
}

enum AgenticPaymentDecisionKind: String, Codable, Equatable {
    case allow
    case askUser
    case deny
    case revise
    case stepUp
    case expired
    case revoked
}

struct AgenticPaymentPolicyDecision: Codable, Equatable {
    var kind: AgenticPaymentDecisionKind
    var reasons: [String]
    var requiredApprovalLabels: [String]

    var requiresUserApproval: Bool {
        kind == .askUser || kind == .stepUp
    }
}

struct AgenticPaymentReview: Codable, Equatable, Identifiable {
    let id: String
    var intent: AgenticPaymentIntent
    var eudiDecision: EUDIPresentationDecision?
    var visaTrustedAgent: VisaTrustedAgentVerification?
    var acpCheckout: ACPCheckoutSession?
    var ap2Mandates: [AP2Mandate]
    var x402Requirement: X402PaymentRequirement?
    var x402Payload: X402PaymentPayload?
    var notabeneTransfer: NotabeneTransferRequest?
    var userApproved: Bool

    var protocolEvidenceLabels: [String] {
        var labels = [intent.protocolName.title]
        if eudiDecision != nil { labels.append("EUDI presentation") }
        if visaTrustedAgent != nil { labels.append("Visa trusted agent") }
        if acpCheckout != nil { labels.append("ACP checkout") }
        if !ap2Mandates.isEmpty { labels.append("AP2 mandates") }
        if x402Requirement != nil { labels.append("x402 requirement") }
        if notabeneTransfer != nil { labels.append("Notabene TAP transfer") }
        return labels
    }

    var bindingHashes: [String] {
        var hashes = [intent.pageSnapshotHash]
        if let eudiDecision { hashes.append(eudiDecision.receiptHash) }
        if let acpCheckout { hashes.append(acpCheckout.basketHash) }
        hashes.append(contentsOf: ap2Mandates.map(\.mandateHash))
        if let x402Requirement { hashes.append(x402Requirement.requirementHash) }
        if let notabeneTransfer { hashes.append(notabeneTransfer.transferHash) }
        return hashes
    }
}

enum AgenticPaymentReceiptStatus: String, Codable, Equatable {
    case approved
    case denied
    case expired
    case revoked
}

struct AgenticPaymentReceipt: Codable, Equatable, Identifiable {
    let id: String
    var reviewID: String
    var intentID: String
    var protocolName: AgenticPaymentProtocol
    var status: AgenticPaymentReceiptStatus
    var amountMinorUnits: Int
    var currencyOrAsset: String
    var bindingHashes: [String]
    var identityDisclosureHash: String?
    var createdAt: Date
    var storesRawPaymentCredential: Bool
    var summary: String
}

enum WalletPrincipalKind: String, CaseIterable, Codable, Equatable {
    case human
    case agent

    var title: String {
        switch self {
        case .human: "Human wallet"
        case .agent: "Agent wallet"
        }
    }
}

enum WalletCapabilityVault: String, CaseIterable, Codable, Equatable, Identifiable {
    case identity
    case payment
    case crypto
    case browsing
    case signing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identity: "Identity vault"
        case .payment: "Payment vault"
        case .crypto: "Crypto vault"
        case .browsing: "Browsing vault"
        case .signing: "Signing vault"
        }
    }
}

enum DelegatedCapability: String, CaseIterable, Codable, Equatable, Identifiable {
    case identityPresentation
    case paymentAuthorization
    case cryptoSessionKey
    case browsingAutomation
    case messageSigning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identityPresentation: "Selective identity proof"
        case .paymentAuthorization: "Delegated payment"
        case .cryptoSessionKey: "Scoped crypto session"
        case .browsingAutomation: "Browsing automation"
        case .messageSigning: "Message signing"
        }
    }

    var vault: WalletCapabilityVault {
        switch self {
        case .identityPresentation: .identity
        case .paymentAuthorization: .payment
        case .cryptoSessionKey: .crypto
        case .browsingAutomation: .browsing
        case .messageSigning: .signing
        }
    }
}

enum AgentWalletTrustStatus: String, Codable, Equatable {
    case trusted
    case limited
    case untrusted
    case revoked

    var title: String {
        switch self {
        case .trusted: "Trusted"
        case .limited: "Limited"
        case .untrusted: "Untrusted"
        case .revoked: "Revoked"
        }
    }
}

struct AgentWalletProfile: Codable, Equatable, Identifiable {
    var id: String
    var agentDID: String
    var providerID: String
    var trustStatus: AgentWalletTrustStatus
    var identityAttestations: [String]
    var allowedProtocols: [AgenticPaymentProtocol]
    var createdAt: Date

    var isUsable: Bool {
        trustStatus == .trusted || trustStatus == .limited
    }
}

struct WalletPrincipal: Codable, Equatable, Identifiable {
    let id: String
    var kind: WalletPrincipalKind
    var displayName: String
    var parentPrincipalID: String?
    var vaults: [WalletCapabilityVault]
    var agentProfile: AgentWalletProfile?
    var attestationLabels: [String]

    var isRootAuthority: Bool {
        kind == .human && parentPrincipalID == nil
    }

    var delegationSummary: String {
        switch kind {
        case .human:
            return isRootAuthority ? "Root authority" : "Human delegated wallet"
        case .agent:
            return parentPrincipalID.map { "Delegated by \($0)" } ?? "Agent wallet without root"
        }
    }
}

struct CapabilityGrant: Codable, Equatable, Identifiable {
    let id: String
    var authorityPrincipalID: String
    var principalID: String
    var capability: DelegatedCapability
    var budgetMinorUnits: Int?
    var spentMinorUnits: Int
    var currencyOrAsset: String?
    var merchantAllowlist: [String]
    var protocolAllowlist: [AgenticPaymentProtocol]
    var chainAllowlist: [String]
    var identityClaimAllowlist: [String]
    var sessionKeyReference: String?
    var mandateReference: String?
    var issuedAt: Date
    var expiresAt: Date
    var revokedAt: Date?
    var approvalLabel: String

    var remainingBudgetMinorUnits: Int? {
        budgetMinorUnits.map { max(0, $0 - spentMinorUnits) }
    }

    func isActive(now: Date = Date()) -> Bool {
        revokedAt == nil && expiresAt > now
    }

    func statusTitle(now: Date = Date()) -> String {
        if revokedAt != nil { return "Revoked" }
        if expiresAt <= now { return "Expired" }
        return "Active"
    }

    func budgetSummary() -> String {
        guard let budgetMinorUnits else { return "No spend budget" }
        let remaining = max(0, budgetMinorUnits - spentMinorUnits)
        return "\(remaining)/\(budgetMinorUnits) \(currencyOrAsset ?? "minor units") remaining"
    }

    func coversScope(_ request: WalletCapabilityRequest) -> Bool {
        guard principalID == request.principalID, capability == request.capability else {
            return false
        }
        if let protocolName = request.protocolName, !protocolAllowlist.isEmpty, !protocolAllowlist.contains(protocolName) {
            return false
        }
        if let merchantID = request.merchantID, !merchantAllowlist.isEmpty, !merchantAllowlist.contains(merchantID) {
            return false
        }
        if !request.requestedIdentityClaims.isEmpty {
            let allowedClaims = Set(identityClaimAllowlist)
            guard Set(request.requestedIdentityClaims).isSubset(of: allowedClaims) else {
                return false
            }
        }
        return true
    }

    func allowsBudget(_ amountMinorUnits: Int?) -> Bool {
        guard let amountMinorUnits, let remainingBudgetMinorUnits else {
            return true
        }
        return amountMinorUnits <= remainingBudgetMinorUnits
    }
}

enum WalletReceiptKind: String, Codable, Equatable {
    case identityDisclosure
    case paymentAuthorization
    case cryptoSignature
    case protocolProof
    case grantRevocation

    var title: String {
        switch self {
        case .identityDisclosure: "Identity disclosure"
        case .paymentAuthorization: "Payment authorization"
        case .cryptoSignature: "Crypto signature"
        case .protocolProof: "Protocol proof"
        case .grantRevocation: "Grant revocation"
        }
    }
}

enum WalletReceiptStatus: String, Codable, Equatable {
    case recorded
    case approved
    case denied
    case expired
    case revoked
}

struct WalletReceipt: Codable, Equatable, Identifiable {
    let id: String
    var kind: WalletReceiptKind
    var status: WalletReceiptStatus
    var principalID: String
    var authorityPrincipalID: String
    var grantID: String?
    var protocolName: AgenticPaymentProtocol?
    var merchantID: String?
    var amountMinorUnits: Int?
    var currencyOrAsset: String?
    var selectiveDisclosureClaims: [String]
    var bindingHashes: [String]
    var createdAt: Date
    var summary: String
    var storesRawPaymentCredential: Bool
    var exposesRootCredential: Bool

    var receiptHash: String {
        AgenticPaymentHash.stable([
            id,
            kind.rawValue,
            status.rawValue,
            principalID,
            authorityPrincipalID,
            grantID ?? "",
            protocolName?.rawValue ?? "",
            merchantID ?? "",
            amountMinorUnits.map(String.init) ?? "",
            currencyOrAsset ?? "",
            selectiveDisclosureClaims.joined(separator: "|"),
            bindingHashes.joined(separator: "|"),
            storesRawPaymentCredential ? "raw-payment" : "tokenized",
            exposesRootCredential ? "root" : "delegated"
        ])
    }
}

enum EUDIAgentIdentityIssuanceState: String, Codable, Equatable {
    case issued
    case denied
    case expired
    case revoked
    case missingHumanCredential
    case missingAgentPrincipal
    case rootAccessDenied
}

struct EUDIAgentIdentityIssuanceRequest: Equatable, Identifiable {
    let id: String
    var humanPrincipalID: String
    var agentPrincipalID: String
    var sourceCredentialID: String
    var requestedClaims: [String]
    var relyingPartyID: String?
    var relyingPartyName: String?
    var protocolName: AgenticPaymentProtocol?
    var purpose: String
    var expiresAt: Date
    var requiresRootCredentialAccess: Bool

    var requestHash: String {
        AgenticPaymentHash.stable([
            id,
            humanPrincipalID,
            agentPrincipalID,
            sourceCredentialID,
            requestedClaims.sorted().joined(separator: "|"),
            relyingPartyID ?? "",
            protocolName?.rawValue ?? "",
            purpose
        ])
    }
}

struct EUDIAgentIdentityCredential: Codable, Equatable, Identifiable {
    let id: String
    var agentPrincipalID: String
    var authorityPrincipalID: String
    var sourceCredentialID: String
    var sourceCredentialHash: String
    var issuer: String
    var subjectDID: String
    var claims: [String: String]
    var protocolName: AgenticPaymentProtocol?
    var relyingPartyID: String?
    var grantID: String
    var issuedAt: Date
    var expiresAt: Date
    var receiptID: String
    var exposesRootCredential: Bool

    var isUsable: Bool {
        expiresAt > Date() && !exposesRootCredential
    }

    var claimNames: [String] {
        claims.keys.sorted()
    }
}

struct EUDIAgentIdentityIssuanceResult: Equatable {
    var state: EUDIAgentIdentityIssuanceState
    var decision: WalletControlPlaneDecision
    var credential: EUDIAgentIdentityCredential?
    var receipt: WalletReceipt
    var reasons: [String]

    var isIssued: Bool {
        state == .issued && credential != nil
    }
}

enum EUDIWalletIdentityIssuer {
    static func issueAgentIdentity(
        _ request: EUDIAgentIdentityIssuanceRequest,
        snapshot: WalletControlPlaneSnapshot,
        now: Date = Date()
    ) -> EUDIAgentIdentityIssuanceResult {
        guard let humanPrincipal = snapshot.principal(id: request.humanPrincipalID),
              humanPrincipal.kind == .human,
              humanPrincipal.isRootAuthority else {
            return deniedResult(
                state: .missingHumanCredential,
                request: request,
                decision: WalletControlPlaneDecision(kind: .deny, grantID: nil, reasons: ["Human root wallet principal is missing."]),
                reason: "Human root wallet principal is missing.",
                now: now
            )
        }
        guard let agentPrincipal = snapshot.principal(id: request.agentPrincipalID),
              agentPrincipal.kind == .agent else {
            return deniedResult(
                state: .missingAgentPrincipal,
                request: request,
                decision: WalletControlPlaneDecision(kind: .deny, grantID: nil, reasons: ["Agent wallet principal is missing."]),
                reason: "Agent wallet principal is missing.",
                now: now
            )
        }
        guard !request.requiresRootCredentialAccess else {
            return deniedResult(
                state: .rootAccessDenied,
                request: request,
                decision: WalletControlPlaneDecision(
                    kind: .deny,
                    grantID: nil,
                    reasons: ["Agent identity issuance cannot expose the human root credential."]
                ),
                reason: "Agent identity issuance cannot expose the human root credential.",
                now: now
            )
        }
        guard request.expiresAt > now else {
            return deniedResult(
                state: .expired,
                request: request,
                decision: WalletControlPlaneDecision(kind: .expired, grantID: nil, reasons: ["Agent identity issuance request is expired."]),
                reason: "Agent identity issuance request is expired.",
                now: now
            )
        }
        guard let sourceCredential = snapshot.humanIdentityCredentials.first(where: { $0.id == request.sourceCredentialID && $0.kind == .verifiedEmail && $0.isUsable }) else {
            return deniedResult(
                state: .missingHumanCredential,
                request: request,
                decision: WalletControlPlaneDecision(kind: .deny, grantID: nil, reasons: ["Usable verified email credential is missing from the human identity vault."]),
                reason: "Usable verified email credential is missing from the human identity vault.",
                now: now
            )
        }

        let requestedClaimSet = Set(request.requestedClaims)
        let availableClaimSet = Set(sourceCredential.claims.keys)
        guard !requestedClaimSet.isEmpty, requestedClaimSet.isSubset(of: availableClaimSet) else {
            return deniedResult(
                state: .denied,
                request: request,
                decision: WalletControlPlaneDecision(kind: .deny, grantID: nil, reasons: ["Requested identity claims are not available in the source credential."]),
                reason: "Requested identity claims are not available in the source credential.",
                now: now
            )
        }

        let capabilityRequest = WalletCapabilityRequest(
            principalID: agentPrincipal.id,
            capability: .identityPresentation,
            protocolName: request.protocolName,
            merchantID: request.relyingPartyID,
            amountMinorUnits: nil,
            requestedIdentityClaims: request.requestedClaims,
            requiresRootCredentialAccess: false
        )
        let decision = WalletControlPlanePolicyEngine.evaluate(capabilityRequest, snapshot: snapshot, now: now)
        guard decision.isAllowed, let grantID = decision.grantID else {
            return deniedResult(
                state: state(for: decision),
                request: request,
                decision: decision,
                reason: decision.reasons.joined(separator: " "),
                now: now
            )
        }

        let disclosedClaims = sourceCredential.claims.filter { requestedClaimSet.contains($0.key) }
        let sourceHash = sourceCredential.claims["source_credential_hash"] ?? AgenticPaymentHash.stable([
            sourceCredential.id,
            sourceCredential.issuer,
            sourceCredential.subjectHint
        ])
        let receiptID = "wallet-receipt-agent-identity-\(request.id)"
        let credential = EUDIAgentIdentityCredential(
            id: "agent-identity-\(request.id)",
            agentPrincipalID: agentPrincipal.id,
            authorityPrincipalID: humanPrincipal.id,
            sourceCredentialID: sourceCredential.id,
            sourceCredentialHash: sourceHash,
            issuer: "dBrowser delegated identity issuer",
            subjectDID: agentPrincipal.agentProfile?.agentDID ?? agentPrincipal.id,
            claims: disclosedClaims,
            protocolName: request.protocolName,
            relyingPartyID: request.relyingPartyID,
            grantID: grantID,
            issuedAt: now,
            expiresAt: min(request.expiresAt, sourceCredential.expiresAt ?? request.expiresAt),
            receiptID: receiptID,
            exposesRootCredential: false
        )
        let receipt = WalletReceipt(
            id: receiptID,
            kind: .identityDisclosure,
            status: .approved,
            principalID: agentPrincipal.id,
            authorityPrincipalID: humanPrincipal.id,
            grantID: grantID,
            protocolName: request.protocolName,
            merchantID: request.relyingPartyID,
            amountMinorUnits: nil,
            currencyOrAsset: nil,
            selectiveDisclosureClaims: credential.claimNames,
            bindingHashes: [sourceHash, request.requestHash],
            createdAt: now,
            summary: "Agent received a delegated verified-email identity credential, not the human email VC.",
            storesRawPaymentCredential: false,
            exposesRootCredential: false
        )
        return EUDIAgentIdentityIssuanceResult(
            state: .issued,
            decision: decision,
            credential: credential,
            receipt: receipt,
            reasons: ["Delegated identity credential issued from a human-approved grant."]
        )
    }

    private static func state(for decision: WalletControlPlaneDecision) -> EUDIAgentIdentityIssuanceState {
        switch decision.kind {
        case .allow:
            .issued
        case .expired:
            .expired
        case .revoked:
            .revoked
        case .deny, .overBudget:
            .denied
        }
    }

    private static func deniedResult(
        state: EUDIAgentIdentityIssuanceState,
        request: EUDIAgentIdentityIssuanceRequest,
        decision: WalletControlPlaneDecision,
        reason: String,
        now: Date
    ) -> EUDIAgentIdentityIssuanceResult {
        let receipt = WalletReceipt(
            id: "wallet-receipt-agent-identity-\(request.id)",
            kind: .identityDisclosure,
            status: receiptStatus(for: state),
            principalID: request.agentPrincipalID,
            authorityPrincipalID: request.humanPrincipalID,
            grantID: decision.grantID,
            protocolName: request.protocolName,
            merchantID: request.relyingPartyID,
            amountMinorUnits: nil,
            currencyOrAsset: nil,
            selectiveDisclosureClaims: request.requestedClaims.sorted(),
            bindingHashes: [request.requestHash],
            createdAt: now,
            summary: reason,
            storesRawPaymentCredential: false,
            exposesRootCredential: false
        )
        return EUDIAgentIdentityIssuanceResult(
            state: state,
            decision: decision,
            credential: nil,
            receipt: receipt,
            reasons: [reason]
        )
    }

    private static func receiptStatus(for state: EUDIAgentIdentityIssuanceState) -> WalletReceiptStatus {
        switch state {
        case .issued:
            .approved
        case .expired:
            .expired
        case .revoked:
            .revoked
        case .denied, .missingHumanCredential, .missingAgentPrincipal, .rootAccessDenied:
            .denied
        }
    }
}

struct WalletControlPlaneSnapshot: Codable, Equatable {
    var principals: [WalletPrincipal]
    var grants: [CapabilityGrant]
    var receipts: [WalletReceipt]
    var humanIdentityCredentials: [EUDICredentialDocument]
    var agentIdentityCredentials: [EUDIAgentIdentityCredential]

    var humanPrincipals: [WalletPrincipal] {
        principals.filter { $0.kind == .human }
    }

    var agentPrincipals: [WalletPrincipal] {
        principals.filter { $0.kind == .agent }
    }

    var activeGrants: [CapabilityGrant] {
        grants.filter { $0.isActive() }
    }

    var verifiedEmailCredentials: [EUDICredentialDocument] {
        humanIdentityCredentials.filter { $0.kind == .verifiedEmail && $0.isUsable }
    }

    var activeAgentIdentityCredentials: [EUDIAgentIdentityCredential] {
        agentIdentityCredentials.filter(\.isUsable)
    }

    var policySummary: String {
        let emailCount = verifiedEmailCredentials.count
        let agentIdentityCount = activeAgentIdentityCredentials.count
        return "\(humanPrincipals.count) human, \(agentPrincipals.count) agent, \(activeGrants.count) active grant\(activeGrants.count == 1 ? "" : "s"), \(emailCount) verified email\(emailCount == 1 ? "" : "s"), \(agentIdentityCount) agent identit\(agentIdentityCount == 1 ? "y" : "ies")"
    }

    func principal(id: String) -> WalletPrincipal? {
        principals.first { $0.id == id }
    }

    func grants(for principalID: String) -> [CapabilityGrant] {
        grants.filter { $0.principalID == principalID }
    }

    func receipts(for principalID: String) -> [WalletReceipt] {
        receipts.filter { $0.principalID == principalID }
    }

    func delegationChain(for principalID: String) -> [WalletPrincipal] {
        var chain = [WalletPrincipal]()
        var currentID: String? = principalID
        var seen = Set<String>()

        while let id = currentID, !seen.contains(id), let principal = principal(id: id) {
            seen.insert(id)
            chain.append(principal)
            currentID = principal.parentPrincipalID
        }

        return chain
    }

    static func defaultDelegation(rootWalletFingerprint: String? = nil) -> WalletControlPlaneSnapshot {
        let issuedAt = Date(timeIntervalSince1970: 1_798_200_000)
        let expiresAt = Date(timeIntervalSince1970: 4_102_444_800)
        let humanID = "principal-human-root"
        let agentID = "principal-agent-travel"
        let fingerprintLabel = rootWalletFingerprint.map { "Embedded wallet fingerprint \($0)" }
        let verifiedEmailCredentialID = "https://verifiedemail.showntell.dev/credentials/email/human-dbrowser-fixture"
        let verifiedEmailSourceHash = AgenticPaymentHash.stable([
            verifiedEmailCredentialID,
            "https://verifiedemail.showntell.dev",
            "johan.sellstrom@iproov.com",
            "did:dbrowser:human:johan"
        ])
        let verifiedEmailDocument = EUDICredentialDocument(
            id: verifiedEmailCredentialID,
            kind: .verifiedEmail,
            issuer: "https://verifiedemail.showntell.dev",
            subjectHint: "johan.sellstrom@iproov.com",
            claims: [
                "email": "johan.sellstrom@iproov.com",
                "email_normalized": "johan.sellstrom@iproov.com",
                "email_verified": "true",
                "holder_did": "did:dbrowser:human:johan",
                "holder_jwk_thumbprint": "human-email-jwk-thumbprint",
                "source_credential_id": verifiedEmailCredentialID,
                "source_credential_hash": verifiedEmailSourceHash,
                "subject_type": "user"
            ],
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            isRevoked: false
        )
        let human = WalletPrincipal(
            id: humanID,
            kind: .human,
            displayName: "Personal dBrowser wallet",
            parentPrincipalID: nil,
            vaults: [.identity, .payment, .crypto, .signing],
            agentProfile: nil,
            attestationLabels: [
                "EUDI wallet-compatible client",
                "Root payment instruments stay tokenized",
                "Full crypto recovery retained by user",
                "Verified email from cliwallet-compatible issuer"
            ] + [fingerprintLabel].compactMap { $0 }
        )
        let agentProfile = AgentWalletProfile(
            id: "agent-profile-travel",
            agentDID: "did:dbrowser:agent:travel-concierge",
            providerID: "dbrowser.local",
            trustStatus: .limited,
            identityAttestations: [
                "App attestation fixture",
                "Visa TAP trust material fixture"
            ],
            allowedProtocols: [.visaTrustedAgent, .agenticCommerceProtocol, .agentPaymentsProtocol, .x402],
            createdAt: issuedAt
        )
        let agent = WalletPrincipal(
            id: agentID,
            kind: .agent,
            displayName: "Travel concierge agent",
            parentPrincipalID: humanID,
            vaults: [.identity, .payment, .crypto, .browsing],
            agentProfile: agentProfile,
            attestationLabels: [
                "Child principal",
                "No raw EUDI credential access",
                "No root payment instrument access"
            ]
        )
        let identityGrant = CapabilityGrant(
            id: "grant-age-proof",
            authorityPrincipalID: humanID,
            principalID: agentID,
            capability: .identityPresentation,
            budgetMinorUnits: nil,
            spentMinorUnits: 0,
            currencyOrAsset: nil,
            merchantAllowlist: ["merchant.example"],
            protocolAllowlist: [.visaTrustedAgent, .agenticCommerceProtocol, .agentPaymentsProtocol],
            chainAllowlist: [],
            identityClaimAllowlist: ["age_over_18"],
            sessionKeyReference: nil,
            mandateReference: "eudi-presentation-receipt-only",
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            revokedAt: nil,
            approvalLabel: "Use age-over-18 proof at merchant.example"
        )
        let emailIdentityGrant = CapabilityGrant(
            id: "grant-agent-verified-email",
            authorityPrincipalID: humanID,
            principalID: agentID,
            capability: .identityPresentation,
            budgetMinorUnits: nil,
            spentMinorUnits: 0,
            currencyOrAsset: nil,
            merchantAllowlist: ["dbrowser.local"],
            protocolAllowlist: [.manualApproval],
            chainAllowlist: [],
            identityClaimAllowlist: ["email", "email_verified"],
            sessionKeyReference: nil,
            mandateReference: "human-email-vc-selective-agent-identity",
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            revokedAt: nil,
            approvalLabel: "Issue verified email identity to the travel agent"
        )
        let paymentGrant = CapabilityGrant(
            id: "grant-merchant-payment",
            authorityPrincipalID: humanID,
            principalID: agentID,
            capability: .paymentAuthorization,
            budgetMinorUnits: 5_000,
            spentMinorUnits: 1_999,
            currencyOrAsset: "USD cents",
            merchantAllowlist: ["merchant.example"],
            protocolAllowlist: [.agenticCommerceProtocol, .agentPaymentsProtocol, .visaTrustedAgent],
            chainAllowlist: [],
            identityClaimAllowlist: [],
            sessionKeyReference: nil,
            mandateReference: "ap2-mandate-ref-merchant-example",
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            revokedAt: nil,
            approvalLabel: "Spend up to USD 50.00 at merchant.example"
        )
        let cryptoGrant = CapabilityGrant(
            id: "grant-x402-session",
            authorityPrincipalID: humanID,
            principalID: agentID,
            capability: .cryptoSessionKey,
            budgetMinorUnits: 500,
            spentMinorUnits: 125,
            currencyOrAsset: "USDC cents",
            merchantAllowlist: ["api.example.test"],
            protocolAllowlist: [.x402],
            chainAllowlist: ["base-sepolia"],
            identityClaimAllowlist: [],
            sessionKeyReference: "session-key:x402:base-sepolia",
            mandateReference: "x402-allowance-api-example",
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            revokedAt: nil,
            approvalLabel: "Pay x402 API calls up to 500 USDC cents/day"
        )
        let receipts = [
            WalletReceipt(
                id: "wallet-receipt-age-proof",
                kind: .identityDisclosure,
                status: .approved,
                principalID: agentID,
                authorityPrincipalID: humanID,
                grantID: identityGrant.id,
                protocolName: .agenticCommerceProtocol,
                merchantID: "merchant.example",
                amountMinorUnits: nil,
                currencyOrAsset: nil,
                selectiveDisclosureClaims: ["age_over_18"],
                bindingHashes: ["eudi-selective-proof-hash"],
                createdAt: issuedAt,
                summary: "Agent received an age-over-18 proof receipt, not the PID credential.",
                storesRawPaymentCredential: false,
                exposesRootCredential: false
            ),
            WalletReceipt(
                id: "wallet-receipt-acp-payment",
                kind: .paymentAuthorization,
                status: .approved,
                principalID: agentID,
                authorityPrincipalID: humanID,
                grantID: paymentGrant.id,
                protocolName: .agenticCommerceProtocol,
                merchantID: "merchant.example",
                amountMinorUnits: 1_999,
                currencyOrAsset: "USD cents",
                selectiveDisclosureClaims: [],
                bindingHashes: ["acp-basket-hash", "ap2-mandate-ref-merchant-example"],
                createdAt: issuedAt,
                summary: "Agent used an ACP delegated payment token bound to the approved basket.",
                storesRawPaymentCredential: false,
                exposesRootCredential: false
            )
        ]

        var snapshot = WalletControlPlaneSnapshot(
            principals: [human, agent],
            grants: [identityGrant, emailIdentityGrant, paymentGrant, cryptoGrant],
            receipts: receipts,
            humanIdentityCredentials: [verifiedEmailDocument],
            agentIdentityCredentials: []
        )
        let issuanceRequest = EUDIAgentIdentityIssuanceRequest(
            id: "verified-email-travel-agent",
            humanPrincipalID: humanID,
            agentPrincipalID: agentID,
            sourceCredentialID: verifiedEmailCredentialID,
            requestedClaims: ["email", "email_verified"],
            relyingPartyID: "dbrowser.local",
            relyingPartyName: "dBrowser Wallet Control Plane",
            protocolName: .manualApproval,
            purpose: "Agent identity bootstrap",
            expiresAt: expiresAt,
            requiresRootCredentialAccess: false
        )
        let issuanceResult = EUDIWalletIdentityIssuer.issueAgentIdentity(
            issuanceRequest,
            snapshot: snapshot,
            now: issuedAt
        )
        if let credential = issuanceResult.credential {
            snapshot.agentIdentityCredentials.append(credential)
        }
        snapshot.receipts.append(issuanceResult.receipt)
        return snapshot
    }
}

struct WalletCapabilityRequest: Equatable {
    var principalID: String
    var capability: DelegatedCapability
    var protocolName: AgenticPaymentProtocol?
    var merchantID: String?
    var amountMinorUnits: Int?
    var requestedIdentityClaims: [String]
    var requiresRootCredentialAccess: Bool
}

enum WalletControlPlaneDecisionKind: String, Equatable {
    case allow
    case deny
    case expired
    case revoked
    case overBudget
}

struct WalletControlPlaneDecision: Equatable {
    var kind: WalletControlPlaneDecisionKind
    var grantID: String?
    var reasons: [String]

    var isAllowed: Bool {
        kind == .allow
    }
}

enum WalletControlPlanePolicyEngine {
    static func evaluate(
        _ request: WalletCapabilityRequest,
        snapshot: WalletControlPlaneSnapshot,
        now: Date = Date()
    ) -> WalletControlPlaneDecision {
        guard let principal = snapshot.principal(id: request.principalID) else {
            return WalletControlPlaneDecision(kind: .deny, grantID: nil, reasons: ["Unknown wallet principal"])
        }

        if principal.kind == .agent && request.requiresRootCredentialAccess {
            return WalletControlPlaneDecision(
                kind: .deny,
                grantID: nil,
                reasons: ["Agent principals cannot receive root human credentials, raw payment instruments, or unrestricted signing authority"]
            )
        }

        if principal.kind == .agent, principal.agentProfile?.trustStatus == .revoked {
            return WalletControlPlaneDecision(kind: .revoked, grantID: nil, reasons: ["Agent wallet trust is revoked"])
        }

        if principal.kind == .human && principal.isRootAuthority {
            return WalletControlPlaneDecision(kind: .allow, grantID: nil, reasons: ["Human root authority controls the wallet vaults"])
        }

        let scopedGrants = snapshot.grants.filter { $0.coversScope(request) }
        guard !scopedGrants.isEmpty else {
            return WalletControlPlaneDecision(kind: .deny, grantID: nil, reasons: ["No delegated capability grant covers this request"])
        }

        if let activeGrant = scopedGrants.first(where: { $0.isActive(now: now) }) {
            guard activeGrant.allowsBudget(request.amountMinorUnits) else {
                return WalletControlPlaneDecision(
                    kind: .overBudget,
                    grantID: activeGrant.id,
                    reasons: ["Requested amount exceeds delegated budget"]
                )
            }
            return WalletControlPlaneDecision(
                kind: .allow,
                grantID: activeGrant.id,
                reasons: ["Delegated capability grant covers the requested vault action"]
            )
        }

        if let revokedGrant = scopedGrants.first(where: { $0.revokedAt != nil }) {
            return WalletControlPlaneDecision(kind: .revoked, grantID: revokedGrant.id, reasons: ["Delegated capability grant is revoked"])
        }

        return WalletControlPlaneDecision(kind: .expired, grantID: scopedGrants.first?.id, reasons: ["Delegated capability grant is expired"])
    }
}

enum AgenticPaymentPolicyEngine {
    static func evaluate(_ review: AgenticPaymentReview, now: Date = Date()) -> AgenticPaymentPolicyDecision {
        var reasons = [String]()
        var approvalLabels = ["User approval"]

        if review.intent.expiresAt <= now {
            return AgenticPaymentPolicyDecision(kind: .expired, reasons: ["Intent expired"], requiredApprovalLabels: [])
        }
        if review.intent.amountMinorUnits <= 0 {
            return AgenticPaymentPolicyDecision(kind: .revise, reasons: ["Amount must be greater than zero"], requiredApprovalLabels: [])
        }
        if review.intent.pageSnapshotHash.isEmpty {
            return AgenticPaymentPolicyDecision(kind: .revise, reasons: ["Missing page snapshot hash"], requiredApprovalLabels: [])
        }
        if let recurringPolicy = review.intent.recurringPolicy {
            if recurringPolicy.isRevoked {
                return AgenticPaymentPolicyDecision(kind: .revoked, reasons: ["Recurring policy revoked"], requiredApprovalLabels: [])
            }
            if !recurringPolicy.allows(intent: review.intent) {
                return AgenticPaymentPolicyDecision(kind: .deny, reasons: ["Recurring policy does not allow this payment"], requiredApprovalLabels: [])
            }
            approvalLabels.append("Recurring policy")
        }
        if review.eudiDecision?.state == .stepUpRequired {
            return AgenticPaymentPolicyDecision(kind: .stepUp, reasons: ["EUDI user authentication required"], requiredApprovalLabels: ["EUDI step-up"])
        }
        if let eudiDecision = review.eudiDecision, eudiDecision.state != .approved {
            return AgenticPaymentPolicyDecision(kind: .deny, reasons: ["EUDI disclosure not approved"], requiredApprovalLabels: [])
        }
        if let visaTrustedAgent = review.visaTrustedAgent, !visaTrustedAgent.isVerified {
            return AgenticPaymentPolicyDecision(kind: .deny, reasons: ["Visa Trusted Agent verification failed: \(visaTrustedAgent.status.rawValue)"], requiredApprovalLabels: [])
        }
        if let acpCheckout = review.acpCheckout {
            if acpCheckout.totalMinorUnits != review.intent.amountMinorUnits {
                return AgenticPaymentPolicyDecision(kind: .revise, reasons: ["ACP cart total differs from payment intent"], requiredApprovalLabels: [])
            }
            if acpCheckout.delegatedPaymentToken?.storesRawPaymentCredential == true {
                return AgenticPaymentPolicyDecision(kind: .deny, reasons: ["ACP token must not expose raw payment credentials"], requiredApprovalLabels: [])
            }
            approvalLabels.append("ACP basket")
        }
        if review.intent.protocolName == .agentPaymentsProtocol {
            let kinds = Set(review.ap2Mandates.map(\.kind))
            guard kinds == Set([.intent, .cart, .payment]) else {
                return AgenticPaymentPolicyDecision(kind: .revise, reasons: ["AP2 requires intent, cart, and payment mandates"], requiredApprovalLabels: [])
            }
            guard review.ap2Mandates.allSatisfy(\.isUsable) else {
                return AgenticPaymentPolicyDecision(kind: .deny, reasons: ["AP2 mandate is expired, revoked, or unsigned"], requiredApprovalLabels: [])
            }
            approvalLabels.append("AP2 mandate")
        }
        if let requirement = review.x402Requirement {
            if requirement.amountMinorUnits != review.intent.amountMinorUnits {
                return AgenticPaymentPolicyDecision(kind: .revise, reasons: ["x402 requirement differs from payment intent"], requiredApprovalLabels: [])
            }
            guard review.x402Payload?.requirementHash == requirement.requirementHash && review.x402Payload?.isSigned == true else {
                return AgenticPaymentPolicyDecision(kind: .revise, reasons: ["x402 payload is missing or not bound to the requirement"], requiredApprovalLabels: [])
            }
            approvalLabels.append("x402 requirement")
        }
        if let transfer = review.notabeneTransfer {
            if transfer.amountMinorUnits != review.intent.amountMinorUnits {
                return AgenticPaymentPolicyDecision(kind: .revise, reasons: ["Notabene TAP transfer differs from payment intent"], requiredApprovalLabels: [])
            }
            if transfer.state != .authorized {
                return AgenticPaymentPolicyDecision(kind: .askUser, reasons: ["Notabene TAP transfer needs authorization"], requiredApprovalLabels: approvalLabels + ["Transfer authorization"])
            }
            approvalLabels.append("Transfer authorization")
        }

        if review.userApproved {
            reasons.append("Typed intent, protocol evidence, and user approval are present")
            return AgenticPaymentPolicyDecision(kind: .allow, reasons: reasons, requiredApprovalLabels: [])
        } else {
            reasons.append("Payment-ready request requires explicit approval")
            return AgenticPaymentPolicyDecision(kind: .askUser, reasons: reasons, requiredApprovalLabels: approvalLabels)
        }
    }

    static func receipt(
        for review: AgenticPaymentReview,
        decision: AgenticPaymentPolicyDecision,
        now: Date = Date()
    ) -> AgenticPaymentReceipt {
        let status: AgenticPaymentReceiptStatus
        switch decision.kind {
        case .allow:
            status = .approved
        case .expired:
            status = .expired
        case .revoked:
            status = .revoked
        default:
            status = .denied
        }

        return AgenticPaymentReceipt(
            id: "payment-receipt-\(review.id)",
            reviewID: review.id,
            intentID: review.intent.id,
            protocolName: review.intent.protocolName,
            status: status,
            amountMinorUnits: review.intent.amountMinorUnits,
            currencyOrAsset: review.intent.currencyOrAsset,
            bindingHashes: review.bindingHashes,
            identityDisclosureHash: review.eudiDecision?.receiptHash,
            createdAt: now,
            storesRawPaymentCredential: review.acpCheckout?.delegatedPaymentToken?.storesRawPaymentCredential ?? false,
            summary: "\(review.intent.protocolName.title): \(status.rawValue) \(review.intent.amountMinorUnits) \(review.intent.currencyOrAsset)"
        )
    }
}

enum AgenticPaymentFixtures {
    static let now = Date(timeIntervalSince1970: 1_798_200_000)

    static var eudiDocument: EUDICredentialDocument {
        EUDICredentialDocument(
            id: "eudi-doc-pid",
            kind: .personIdentificationData,
            issuer: "EU Member State PID Provider",
            subjectHint: "local-user",
            claims: [
                "age_over_18": "true",
                "country": "SE",
                "family_name": "Redacted"
            ],
            issuedAt: now.addingTimeInterval(-86_400),
            expiresAt: now.addingTimeInterval(86_400 * 30),
            isRevoked: false
        )
    }

    static var eudiRequest: EUDIPresentationRequest {
        EUDIPresentationRequest(
            id: "eudi-request-age",
            relyingPartyID: "merchant.example",
            relyingPartyName: "Merchant Example",
            purpose: "Age-gated checkout",
            legalBasis: "User consent",
            protocolName: .openID4VP,
            requestedAttributes: [
                EUDIAttributeRequest(claimName: "age_over_18", purpose: "Eligibility", isRequired: true),
                EUDIAttributeRequest(claimName: "country", purpose: "Shipping rules", isRequired: false)
            ],
            transactionDataHash: "txn-age-hash",
            expiresAt: now.addingTimeInterval(600)
        )
    }

    static var cliwalletVerifiedEmailCredentialJSON: Data {
        """
        {
          "@context": [
            "https://www.w3.org/ns/credentials/v2",
            "https://schemas.wauth.dev/contexts/email-address-credential-v0.1.jsonld"
          ],
          "id": "https://verifiedemail.showntell.dev/credentials/email/human-test",
          "type": ["VerifiableCredential", "EmailAddressCredential"],
          "issuer": "https://verifiedemail.showntell.dev",
          "validFrom": "2026-01-01T00:00:00Z",
          "validUntil": "2100-01-01T00:00:00Z",
          "credentialSubject": {
            "id": "did:key:z6MkiHumanWallet",
            "email": "johan.sellstrom@iproov.com",
            "email_normalized": "johan.sellstrom@iproov.com",
            "email_verified": true,
            "subject_type": "user",
            "holder": {
              "holder_did": "did:key:z6MkiHumanWallet",
              "holder_public_key_jwk": {
                "kty": "OKP",
                "crv": "Ed25519",
                "x": "human-email-public-key",
                "kid": "human-email-key"
              },
              "holder_jwk_thumbprint": "human-email-thumbprint"
            }
          },
          "evidence": [
            {
              "method": "email_code_challenge",
              "challenge_id": "01234567-89ab-cdef-0123-456789abcdef",
              "nonce_hash": "sha256:noncehash",
              "email_hash": "sha256:emailhash",
              "verified_at": "2026-01-01T00:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!
    }

    static var cliwalletVerifiedEmailResponseJSON: Data {
        """
        {
          "credential_id": "https://verifiedemail.showntell.dev/credentials/email/human-test",
          "format": "vc+json",
          "vc_jwt": null,
          "credential": {
            "@context": [
              "https://www.w3.org/ns/credentials/v2",
              "https://schemas.wauth.dev/contexts/email-address-credential-v0.1.jsonld"
            ],
            "id": "https://verifiedemail.showntell.dev/credentials/email/human-test",
            "type": ["VerifiableCredential", "EmailAddressCredential"],
            "issuer": "https://verifiedemail.showntell.dev",
            "validFrom": "2026-01-01T00:00:00Z",
            "validUntil": "2100-01-01T00:00:00Z",
            "credentialSubject": {
              "id": "did:key:z6MkiHumanWallet",
              "email": "johan.sellstrom@iproov.com",
              "email_normalized": "johan.sellstrom@iproov.com",
              "email_verified": true,
              "subject_type": "user",
              "holder": {
                "holder_did": "did:key:z6MkiHumanWallet",
                "holder_public_key_jwk": {
                  "kty": "OKP",
                  "crv": "Ed25519",
                  "x": "human-email-public-key",
                  "kid": "human-email-key"
                },
                "holder_jwk_thumbprint": "human-email-thumbprint"
              }
            },
            "evidence": [
              {
                "method": "email_code_challenge",
                "challenge_id": "01234567-89ab-cdef-0123-456789abcdef",
                "nonce_hash": "sha256:noncehash",
                "email_hash": "sha256:emailhash",
                "verified_at": "2026-01-01T00:00:00Z"
              }
            ]
          }
        }
        """.data(using: .utf8)!
    }

    static var visaRequest: VisaTrustedAgentRequest {
        VisaTrustedAgentRequest(
            id: "visa-tap-request",
            agentProviderID: "dbrowser-agent",
            paymentSchemeID: "visa-intelligent-commerce",
            merchantID: "merchant.example",
            method: "POST",
            targetURI: "https://merchant.example/agent/checkout",
            bodyDigest: "sha256-body-digest",
            signature: VisaTrustedAgentSignature(
                keyID: "visa-key-1",
                algorithm: "ecdsa-p256-sha256",
                signatureReference: "signature-ref",
                signedHeaders: ["method", "target-uri", "body-digest", "created", "expires"],
                issuedAt: now.addingTimeInterval(-60),
                expiresAt: now.addingTimeInterval(600),
                sessionID: "session-1"
            ),
            consumerIdentityHash: "consumer-hash",
            paymentContainerHash: "payment-container-hash"
        )
    }

    static var acpCheckout: ACPCheckoutSession {
        let items = [
            ACPLineItem(id: "sku-1", title: "Research subscription", quantity: 1, unitAmountMinorUnits: 1_999)
        ]
        let basketHash = AgenticPaymentHash.stable([
            "merchant.example",
            "USD",
            items.map { "\($0.id):\($0.quantity):\($0.unitAmountMinorUnits)" }.joined(separator: "|"),
            "1999"
        ])
        return ACPCheckoutSession(
            id: "acp-checkout-1",
            merchantID: "merchant.example",
            merchantName: "Merchant Example",
            currency: "USD",
            lineItems: items,
            fulfillmentOptions: ["digital"],
            delegatedPaymentToken: ACPDelegatedPaymentTokenReference(
                tokenReference: "spt_ref_123",
                merchantID: "merchant.example",
                basketHash: basketHash,
                amountMinorUnits: 1_999,
                currency: "USD",
                expiresAt: now.addingTimeInterval(600)
            ),
            status: .delegatedPaymentTokenIssued
        )
    }

    static var intent: AgenticPaymentIntent {
        AgenticPaymentIntent(
            id: "intent-1",
            objective: "Buy the approved research subscription",
            merchantID: "merchant.example",
            counterpartyID: nil,
            amountMinorUnits: 1_999,
            currencyOrAsset: "USD",
            protocolName: .agenticCommerceProtocol,
            risk: .medium,
            pageSnapshotHash: "page-snapshot-hash",
            expiresAt: now.addingTimeInterval(600),
            recurringPolicy: nil
        )
    }
}

enum AgenticPaymentHash {
    static func stable(_ components: [String]) -> String {
        let canonical = components.joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
