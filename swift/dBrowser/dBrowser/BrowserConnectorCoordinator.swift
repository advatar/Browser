import Combine
import Foundation

@MainActor
final class BrowserConnectorCoordinator: ObservableObject {
    @Published private(set) var profiles: [BrowserConnectorProfile]
    @Published private(set) var gmailMessages: [BrowserGmailMessageSummary] = []
    @Published private(set) var calendarEvents: [BrowserCalendarEventSummary] = []
    @Published private(set) var mutationProposals: [BrowserConnectorMutationProposal] = []
    @Published private(set) var statusMessage: String
    @Published private(set) var isWorking = false

    let oauthConfiguration: BrowserGoogleOAuthConfiguration

    private let oauthContract: BrowserGoogleOAuthContract
    private let authorizationRegistry: BrowserOAuthAuthorizationRegistry
    private let credentialStore: any BrowserConnectorCredentialStoring
    private let connectorClient: BrowserGoogleConnectorClient
    private let session: URLSession
    private let defaults: UserDefaults
    private let defaultsKey: String
    private var pendingOAuthCallbackURLs: [URL] = []

    init(
        oauthConfiguration: BrowserGoogleOAuthConfiguration? = nil,
        credentialStore: (any BrowserConnectorCredentialStoring)? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        defaultsKey: String = "dBrowser.connector-profiles.v1"
    ) {
        let environment = ProcessInfo.processInfo.environment
        let resolvedConfiguration = oauthConfiguration ?? BrowserGoogleOAuthConfiguration(
            clientID: environment["DBROWSER_GOOGLE_OAUTH_CLIENT_ID"] ?? "",
            redirectURI: URL(string: "dbrowser://oauth/google")
        )
        let resolvedCredentialStore = credentialStore ?? KeychainBrowserConnectorCredentialStore()
        self.oauthConfiguration = resolvedConfiguration
        self.oauthContract = BrowserGoogleOAuthContract()
        self.authorizationRegistry = BrowserOAuthAuthorizationRegistry()
        self.credentialStore = resolvedCredentialStore
        self.connectorClient = BrowserGoogleConnectorClient(
            session: session,
            credentialStore: resolvedCredentialStore,
            oauthConfiguration: resolvedConfiguration
        )
        self.session = session
        self.defaults = defaults
        self.defaultsKey = defaultsKey

        let storedData = defaults.data(forKey: defaultsKey)
        let persistedState = storedData.flatMap {
            try? JSONDecoder().decode(BrowserConnectorPersistencePayload.self, from: $0)
        }
        // Migrate the original profiles-only array in place so existing
        // connector setup survives adoption of the durable proposal ledger.
        let legacyProfiles: [BrowserConnectorProfile]? = persistedState == nil
            ? storedData.flatMap { try? JSONDecoder().decode([BrowserConnectorProfile].self, from: $0) }
            : nil
        let decodedProfiles = persistedState?.profiles ?? legacyProfiles ?? []
        self.profiles = BrowserConnectorKind.allCases.map { kind in
            if let stored = decodedProfiles.first(where: { $0.kind == kind }) {
                return stored
            }
            return BrowserConnectorProfile(
                kind: kind,
                connectionState: resolvedConfiguration.isConfigured
                    ? .disconnected
                    : .configurationRequired
            )
        }
        self.mutationProposals = BrowserConnectorPersistencePayload.boundedMutationProposals(
            (persistedState?.mutationProposals ?? []).map {
                $0.reconcilingAfterRelaunch()
            }
        )
        self.statusMessage = resolvedConfiguration.isConfigured
            ? "Connectors are disconnected until you authorize exact Google scopes."
            : "Set DBROWSER_GOOGLE_OAUTH_CLIENT_ID to enable Google authorization."
        if persistedState != nil || legacyProfiles != nil {
            persistState()
        }
    }

    func profile(for kind: BrowserConnectorKind) -> BrowserConnectorProfile? {
        profiles.first { $0.kind == kind }
    }

