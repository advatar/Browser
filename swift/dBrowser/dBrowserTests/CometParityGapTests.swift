import Foundation
import Testing
@testable import dBrowser

@MainActor
private final class StubBrowserSearchService: BrowserSearchServicing {
    var response: BrowserSearchResponse

    init(response: BrowserSearchResponse) {
        self.response = response
    }

    func search(_ request: BrowserSearchRequest) async throws -> BrowserSearchResponse {
        response
    }
}

@MainActor
private final class StubVoiceInputService: BrowserVoiceInputServicing {
    var authorizationStatus: BrowserVoiceAuthorizationStatus = .notDetermined
    var handler: BrowserVoiceRecognitionHandler?
    var authorizationRequests = 0
    var starts = 0
    var stops = 0
    var cancels = 0

    func capability(for configuration: BrowserVoiceRecognitionConfiguration) -> BrowserVoiceInputCapability {
        BrowserVoiceInputCapability(isAvailable: true, reason: "Available")
    }

    func requestAuthorization() async -> BrowserVoiceAuthorizationStatus {
        authorizationRequests += 1
        authorizationStatus = .authorized
        return .authorized
    }

    func startRecognition(
        configuration: BrowserVoiceRecognitionConfiguration,
        onUpdate: @escaping BrowserVoiceRecognitionHandler
    ) throws {
        starts += 1
        handler = onUpdate
    }

    func stopRecognition() { stops += 1 }
    func cancelRecognition() { cancels += 1 }
}

@MainActor
private final class FixedOAuthEntropy: BrowserOAuthEntropyGenerating {
    private var value = 0

    func randomBase64URL(byteCount: Int) throws -> String {
        value += 1
        return String(repeating: value == 1 ? "a" : "b", count: 64)
    }
}

@MainActor
private final class ConnectorLedgerCredentialStore: BrowserConnectorCredentialStoring {
    private var tokensByProfileID: [String: BrowserConnectorOAuthTokens] = [:]

    func setTokens(_ tokens: BrowserConnectorOAuthTokens, for profile: BrowserConnectorProfile) {
        tokensByProfileID[profile.id] = tokens
    }

    func loadTokens(for profile: BrowserConnectorProfile) throws -> BrowserConnectorOAuthTokens? {
        tokensByProfileID[profile.id]
    }

    func saveTokens(_ tokens: BrowserConnectorOAuthTokens, for profile: BrowserConnectorProfile) throws {
        tokensByProfileID[profile.id] = tokens
    }

    func deleteTokens(for profile: BrowserConnectorProfile) throws {
        tokensByProfileID[profile.id] = nil
    }
}

private final class ConnectorLedgerNetworkCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var requestCountStorage = 0
    private var persistedPayloadDataStorage: [Data] = []

    func record(defaults: UserDefaults, key: String) {
        let data = defaults.data(forKey: key)
        lock.lock()
        requestCountStorage += 1
        if let data {
            persistedPayloadDataStorage.append(data)
        }
        lock.unlock()
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCountStorage
    }

    var persistedPayloadData: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return persistedPayloadDataStorage
    }
}

