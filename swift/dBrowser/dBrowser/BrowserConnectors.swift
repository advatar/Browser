//
//  BrowserConnectors.swift
//  dBrowser
//
//  Secure, provider-specific contracts for first-party Google-style connectors.
//  Persisted connector profiles contain metadata only. OAuth access and refresh
//  tokens stay behind BrowserConnectorCredentialStoring and the production store
//  fails closed when the system Keychain is unavailable.
//

import CryptoKit
import Foundation
import Security

enum BrowserConnectorPolicy {
    nonisolated static let maximumLabelCharacters = 160
    nonisolated static let maximumErrorCharacters = 600
    nonisolated static let maximumQueryCharacters = 512
    nonisolated static let maximumIdentifierCharacters = 512
    nonisolated static let maximumSubjectCharacters = 998
    nonisolated static let maximumMessageCharacters = 40_000
    nonisolated static let maximumEventDescriptionCharacters = 8_000
    nonisolated static let maximumRecipients = 20
    nonisolated static let maximumResults = 50
    nonisolated static let maximumPersistedMutationProposals = 50
    nonisolated static let maximumResponseBytes = 2_000_000
    nonisolated static let authorizationLifetime: TimeInterval = 10 * 60
    nonisolated static let proposalLifetime: TimeInterval = 15 * 60

    nonisolated static func boundedText(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(0, limit)))
    }
}

enum BrowserConnectorKind: String, Codable, CaseIterable, Equatable, Identifiable {
    case gmail
    case googleCalendar

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .gmail: "Gmail"
        case .googleCalendar: "Google Calendar"
        }
    }
}

enum BrowserConnectorScope: String, Codable, CaseIterable, Equatable, Identifiable {
    case gmailRead
    case gmailDraft
    case calendarRead
    case calendarEvents

    nonisolated var id: String { rawValue }

    nonisolated var connectorKind: BrowserConnectorKind {
        switch self {
        case .gmailRead, .gmailDraft: .gmail
        case .calendarRead, .calendarEvents: .googleCalendar
        }
    }

    /// Official Google OAuth scope URI. The app requests incremental scopes and
    /// never converts an unrecognized server scope into a local capability.
    nonisolated var oauthValue: String {
        switch self {
        case .gmailRead:
            "https://www.googleapis.com/auth/gmail.readonly"
        case .gmailDraft:
            "https://www.googleapis.com/auth/gmail.compose"
        case .calendarRead:
            "https://www.googleapis.com/auth/calendar.readonly"
        case .calendarEvents:
            "https://www.googleapis.com/auth/calendar.events"
        }
    }

    nonisolated var title: String {
        switch self {
        case .gmailRead: "Read Gmail"
        case .gmailDraft: "Create Gmail drafts"
        case .calendarRead: "Read Calendar"
        case .calendarEvents: "Propose Calendar events"
        }
    }

    nonisolated static func recognized(
        oauthValues: some Sequence<String>,
        for kind: BrowserConnectorKind
    ) -> Set<BrowserConnectorScope> {
        let values = Set(oauthValues)
        return Set(allCases.filter { $0.connectorKind == kind && values.contains($0.oauthValue) })
    }
}

enum BrowserConnectorAction: String, Codable, CaseIterable, Equatable, Identifiable {
    case gmailSearch
    case gmailReadMessage
    case gmailCreateDraft
    case calendarListEvents
    case calendarProposeEvent

    nonisolated var id: String { rawValue }

    nonisolated var connectorKind: BrowserConnectorKind {
        switch self {
        case .gmailSearch, .gmailReadMessage, .gmailCreateDraft: .gmail
        case .calendarListEvents, .calendarProposeEvent: .googleCalendar
        }
    }

    nonisolated var requiredScopes: Set<BrowserConnectorScope> {
        switch self {
        case .gmailSearch, .gmailReadMessage: [.gmailRead]
        case .gmailCreateDraft: [.gmailDraft]
        case .calendarListEvents: [.calendarRead]
        case .calendarProposeEvent: [.calendarEvents]
        }
    }

    nonisolated var isMutating: Bool {
        switch self {
        case .gmailCreateDraft, .calendarProposeEvent: true
        case .gmailSearch, .gmailReadMessage, .calendarListEvents: false
        }
    }

    nonisolated var title: String {
        switch self {
        case .gmailSearch: "Search Gmail"
        case .gmailReadMessage: "Read Gmail message"
        case .gmailCreateDraft: "Create Gmail draft"
        case .calendarListEvents: "Read Calendar events"
        case .calendarProposeEvent: "Create proposed Calendar event"
        }
    }
}

enum BrowserConnectorConnectionState: String, Codable, Equatable {
    case configurationRequired
    case disconnected
    case authorizing
    case connected
    case expired
    case failed
}

enum BrowserConnectorActionDecision: Equatable {
    case allowed
    case approvalRequired
    case configurationRequired
    case disconnected
    case wrongConnector
    case missingScopes(Set<BrowserConnectorScope>)
}

/// Codable connector metadata. This type deliberately has no token, secret,
/// authorization header, OAuth verifier, or credential-reference payload.
struct BrowserConnectorProfile: Identifiable, Equatable, Codable {
    let id: String
    var kind: BrowserConnectorKind
    var displayName: String
    var accountLabel: String?
    var authorizedScopes: Set<BrowserConnectorScope>
    var connectionState: BrowserConnectorConnectionState
    var lastUsedAt: Date?
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayName
        case accountLabel
        case authorizedScopes
        case connectionState
        case lastUsedAt
        case lastError
        case createdAt
        case updatedAt
    }

    nonisolated init(
        id: String = "connector:" + UUID().uuidString.lowercased(),
        kind: BrowserConnectorKind,
        displayName: String? = nil,
        accountLabel: String? = nil,
        authorizedScopes: Set<BrowserConnectorScope> = [],
        connectionState: BrowserConnectorConnectionState = .configurationRequired,
        lastUsedAt: Date? = nil,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let normalizedID = BrowserConnectorPolicy.boundedText(
            id,
            limit: BrowserConnectorPolicy.maximumIdentifierCharacters
        )
        self.id = normalizedID.isEmpty ? "connector:" + UUID().uuidString.lowercased() : normalizedID
        self.kind = kind
        self.displayName = BrowserConnectorPolicy.boundedText(
            displayName ?? kind.title,
            limit: BrowserConnectorPolicy.maximumLabelCharacters
        )
        self.accountLabel = accountLabel.flatMap {
            let bounded = BrowserConnectorPolicy.boundedText(
                $0,
                limit: BrowserConnectorPolicy.maximumLabelCharacters
            )
            return bounded.isEmpty ? nil : bounded
        }
        self.authorizedScopes = Set(authorizedScopes.filter { $0.connectorKind == kind })
        self.connectionState = connectionState
        self.lastUsedAt = lastUsedAt
        self.lastError = lastError.map {
            BrowserConnectorPolicy.boundedText($0, limit: BrowserConnectorPolicy.maximumErrorCharacters)
        }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            kind: try container.decode(BrowserConnectorKind.self, forKey: .kind),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            accountLabel: try container.decodeIfPresent(String.self, forKey: .accountLabel),
            authorizedScopes: try container.decodeIfPresent(
                Set<BrowserConnectorScope>.self,
                forKey: .authorizedScopes
            ) ?? [],
            connectionState: try container.decodeIfPresent(
                BrowserConnectorConnectionState.self,
                forKey: .connectionState
            ) ?? .configurationRequired,
            lastUsedAt: try container.decodeIfPresent(Date.self, forKey: .lastUsedAt),
            lastError: try container.decodeIfPresent(String.self, forKey: .lastError),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(accountLabel, forKey: .accountLabel)
        try container.encode(authorizedScopes, forKey: .authorizedScopes)
        try container.encode(connectionState, forKey: .connectionState)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    nonisolated func decision(for action: BrowserConnectorAction) -> BrowserConnectorActionDecision {
        guard action.connectorKind == kind else { return .wrongConnector }
        switch connectionState {
        case .configurationRequired:
            return .configurationRequired
        case .connected:
            break
        case .disconnected, .authorizing, .expired, .failed:
            return .disconnected
        }
        let missing = action.requiredScopes.subtracting(authorizedScopes)
        guard missing.isEmpty else { return .missingScopes(missing) }
        return action.isMutating ? .approvalRequired : .allowed
    }

    nonisolated var credentialAccount: String {
        "oauth:" + id
    }
}

