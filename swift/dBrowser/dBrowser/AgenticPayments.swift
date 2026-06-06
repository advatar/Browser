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

    var title: String {
        switch self {
        case .personIdentificationData: "PID"
        case .mobileDrivingLicence: "mDL"
        case .qualifiedAttribute: "Qualified attribute"
        case .pseudonym: "Pseudonym"
        case .paymentAuthentication: "Payment authentication"
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
        supportedCredentialKinds: [.personIdentificationData, .mobileDrivingLicence, .qualifiedAttribute, .pseudonym, .paymentAuthentication],
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

struct WalletControlPlaneSnapshot: Codable, Equatable {
    var principals: [WalletPrincipal]
    var grants: [CapabilityGrant]
    var receipts: [WalletReceipt]

    var humanPrincipals: [WalletPrincipal] {
        principals.filter { $0.kind == .human }
    }

    var agentPrincipals: [WalletPrincipal] {
        principals.filter { $0.kind == .agent }
    }

    var activeGrants: [CapabilityGrant] {
        grants.filter { $0.isActive() }
    }

    var policySummary: String {
        "\(humanPrincipals.count) human, \(agentPrincipals.count) agent, \(activeGrants.count) active grant\(activeGrants.count == 1 ? "" : "s")"
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
                "Full crypto recovery retained by user"
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

        return WalletControlPlaneSnapshot(
            principals: [human, agent],
            grants: [identityGrant, paymentGrant, cryptoGrant],
            receipts: receipts
        )
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