private final class ConnectorLedgerMockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requestHandler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let lock = NSLock()

    nonisolated static func register(
        _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        requestHandler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.requestHandler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct UnboundedConnectorPersistenceEnvelope: Encodable {
    let schemaVersion: Int
    let profiles: [BrowserConnectorProfile]
    let mutationProposals: [BrowserConnectorMutationProposal]
}

@Suite("Comet parity gap closure")
@MainActor
struct CometParityGapTests {
    @Test func legacyConversationPayloadMigratesToPersistentArchive() throws {
        let legacyConversation = LLMConversation(
            id: UUID(),
            title: "Legacy",
            messages: [LLMConversationMessage(role: .user, text: "Keep this")]
        )
        let legacyObject: [String: Any] = [
            "conversation": try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyConversation)),
            "selectedModelID": LLMModelRegistry.localGemmaID
        ]
        let payload = try JSONDecoder().decode(
            LLMConversationStorePayload.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )

        #expect(payload.conversations.count == 1)
        #expect(payload.conversation.id == legacyConversation.id)
        #expect(payload.conversation.messages.first?.text == "Keep this")

        var archive = payload
        let second = LLMConversation(title: "Second")
        archive.upsertConversation(second, select: true)
        #expect(archive.conversations.count == 2)
        #expect(archive.selectedConversationID == second.id)
        let removedSecondConversation = archive.removeConversation(second.id)
        #expect(removedSecondConversation)
        #expect(archive.conversation.id == legacyConversation.id)
    }

    @Test func relaunchReconcilesToolProposalsAcrossConversationArchive() throws {
        let tabID = UUID()
        let pageURL = "https://example.com/relaunch"
        let pendingProposal = try CopilotToolProposalFactory.make(
            toolCall: LLMRouterToolCall(
                id: "pending-before-relaunch",
                name: "browser.query",
                arguments: ["selector": "main"],
                approvalRequired: true
            ),
            sourceRunID: UUID(),
            targetTabID: tabID,
            targetURLString: pageURL,
            navigationGeneration: 1
        )
        var executingProposal = try CopilotToolProposalFactory.make(
            toolCall: LLMRouterToolCall(
                id: "executing-before-relaunch",
                name: "browser.click",
                arguments: ["selector": "button"],
                approvalRequired: true
            ),
            sourceRunID: UUID(),
            targetTabID: tabID,
            targetURLString: pageURL,
            navigationGeneration: 1
        )
        executingProposal.status = .executing
        executingProposal.statusMessage = "Approved and executing before termination."

        let selectedConversation = LLMConversation(
            title: "Pending conversation",
            toolProposals: [pendingProposal]
        )
        let archivedConversation = LLMConversation(
            title: "Executing conversation",
            toolProposals: [executingProposal]
        )
        let store = LLMConversationStore.ephemeral(
            seed: LLMConversationStorePayload(
                conversations: [selectedConversation, archivedConversation],
                selectedConversationID: selectedConversation.id,
                selectedModelID: selectedConversation.activeModelID
            )
        )

        let model = makeViewModel(llmConversationStore: store)
        let restoredPending = try #require(
            model.copilotToolProposals.first { $0.id == pendingProposal.id }
        )
        #expect(restoredPending.status == .expired)
        #expect(restoredPending.statusMessage.contains("Nothing executed"))
        #expect(
            model.llmConversation.events.contains {
                $0.kind == .toolDenied && $0.relatedToolProposalID == pendingProposal.id
            }
        )

        let restoredArchived = try #require(
            model.llmConversations.first { $0.id == archivedConversation.id }
        )
        let restoredExecuting = try #require(
            restoredArchived.toolProposals.first { $0.id == executingProposal.id }
        )
        #expect(restoredExecuting.status == .consumed)
        #expect(restoredExecuting.statusMessage.contains("outcome is unconfirmed"))
        #expect(restoredExecuting.statusMessage.contains("will not be retried"))
        #expect(
            restoredArchived.events.contains {
                $0.kind == .toolExecuted && $0.relatedToolProposalID == executingProposal.id
            }
        )

        #expect(model.selectLLMConversation(archivedConversation.id))
        #expect(model.copilotToolProposals.first?.status == .consumed)
        #expect(model.approveToolProposal(executingProposal.id) == nil)
    }

    @Test func boundedFileAttachmentDropsPathAndRecomputesCommitment() throws {
        let attachment = LLMTextFileAttachment(
            displayName: "/Users/example/private/report.txt",
            text: String(repeating: "é", count: 30_000)
        )
        #expect(attachment.displayName == "report.txt")
        #expect(attachment.textUTF8ByteCount <= LLMTextFileAttachmentPolicy.textUTF8ByteLimit)
        #expect(attachment.wasTruncated)

        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(attachment)) as? [String: Any]
        )
        object["contentSHA256"] = "tampered"
        let decoded = try JSONDecoder().decode(
            LLMTextFileAttachment.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.contentSHA256 == attachment.contentSHA256)
        #expect(decoded.contentSHA256 != "tampered")
    }

    @Test func pageSnapshotsNormalizeBoundsWithoutMetadataCollisionOverwrite() throws {
        let oversizedElement = DOMElementRecord(
            index: -5,
            tagName: String(repeating: "t", count: 100),
            role: String(repeating: "r", count: 140),
            ariaLabel: String(repeating: "a", count: 200),
            text: String(repeating: "x", count: 200),
            value: String(repeating: "v", count: 140),
            href: "https://example.com/" + String(repeating: "h", count: 2_100),
            inputType: String(repeating: "i", count: 80),
            name: String(repeating: "n", count: 200),
            placeholder: String(repeating: "p", count: 200),
            disabled: false,
            hidden: false
        )
        let metadata = Dictionary(uniqueKeysWithValues: (0..<31).map {
            ("key-\($0)", String(repeating: "m", count: 300))
        })
        let snapshot = PageSnapshot(
            urlString: "https://example.com/" + String(repeating: "u", count: 2_100),
            title: String(repeating: "T", count: 300),
            visibleText: String(repeating: "V", count: 20_100),
            headings: Array(repeating: String(repeating: "H", count: 200), count: 101),
            links: Array(repeating: oversizedElement, count: 101),
            buttons: Array(repeating: oversizedElement, count: 101),
            formControls: Array(repeating: oversizedElement, count: 101),
            metadata: metadata,
            truncated: false,
            redactionCount: -20
        )
        #expect(snapshot.urlString.isEmpty)
        #expect(snapshot.title.count == 240)
        #expect(snapshot.visibleText.count == 20_000)
        #expect(snapshot.headings.count == 100)
        #expect(snapshot.headings.allSatisfy { $0.count == 160 })
        #expect(snapshot.links.count == 100)
        #expect(snapshot.buttons.count == 100)
        #expect(snapshot.formControls.count == 100)
        #expect(snapshot.links.first?.index == 0)
        #expect(snapshot.links.first?.tagName.count == 64)
        #expect(snapshot.links.first?.href?.count == 2_048)
        #expect(snapshot.metadata.count == 30)
        #expect(snapshot.metadata.values.allSatisfy { $0.count == 240 })
        #expect(snapshot.redactionCount == 0)
        #expect(snapshot.truncated)
        #expect(try JSONDecoder().decode(PageSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)

        let sharedPrefix = String(repeating: "k", count: 120)
        let collisionSnapshot = PageSnapshot(
            urlString: "https://example.com/",
            title: "Metadata collision",
            visibleText: "Bounded",
            headings: [],
            links: [],
            buttons: [],
            formControls: [],
            metadata: [
                sharedPrefix: "trusted exact key",
                sharedPrefix + "-attacker-controlled-suffix": "must not overwrite"
            ],
            truncated: false,
            redactionCount: 0
        )
        #expect(collisionSnapshot.metadata.count == 1)
        #expect(collisionSnapshot.metadata[sharedPrefix] == "trusted exact key")
    }

    @Test func provenanceSummaryAndRegenerationLinksRoundTrip() throws {
        let source = LLMConversationMessage(role: .user, text: "Compare sources")
        let model = LLMModelRegistry.models()[0]
        let provenance = LLMMessageProviderProvenance(model: model)
        var conversation = LLMConversation(messages: [source], activeModelID: model.id)
        let protectedEvent = LLMConversationEvent(kind: .toolDenied, message: "Denied")
        conversation.appendEvent(protectedEvent)
        let artifact = LLMContextSummaryArtifact(
            summary: "User asked to compare sources.",
            sourceMessageIDs: [source.id],
            protectedEventIDs: [protectedEvent.id],
            targetModelID: model.id,
            providerProvenance: provenance
        )
        let appendedSummaryArtifact = conversation.appendContextSummaryArtifact(artifact)
        #expect(appendedSummaryArtifact)
        let assistant = LLMConversationMessage(
            role: .assistant,
            text: "Comparison",
            modelID: model.id,
            providerProvenance: provenance,
            sourceMessageID: source.id,
            regeneratedFromMessageID: UUID(),
            contextSummaryArtifactID: artifact.id
        )
        conversation.appendMessage(assistant)

        let decoded = try JSONDecoder().decode(
            LLMConversation.self,
            from: JSONEncoder().encode(conversation)
        )
        #expect(decoded.contextSummaryArtifacts.first?.commitment == artifact.commitment)
        #expect(decoded.latestAssistantMessage?.providerProvenance == provenance)
        #expect(decoded.latestAssistantMessage?.sourceMessageID == source.id)
        #expect(decoded.latestAssistantMessage?.contextSummaryArtifactID == artifact.id)
    }

    @Test func nativeSearchProducesStableSourcesAndRejectsInventedCitations() throws {
        let result = try #require(
            BrowserSearchResult(
                title: "Source",
                urlString: "https://example.com/report?utm_source=test&year=2026#section",
                snippet: "Evidence"
            )
        )
        #expect(result.urlString == "https://example.com/report?year=2026")
        let orderedQueryResult = try #require(
            BrowserSearchResult(
                title: "Ordered query source",
                urlString: "https://example.com/flow?step=2&utm_source=x&step=1",
                snippet: "Repeated query parameters retain provider order."
            )
        )
        #expect(orderedQueryResult.urlString == "https://example.com/flow?step=2&step=1")
        let maximumLengthURL = "https://example.com/" + String(
            repeating: "a",
            count: BrowserResearchSearchPolicy.maximumURLCharacters - "https://example.com/".count
        )
        #expect(maximumLengthURL.count == BrowserResearchSearchPolicy.maximumURLCharacters)
        #expect(
            BrowserSearchResult(
                title: "Maximum length source",
                urlString: maximumLengthURL,
                snippet: "A source exactly at the URL limit remains valid."
            ) != nil
        )
        let overLimitURL = maximumLengthURL + "never-truncate-this-suffix"
        #expect(overLimitURL.count > BrowserResearchSearchPolicy.maximumURLCharacters)
        #expect(BrowserResearchURLPolicy.canonicalURLString(overLimitURL) == nil)
        #expect(
            BrowserSearchResult(
                title: "Over-limit source",
                urlString: overLimitURL,
                snippet: "This source must be rejected instead of prefix-truncated."
            ) == nil
        )
        let request = BrowserResearchSynthesisRequest(
            query: "What happened?",
            sources: [BrowserResearchSource(result: result)]
        )
        let completedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let valid = try BrowserResearchSynthesisValidator.validate(
            BrowserResearchSynthesisEnvelope(
                answer: "It happened.",
                citations: [.init(sourceID: request.sources[0].id, claim: "Supports the answer")]
            ),
            against: request,
            completedAt: completedAt
        )
        #expect(valid.citations.count == 1)
        let differentClaim = try BrowserResearchSynthesisValidator.validate(
            BrowserResearchSynthesisEnvelope(
                answer: valid.answer,
                citations: [
                    .init(
                        sourceID: request.sources[0].id,
                        claim: "Supports a materially different claim"
                    )
                ]
            ),
            against: request,
            completedAt: completedAt
        )
        #expect(differentClaim.requestCommitment == valid.requestCommitment)
        #expect(differentClaim.commitment != valid.commitment)
        #expect(differentClaim.id != valid.id)

        var ledger = BrowserResearchLedger(topic: "Validated synthesis", entries: [])
        ledger.upsertValidatedSynthesis(valid)
        let decodedLedger = try JSONDecoder().decode(
            BrowserResearchLedger.self,
            from: JSONEncoder().encode(ledger)
        )
        let persistedSynthesis = try #require(decodedLedger.syntheses.first)
        #expect(persistedSynthesis.answer == valid.answer)
        #expect(persistedSynthesis.citations.map(\.claim) == valid.citations.map(\.claim))
        #expect(persistedSynthesis.citations.map(\.sourceID) == valid.citations.map(\.source.id))
        #expect(
            persistedSynthesis.citations.map(\.sourceCommitment)
                == valid.citations.map(\.source.commitment)
        )
        #expect(persistedSynthesis.requestCommitment == valid.requestCommitment)
        #expect(persistedSynthesis.resultCommitment == valid.commitment)
        #expect(persistedSynthesis.completedAt == completedAt)

        let updatedSearchResult = try #require(
            BrowserSearchResult(
                title: "Source after provider update",
                urlString: "https://example.com/report?year=2026&utm_source=updated",
                snippet: "Later evidence that must not rewrite the first synthesis snapshot.",
                retrievedAt: completedAt.addingTimeInterval(3_600)
            )
        )
        let updatedRequest = BrowserResearchSynthesisRequest(
            query: request.query,
            sources: [BrowserResearchSource(result: updatedSearchResult)]
        )
        let updatedSynthesis = try BrowserResearchSynthesisValidator.validate(
            BrowserResearchSynthesisEnvelope(
                answer: "The source later changed.",
                citations: [
                    .init(
                        sourceID: updatedRequest.sources[0].id,
                        claim: "Supports the later answer"
                    )
                ]
            ),
            against: updatedRequest,
            completedAt: completedAt.addingTimeInterval(3_600)
        )
        #expect(updatedRequest.sources[0].id == request.sources[0].id)
        #expect(updatedRequest.sources[0].commitment != request.sources[0].commitment)
        ledger.upsertValidatedSynthesis(updatedSynthesis)
        let updatedLedger = try JSONDecoder().decode(
            BrowserResearchLedger.self,
            from: JSONEncoder().encode(ledger)
        )
        let originalRecord = try #require(
            updatedLedger.syntheses.first { $0.id == valid.id }
        )
        let laterRecord = try #require(
            updatedLedger.syntheses.first { $0.id == updatedSynthesis.id }
        )
        #expect(originalRecord.citations.first?.sourceEvidence == request.sources[0].evidence)
        #expect(originalRecord.citations.first?.sourceTitle == request.sources[0].title)
        #expect(originalRecord.citations.first?.sourceCommitment == request.sources[0].commitment)
        #expect(originalRecord.citations.first?.sourceRetrievedAt == request.sources[0].retrievedAt)
        #expect(laterRecord.citations.first?.sourceEvidence == updatedRequest.sources[0].evidence)
        #expect(laterRecord.citations.first?.sourceCommitment == updatedRequest.sources[0].commitment)

        let legacyLedgerData = try #require(
            #"{"topic":"Legacy research","entries":[]}"#.data(using: .utf8)
        )
        let legacyLedger = try JSONDecoder().decode(
            BrowserResearchLedger.self,
            from: legacyLedgerData
        )
        #expect(legacyLedger.topic == "Legacy research")
        #expect(legacyLedger.syntheses.isEmpty)
        #expect(throws: BrowserResearchSynthesisValidationError.unknownCitation("invented")) {
            try BrowserResearchSynthesisValidator.validate(
                BrowserResearchSynthesisEnvelope(
                    answer: "Invented",
                    citations: [.init(sourceID: "invented", claim: "No source")]
                ),
                against: request
            )
        }
    }

    @Test func addressTermsResolveToNativeSearchInsteadOfWebNavigation() {
        let resolution = BrowserURLResolver.resolve("zero knowledge proofs")
        guard case .search(let query) = resolution else {
            Issue.record("Expected native search resolution")
            return
        }
        #expect(query == "zero knowledge proofs")
    }

    @Test func oauthUsesPKCEStateAndMutationRequestRequiresExactApproval() throws {
        let profile = BrowserConnectorProfile(
            kind: .gmail,
            authorizedScopes: [.gmailDraft],
            connectionState: .connected
        )
        let configuration = BrowserGoogleOAuthConfiguration(
            clientID: "client-id",
            redirectURI: URL(string: "dbrowser://oauth/google")
        )
        #expect(
            configuration.matchesCallbackURL(
                URL(string: "dbrowser://oauth/google?state=state&code=code")!
            )
        )
        #expect(!configuration.matchesCallbackURL(URL(string: "dbrowser://oauth/wrong")!))
        #expect(!configuration.matchesCallbackURL(URL(string: "otherbrowser://oauth/google")!))
        let contract = BrowserGoogleOAuthContract(entropy: FixedOAuthEntropy())
        let authorization = try contract.makeAuthorizationRequest(
            profile: profile,
            scopes: [.gmailDraft],
            configuration: configuration
        )
        #expect(authorization.authorizationURL.query?.contains("code_challenge_method=S256") == true)
        let registry = BrowserOAuthAuthorizationRegistry()
        registry.register(authorization.pending)
        let callback = try registry.consumeCallback(
            URL(string: "dbrowser://oauth/google?state=\(authorization.pending.state)&code=code")!
        )
        #expect(callback.authorizationCode == "code")
        #expect(throws: BrowserOAuthContractError.unknownOrReplayedState) {
            try registry.consumeCallback(
                URL(string: "dbrowser://oauth/google?state=\(authorization.pending.state)&code=replay")!
            )
        }

        let tokens = try #require(
            BrowserConnectorOAuthTokens(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3_600),
                grantedScopes: [.gmailDraft]
            )
        )
        let proposal = BrowserConnectorMutationProposal(
            profile: profile,
            payload: .gmailDraft(
                BrowserGmailDraftContent(to: ["a@example.com"], subject: "Subject", body: "Body")
            )
        )
        #expect(throws: BrowserConnectorRequestError.approvalRequired) {
            try BrowserGoogleRESTRequestBuilder.gmailCreateDraft(
                profile: profile,
                tokens: tokens,
                proposal: proposal
            )
        }
        let approved = try proposal.approving(receiptID: "user-approved")
        let executing = try approved.beginningExecution()
        let request = try BrowserGoogleRESTRequestBuilder.gmailCreateDraft(
            profile: profile,
            tokens: tokens,
            proposal: executing
        )
        #expect(request.request.httpMethod == "POST")
        #expect(request.request.url?.absoluteString.hasSuffix("/drafts") == true)
        #expect(approved.status == .approved)
        #expect(executing.status == .executing)
        #expect(throws: BrowserConnectorRequestError.invalidProposalState) {
            try approved.approving(receiptID: "duplicate-approval")
        }
        #expect(throws: BrowserConnectorRequestError.invalidProposalState) {
            try executing.beginningExecution()
        }
        let completed = try executing.completing()
        #expect(completed.status == .completed)
        #expect(completed.status.isTerminal)
        #expect(throws: BrowserConnectorRequestError.invalidProposalState) {
            try completed.beginningExecution()
        }

        let denied = try BrowserConnectorMutationProposal(
            profile: profile,
            payload: .gmailDraft(
                BrowserGmailDraftContent(to: ["a@example.com"], subject: "Denied", body: "Body")
            )
        ).denying()
        #expect(denied.status == .denied)
        #expect(denied.status.isTerminal)

        let expiring = BrowserConnectorMutationProposal(
            profile: profile,
            payload: .gmailDraft(
                BrowserGmailDraftContent(to: ["a@example.com"], subject: "Expired", body: "Body")
            )
        )
        let expired = try expiring.expiring(now: expiring.expiresAt.addingTimeInterval(1))
        #expect(expired.status == .expired)
        #expect(expired.status.isTerminal)

        let fullPreview = BrowserGmailDraftContent(
            to: ["to@example.com"],
            cc: ["cc@example.com"],
            bcc: ["bcc@example.com"],
            subject: "Exact subject",
            body: "Exact body"
        )
        let changedBCC = BrowserGmailDraftContent(
            to: ["to@example.com"],
            cc: ["cc@example.com"],
            bcc: ["other@example.com"],
            subject: "Exact subject",
            body: "Exact body"
        )
        #expect(fullPreview.commitment != changedBCC.commitment)

        let calendarProfile = BrowserConnectorProfile(
            kind: .googleCalendar,
            authorizedScopes: [.calendarEvents],
            connectionState: .connected
        )
        let calendarTokens = try #require(
            BrowserConnectorOAuthTokens(
                accessToken: "calendar-access",
                refreshToken: "calendar-refresh",
                expiresAt: Date().addingTimeInterval(3_600),
                grantedScopes: [.calendarEvents]
            )
        )
        let eventContent = BrowserCalendarEventProposalContent(
            calendarID: "primary",
            title: "Fractional boundary",
            start: Date(timeIntervalSince1970: 2_000_000_000.123),
            end: Date(timeIntervalSince1970: 2_000_003_600.987),
            timeZoneIdentifier: "UTC",
            location: "Room 1",
            notes: "Keep exact approved times"
        )
        let eventProposal = try BrowserConnectorMutationProposal(
            profile: calendarProfile,
            payload: .calendarEvent(eventContent)
        )
        .approving(receiptID: "calendar-user-approved")
        .beginningExecution()
        let eventRequest = try BrowserGoogleRESTRequestBuilder.calendarCreateProposedEvent(
            profile: calendarProfile,
            tokens: calendarTokens,
            proposal: eventProposal
        )
        let eventBody = try #require(eventRequest.request.httpBody)
        let eventObject = try #require(
            JSONSerialization.jsonObject(with: eventBody) as? [String: Any]
        )
        let encodedStart = try #require(eventObject["start"] as? [String: Any])
        let encodedEnd = try #require(eventObject["end"] as? [String: Any])
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(encodedStart["dateTime"] as? String == fractionalFormatter.string(from: eventContent.start))
        #expect(encodedEnd["dateTime"] as? String == fractionalFormatter.string(from: eventContent.end))
    }

    @Test func connectorMutationIsDurableBeforeNetworkAndNeverReplaysAfterRelaunch() async throws {
        let suiteName = "CometParityGapTests.connector-ledger.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = BrowserConnectorProfile(
            id: "connector:durable-gmail",
            kind: .gmail,
            authorizedScopes: [.gmailDraft],
            connectionState: .connected
        )
        defaults.set(
            try JSONEncoder().encode(
                BrowserConnectorPersistencePayload(profiles: [profile], mutationProposals: [])
            ),
            forKey: suiteName
        )

        let credentialStore = ConnectorLedgerCredentialStore()
        let accessToken = "must-not-persist-access-token"
        let refreshToken = "must-not-persist-refresh-token"
        credentialStore.setTokens(
            try #require(
                BrowserConnectorOAuthTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: Date().addingTimeInterval(3_600),
                    grantedScopes: [.gmailDraft]
                )
            ),
            for: profile
        )

        let capture = ConnectorLedgerNetworkCapture()
        ConnectorLedgerMockURLProtocol.register { request in
            capture.record(defaults: defaults, key: suiteName)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"error":"ambiguous provider failure"}"#.utf8))
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ConnectorLedgerMockURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let oauthConfiguration = BrowserGoogleOAuthConfiguration(
            clientID: "durable-ledger-client",
            redirectURI: URL(string: "dbrowser://oauth/google")
        )
        let coordinator = BrowserConnectorCoordinator(
            oauthConfiguration: oauthConfiguration,
            credentialStore: credentialStore,
            session: session,
            defaults: defaults,
            defaultsKey: suiteName
        )
        let proposal = try #require(
            coordinator.proposeGmailDraft(
                BrowserGmailDraftContent(
                    to: ["recipient@example.com"],
                    subject: "Durable one shot",
                    body: "Never replay after a crash."
                )
            )
        )
        let proposedPayload = try JSONDecoder().decode(
            BrowserConnectorPersistencePayload.self,
            from: try #require(defaults.data(forKey: suiteName))
        )
        #expect(proposedPayload.mutationProposals.first?.status == .requiresApproval)
        #expect(proposedPayload.mutationProposals.first?.payloadCommitment == proposal.payloadCommitment)
        #expect(proposedPayload.mutationProposals.first?.payload == proposal.payload)

        await coordinator.approveAndExecuteMutation(proposal.id)

        #expect(capture.requestCount == 1)
        let networkBoundaryPayloads = try capture.persistedPayloadData.map {
            try JSONDecoder().decode(BrowserConnectorPersistencePayload.self, from: $0)
        }
        #expect(networkBoundaryPayloads.map { $0.mutationProposals.first?.status } == [.executing])
        #expect(
            coordinator.mutationProposals.first(where: { $0.id == proposal.id })?.status
                == .ambiguousFailed
        )
        let failureData = try #require(defaults.data(forKey: suiteName))
        let failurePayload = try JSONDecoder().decode(
            BrowserConnectorPersistencePayload.self,
            from: failureData
        )
        #expect(
            failurePayload.mutationProposals.first(where: { $0.id == proposal.id })?.status
                == .ambiguousFailed
        )
        let persistedJSON = String(decoding: failureData, as: UTF8.self)
        #expect(!persistedJSON.contains(accessToken))
        #expect(!persistedJSON.contains(refreshToken))

        let relaunched = BrowserConnectorCoordinator(
            oauthConfiguration: oauthConfiguration,
            credentialStore: credentialStore,
            session: session,
            defaults: defaults,
            defaultsKey: suiteName
        )
        #expect(
            relaunched.mutationProposals.first(where: { $0.id == proposal.id })?.status
                == .ambiguousFailed
        )
        await relaunched.approveAndExecuteMutation(proposal.id)
        #expect(capture.requestCount == 1)
        #expect(!relaunched.isWorking)
    }

    @Test func connectorMutationRelaunchReconcilesStatesAndBoundsAuditHistory() throws {
        let referenceDate = Date()
        let profile = BrowserConnectorProfile(
            id: "connector:relaunch-gmail",
            kind: .gmail,
            authorizedScopes: [.gmailDraft],
            connectionState: .connected
        )
        func proposal(_ subject: String, createdAt: Date) -> BrowserConnectorMutationProposal {
            BrowserConnectorMutationProposal(
                profile: profile,
                payload: .gmailDraft(
                    BrowserGmailDraftContent(
                        to: ["audit@example.com"],
                        subject: subject,
                        body: "Persist this audit state."
                    )
                ),
                createdAt: createdAt
            )
        }

        let pending = proposal("pending", createdAt: referenceDate)
        let stalePending = proposal(
            "stale pending",
            createdAt: referenceDate.addingTimeInterval(-BrowserConnectorPolicy.proposalLifetime - 1)
        )
        let approved = try proposal("approved", createdAt: referenceDate)
            .approving(receiptID: "approved-before-crash", now: referenceDate)
        let executing = try proposal("executing", createdAt: referenceDate)
            .approving(receiptID: "executing-before-crash", now: referenceDate)
            .beginningExecution(now: referenceDate)
        let completed = try proposal("completed", createdAt: referenceDate)
            .approving(receiptID: "completed-receipt", now: referenceDate)
            .beginningExecution(now: referenceDate)
            .completing()
        let ambiguous = try proposal("ambiguous", createdAt: referenceDate)
            .approving(receiptID: "ambiguous-receipt", now: referenceDate)
            .beginningExecution(now: referenceDate)
            .failingAmbiguously()
        let denied = try proposal("denied", createdAt: referenceDate)
            .denying(now: referenceDate)
        let expired = try proposal(
            "expired",
            createdAt: referenceDate.addingTimeInterval(-BrowserConnectorPolicy.proposalLifetime - 1)
        ).expiring(now: referenceDate)
        let stateRecords = [pending, stalePending, approved, executing, completed, ambiguous, denied, expired]
        let extras = (0..<BrowserConnectorPolicy.maximumPersistedMutationProposals).map {
            proposal("extra \($0)", createdAt: referenceDate)
        }
        let unboundedData = try JSONEncoder().encode(
            UnboundedConnectorPersistenceEnvelope(
                schemaVersion: BrowserConnectorPersistencePayload.currentSchemaVersion,
                profiles: [profile],
                mutationProposals: stateRecords + [pending] + extras
            )
        )
        let payload = try JSONDecoder().decode(
            BrowserConnectorPersistencePayload.self,
            from: unboundedData
        )
        #expect(payload.schemaVersion == BrowserConnectorPersistencePayload.currentSchemaVersion)
        #expect(payload.profiles == [profile])
        #expect(
            payload.mutationProposals.first(where: { $0.id == pending.id })?.payloadCommitment
                == pending.payloadCommitment
        )
        #expect(
            payload.mutationProposals.first(where: { $0.id == pending.id })?.payload
                == pending.payload
        )
        #expect(payload.mutationProposals.count == BrowserConnectorPolicy.maximumPersistedMutationProposals)
        #expect(Set(payload.mutationProposals.map(\.id)).count == payload.mutationProposals.count)

        let suiteName = "CometParityGapTests.connector-relaunch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(unboundedData, forKey: suiteName)

        let coordinator = BrowserConnectorCoordinator(
            oauthConfiguration: BrowserGoogleOAuthConfiguration(
                clientID: "relaunch-client",
                redirectURI: URL(string: "dbrowser://oauth/google")
            ),
            credentialStore: ConnectorLedgerCredentialStore(),
            defaults: defaults,
            defaultsKey: suiteName
        )
        let statuses = Dictionary(
            uniqueKeysWithValues: coordinator.mutationProposals.map { ($0.id, $0.status) }
        )
        #expect(statuses[pending.id] == .expired)
        #expect(statuses[stalePending.id] == .expired)
        #expect(statuses[approved.id] == .ambiguousFailed)
        #expect(statuses[executing.id] == .ambiguousFailed)
        #expect(statuses[completed.id] == .completed)
        #expect(statuses[ambiguous.id] == .ambiguousFailed)
        #expect(statuses[denied.id] == .denied)
        #expect(statuses[expired.id] == .expired)

        let restoredPayload = try JSONDecoder().decode(
            BrowserConnectorPersistencePayload.self,
            from: try #require(defaults.data(forKey: suiteName))
        )
        #expect(restoredPayload.schemaVersion == BrowserConnectorPersistencePayload.currentSchemaVersion)
        #expect(
            restoredPayload.mutationProposals.count
                == BrowserConnectorPolicy.maximumPersistedMutationProposals
        )
        #expect(
            restoredPayload.mutationProposals.first(where: { $0.id == approved.id })?.status
                == .ambiguousFailed
        )
        #expect(
            restoredPayload.mutationProposals.first(where: { $0.id == stalePending.id })?.status
                == .expired
        )
        #expect(
            restoredPayload.mutationProposals.first(where: { $0.id == pending.id })?.payloadCommitment
                == pending.payloadCommitment
        )
        #expect(
            restoredPayload.mutationProposals.first(where: { $0.id == pending.id })?.payload
                == pending.payload
        )
    }

    @Test func voiceAuthorizationIsUserTriggeredAndTranscriptNeverAutoSends() async {
        let service = StubVoiceInputService()
        let controller = BrowserVoiceInputController(service: service)
        #expect(service.authorizationRequests == 0)
        await controller.startFromUserAction()
        #expect(service.authorizationRequests == 1)
        #expect(service.starts == 1)
        let firstSessionHandler = service.handler
        firstSessionHandler?(.success(.init(transcript: "editable words", isFinal: false)))
        #expect(controller.transcript == "editable words")
        #expect(controller.state == .transcribing)

        controller.cancel()
        #expect(service.cancels == 1)
        #expect(controller.state == .stopped)
        firstSessionHandler?(.success(.init(transcript: "late words", isFinal: true)))
        #expect(controller.transcript == "editable words")

        await controller.startFromUserAction()
        #expect(service.authorizationRequests == 1)
        #expect(service.starts == 2)
        service.handler?(.success(.init(transcript: "new words", isFinal: true)))
        #expect(controller.transcript == "editable words new words")
        #expect(controller.state == .stopped)
        controller.editTranscript("edited by user")
        #expect(controller.transcript == "edited by user")
    }

    @Test func providerToolCallIsAllowlistedBoundAndAlwaysPendingApproval() throws {
        let tabID = UUID()
        let runID = UUID()
        let call = LLMRouterToolCall(
            id: "tool-1",
            name: "browser.navigate",
            arguments: ["url": "https://example.com/next"],
            approvalRequired: false
        )
        let proposal = try CopilotToolProposalFactory.make(
            toolCall: call,
            sourceRunID: runID,
            targetTabID: tabID,
            targetURLString: "https://example.com/current?secret=1",
            navigationGeneration: 4
        )
        #expect(proposal.status == .pendingApproval)
        #expect(proposal.targetTabID == tabID)
        #expect(proposal.targetURLString == "https://example.com/current")
        #expect(proposal.navigationGeneration == 4)
        #expect(
            CopilotToolProposalFactory.commitment(
                name: "browser.test",
                arguments: ["a": "b&c=d"]
            ) != CopilotToolProposalFactory.commitment(
                name: "browser.test",
                arguments: ["a": "b", "c": "d"]
            )
        )
        let overlongPageURL = "https://example.com/" + String(repeating: "é", count: 1_015)
        #expect(overlongPageURL.count < CopilotToolProposalFactory.maximumPageURLBytes)
        #expect(overlongPageURL.utf8.count > CopilotToolProposalFactory.maximumPageURLBytes)
        #expect(CopilotToolProposalFactory.pageCommitment(urlString: overlongPageURL) == nil)
        #expect(
            CopilotToolProposalFactory.pageCommitment(
                urlString: "https://user:password@example.com/private"
            ) == nil
        )
        #expect(
            throws: CopilotToolProposalError.invalidArguments(
                "provider tools require a bounded HTTP(S) source page"
            )
        ) {
            try CopilotToolProposalFactory.make(
                toolCall: call,
                sourceRunID: runID,
                targetTabID: tabID,
                targetURLString: overlongPageURL,
                navigationGeneration: 4
            )
        }
        #expect(throws: CopilotToolProposalError.unsupportedTool("wallet.sign")) {
            try CopilotToolProposalFactory.command(
                for: LLMRouterToolCall(
                    id: "bad",
                    name: "wallet.sign",
                    arguments: [:],
                    approvalRequired: false
                )
            )
        }
        let indexedClick = try CopilotToolProposalFactory.command(
            for: LLMRouterToolCall(
                id: "indexed-click",
                name: "browser.click",
                arguments: ["selector": ".result", "element_index": "2"],
                approvalRequired: false
            )
        )
        #expect(indexedClick.approvalSummary.contains("match index 2 of selector .result"))
        let defaultClick = try CopilotToolProposalFactory.command(
            for: LLMRouterToolCall(
                id: "default-click",
                name: "browser.click",
                arguments: ["selector": ".result"],
                approvalRequired: false
            )
        )
        #expect(defaultClick.approvalSummary.contains("match index 0 of selector .result"))
        let appendType = try CopilotToolProposalFactory.command(
            for: LLMRouterToolCall(
                id: "append-type",
                name: "browser.type",
                arguments: [
                    "selector": "#notes",
                    "element_index": "1",
                    "text": "append me",
                    "clear_existing": "false"
                ],
                approvalRequired: false
            )
        )
        #expect(appendType.approvalSummary.contains("Append to existing content"))
        #expect(appendType.approvalSummary.contains("match index 1 of selector #notes"))
        let replaceType = try CopilotToolProposalFactory.command(
            for: LLMRouterToolCall(
                id: "replace-type",
                name: "browser.type",
                arguments: ["selector": "#notes", "text": "replace me"],
                approvalRequired: false
            )
        )
        #expect(replaceType.approvalSummary.contains("Replace existing content"))
        #expect(
            CopilotToolCommand.domQuery(
                DOMQueryRequest(selector: "main", limit: 3, includeHidden: true)
            ).approvalSummary.contains("include hidden elements: true")
        )
        #expect(
            CopilotToolCommand.pageSnapshot(
                PageSnapshotRequest(maxTextCharacters: 500, maxElements: 2, includeMetadata: false)
            ).approvalSummary.contains("include page metadata: false")
        )
        #expect(throws: CopilotToolProposalError.invalidArguments("click requires a selector")) {
            try CopilotToolProposalFactory.command(
                for: LLMRouterToolCall(
                    id: "missing-selector",
                    name: "browser.click",
                    arguments: [:],
                    approvalRequired: false
                )
            )
        }
        #expect(
            throws: CopilotToolProposalError.invalidArguments(
                "click requires a non-negative bounded element_index"
            )
        ) {
            try CopilotToolProposalFactory.command(
                for: LLMRouterToolCall(
                    id: "negative-index",
                    name: "browser.click",
                    arguments: ["selector": ".result", "element_index": "-1"],
                    approvalRequired: false
                )
            )
        }
    }

    @Test func automationGrantMatchesOnlyItsExactPageGenerationAndCommand() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tabID = UUID()
        let pageURL = "https://example.com/report"
        let readProposal = try CopilotToolProposalFactory.make(
            toolCall: LLMRouterToolCall(
                id: "read-main",
                name: "browser.query",
                arguments: ["selector": "main"],
                approvalRequired: false
            ),
            sourceRunID: UUID(),
            targetTabID: tabID,
            targetURLString: pageURL,
            navigationGeneration: 7,
            now: now
        )
        let readGrant = BrowserAutomationApprovalGrant(
            proposalID: readProposal.id,
            sourceRunID: readProposal.sourceRunID,
            targetTabID: tabID,
            targetURLString: readProposal.targetURLString,
            targetPageCommitment: try #require(readProposal.targetPageCommitment),
            navigationGeneration: readProposal.navigationGeneration,
            argumentCommitment: readProposal.argumentCommitment,
            commandCommitment: try #require(readProposal.commandCommitment),
            approvalBindingCommitment: try #require(readProposal.approvalBindingCommitment),
            approvedAt: now,
            expiresAt: readProposal.expiresAt
        )
        let readRequest = BrowserAutomationRequest(
            tabID: tabID,
            command: readProposal.command.browserCommand,
            navigationGeneration: 7,
            approvalGrant: readGrant
        )

        #expect(
            BrowserAutomationGrantPolicy.matches(
                readGrant,
                request: readRequest,
                currentURLString: pageURL,
                currentNavigationGeneration: 7,
                now: now.addingTimeInterval(1)
            )
        )
        let wrongSourceGrant = BrowserAutomationApprovalGrant(
            proposalID: readGrant.proposalID,
            sourceRunID: UUID(),
            targetTabID: readGrant.targetTabID,
            targetURLString: readGrant.targetURLString,
            targetPageCommitment: readGrant.targetPageCommitment,
            navigationGeneration: readGrant.navigationGeneration,
            argumentCommitment: readGrant.argumentCommitment,
            commandCommitment: readGrant.commandCommitment,
            approvalBindingCommitment: readGrant.approvalBindingCommitment,
            approvedAt: readGrant.approvedAt,
            expiresAt: readGrant.expiresAt
        )
        #expect(
            !BrowserAutomationGrantPolicy.matches(
                wrongSourceGrant,
                request: readRequest,
                currentURLString: pageURL,
                currentNavigationGeneration: 7,
                now: now.addingTimeInterval(1)
            )
        )
        let changedExpiryGrant = BrowserAutomationApprovalGrant(
            proposalID: readGrant.proposalID,
            sourceRunID: readGrant.sourceRunID,
            targetTabID: readGrant.targetTabID,
            targetURLString: readGrant.targetURLString,
            targetPageCommitment: readGrant.targetPageCommitment,
            navigationGeneration: readGrant.navigationGeneration,
            argumentCommitment: readGrant.argumentCommitment,
            commandCommitment: readGrant.commandCommitment,
            approvalBindingCommitment: readGrant.approvalBindingCommitment,
            approvedAt: readGrant.approvedAt,
            expiresAt: readGrant.expiresAt.addingTimeInterval(1)
        )
        #expect(
            !BrowserAutomationGrantPolicy.matches(
                changedExpiryGrant,
                request: readRequest,
                currentURLString: pageURL,
                currentNavigationGeneration: 7,
                now: now.addingTimeInterval(1)
            )
        )
        #expect(
            !BrowserAutomationGrantPolicy.matches(
                readGrant,
                request: readRequest,
                currentURLString: "https://example.com/other",
                currentNavigationGeneration: 7,
                now: now.addingTimeInterval(1)
            )
        )
        #expect(
            !BrowserAutomationGrantPolicy.matches(
                readGrant,
                request: readRequest,
                currentURLString: pageURL,
                currentNavigationGeneration: 8,
                now: now.addingTimeInterval(1)
            )
        )
        let changedCommandRequest = BrowserAutomationRequest(
            tabID: tabID,
            command: .domQuery(DOMQueryRequest(selector: "form", limit: 1)),
            navigationGeneration: 7,
            approvalGrant: readGrant
        )
        #expect(
            !BrowserAutomationGrantPolicy.matches(
                readGrant,
                request: changedCommandRequest,
                currentURLString: pageURL,
                currentNavigationGeneration: 7,
                now: now.addingTimeInterval(1)
            )
        )
        let wrongTabRequest = BrowserAutomationRequest(
            tabID: UUID(),
            command: readProposal.command.browserCommand,
            navigationGeneration: 7,
            approvalGrant: readGrant
        )
        #expect(
            !BrowserAutomationGrantPolicy.matches(
                readGrant,
                request: wrongTabRequest,
                currentURLString: pageURL,
                currentNavigationGeneration: 7,
                now: now.addingTimeInterval(1)
            )
        )

        let stopProposal = try CopilotToolProposalFactory.make(
            toolCall: LLMRouterToolCall(
                id: "stop-once",
                name: "browser.stop",
                arguments: [:],
                approvalRequired: false
            ),
            sourceRunID: UUID(),
            targetTabID: tabID,
            targetURLString: pageURL,
            navigationGeneration: 7,
            now: now
        )
        let stopGrant = BrowserAutomationApprovalGrant(
            proposalID: stopProposal.id,
            sourceRunID: stopProposal.sourceRunID,
            targetTabID: tabID,
            targetURLString: stopProposal.targetURLString,
            targetPageCommitment: try #require(stopProposal.targetPageCommitment),
            navigationGeneration: stopProposal.navigationGeneration,
            argumentCommitment: stopProposal.argumentCommitment,
            commandCommitment: try #require(stopProposal.commandCommitment),
            approvalBindingCommitment: try #require(stopProposal.approvalBindingCommitment),
            approvedAt: now,
            expiresAt: stopProposal.expiresAt
        )
        let stopRequest = BrowserAutomationRequest(
            tabID: tabID,
            command: stopProposal.command.browserCommand,
            navigationGeneration: 7,
            approvalGrant: stopGrant
        )
        #expect(
            BrowserAutomationGrantPolicy.matches(
                stopGrant,
                request: stopRequest,
                currentURLString: pageURL,
                currentNavigationGeneration: 7,
                now: now.addingTimeInterval(1)
            )
        )
        #expect(
            !BrowserAutomationGrantPolicy.matches(
                readGrant,
                request: stopRequest,
                currentURLString: pageURL,
                currentNavigationGeneration: 7,
                now: now.addingTimeInterval(1)
            )
        )
    }

    @Test func approvedAutomationAcceptsOnlyTheClaimingCoordinatorResult() throws {
        let model = makeViewModel()
        model.navigate("https://example.com/report")
        finishLoad(model)
        let tab = try #require(model.activeTab)
        let navigationGeneration = model.navigationGeneration(for: tab.id)
        let now = Date()
        let proposal = try CopilotToolProposalFactory.make(
            toolCall: LLMRouterToolCall(
                id: "coordinator-owned-read",
                name: "browser.query",
                arguments: ["selector": "main"],
                approvalRequired: true
            ),
            sourceRunID: UUID(),
            targetTabID: tab.id,
            targetURLString: tab.urlString,
            navigationGeneration: navigationGeneration,
            now: now
        )
        let grant = BrowserAutomationApprovalGrant(
            proposalID: proposal.id,
            sourceRunID: proposal.sourceRunID,
            targetTabID: proposal.targetTabID,
            targetURLString: proposal.targetURLString,
            targetPageCommitment: try #require(proposal.targetPageCommitment),
            navigationGeneration: proposal.navigationGeneration,
            argumentCommitment: proposal.argumentCommitment,
            commandCommitment: try #require(proposal.commandCommitment),
            approvalBindingCommitment: try #require(proposal.approvalBindingCommitment),
            approvedAt: now,
            expiresAt: proposal.expiresAt
        )
        let request = BrowserAutomationRequest(
            tabID: tab.id,
            command: proposal.command.browserCommand,
            navigationGeneration: navigationGeneration,
            approvalGrant: grant
        )
        model.automationRequest = request

        let dispatchingCoordinatorID = UUID()
        let replacementCoordinatorID = UUID()
        #expect(
            model.claimApprovedAutomationDispatch(
                request.id,
                ownerID: dispatchingCoordinatorID
            )
        )
        #expect(
            !model.claimApprovedAutomationDispatch(
                request.id,
                ownerID: replacementCoordinatorID
            )
        )

        let replacementFailure = BrowserAutomationResult(
            requestID: request.id,
            tabID: request.tabID,
            approvedAutomationDispatchOwnerID: replacementCoordinatorID,
            status: .failed,
            message: "Replacement coordinator has no matching loaded page."
        )
        model.applyAutomationResult(replacementFailure)

        #expect(model.automationRequest?.id == request.id)
        #expect(model.automationResults.isEmpty)
        #expect(!model.canChangeLLMConversation)

        let dispatchingResult = BrowserAutomationResult(
            requestID: request.id,
            tabID: request.tabID,
            approvedAutomationDispatchOwnerID: dispatchingCoordinatorID,
            status: .success,
            message: "The claiming coordinator completed exactly once."
        )
        model.applyAutomationResult(dispatchingResult)

        #expect(model.automationRequest == nil)
        #expect(model.automationResults == [dispatchingResult])
        #expect(model.canChangeLLMConversation)

        model.applyAutomationResult(dispatchingResult)
        #expect(model.automationResults == [dispatchingResult])
    }

    @Test func schedulesBecomeDueWithoutBypassingTargetPolicy() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let workflow = SavedCopilotWorkflow(
            title: "Daily",
            promptTemplate: "Summarize",
            targetURLPattern: "example.com/reports",
            schedule: .interval(hours: 24),
            lastRunAt: now.addingTimeInterval(-25 * 3_600)
        )
        #expect(workflow.isDue(now: now))
        #expect(workflow.targetMatches("https://example.com/reports"))
        #expect(workflow.targetMatches("https://example.com/reports/today"))
        #expect(!workflow.targetMatches("https://other.example/"))
        #expect(!workflow.targetMatches("https://evil.example/?next=example.com/reports"))
        #expect(!workflow.targetMatches("https://example.com/other?next=/reports"))
        #expect(!workflow.targetMatches("https://example.com.evil.test/reports"))
        #expect(!workflow.targetMatches("https://example.com@evil.test/reports"))

        let defaultPortWorkflow = SavedCopilotWorkflow(
            title: "Default HTTPS service",
            promptTemplate: "Summarize",
            targetURLPattern: "https://example.com/reports"
        )
        #expect(defaultPortWorkflow.targetMatches("https://example.com/reports"))
        #expect(defaultPortWorkflow.targetMatches("https://example.com:443/reports"))
        #expect(!defaultPortWorkflow.targetMatches("https://example.com:8443/reports"))
    }

    @Test func everyLaunchScheduleUsesSessionStateInsteadOfPersistedLastRun() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let workflow = SavedCopilotWorkflow(
            title: "Launch briefing",
            promptTemplate: "Summarize",
            schedule: .everyLaunch,
            lastRunAt: now.addingTimeInterval(-60)
        )

        #expect(workflow.isDue(now: now, hasRunThisLaunch: false))
        #expect(!workflow.isDue(now: now, hasRunThisLaunch: true))
    }

    @Test func blankTargetWorkflowsWaitOnNonWebSurfaces() {
        let surfaces: [(name: String, address: String?)] = [
            ("home", nil),
            ("private overlay", "example.onion/private"),
            (
                "torrent",
                "magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01"
            )
        ]

        for surface in surfaces {
            let model = makeViewModel()
            if let address = surface.address {
                model.navigate(address)
            }
            let due = model.saveCopilotWorkflow(
                title: "Due on \(surface.name)",
                promptTemplate: "Summarize",
                targetURLPattern: "   ",
                schedule: .interval(hours: 1)
            )
            let manual = model.saveCopilotWorkflow(
                title: "Manual on \(surface.name)",
                promptTemplate: "Summarize",
                targetURLPattern: nil,
                schedule: .manual
            )

            model.evaluateScheduledWorkflows(now: Date(timeIntervalSince1970: 2_000_000_000))
            let dueState = model.scheduledWorkflowStates.first { $0.workflowID == due.id }
            #expect(dueState?.phase == .waitingForUser, "\(surface.name) due workflow must wait")
            #expect(dueState?.message.isEmpty == false)
            #expect(dueState?.runID == nil)

            #expect(model.runWorkflow(manual.id) == nil)
            let manualState = model.scheduledWorkflowStates.first { $0.workflowID == manual.id }
            #expect(manualState?.phase == .waitingForUser, "\(surface.name) manual workflow must wait")
            #expect(manualState?.message.isEmpty == false)
            #expect(manualState?.runID == nil)
            #expect(model.copilotRuns.isEmpty)
            #expect(model.automationRequest == nil)
        }
    }

    @Test func manualAndAppIntentWorkflowsRequireAnIdleCopilot() throws {
        let model = makeViewModel()
        model.navigate("https://example.com/reports")
        finishLoad(model)
        let workflow = model.saveCopilotWorkflow(
            title: "Idle-only report",
            promptTemplate: "Summarize this report",
            targetURLPattern: "example.com/reports"
        )

        let activeRunID = try #require(
            model.sendLLMMessageWithFreshContext("Keep this run active.")
        )
        #expect(model.activeCopilotRunCount == 1)

        #expect(model.runWorkflow(workflow.id) == nil)
        let directState = model.scheduledWorkflowStates.first { $0.workflowID == workflow.id }
        #expect(directState?.phase == .waitingForUser)
        #expect(directState?.message.contains("idle") == true)
        #expect(directState?.runID == nil)

        let handoffMessage = model.handleSystemHandoff(
            .runWorkflow(id: workflow.id, title: workflow.title)
        )
        #expect(handoffMessage == "Could not start “\(workflow.title)”.")
        #expect(model.activeCopilotRunCount == 1)
        #expect(model.copilotRuns.map(\.id) == [activeRunID])
    }

    @Test func inactiveTabCaptureRequiresConfirmationAndDoesNotAutoAttach() {
        let model = makeViewModel()
        model.navigate("https://first.example/")
        finishLoad(model)
        let firstID = model.activeTabID
        model.newTab()
        model.navigate("https://second.example/")
        finishLoad(model)
        let secondID = model.activeTabID
        model.activateTab(firstID)

        model.prepareInactiveTabCapture(secondID)
        #expect(model.inactiveTabCaptureState.phase == .awaitingConfirmation)
        let request = model.confirmInactiveTabCapture()
        #expect(request?.tabID == secondID)
        #expect(model.inactiveTabCaptureState.phase == .capturing)
        guard let request else { return }
        model.applyAutomationResult(
            BrowserAutomationResult(
                requestID: request.id,
                tabID: secondID,
                status: .success,
                message: "captured",
                pageSnapshot: PageSnapshot(
                    urlString: "https://second.example/",
                    title: "Second",
                    visibleText: "Bounded text",
                    headings: [],
                    links: [],
                    buttons: [],
                    formControls: [],
                    metadata: [:],
                    truncated: false,
                    redactionCount: 0
                )
            )
        )
        #expect(model.inactiveTabCaptureState.phase == .captured)
        #expect(model.pageSnapshotsByTabID[secondID] != nil)
        #expect(!model.selectedCopilotContextTabIDs.contains(secondID))
    }

    @Test func inactiveTabCaptureConsentExpiresWhenHiddenPageChanges() {
        let model = makeViewModel()
        model.navigate("https://active.example/")
        finishLoad(model)
        let activeID = model.activeTabID
        model.newTab()
        model.navigate("https://hidden.example/report?token=private")
        finishLoad(model)
        let hiddenID = model.activeTabID
        model.activateTab(activeID)

        model.prepareInactiveTabCapture(hiddenID)
        #expect(model.inactiveTabCaptureState.phase == .awaitingConfirmation)
        #expect(model.inactiveTabCaptureState.targetURLString == "https://hidden.example/report?token=private")
        #expect(model.inactiveTabCaptureState.displayURLString == "https://hidden.example/report")
        let reviewedGeneration = model.inactiveTabCaptureState.navigationGeneration

        model.activateTab(hiddenID)
        model.reload()
        finishLoad(model)
        #expect(reviewedGeneration.map { model.navigationGeneration(for: hiddenID) != $0 } == true)
        model.activateTab(activeID)

        #expect(model.confirmInactiveTabCapture() == nil)
        #expect(model.inactiveTabCaptureState.phase == .failed)
        #expect(model.automationRequest == nil)
        #expect(model.pageSnapshotsByTabID[hiddenID] == nil)
    }

    private func makeViewModel(
        llmConversationStore: LLMConversationStore = .ephemeral()
    ) -> BrowserViewModel {
        BrowserViewModel(
            initialURL: "about:home",
            runtimeBridge: MobileRuntimeBridge(),
            copilotWorkflowStore: .ephemeral(),
            researchLedgerStore: .ephemeral(),
            developerWorkflowStore: .ephemeral(),
            smartHistoryStore: .ephemeral(),
            llmConversationStore: llmConversationStore,
            adBlockingDefaults: UserDefaults(suiteName: "CometParityGapTests.\(UUID())") ?? .standard
        )
    }

    private func finishLoad(_ model: BrowserViewModel) {
        guard let tab = model.activeTab else { return }
        model.applyNavigationUpdate(
            BrowserNavigationUpdate(
                tabID: tab.id,
                urlString: tab.urlString,
                title: tab.title,
                isLoading: false,
                canGoBack: false,
                canGoForward: false
            )
        )
    }
}