/// Secrets are intentionally neither Codable nor printable. Token fields are
/// fileprivate so only this credential/HTTP boundary can place them in Keychain
/// records or Authorization headers.
struct BrowserConnectorOAuthTokens: Equatable {
    fileprivate let accessToken: String
    fileprivate let refreshToken: String?
    let expiresAt: Date
    let grantedScopes: Set<BrowserConnectorScope>

    nonisolated init?(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date,
        grantedScopes: Set<BrowserConnectorScope>
    ) {
        let boundedAccess = String(accessToken.prefix(32_768))
        let boundedRefresh = refreshToken.map { String($0.prefix(32_768)) }
        guard !boundedAccess.isEmpty else { return nil }
        self.accessToken = boundedAccess
        self.refreshToken = boundedRefresh?.isEmpty == true ? nil : boundedRefresh
        self.expiresAt = expiresAt
        self.grantedScopes = grantedScopes
    }

    nonisolated func isExpired(at date: Date = Date(), leeway: TimeInterval = 30) -> Bool {
        expiresAt <= date.addingTimeInterval(max(0, leeway))
    }

    nonisolated var hasRefreshToken: Bool {
        refreshToken?.isEmpty == false
    }
}

enum BrowserConnectorCredentialStoreError: Error, LocalizedError, Equatable {
    case invalidCredential
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            "Connector credentials in Keychain were invalid."
        case .keychain(let status):
            "Connector Keychain operation failed with status \(status)."
        }
    }
}

@MainActor
protocol BrowserConnectorCredentialStoring: AnyObject {
    func loadTokens(for profile: BrowserConnectorProfile) throws -> BrowserConnectorOAuthTokens?
    func saveTokens(_ tokens: BrowserConnectorOAuthTokens, for profile: BrowserConnectorProfile) throws
    func deleteTokens(for profile: BrowserConnectorProfile) throws
}

@MainActor
final class KeychainBrowserConnectorCredentialStore: BrowserConnectorCredentialStoring {
    private let service: String

    init(service: String = "com.advatarsystems.dBrowser.connectors.oauth") {
        self.service = service
    }

    func loadTokens(for profile: BrowserConnectorProfile) throws -> BrowserConnectorOAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profile.credentialAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw BrowserConnectorCredentialStoreError.keychain(status)
        }
        guard let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let accessToken = payload["access_token"] as? String,
              let expiresAt = payload["expires_at"] as? TimeInterval,
              let scopeValues = payload["scopes"] as? [String],
              let tokens = BrowserConnectorOAuthTokens(
                accessToken: accessToken,
                refreshToken: payload["refresh_token"] as? String,
                expiresAt: Date(timeIntervalSince1970: expiresAt),
                grantedScopes: BrowserConnectorScope.recognized(
                    oauthValues: scopeValues,
                    for: profile.kind
                )
              ) else {
            throw BrowserConnectorCredentialStoreError.invalidCredential
        }
        return tokens
    }

    func saveTokens(_ tokens: BrowserConnectorOAuthTokens, for profile: BrowserConnectorProfile) throws {
        var payload: [String: Any] = [
            "access_token": tokens.accessToken,
            "expires_at": tokens.expiresAt.timeIntervalSince1970,
            "scopes": tokens.grantedScopes.map(\.oauthValue).sorted()
        ]
        if let refreshToken = tokens.refreshToken {
            payload["refresh_token"] = refreshToken
        }
        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: payload,
                format: .binary,
                options: 0
            )
        } catch {
            throw BrowserConnectorCredentialStoreError.invalidCredential
        }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profile.credentialAccount
        ]
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw BrowserConnectorCredentialStoreError.keychain(updateStatus)
        }

        var attributes = identity
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw BrowserConnectorCredentialStoreError.keychain(addStatus)
        }
    }

    func deleteTokens(for profile: BrowserConnectorProfile) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profile.credentialAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BrowserConnectorCredentialStoreError.keychain(status)
        }
    }
}

enum BrowserOAuthEntropyError: Error, LocalizedError {
    case unavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable(let status):
            "Secure OAuth entropy was unavailable (\(status))."
        }
    }
}

@MainActor
protocol BrowserOAuthEntropyGenerating: AnyObject {
    func randomBase64URL(byteCount: Int) throws -> String
}

@MainActor
final class SystemBrowserOAuthEntropyGenerator: BrowserOAuthEntropyGenerating {
    func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: max(32, byteCount))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw BrowserOAuthEntropyError.unavailable(status) }
        return Data(bytes).browserBase64URLEncodedString
    }
}

struct BrowserOAuthPKCEPair: Equatable {
    let verifier: String
    let challenge: String

    nonisolated init?(verifier: String) {
        guard (43...128).contains(verifier.count),
              verifier.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
                      .contains($0)
              }) else {
            return nil
        }
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).browserBase64URLEncodedString
    }
}

struct BrowserGoogleOAuthConfiguration: Equatable {
    var clientID: String
    var redirectURI: URL?
    var authorizationEndpoint: URL
    var tokenEndpoint: URL