    func beginAuthorization(for kind: BrowserConnectorKind) throws -> URL {
        guard let index = profiles.firstIndex(where: { $0.kind == kind }) else {
            throw BrowserOAuthContractError.configurationRequired
        }
        let scopes: Set<BrowserConnectorScope> = kind == .gmail
            ? [.gmailRead, .gmailDraft]
            : [.calendarRead, .calendarEvents]
        let request = try oauthContract.makeAuthorizationRequest(
            profile: profiles[index],
            scopes: scopes,
            configuration: oauthConfiguration
        )
        authorizationRegistry.register(request.pending)
        profiles[index].connectionState = .authorizing
        profiles[index].lastError = nil
        profiles[index].updatedAt = Date()
        statusMessage = "Complete Google authorization in the system browser."
        persistState()
        return request.authorizationURL
    }

    func handleOAuthCallback(_ callbackURL: URL) async {
        guard oauthConfiguration.matchesCallbackURL(callbackURL) else { return }
        if isWorking {
            if !pendingOAuthCallbackURLs.contains(callbackURL), pendingOAuthCallbackURLs.count < 4 {
                pendingOAuthCallbackURLs.append(callbackURL)
            }
            statusMessage = "Google authorization callback received and queued behind the current connector operation."
            return
        }
        await processOAuthCallback(callbackURL)
    }

    private func processOAuthCallback(_ callbackURL: URL) async {
        isWorking = true
        defer { finishWorkingAndScheduleOAuthDrain() }
        do {
            let callback = try authorizationRegistry.consumeCallback(callbackURL)
            guard let index = profiles.firstIndex(where: { $0.id == callback.pending.profileID }) else {
                throw BrowserOAuthContractError.unknownOrReplayedState
            }
            let request = try BrowserGoogleOAuthRequestBuilder.tokenExchangeRequest(
                callback: callback,
                configuration: oauthConfiguration
            )
            let (data, http) = try await boundedResponse(
                for: request,
                maximumBytes: 256_000
            )
            guard (200..<300).contains(http.statusCode) else {
                throw BrowserOAuthContractError.invalidTokenResponse
            }
            let tokens = try BrowserGoogleOAuthRequestBuilder.parseTokenResponse(
                data,
                kind: callback.pending.connectorKind,
                requestedScopes: callback.pending.requestedScopes
            )
            try credentialStore.saveTokens(tokens, for: profiles[index])
            profiles[index].authorizedScopes = tokens.grantedScopes
            profiles[index].connectionState = .connected
            profiles[index].lastError = nil
            profiles[index].updatedAt = Date()
            statusMessage = "Connected \(profiles[index].displayName); tokens are stored only in Keychain."
            persistState()
        } catch {
            for index in profiles.indices where profiles[index].connectionState == .authorizing {
                profiles[index].connectionState = .failed
                profiles[index].lastError = BrowserConnectorPolicy.boundedText(
                    error.localizedDescription,
                    limit: BrowserConnectorPolicy.maximumErrorCharacters
                )
                profiles[index].updatedAt = Date()
            }
            statusMessage = error.localizedDescription
            persistState()
        }
    }