    nonisolated init(
        clientID: String,
        redirectURI: URL?,
        authorizationEndpoint: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!
    ) {
        self.clientID = BrowserConnectorPolicy.boundedText(clientID, limit: 1_024)
        self.redirectURI = redirectURI
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
    }

    nonisolated var isConfigured: Bool {
        !clientID.isEmpty
            && redirectURI?.scheme?.isEmpty == false
            && authorizationEndpoint.scheme?.lowercased() == "https"
            && tokenEndpoint.scheme?.lowercased() == "https"
    }

    nonisolated func matchesCallbackURL(_ callbackURL: URL) -> Bool {
        guard let redirectURI,
              let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let expected = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false) else {
            return false
        }
        return callback.scheme?.lowercased() == expected.scheme?.lowercased()
            && callback.host?.lowercased() == expected.host?.lowercased()
            && callback.port == expected.port
            && callback.path == expected.path
    }
}

struct BrowserOAuthPendingAuthorization: Equatable {
    let profileID: String
    let connectorKind: BrowserConnectorKind
    let state: String
    let pkce: BrowserOAuthPKCEPair
    let redirectURI: URL
    let requestedScopes: Set<BrowserConnectorScope>
    let createdAt: Date
}

struct BrowserOAuthAuthorizationRequest: Equatable {
    var authorizationURL: URL
    var pending: BrowserOAuthPendingAuthorization
}

struct BrowserOAuthCallback: Equatable {
    var authorizationCode: String
    var pending: BrowserOAuthPendingAuthorization
}

enum BrowserOAuthContractError: Error, LocalizedError, Equatable {
    case configurationRequired
    case invalidScope
    case invalidPKCE
    case invalidAuthorizationURL
    case unknownOrReplayedState
    case expiredState
    case redirectMismatch
    case providerError(String)
    case missingAuthorizationCode
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .configurationRequired: "Google OAuth client ID and redirect URI are required."
        case .invalidScope: "The connector requested a scope outside its allowlist."
        case .invalidPKCE: "A valid OAuth PKCE verifier could not be created."
        case .invalidAuthorizationURL: "A valid Google authorization URL could not be created."
        case .unknownOrReplayedState: "The OAuth callback state was unknown or already consumed."
        case .expiredState: "The OAuth authorization state expired."
        case .redirectMismatch: "The OAuth callback did not match the registered redirect URI."
        case .providerError(let message): "Google OAuth returned an error: \(message)."
        case .missingAuthorizationCode: "The OAuth callback did not include an authorization code."
        case .invalidTokenResponse: "Google OAuth returned an invalid token response."
        }
    }
}

@MainActor
final class BrowserGoogleOAuthContract {
    private let entropy: BrowserOAuthEntropyGenerating

    init(entropy: BrowserOAuthEntropyGenerating = SystemBrowserOAuthEntropyGenerator()) {
        self.entropy = entropy
    }

    func makeAuthorizationRequest(
        profile: BrowserConnectorProfile,
        scopes: Set<BrowserConnectorScope>,
        configuration: BrowserGoogleOAuthConfiguration,
        now: Date = Date()
    ) throws -> BrowserOAuthAuthorizationRequest {
        guard configuration.isConfigured, let redirectURI = configuration.redirectURI else {
            throw BrowserOAuthContractError.configurationRequired
        }
        guard !scopes.isEmpty, scopes.allSatisfy({ $0.connectorKind == profile.kind }) else {
            throw BrowserOAuthContractError.invalidScope
        }
        let verifier = try entropy.randomBase64URL(byteCount: 48)
        guard let pkce = BrowserOAuthPKCEPair(verifier: verifier) else {
            throw BrowserOAuthContractError.invalidPKCE
        }
        let state = try entropy.randomBase64URL(byteCount: 32)
        let pending = BrowserOAuthPendingAuthorization(
            profileID: profile.id,
            connectorKind: profile.kind,
            state: state,
            pkce: pkce,
            redirectURI: redirectURI,
            requestedScopes: scopes,
            createdAt: now
        )

        guard var components = URLComponents(
            url: configuration.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw BrowserOAuthContractError.invalidAuthorizationURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.map(\.oauthValue).sorted().joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "include_granted_scopes", value: "true")
        ]
        guard let authorizationURL = components.url else {
            throw BrowserOAuthContractError.invalidAuthorizationURL
        }
        return BrowserOAuthAuthorizationRequest(
            authorizationURL: authorizationURL,
            pending: pending
        )
    }
}

/// In-memory single-use state registry. Register immediately before starting
/// ASWebAuthenticationSession; callback consumption removes the state first so
/// an expired, malformed, or replayed callback cannot be tried again.
@MainActor
final class BrowserOAuthAuthorizationRegistry {
    private var pendingByState: [String: BrowserOAuthPendingAuthorization] = [:]

    func register(_ pending: BrowserOAuthPendingAuthorization) {
        pendingByState[pending.state] = pending
    }

    func cancel(state: String) {
        pendingByState[state] = nil
    }

    func consumeCallback(_ callbackURL: URL, now: Date = Date()) throws -> BrowserOAuthCallback {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              let pending = pendingByState.removeValue(forKey: state) else {
            throw BrowserOAuthContractError.unknownOrReplayedState
        }
        guard now.timeIntervalSince(pending.createdAt) >= 0,
              now.timeIntervalSince(pending.createdAt) <= BrowserConnectorPolicy.authorizationLifetime else {
            throw BrowserOAuthContractError.expiredState
        }
        guard Self.matchesRedirect(callbackURL, pending.redirectURI) else {
            throw BrowserOAuthContractError.redirectMismatch
        }
        if let providerError = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = components.queryItems?.first(where: { $0.name == "error_description" })?.value
            throw BrowserOAuthContractError.providerError(
                BrowserConnectorPolicy.boundedText(
                    description ?? providerError,
                    limit: BrowserConnectorPolicy.maximumErrorCharacters
                )
            )
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw BrowserOAuthContractError.missingAuthorizationCode
        }
        return BrowserOAuthCallback(
            authorizationCode: String(code.prefix(8_192)),
            pending: pending
        )
    }

    private static func matchesRedirect(_ callback: URL, _ expected: URL) -> Bool {
        guard let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let expectedComponents = URLComponents(url: expected, resolvingAgainstBaseURL: false) else {
            return false
        }
        return callbackComponents.scheme?.lowercased() == expectedComponents.scheme?.lowercased()
            && callbackComponents.host?.lowercased() == expectedComponents.host?.lowercased()
            && callbackComponents.port == expectedComponents.port
            && callbackComponents.path == expectedComponents.path
    }
}

enum BrowserGoogleOAuthRequestBuilder {
    nonisolated static func tokenExchangeRequest(
        callback: BrowserOAuthCallback,
        configuration: BrowserGoogleOAuthConfiguration
    ) throws -> URLRequest {
        guard configuration.isConfigured else { throw BrowserOAuthContractError.configurationRequired }
        return try formRequest(
            endpoint: configuration.tokenEndpoint,
            fields: [
                ("client_id", configuration.clientID),
                ("code", callback.authorizationCode),
                ("code_verifier", callback.pending.pkce.verifier),
                ("grant_type", "authorization_code"),
                ("redirect_uri", callback.pending.redirectURI.absoluteString)
            ]
        )
    }

    nonisolated static func tokenRefreshRequest(
        tokens: BrowserConnectorOAuthTokens,
        configuration: BrowserGoogleOAuthConfiguration
    ) throws -> URLRequest {
        guard configuration.isConfigured else { throw BrowserOAuthContractError.configurationRequired }
        guard let refreshToken = tokens.refreshToken else {
            throw BrowserOAuthContractError.invalidTokenResponse
        }
        return try formRequest(
            endpoint: configuration.tokenEndpoint,
            fields: [
                ("client_id", configuration.clientID),
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken)
            ]
        )
    }

    nonisolated static func parseTokenResponse(
        _ data: Data,
        kind: BrowserConnectorKind,
        requestedScopes: Set<BrowserConnectorScope>,
        now: Date = Date(),
        priorRefreshToken: String? = nil
    ) throws -> BrowserConnectorOAuthTokens {
        guard data.count <= 256_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue else {
            throw BrowserOAuthContractError.invalidTokenResponse
        }
        let scopeValues = (object["scope"] as? String)?
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init) ?? []
        let recognized = scopeValues.isEmpty
            ? Set(requestedScopes.filter { $0.connectorKind == kind })
            : BrowserConnectorScope.recognized(oauthValues: scopeValues, for: kind)
        guard !recognized.isEmpty,
              let tokens = BrowserConnectorOAuthTokens(
                accessToken: accessToken,
                refreshToken: (object["refresh_token"] as? String) ?? priorRefreshToken,
                expiresAt: now.addingTimeInterval(min(max(1, expiresIn), 86_400)),
                grantedScopes: recognized
              ) else {
            throw BrowserOAuthContractError.invalidTokenResponse
        }
        return tokens
    }

    private nonisolated static func formRequest(
        endpoint: URL,
        fields: [(String, String)]
    ) throws -> URLRequest {
        guard endpoint.scheme?.lowercased() == "https" else {
            throw BrowserOAuthContractError.configurationRequired
        }
        let body = fields.map { key, value in
            "\(key.browserFormEncoded)=\(value.browserFormEncoded)"
        }
        .joined(separator: "&")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

struct BrowserGmailMessageSummary: Identifiable, Equatable {
    let id: String
    var threadID: String?
    var sender: String
    var subject: String
    var snippet: String
    var receivedAt: Date?

    nonisolated init(id: String, threadID: String?, sender: String, subject: String, snippet: String, receivedAt: Date?) {
        self.id = BrowserConnectorPolicy.boundedText(id, limit: BrowserConnectorPolicy.maximumIdentifierCharacters)
        self.threadID = threadID.map {
            BrowserConnectorPolicy.boundedText($0, limit: BrowserConnectorPolicy.maximumIdentifierCharacters)
        }
        self.sender = BrowserConnectorPolicy.boundedText(sender, limit: BrowserConnectorPolicy.maximumLabelCharacters)
        self.subject = BrowserConnectorPolicy.boundedText(subject, limit: BrowserConnectorPolicy.maximumSubjectCharacters)
        self.snippet = BrowserConnectorPolicy.boundedText(snippet, limit: 2_000)
        self.receivedAt = receivedAt
    }
}

struct BrowserCalendarEventSummary: Identifiable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var location: String?

    nonisolated init(id: String, title: String, start: Date, end: Date, location: String? = nil) {
        self.id = BrowserConnectorPolicy.boundedText(id, limit: BrowserConnectorPolicy.maximumIdentifierCharacters)
        self.title = BrowserConnectorPolicy.boundedText(title, limit: BrowserConnectorPolicy.maximumSubjectCharacters)
        self.start = start
        self.end = max(start, end)
        self.location = location.map {
            BrowserConnectorPolicy.boundedText($0, limit: BrowserConnectorPolicy.maximumLabelCharacters)
        }
    }
}

struct BrowserGmailDraftContent: Equatable, Codable {
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var body: String

    nonisolated init(
        to: [String],
        cc: [String] = [],
        bcc: [String] = [],
        subject: String,
        body: String
    ) {
        var seen = Set<String>()
        var remainingRecipients = BrowserConnectorPolicy.maximumRecipients
        self.to = Self.boundedAddresses(
            to,
            seen: &seen,
            remaining: &remainingRecipients
        )
        self.cc = Self.boundedAddresses(
            cc,
            seen: &seen,
            remaining: &remainingRecipients
        )
        self.bcc = Self.boundedAddresses(
            bcc,
            seen: &seen,
            remaining: &remainingRecipients
        )
        self.subject = BrowserConnectorPolicy.boundedText(
            subject.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " "),
            limit: BrowserConnectorPolicy.maximumSubjectCharacters
        )
        self.body = BrowserConnectorPolicy.boundedText(body, limit: BrowserConnectorPolicy.maximumMessageCharacters)
    }

    nonisolated var commitment: String {
        BrowserResearchCommitment.sha256(
            ["to"] + to + ["cc"] + cc + ["bcc"] + bcc + ["subject", subject, "body", body]
        )
    }

    private nonisolated static func boundedAddresses(
        _ values: [String],
        seen: inout Set<String>,
        remaining: inout Int
    ) -> [String] {
        guard remaining > 0 else { return [] }
        var result: [String] = []
        for value in values where remaining > 0 {
            let bounded = BrowserConnectorPolicy.boundedText(
                value.replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\n", with: ""),
                limit: BrowserConnectorPolicy.maximumLabelCharacters
            )
            guard !bounded.isEmpty, seen.insert(bounded.lowercased()).inserted else { continue }
            result.append(bounded)
            remaining -= 1
        }
        return result
    }
}

struct BrowserCalendarEventProposalContent: Equatable, Codable {
    var calendarID: String
    var title: String
    var start: Date
    var end: Date
    var timeZoneIdentifier: String
    var location: String?
    var notes: String?

    nonisolated init(
        calendarID: String = "primary",
        title: String,
        start: Date,
        end: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.calendarID = BrowserConnectorPolicy.boundedText(
            calendarID,
            limit: BrowserConnectorPolicy.maximumIdentifierCharacters
        )
        self.title = BrowserConnectorPolicy.boundedText(title, limit: BrowserConnectorPolicy.maximumSubjectCharacters)
        self.start = start
        self.end = max(start, end)
        self.timeZoneIdentifier = BrowserConnectorPolicy.boundedText(timeZoneIdentifier, limit: 120)
        self.location = location.flatMap {
            let bounded = BrowserConnectorPolicy.boundedText(
                $0,
                limit: BrowserConnectorPolicy.maximumLabelCharacters
            )
            return bounded.isEmpty ? nil : bounded
        }
        self.notes = notes.flatMap {
            let bounded = BrowserConnectorPolicy.boundedText(
                $0,
                limit: BrowserConnectorPolicy.maximumEventDescriptionCharacters
            )
            return bounded.isEmpty ? nil : bounded
        }
    }