    func disconnect(_ kind: BrowserConnectorKind) {
        guard let index = profiles.firstIndex(where: { $0.kind == kind }) else { return }
        do {
            try connectorClient.revokeLocalCredentials(for: profiles[index])
            profiles[index].authorizedScopes = []
            profiles[index].connectionState = oauthConfiguration.isConfigured
                ? .disconnected
                : .configurationRequired
            profiles[index].lastError = nil
            profiles[index].updatedAt = Date()
            statusMessage = "Disconnected \(profiles[index].displayName) and removed local Keychain tokens."
        } catch {
            profiles[index].connectionState = .failed
            profiles[index].lastError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
        persistState()
    }

    func searchGmail(_ query: String) async {
        guard !isWorking, let profile = profile(for: .gmail) else { return }
        isWorking = true
        defer { finishWorkingAndScheduleOAuthDrain() }
        do {
            let data = try await connectorClient.gmailSearch(profile: profile, query: query, maximumResults: 12)
            gmailMessages = try await decodeGmailSearch(data, profile: profile)
            statusMessage = "Loaded \(gmailMessages.count) bounded Gmail result\(gmailMessages.count == 1 ? "" : "s")."
            markUsed(profile.id)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadCalendar(from start: Date, to end: Date) async {
        guard !isWorking, let profile = profile(for: .googleCalendar) else { return }
        isWorking = true
        defer { finishWorkingAndScheduleOAuthDrain() }
        do {
            let data = try await connectorClient.calendarEvents(
                profile: profile,
                from: start,
                to: end,
                maximumResults: 20
            )
            calendarEvents = try decodeCalendarEvents(data)
            statusMessage = "Loaded \(calendarEvents.count) bounded Calendar event\(calendarEvents.count == 1 ? "" : "s")."
            markUsed(profile.id)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func proposeGmailDraft(_ content: BrowserGmailDraftContent) -> BrowserConnectorMutationProposal? {
        guard let profile = profile(for: .gmail),
              profile.decision(for: .gmailCreateDraft) == .approvalRequired,
              !content.to.isEmpty,
              !content.subject.isEmpty,
              !content.body.isEmpty else {
            return nil
        }
        let proposal = BrowserConnectorMutationProposal(profile: profile, payload: .gmailDraft(content))
        mutationProposals.insert(proposal, at: 0)
        mutationProposals = BrowserConnectorPersistencePayload.boundedMutationProposals(mutationProposals)
        persistState()
        statusMessage = "Review the exact Gmail draft and approve it once before creation."
        return proposal
    }

    @discardableResult
    func proposeCalendarEvent(
        _ content: BrowserCalendarEventProposalContent
    ) -> BrowserConnectorMutationProposal? {
        guard let profile = profile(for: .googleCalendar),
              profile.decision(for: .calendarProposeEvent) == .approvalRequired,
              !content.calendarID.isEmpty,
              !content.title.isEmpty,
              TimeZone(identifier: content.timeZoneIdentifier) != nil,
              content.end > content.start else {
            return nil
        }
        let proposal = BrowserConnectorMutationProposal(profile: profile, payload: .calendarEvent(content))
        mutationProposals.insert(proposal, at: 0)
        mutationProposals = BrowserConnectorPersistencePayload.boundedMutationProposals(mutationProposals)
        persistState()
        statusMessage = "Review the exact Calendar event and approve it once before creation."
        return proposal
    }

    func denyMutation(_ id: UUID) {
        guard !isWorking,
              let index = mutationProposals.firstIndex(where: { $0.id == id }) else { return }
        do {
            if Date() > mutationProposals[index].expiresAt {
                mutationProposals[index] = try mutationProposals[index].expiring()
                persistState()
                statusMessage = "Connector mutation expired; no request was sent."
            } else {
                mutationProposals[index] = try mutationProposals[index].denying()
                persistState()
                statusMessage = "Connector mutation denied; no request was sent."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func approveAndExecuteMutation(_ id: UUID) async {
        guard !isWorking,
              let index = mutationProposals.firstIndex(where: { $0.id == id }),
              let profile = profiles.first(where: { $0.id == mutationProposals[index].profileID }) else {
            return
        }

        let executing: BrowserConnectorMutationProposal
        do {
            let approved = try mutationProposals[index].approving(
                receiptID: "user-approval:\(UUID().uuidString)"
            )
            mutationProposals[index] = approved
            guard persistState() else {
                statusMessage = "Could not durably record connector approval; no request was sent."
                return
            }
            executing = try approved.beginningExecution()
            // Publish `.executing` before entering connector networking. This is
            // the one-shot consumption point; the same proposal can never be
            // approved or executed again.
            mutationProposals[index] = executing
            // This durable write is the one-shot consumption boundary and must
            // complete before connector networking can begin.
            guard persistState() else {
                mutationProposals[index] = (try? executing.failingAmbiguously()) ?? executing
                _ = persistState()
                statusMessage = "Could not durably consume connector approval; no request was sent."
                return
            }
        } catch BrowserConnectorRequestError.expiredProposal {
            mutationProposals[index] = (try? mutationProposals[index].expiring())
                ?? mutationProposals[index]
            persistState()
            statusMessage = BrowserConnectorRequestError.expiredProposal.localizedDescription
            return
        } catch {
            statusMessage = error.localizedDescription
            return
        }

        isWorking = true
        defer { finishWorkingAndScheduleOAuthDrain() }
        do {
            switch executing.payload {
            case .gmailDraft:
                _ = try await connectorClient.createGmailDraft(profile: profile, proposal: executing)
                statusMessage = "Created the approved Gmail draft. It was not sent."
            case .calendarEvent:
                _ = try await connectorClient.createCalendarEvent(profile: profile, proposal: executing)
                statusMessage = "Created the approved Calendar event."
            }
            if let currentIndex = mutationProposals.firstIndex(where: { $0.id == id }) {
                mutationProposals[currentIndex] = try mutationProposals[currentIndex].completing()
                persistState()
            }
            markUsed(profile.id)
        } catch {
            if let currentIndex = mutationProposals.firstIndex(where: { $0.id == id }),
               mutationProposals[currentIndex].status == .executing {
                mutationProposals[currentIndex] = (try? mutationProposals[currentIndex].failingAmbiguously())
                    ?? mutationProposals[currentIndex]
                persistState()
            }
            statusMessage = "The one-shot mutation failed or could not be confirmed and was not retried: \(error.localizedDescription)"
        }
    }

    private func finishWorkingAndScheduleOAuthDrain() {
        isWorking = false
        guard !pendingOAuthCallbackURLs.isEmpty else { return }
        let callbackURL = pendingOAuthCallbackURLs.removeFirst()
        Task { @MainActor [weak self] in
            await self?.handleOAuthCallback(callbackURL)
        }
    }

    private func decodeGmailSearch(
        _ data: Data,
        profile: BrowserConnectorProfile
    ) async throws -> [BrowserGmailMessageSummary] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = object["messages"] as? [[String: Any]] else {
            return []
        }
        var summaries: [BrowserGmailMessageSummary] = []
        for item in messages.prefix(12) {
            guard let id = item["id"] as? String else { continue }
            let detail = try await connectorClient.gmailMessage(profile: profile, messageID: id)
            if let summary = try decodeGmailMessage(detail) {
                summaries.append(summary)
            }
        }
        return summaries
    }

    private func decodeGmailMessage(_ data: Data) throws -> BrowserGmailMessageSummary? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else { return nil }
        let payload = object["payload"] as? [String: Any]
        let headers = payload?["headers"] as? [[String: Any]] ?? []
        func header(_ name: String) -> String {
            headers.first {
                ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame
            }?["value"] as? String ?? ""
        }
        let receivedAt = (object["internalDate"] as? String)
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0 / 1_000) }
        return BrowserGmailMessageSummary(
            id: id,
            threadID: object["threadId"] as? String,
            sender: header("From"),
            subject: header("Subject"),
            snippet: object["snippet"] as? String ?? "",
            receivedAt: receivedAt
        )
    }

    private func decodeCalendarEvents(_ data: Data) throws -> [BrowserCalendarEventSummary] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { return [] }
        let formatter = ISO8601DateFormatter()
        return items.prefix(20).compactMap { item in
            guard let id = item["id"] as? String,
                  let startObject = item["start"] as? [String: Any],
                  let endObject = item["end"] as? [String: Any],
                  let startValue = (startObject["dateTime"] ?? startObject["date"]) as? String,
                  let endValue = (endObject["dateTime"] ?? endObject["date"]) as? String,
                  let start = formatter.date(from: startValue) ?? Self.dayDate(startValue),
                  let end = formatter.date(from: endValue) ?? Self.dayDate(endValue) else {
                return nil
            }
            return BrowserCalendarEventSummary(
                id: id,
                title: item["summary"] as? String ?? "Untitled event",
                start: start,
                end: end,
                location: item["location"] as? String
            )
        }
    }

    private static func dayDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func markUsed(_ profileID: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].lastUsedAt = Date()
        profiles[index].updatedAt = Date()
        persistState()
    }

    private func boundedResponse(
        for request: URLRequest,
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
                throw BrowserOAuthContractError.invalidTokenResponse
            }
            data.append(byte)
        }
        return (data, http)
    }

    @discardableResult
    private func persistState() -> Bool {
        let payload = BrowserConnectorPersistencePayload(
            profiles: profiles,
            mutationProposals: mutationProposals
        )
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        defaults.set(data, forKey: defaultsKey)
        return true
    }
}