    nonisolated var commitment: String {
        BrowserResearchCommitment.sha256([
            calendarID,
            title,
            String(start.timeIntervalSince1970),
            String(end.timeIntervalSince1970),
            timeZoneIdentifier,
            location ?? "",
            notes ?? ""
        ])
    }
}

enum BrowserConnectorMutationPayload: Equatable, Codable {
    case gmailDraft(BrowserGmailDraftContent)
    case calendarEvent(BrowserCalendarEventProposalContent)

    nonisolated var action: BrowserConnectorAction {
        switch self {
        case .gmailDraft: .gmailCreateDraft
        case .calendarEvent: .calendarProposeEvent
        }
    }

    nonisolated var commitment: String {
        switch self {
        case .gmailDraft(let content): content.commitment
        case .calendarEvent(let content): content.commitment
        }
    }
}

enum BrowserConnectorProposalStatus: String, Equatable, Codable {
    case requiresApproval
    case approved
    case executing
    case completed
    case ambiguousFailed
    case denied
    case expired

    nonisolated var isTerminal: Bool {
        switch self {
        case .completed, .ambiguousFailed, .denied, .expired:
            true
        case .requiresApproval, .approved, .executing:
            false
        }
    }
}

struct BrowserConnectorMutationProposal: Identifiable, Equatable, Codable {
    let id: UUID
    let profileID: String
    let action: BrowserConnectorAction
    let payload: BrowserConnectorMutationPayload
    let payloadCommitment: String
    let createdAt: Date
    let expiresAt: Date
    private(set) var status: BrowserConnectorProposalStatus
    private(set) var approvalReceiptID: String?

    nonisolated init(
        id: UUID = UUID(),
        profile: BrowserConnectorProfile,
        payload: BrowserConnectorMutationPayload,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profile.id
        self.action = payload.action
        self.payload = payload
        self.payloadCommitment = BrowserResearchCommitment.sha256([
            profile.id,
            payload.action.rawValue,
            payload.commitment
        ])
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(BrowserConnectorPolicy.proposalLifetime)
        self.status = .requiresApproval
        self.approvalReceiptID = nil
    }

    nonisolated func approving(receiptID: String, now: Date = Date()) throws -> BrowserConnectorMutationProposal {
        guard status == .requiresApproval else {
            throw BrowserConnectorRequestError.invalidProposalState
        }
        guard now <= expiresAt else { throw BrowserConnectorRequestError.expiredProposal }
        let boundedReceipt = BrowserConnectorPolicy.boundedText(
            receiptID,
            limit: BrowserConnectorPolicy.maximumIdentifierCharacters
        )
        guard !boundedReceipt.isEmpty else { throw BrowserConnectorRequestError.approvalRequired }
        var copy = self
        copy.status = .approved
        copy.approvalReceiptID = boundedReceipt
        return copy
    }

    /// Consumes the one-shot approval before any network I/O begins. Only an
    /// executing proposal can be converted into a mutating REST request.
    nonisolated func beginningExecution(now: Date = Date()) throws -> BrowserConnectorMutationProposal {
        guard status == .approved, approvalReceiptID?.isEmpty == false else {
            throw BrowserConnectorRequestError.invalidProposalState
        }
        guard now <= expiresAt else { throw BrowserConnectorRequestError.expiredProposal }
        var copy = self
        copy.status = .executing
        return copy
    }

    nonisolated func completing() throws -> BrowserConnectorMutationProposal {
        guard status == .executing else {
            throw BrowserConnectorRequestError.invalidProposalState
        }
        var copy = self
        copy.status = .completed
        return copy
    }

    nonisolated func failingAmbiguously() throws -> BrowserConnectorMutationProposal {
        guard status == .executing else {
            throw BrowserConnectorRequestError.invalidProposalState
        }
        var copy = self
        copy.status = .ambiguousFailed
        return copy
    }

    nonisolated func denying(now: Date = Date()) throws -> BrowserConnectorMutationProposal {
        guard status == .requiresApproval else {
            throw BrowserConnectorRequestError.invalidProposalState
        }
        guard now <= expiresAt else { throw BrowserConnectorRequestError.expiredProposal }
        var copy = self
        copy.status = .denied
        return copy
    }

    nonisolated func expiring(now: Date = Date()) throws -> BrowserConnectorMutationProposal {
        guard !status.isTerminal, status != .executing, now > expiresAt else {
            throw BrowserConnectorRequestError.invalidProposalState
        }
        var copy = self
        copy.status = .expired
        return copy
    }

    /// Restores the durable audit record without ever making an interrupted
    /// one-shot mutation eligible for replay. An approved proposal may have
    /// crossed the network boundary before termination, so it is reconciled
    /// with the same conservative terminal state as an executing proposal.
    nonisolated func reconcilingAfterRelaunch() -> BrowserConnectorMutationProposal {
        guard !status.isTerminal else { return self }
        var copy = self
        switch status {
        case .approved, .executing:
            copy.status = .ambiguousFailed
        case .requiresApproval:
            // Approval is intentionally process-local. Even a proposal whose
            // wall-clock TTL remains must be reviewed as a new proposal after
            // relaunch, never carried forward as actionable durable state.
            copy.status = .expired
        case .completed, .ambiguousFailed, .denied, .expired:
            break
        }
        return copy
    }
}

/// Versioned connector metadata persisted in UserDefaults. Credential values
/// cannot enter this payload because it deliberately contains only profiles
/// and bounded proposal audit records; OAuth tokens remain in the credential
/// store (Keychain in production).
struct BrowserConnectorPersistencePayload: Codable, Equatable {
    nonisolated static let currentSchemaVersion = 2

    let schemaVersion: Int
    var profiles: [BrowserConnectorProfile]
    var mutationProposals: [BrowserConnectorMutationProposal]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profiles
        case mutationProposals
    }

    nonisolated init(
        profiles: [BrowserConnectorProfile],
        mutationProposals: [BrowserConnectorMutationProposal]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.profiles = profiles
        self.mutationProposals = Self.boundedMutationProposals(mutationProposals)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported connector persistence schema version."
            )
        }
        self.schemaVersion = schemaVersion
        self.profiles = try container.decode([BrowserConnectorProfile].self, forKey: .profiles)
        self.mutationProposals = Self.boundedMutationProposals(
            try container.decodeIfPresent(
                [BrowserConnectorMutationProposal].self,
                forKey: .mutationProposals
            ) ?? []
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(
            Self.boundedMutationProposals(mutationProposals),
            forKey: .mutationProposals
        )
    }

    nonisolated static func boundedMutationProposals(
        _ proposals: [BrowserConnectorMutationProposal]
    ) -> [BrowserConnectorMutationProposal] {
        var seen = Set<UUID>()
        var bounded: [BrowserConnectorMutationProposal] = []
        bounded.reserveCapacity(min(proposals.count, BrowserConnectorPolicy.maximumPersistedMutationProposals))
        for proposal in proposals where seen.insert(proposal.id).inserted {
            bounded.append(proposal)
            if bounded.count == BrowserConnectorPolicy.maximumPersistedMutationProposals {
                break
            }
        }
        return bounded
    }
}

enum BrowserConnectorRequestError: Error, LocalizedError, Equatable {
    case configurationRequired
    case disconnected
    case wrongConnector
    case missingScope
    case expiredCredentials
    case invalidInput
    case approvalRequired
    case expiredProposal
    case invalidProposalState
    case proposalMismatch
    case invalidHTTPStatus(Int)
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .configurationRequired: "Connector configuration is required."
        case .disconnected: "Connector is disconnected."
        case .wrongConnector: "Connector does not support this action."
        case .missingScope: "Connector is missing a required OAuth scope."
        case .expiredCredentials: "Connector credentials expired."
        case .invalidInput: "Connector request input was invalid."
        case .approvalRequired: "This connector mutation requires explicit approval."
        case .expiredProposal: "The connector mutation proposal expired."
        case .invalidProposalState: "The connector mutation is no longer in the required state."
        case .proposalMismatch: "The connector approval does not match this mutation payload."
        case .invalidHTTPStatus(let status): "Connector returned HTTP \(status)."
        case .responseTooLarge: "Connector response exceeded the bounded response size."
        }
    }
}

struct BrowserConnectorAuthorizedRequest: Equatable {
    var profileID: String
    var action: BrowserConnectorAction
    var request: URLRequest
}

enum BrowserGoogleRESTRequestBuilder {
    private nonisolated static let gmailRoot = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
    private nonisolated static let calendarRoot = URL(string: "https://www.googleapis.com/calendar/v3")!

    nonisolated static func gmailSearch(
        profile: BrowserConnectorProfile,
        tokens: BrowserConnectorOAuthTokens,
        query: String,
        maximumResults: Int = 20,
        now: Date = Date()
    ) throws -> BrowserConnectorAuthorizedRequest {
        try validate(profile: profile, tokens: tokens, action: .gmailSearch, now: now)
        let boundedQuery = BrowserConnectorPolicy.boundedText(query, limit: BrowserConnectorPolicy.maximumQueryCharacters)
        guard !boundedQuery.isEmpty else { throw BrowserConnectorRequestError.invalidInput }
        var components = URLComponents(url: gmailRoot.appendingPathComponent("messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: boundedQuery),
            URLQueryItem(name: "maxResults", value: String(min(max(1, maximumResults), BrowserConnectorPolicy.maximumResults)))
        ]
        guard let url = components.url else { throw BrowserConnectorRequestError.invalidInput }
        return authorizedRequest(profile: profile, tokens: tokens, action: .gmailSearch, url: url)
    }

    nonisolated static func gmailMessage(
        profile: BrowserConnectorProfile,
        tokens: BrowserConnectorOAuthTokens,
        messageID: String,
        now: Date = Date()
    ) throws -> BrowserConnectorAuthorizedRequest {
        try validate(profile: profile, tokens: tokens, action: .gmailReadMessage, now: now)
        let messageURL = try appendingPathComponent(
            messageID,
            to: gmailRoot.appendingPathComponent("messages")
        )
        var components = URLComponents(
            url: messageURL,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "metadata")]
        guard let url = components.url else { throw BrowserConnectorRequestError.invalidInput }
        return authorizedRequest(profile: profile, tokens: tokens, action: .gmailReadMessage, url: url)
    }

    nonisolated static func gmailCreateDraft(
        profile: BrowserConnectorProfile,
        tokens: BrowserConnectorOAuthTokens,
        proposal: BrowserConnectorMutationProposal,
        now: Date = Date()
    ) throws -> BrowserConnectorAuthorizedRequest {
        try validateApproved(proposal, profile: profile, action: .gmailCreateDraft, now: now)
        try validate(profile: profile, tokens: tokens, action: .gmailCreateDraft, now: now, permitsApprovedMutation: true)
        guard case .gmailDraft(let content) = proposal.payload,
              !content.to.isEmpty,
              !content.subject.isEmpty,
              !content.body.isEmpty else {
            throw BrowserConnectorRequestError.invalidInput
        }
        let rawMessage = [
            "To: \(content.to.joined(separator: ", "))",
            content.cc.isEmpty ? nil : "Cc: \(content.cc.joined(separator: ", "))",
            content.bcc.isEmpty ? nil : "Bcc: \(content.bcc.joined(separator: ", "))",
            "Subject: \(content.subject)",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "",
            content.body
        ]
        .compactMap { $0 }
        .joined(separator: "\r\n")
        let body = try JSONSerialization.data(
            withJSONObject: ["message": ["raw": Data(rawMessage.utf8).browserBase64URLEncodedString]],
            options: [.sortedKeys]
        )
        return authorizedRequest(
            profile: profile,
            tokens: tokens,
            action: .gmailCreateDraft,
            url: gmailRoot.appendingPathComponent("drafts"),
            method: "POST",
            body: body
        )
    }

    nonisolated static func calendarEvents(
        profile: BrowserConnectorProfile,
        tokens: BrowserConnectorOAuthTokens,
        calendarID: String = "primary",
        from start: Date,
        to end: Date,
        maximumResults: Int = 20,
        now: Date = Date()
    ) throws -> BrowserConnectorAuthorizedRequest {
        try validate(profile: profile, tokens: tokens, action: .calendarListEvents, now: now)
        guard end >= start, end.timeIntervalSince(start) <= 366 * 24 * 60 * 60 else {
            throw BrowserConnectorRequestError.invalidInput
        }
        let calendarURL = try appendingPathComponent(
            calendarID,
            to: calendarRoot.appendingPathComponent("calendars")
        )
        var components = URLComponents(
            url: calendarURL.appendingPathComponent("events"),
            resolvingAgainstBaseURL: false
        )!
        let formatter = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: String(min(max(1, maximumResults), BrowserConnectorPolicy.maximumResults)))
        ]
        guard let url = components.url else { throw BrowserConnectorRequestError.invalidInput }
        return authorizedRequest(profile: profile, tokens: tokens, action: .calendarListEvents, url: url)
    }

    nonisolated static func calendarCreateProposedEvent(
        profile: BrowserConnectorProfile,
        tokens: BrowserConnectorOAuthTokens,
        proposal: BrowserConnectorMutationProposal,
        now: Date = Date()
    ) throws -> BrowserConnectorAuthorizedRequest {
        try validateApproved(proposal, profile: profile, action: .calendarProposeEvent, now: now)
        try validate(profile: profile, tokens: tokens, action: .calendarProposeEvent, now: now, permitsApprovedMutation: true)
        guard case .calendarEvent(let content) = proposal.payload,
              !content.calendarID.isEmpty,
              !content.title.isEmpty,
              TimeZone(identifier: content.timeZoneIdentifier) != nil,
              content.end > content.start else {
            throw BrowserConnectorRequestError.invalidInput
        }
        let calendarURL = try appendingPathComponent(
            content.calendarID,
            to: calendarRoot.appendingPathComponent("calendars")
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var object: [String: Any] = [
            "summary": content.title,
            "start": [
                "dateTime": formatter.string(from: content.start),
                "timeZone": content.timeZoneIdentifier
            ],
            "end": [
                "dateTime": formatter.string(from: content.end),
                "timeZone": content.timeZoneIdentifier
            ]
        ]
        if let location = content.location { object["location"] = location }
        if let notes = content.notes { object["description"] = notes }
        let body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let url = calendarURL.appendingPathComponent("events")
        return authorizedRequest(
            profile: profile,
            tokens: tokens,
            action: .calendarProposeEvent,
            url: url,
            method: "POST",
            body: body
        )
    }

    private nonisolated static func validate(
        profile: BrowserConnectorProfile,
        tokens: BrowserConnectorOAuthTokens,
        action: BrowserConnectorAction,
        now: Date,
        permitsApprovedMutation: Bool = false
    ) throws {
        switch profile.decision(for: action) {
        case .allowed:
            break
        case .approvalRequired where permitsApprovedMutation:
            break
        case .approvalRequired:
            throw BrowserConnectorRequestError.approvalRequired
        case .configurationRequired:
            throw BrowserConnectorRequestError.configurationRequired
        case .disconnected:
            throw BrowserConnectorRequestError.disconnected
        case .wrongConnector:
            throw BrowserConnectorRequestError.wrongConnector
        case .missingScopes:
            throw BrowserConnectorRequestError.missingScope
        }
        guard !tokens.isExpired(at: now) else { throw BrowserConnectorRequestError.expiredCredentials }
        guard action.requiredScopes.isSubset(of: tokens.grantedScopes) else {
            throw BrowserConnectorRequestError.missingScope
        }
    }

    private nonisolated static func validateApproved(
        _ proposal: BrowserConnectorMutationProposal,
        profile: BrowserConnectorProfile,
        action: BrowserConnectorAction,
        now: Date
    ) throws {
        guard proposal.status == .executing, proposal.approvalReceiptID?.isEmpty == false else {
            throw BrowserConnectorRequestError.approvalRequired
        }
        guard now <= proposal.expiresAt else { throw BrowserConnectorRequestError.expiredProposal }
        guard proposal.profileID == profile.id,
              proposal.action == action,
              proposal.action == proposal.payload.action,
              proposal.payloadCommitment == BrowserResearchCommitment.sha256([
                profile.id,
                proposal.action.rawValue,
                proposal.payload.commitment
              ]) else {
            throw BrowserConnectorRequestError.proposalMismatch
        }
    }

    private nonisolated static func authorizedRequest(
        profile: BrowserConnectorProfile,
        tokens: BrowserConnectorOAuthTokens,
        action: BrowserConnectorAction,
        url: URL,
        method: String = "GET",
        body: Data? = nil
    ) -> BrowserConnectorAuthorizedRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = body
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return BrowserConnectorAuthorizedRequest(profileID: profile.id, action: action, request: request)
    }

    private nonisolated static func appendingPathComponent(
        _ rawValue: String,
        to baseURL: URL
    ) throws -> URL {
        let bounded = BrowserConnectorPolicy.boundedText(
            rawValue,
            limit: BrowserConnectorPolicy.maximumIdentifierCharacters
        )
        guard !bounded.isEmpty else { throw BrowserConnectorRequestError.invalidInput }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = bounded.addingPercentEncoding(withAllowedCharacters: allowed),
              !encoded.isEmpty,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BrowserConnectorRequestError.invalidInput
        }
        let separator = components.percentEncodedPath.hasSuffix("/") ? "" : "/"
        components.percentEncodedPath += separator + encoded
        guard let url = components.url else { throw BrowserConnectorRequestError.invalidInput }
        return url
    }
}

/// URLSession and credential-store injection keep connector networking testable.
/// Callers receive bounded JSON bytes; typed Gmail/Calendar presentation models
/// can decode only the fields their UI has explicitly requested.
@MainActor
final class BrowserGoogleConnectorClient {
    private let session: URLSession
    private let credentialStore: BrowserConnectorCredentialStoring
    private let oauthConfiguration: BrowserGoogleOAuthConfiguration
    private var refreshTasks: [String: Task<BrowserConnectorOAuthTokens, Error>] = [:]
    private var consumedMutationExpirations: [UUID: Date] = [:]

    init(
        session: URLSession = .shared,
        credentialStore: BrowserConnectorCredentialStoring = KeychainBrowserConnectorCredentialStore(),
        oauthConfiguration: BrowserGoogleOAuthConfiguration = BrowserGoogleOAuthConfiguration(
            clientID: "",
            redirectURI: nil
        )
    ) {
        self.session = session
        self.credentialStore = credentialStore
        self.oauthConfiguration = oauthConfiguration
    }

    func gmailSearch(
        profile: BrowserConnectorProfile,
        query: String,
        maximumResults: Int = 20,
        now: Date = Date()
    ) async throws -> Data {
        try await executeRead(profile: profile, now: now) { tokens in
            try BrowserGoogleRESTRequestBuilder.gmailSearch(
                profile: profile,
                tokens: tokens,
                query: query,
                maximumResults: maximumResults,
                now: now
            )
        }
    }

    func gmailMessage(
        profile: BrowserConnectorProfile,
        messageID: String,
        now: Date = Date()
    ) async throws -> Data {
        try await executeRead(profile: profile, now: now) { tokens in
            try BrowserGoogleRESTRequestBuilder.gmailMessage(
                profile: profile,
                tokens: tokens,
                messageID: messageID,
                now: now
            )
        }
    }

    func createGmailDraft(
        profile: BrowserConnectorProfile,
        proposal: BrowserConnectorMutationProposal,
        now: Date = Date()
    ) async throws -> Data {
        try consumeMutation(proposal, now: now)
        let tokens = try await usableTokens(for: profile, now: now)
        // Mutations are deliberately executed exactly once. In particular, a
        // 401 or transport error after this point is never replayed because the
        // provider may already have committed the draft/event.
        return try await execute(
            BrowserGoogleRESTRequestBuilder.gmailCreateDraft(
                profile: profile,
                tokens: tokens,
                proposal: proposal,
                now: now
            )
        )
    }

    func calendarEvents(
        profile: BrowserConnectorProfile,
        calendarID: String = "primary",
        from start: Date,
        to end: Date,
        maximumResults: Int = 20,
        now: Date = Date()
    ) async throws -> Data {
        try await executeRead(profile: profile, now: now) { tokens in
            try BrowserGoogleRESTRequestBuilder.calendarEvents(
                profile: profile,
                tokens: tokens,
                calendarID: calendarID,
                from: start,
                to: end,
                maximumResults: maximumResults,
                now: now
            )
        }
    }

    func createCalendarEvent(
        profile: BrowserConnectorProfile,
        proposal: BrowserConnectorMutationProposal,
        now: Date = Date()
    ) async throws -> Data {
        try consumeMutation(proposal, now: now)
        let tokens = try await usableTokens(for: profile, now: now)
        // Approval has already been consumed into `.executing`; never retry a
        // mutating request when its outcome could be ambiguous.
        return try await execute(
            BrowserGoogleRESTRequestBuilder.calendarCreateProposedEvent(
                profile: profile,
                tokens: tokens,
                proposal: proposal,
                now: now
            )
        )
    }

    func revokeLocalCredentials(for profile: BrowserConnectorProfile) throws {
        try credentialStore.deleteTokens(for: profile)
    }

    private func requiredTokens(for profile: BrowserConnectorProfile) throws -> BrowserConnectorOAuthTokens {
        guard let tokens = try credentialStore.loadTokens(for: profile) else {
            throw BrowserConnectorRequestError.disconnected
        }
        return tokens
    }

    private func consumeMutation(
        _ proposal: BrowserConnectorMutationProposal,
        now: Date
    ) throws {
        consumedMutationExpirations = consumedMutationExpirations.filter { _, expiration in
            expiration >= now
        }
        guard proposal.status == .executing,
              proposal.approvalReceiptID?.isEmpty == false,
              now <= proposal.expiresAt else {
            throw BrowserConnectorRequestError.invalidProposalState
        }
        guard consumedMutationExpirations[proposal.id] == nil else {
            throw BrowserConnectorRequestError.invalidProposalState
        }
        consumedMutationExpirations[proposal.id] = proposal.expiresAt
    }

    private func usableTokens(
        for profile: BrowserConnectorProfile,
        now: Date
    ) async throws -> BrowserConnectorOAuthTokens {
        let tokens = try requiredTokens(for: profile)
        guard tokens.isExpired(at: now) else { return tokens }
        guard tokens.hasRefreshToken else {
            throw BrowserConnectorRequestError.expiredCredentials
        }
        return try await refreshTokens(for: profile, replacing: tokens, now: now)
    }

    /// Read-only operations may make one bounded retry after a 401. No other
    /// response or transport failure is retried.
    private func executeRead(
        profile: BrowserConnectorProfile,
        now: Date,
        makeRequest: (BrowserConnectorOAuthTokens) throws -> BrowserConnectorAuthorizedRequest
    ) async throws -> Data {
        let tokens = try await usableTokens(for: profile, now: now)
        do {
            return try await execute(try makeRequest(tokens))
        } catch BrowserConnectorRequestError.invalidHTTPStatus(401) {
            let refreshed = try await tokensAfterUnauthorized(
                for: profile,
                rejectedTokens: tokens,
                now: now
            )
            return try await execute(try makeRequest(refreshed))
        }
    }

    private func tokensAfterUnauthorized(
        for profile: BrowserConnectorProfile,
        rejectedTokens: BrowserConnectorOAuthTokens,
        now: Date
    ) async throws -> BrowserConnectorOAuthTokens {
        let current = try requiredTokens(for: profile)
        if current.accessToken != rejectedTokens.accessToken {
            if current.isExpired(at: now) {
                guard current.hasRefreshToken else {
                    throw BrowserConnectorRequestError.expiredCredentials
                }
                return try await refreshTokens(for: profile, replacing: current, now: now)
            }
            return current
        }
        guard current.hasRefreshToken else {
            throw BrowserConnectorRequestError.expiredCredentials
        }
        return try await refreshTokens(for: profile, replacing: current, now: now)
    }

    /// Coalesces refreshes per connector profile. The rotated access token and
    /// provider-returned refresh token (or the prior refresh token when omitted)
    /// are saved back to Keychain before any waiter receives them.
    private func refreshTokens(
        for profile: BrowserConnectorProfile,
        replacing priorTokens: BrowserConnectorOAuthTokens,
        now: Date
    ) async throws -> BrowserConnectorOAuthTokens {
        if let task = refreshTasks[profile.id] {
            return try await task.value
        }

        let task = Task { @MainActor [session, credentialStore, oauthConfiguration] in
            let request = try BrowserGoogleOAuthRequestBuilder.tokenRefreshRequest(
                tokens: priorTokens,
                configuration: oauthConfiguration
            )
            let (data, response) = try await Self.boundedResponse(
                session: session,
                request: request,
                maximumBytes: 256_000
            )
            guard (200..<300).contains(response.statusCode) else {
                throw BrowserConnectorRequestError.invalidHTTPStatus(response.statusCode)
            }
            let refreshed = try BrowserGoogleOAuthRequestBuilder.parseTokenResponse(
                data,
                kind: profile.kind,
                requestedScopes: priorTokens.grantedScopes,
                now: now,
                priorRefreshToken: priorTokens.refreshToken
            )
            try credentialStore.saveTokens(refreshed, for: profile)
            return refreshed
        }
        refreshTasks[profile.id] = task
        do {
            let refreshed = try await task.value
            refreshTasks[profile.id] = nil
            return refreshed
        } catch {
            refreshTasks[profile.id] = nil
            throw error
        }
    }

    private func execute(_ authorized: BrowserConnectorAuthorizedRequest) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: authorized.request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw BrowserConnectorRequestError.invalidHTTPStatus(
                (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
        var data = Data()
        data.reserveCapacity(min(BrowserConnectorPolicy.maximumResponseBytes, 64 * 1_024))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < BrowserConnectorPolicy.maximumResponseBytes else {
                throw BrowserConnectorRequestError.responseTooLarge
            }
            data.append(byte)
        }
        return data
    }

    private static func boundedResponse(
        session: URLSession,
        request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BrowserOAuthContractError.invalidTokenResponse
        }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, 32 * 1_024))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else {
                throw BrowserConnectorRequestError.responseTooLarge
            }
            data.append(byte)
        }
        return (data, http)
    }
}

private extension Data {
    nonisolated var browserBase64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    nonisolated var browserFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
