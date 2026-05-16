import Foundation

struct OpenMindMemoryEndpointConfiguration: Equatable {
    var httpBaseURL: URL?
    var clientID: String

    nonisolated static let disabled = OpenMindMemoryEndpointConfiguration(httpBaseURL: nil)

    nonisolated static let localHTTP = OpenMindMemoryEndpointConfiguration(
        httpBaseURL: URL(string: "http://127.0.0.1:4840")!
    )

    nonisolated init(httpBaseURL: URL?, clientID: String = "dBrowser.swift") {
        self.httpBaseURL = httpBaseURL
        self.clientID = clientID
    }
}

enum OpenMindMemoryCapabilityStatus: String, Codable, Equatable {
    case disabled
    case available
    case unavailable
}

struct OpenMindMemoryCapabilityState: Codable, Equatable {
    var status: OpenMindMemoryCapabilityStatus
    var capabilities: [String]
    var posture: String?
    var message: String

    nonisolated static let disabled = OpenMindMemoryCapabilityState(
        status: .disabled,
        capabilities: [],
        posture: nil,
        message: "OpenMind memory is disabled until an MCP endpoint is configured."
    )

    nonisolated static func unavailable(_ message: String) -> OpenMindMemoryCapabilityState {
        OpenMindMemoryCapabilityState(
            status: .unavailable,
            capabilities: [],
            posture: nil,
            message: message
        )
    }

    var isAvailable: Bool {
        status == .available
    }
}

enum OpenMindResourceStatus: String, Codable, Equatable {
    case disabled
    case available
    case unavailable
}

struct OpenMindContinuityState: Codable, Equatable {
    var status: OpenMindResourceStatus
    var version: String?
    var mode: String?
    var summary: String
    var pendingStepUps: Int
    var updatedAt: String?
    var notices: [String]

    nonisolated static let disabled = OpenMindContinuityState(
        status: .disabled,
        version: nil,
        mode: nil,
        summary: "OpenMind continuity is disabled until an MCP endpoint is configured.",
        pendingStepUps: 0,
        updatedAt: nil,
        notices: []
    )

    nonisolated static func unavailable(_ message: String) -> OpenMindContinuityState {
        OpenMindContinuityState(
            status: .unavailable,
            version: nil,
            mode: nil,
            summary: message,
            pendingStepUps: 0,
            updatedAt: nil,
            notices: [message]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case available
        case version
        case mode
        case summary
        case pendingStepUps
        case pendingStepUpCount
        case updatedAt
        case notices
    }

    nonisolated init(
        status: OpenMindResourceStatus,
        version: String?,
        mode: String?,
        summary: String,
        pendingStepUps: Int,
        updatedAt: String?,
        notices: [String]
    ) {
        self.status = status
        self.version = version
        self.mode = mode
        self.summary = summary
        self.pendingStepUps = pendingStepUps
        self.updatedAt = updatedAt
        self.notices = notices
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStatus = try container.decodeIfPresent(OpenMindResourceStatus.self, forKey: .status)
        let available = try container.decodeIfPresent(Bool.self, forKey: .available)
        let version = try container.decodeIfPresent(String.self, forKey: .version)
        let mode = try container.decodeIfPresent(String.self, forKey: .mode)
        let summary = try container.decodeIfPresent(String.self, forKey: .summary)
        let pendingStepUps = try container.decodeIfPresent(Int.self, forKey: .pendingStepUps)
            ?? container.decodeIfPresent(Int.self, forKey: .pendingStepUpCount)
            ?? 0

        self.status = decodedStatus ?? (available == false ? .unavailable : .available)
        self.version = version
        self.mode = mode
        self.summary = summary ?? mode ?? "OpenMind continuity is available."
        self.pendingStepUps = pendingStepUps
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.notices = try container.decodeIfPresent([String].self, forKey: .notices) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encode(summary, forKey: .summary)
        try container.encode(pendingStepUps, forKey: .pendingStepUps)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(notices, forKey: .notices)
    }
}

struct OpenMindPostureState: Codable, Equatable {
    var status: OpenMindResourceStatus
    var mode: String?
    var userMessage: String?
    var allowsMemoryWriteback: Bool
    var requiresExplicitConfirmation: Bool
    var summary: String
    var notices: [String]

    nonisolated static let disabled = OpenMindPostureState(
        status: .disabled,
        mode: nil,
        userMessage: nil,
        allowsMemoryWriteback: false,
        requiresExplicitConfirmation: true,
        summary: "OpenMind posture is disabled until an MCP endpoint is configured.",
        notices: []
    )

    nonisolated static func unavailable(_ message: String) -> OpenMindPostureState {
        OpenMindPostureState(
            status: .unavailable,
            mode: nil,
            userMessage: nil,
            allowsMemoryWriteback: false,
            requiresExplicitConfirmation: true,
            summary: message,
            notices: [message]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case available
        case mode
        case posture
        case userMessage
        case message
        case allowsMemoryWriteback
        case memoryWritebackAllowed
        case requiresExplicitConfirmation
        case requiresConfirmation
        case summary
        case notices
    }

    nonisolated init(
        status: OpenMindResourceStatus,
        mode: String?,
        userMessage: String?,
        allowsMemoryWriteback: Bool,
        requiresExplicitConfirmation: Bool,
        summary: String,
        notices: [String]
    ) {
        self.status = status
        self.mode = mode
        self.userMessage = userMessage
        self.allowsMemoryWriteback = allowsMemoryWriteback
        self.requiresExplicitConfirmation = requiresExplicitConfirmation
        self.summary = summary
        self.notices = notices
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStatus = try container.decodeIfPresent(OpenMindResourceStatus.self, forKey: .status)
        let available = try container.decodeIfPresent(Bool.self, forKey: .available)
        let mode = try container.decodeIfPresent(String.self, forKey: .mode)
            ?? container.decodeIfPresent(String.self, forKey: .posture)
        let userMessage = try container.decodeIfPresent(String.self, forKey: .userMessage)
            ?? container.decodeIfPresent(String.self, forKey: .message)
        let summary = try container.decodeIfPresent(String.self, forKey: .summary)
            ?? userMessage
            ?? mode
            ?? "OpenMind posture is available."
        let allowsMemoryWriteback = try container.decodeIfPresent(Bool.self, forKey: .allowsMemoryWriteback)
            ?? container.decodeIfPresent(Bool.self, forKey: .memoryWritebackAllowed)
            ?? true
        let requiresExplicitConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresExplicitConfirmation)
            ?? container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation)
            ?? false

        self.status = decodedStatus ?? (available == false ? .unavailable : .available)
        self.mode = mode
        self.userMessage = userMessage
        self.allowsMemoryWriteback = allowsMemoryWriteback
        self.requiresExplicitConfirmation = requiresExplicitConfirmation
        self.summary = summary
        self.notices = try container.decodeIfPresent([String].self, forKey: .notices) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(userMessage, forKey: .userMessage)
        try container.encode(allowsMemoryWriteback, forKey: .allowsMemoryWriteback)
        try container.encode(requiresExplicitConfirmation, forKey: .requiresExplicitConfirmation)
        try container.encode(summary, forKey: .summary)
        try container.encode(notices, forKey: .notices)
    }
}

struct OpenMindMemoryRuntimeState: Codable, Equatable {
    var capability: OpenMindMemoryCapabilityState
    var continuity: OpenMindContinuityState
    var posture: OpenMindPostureState

    nonisolated static let disabled = OpenMindMemoryRuntimeState(
        capability: .disabled,
        continuity: .disabled,
        posture: .disabled
    )
}

struct OpenMindAccessIntent: Codable, Equatable {
    var prompt: String
    var pageURLString: String?
    var pageTitle: String?
    var snapshotCommitment: String?
    var purpose: String
    var sensitivityCeiling: String
}

enum OpenMindAccessDecisionStatus: String, Codable, Equatable {
    case allowed
    case denied
    case stepUpRequired
    case unavailable
}

struct OpenMindAccessDecision: Codable, Equatable {
    var status: OpenMindAccessDecisionStatus
    var allowedScopes: [String]
    var reason: String
    var redactionCount: Int
    var stepUpPrompt: String?

    nonisolated static func unavailable(_ message: String) -> OpenMindAccessDecision {
        OpenMindAccessDecision(
            status: .unavailable,
            allowedScopes: [],
            reason: message,
            redactionCount: 0,
            stepUpPrompt: nil
        )
    }
}

struct OpenMindMemoryRecord: Codable, Equatable, Identifiable {
    var id: String
    var summary: String
    var source: String
    var sensitivity: String?
    var evidenceURLString: String?
}

struct OpenMindEvidenceBundleQuery: Codable, Equatable {
    var text: String
    var purpose: String?
}

struct OpenMindEvidenceBundleScope: Codable, Equatable {
    var domains: [String]
    var maxSensitivity: String?
    var outputMode: String?
}

struct OpenMindEvidenceBundleItem: Codable, Equatable, Identifiable {
    var kind: String
    var id: String
    var summary: String
    var confidence: Double?
    var evidenceRefs: [String]
    var why: String?
    var sensitivity: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case summary
        case confidence
        case evidenceRefs
        case why
        case sensitivity
    }

    init(
        kind: String,
        id: String,
        summary: String,
        confidence: Double?,
        evidenceRefs: [String],
        why: String?,
        sensitivity: String?
    ) {
        self.kind = kind
        self.id = id
        self.summary = summary
        self.confidence = confidence
        self.evidenceRefs = evidenceRefs
        self.why = why
        self.sensitivity = sensitivity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "memory"
        self.id = try container.decode(String.self, forKey: .id)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        self.evidenceRefs = try container.decodeIfPresent([String].self, forKey: .evidenceRefs) ?? []
        self.why = try container.decodeIfPresent(String.self, forKey: .why)
        self.sensitivity = try container.decodeIfPresent(String.self, forKey: .sensitivity)
    }
}

struct OpenMindEvidenceBundle: Codable, Equatable, Identifiable {
    var bundleID: String
    var profile: String?
    var createdAt: String?
    var query: OpenMindEvidenceBundleQuery?
    var scope: OpenMindEvidenceBundleScope?
    var items: [OpenMindEvidenceBundleItem]
    var governanceNotes: [String]

    var id: String { bundleID }

    private enum CodingKeys: String, CodingKey {
        case bundleID = "bundleId"
        case profile
        case createdAt
        case query
        case scope
        case items
        case governanceNotes
    }

    init(
        bundleID: String,
        profile: String?,
        createdAt: String?,
        query: OpenMindEvidenceBundleQuery?,
        scope: OpenMindEvidenceBundleScope?,
        items: [OpenMindEvidenceBundleItem],
        governanceNotes: [String]
    ) {
        self.bundleID = bundleID
        self.profile = profile
        self.createdAt = createdAt
        self.query = query
        self.scope = scope
        self.items = items
        self.governanceNotes = governanceNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bundleID = try container.decode(String.self, forKey: .bundleID)
        self.profile = try container.decodeIfPresent(String.self, forKey: .profile)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.query = try container.decodeIfPresent(OpenMindEvidenceBundleQuery.self, forKey: .query)
        self.scope = try container.decodeIfPresent(OpenMindEvidenceBundleScope.self, forKey: .scope)
        self.items = try container.decodeIfPresent([OpenMindEvidenceBundleItem].self, forKey: .items) ?? []
        self.governanceNotes = try container.decodeIfPresent([String].self, forKey: .governanceNotes) ?? []
    }
}

struct OpenMindStepUpRequest: Codable, Equatable, Identifiable {
    var requestID: String
    var status: String
    var operation: String?
    var requestedScopes: [String]
    var purpose: String?
    var requestedTTL: String?
    var justification: String?

    var id: String { requestID }

    private enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case status
        case operation
        case requestedScopes
        case purpose
        case requestedTTL = "requestedTtl"
        case justification
    }

    init(
        requestID: String,
        status: String,
        operation: String?,
        requestedScopes: [String],
        purpose: String?,
        requestedTTL: String?,
        justification: String?
    ) {
        self.requestID = requestID
        self.status = status
        self.operation = operation
        self.requestedScopes = requestedScopes
        self.purpose = purpose
        self.requestedTTL = requestedTTL
        self.justification = justification
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.requestID = try container.decode(String.self, forKey: .requestID)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        self.operation = try container.decodeIfPresent(String.self, forKey: .operation)
        self.requestedScopes = try container.decodeIfPresent([String].self, forKey: .requestedScopes) ?? []
        self.purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
        self.requestedTTL = try container.decodeIfPresent(String.self, forKey: .requestedTTL)
        self.justification = try container.decodeIfPresent(String.self, forKey: .justification)
    }
}

struct OpenMindMemoryRecallResult: Codable, Equatable {
    var decision: OpenMindAccessDecision
    var memories: [OpenMindMemoryRecord]
    var notices: [String]
    var intent: OpenMindAccessIntent? = nil
    var evidenceBundle: OpenMindEvidenceBundle? = nil
    var stepUpRequest: OpenMindStepUpRequest? = nil

    nonisolated static func unavailable(_ message: String) -> OpenMindMemoryRecallResult {
        OpenMindMemoryRecallResult(
            decision: .unavailable(message),
            memories: [],
            notices: [message]
        )
    }

    var approvedContextSummary: String {
        memories
            .map { "\($0.id): \($0.summary)" }
            .joined(separator: "\n")
    }
}

struct OpenMindWritebackRequest: Codable, Equatable {
    var runID: UUID
    var prompt: String
    var pageURLString: String?
    var summary: String
    var source: String
    var snapshotCommitment: String?
    var idempotencyKey: String
}

struct OpenMindWritebackOutcome: Codable, Equatable {
    enum Status: String, Codable, Equatable {
        case recorded
        case proposed
        case denied
        case unavailable
    }

    var status: Status
    var revisionID: String?
    var message: String
}

enum OpenMindMemoryClientError: Error, LocalizedError {
    case disabled
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "OpenMind memory is disabled."
        case .invalidResponse:
            return "OpenMind memory service returned an invalid response."
        case .httpStatus(let status):
            return "OpenMind memory service returned HTTP \(status)."
        }
    }
}

final class OpenMindMemoryClient {
    private struct CapabilityResponse: Decodable {
        var available: Bool?
        var capabilities: [String]?
        var posture: String?
        var message: String?
    }

    private struct AccessIntentRequest: Encodable {
        var clientID: String
        var intent: OpenMindAccessIntent
    }

    private struct MemorySearchRequest: Encodable {
        var clientID: String
        var intent: OpenMindAccessIntent
        var limit: Int
    }

    private struct MemorySearchResponse: Decodable {
        var memories: [OpenMindMemoryRecord]
        var notices: [String]?
    }

    private struct EvidenceBundleRequest: Encodable {
        var clientID: String
        var query: String
        var purpose: String
        var domains: [String]
        var maxSensitivity: String
        var limit: Int
    }

    private struct StepUpGrantIntent: Encodable {
        var operation: String
        var purpose: String
        var requiredScopes: [String]
        var requestedDomains: [String]
        var outputMode: String
        var reasonCodes: [String]
        var prompt: String
        var pageURLString: String?
        var snapshotCommitment: String?
    }

    private struct StepUpGrantRequest: Encodable {
        var clientID: String
        var intent: StepUpGrantIntent
        var justification: String
        var requestedTtl: String
    }

    private struct WritebackEnvelope: Encodable {
        var clientID: String
        var request: OpenMindWritebackRequest
    }

    private struct PostureRequest: Encodable {
        var clientID: String
    }

    private let configuration: OpenMindMemoryEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: OpenMindMemoryEndpointConfiguration = .disabled,
        session: URLSession = OpenMindMemoryClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func refreshCapabilities() async -> OpenMindMemoryCapabilityState {
        guard configuration.httpBaseURL != nil else {
            return .disabled
        }

        do {
            let response: CapabilityResponse = try await send(method: "GET", path: "/mcp/capabilities")
            let available = response.available ?? true
            return OpenMindMemoryCapabilityState(
                status: available ? .available : .unavailable,
                capabilities: response.capabilities ?? [],
                posture: response.posture,
                message: response.message ?? (available ? "OpenMind MCP memory is available." : "OpenMind MCP memory is unavailable.")
            )
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func refreshContinuity() async -> OpenMindContinuityState {
        guard configuration.httpBaseURL != nil else {
            return .disabled
        }

        do {
            return try await send(method: "GET", path: "/mcp/resources/mind/continuity")
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func refreshPosture() async -> OpenMindPostureState {
        guard configuration.httpBaseURL != nil else {
            return .disabled
        }

        do {
            return try await send(
                method: "POST",
                path: "/mcp/tools/posture.get",
                body: PostureRequest(clientID: configuration.clientID)
            )
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func refreshRuntimeState() async -> OpenMindMemoryRuntimeState {
        guard configuration.httpBaseURL != nil else {
            return .disabled
        }

        async let capability = refreshCapabilities()
        async let continuity = refreshContinuity()
        async let posture = refreshPosture()
        return await OpenMindMemoryRuntimeState(
            capability: capability,
            continuity: continuity,
            posture: posture
        )
    }

    func recall(
        prompt: String,
        pageURLString: String?,
        pageSnapshot: PageSnapshot?,
        limit: Int = 5
    ) async -> OpenMindMemoryRecallResult {
        guard configuration.httpBaseURL != nil else {
            return .unavailable("OpenMind memory is disabled until an MCP endpoint is configured.")
        }

        let intent = Self.accessIntent(
            prompt: prompt,
            pageURLString: pageURLString,
            pageSnapshot: pageSnapshot
        )

        do {
            let decision: OpenMindAccessDecision = try await send(
                method: "POST",
                path: "/mcp/tools/gateway.evaluate_access_intent",
                body: AccessIntentRequest(clientID: configuration.clientID, intent: intent)
            )

            guard decision.status == .allowed else {
                return OpenMindMemoryRecallResult(
                    decision: decision,
                    memories: [],
                    notices: [decision.reason],
                    intent: intent
                )
            }

            let evidenceBundle = try? await retrieveEvidenceBundle(intent: intent, limit: limit)
            let search: MemorySearchResponse = try await send(
                method: "POST",
                path: "/mcp/tools/mind.search_memories",
                body: MemorySearchRequest(
                    clientID: configuration.clientID,
                    intent: intent,
                    limit: max(1, min(limit, 20))
                )
            )
            return OpenMindMemoryRecallResult(
                decision: decision,
                memories: Self.mergedMemories(search.memories, evidenceBundle: evidenceBundle),
                notices: search.notices ?? [],
                intent: intent,
                evidenceBundle: evidenceBundle
            )
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func retrieveEvidenceBundle(
        intent: OpenMindAccessIntent,
        limit: Int = 5
    ) async throws -> OpenMindEvidenceBundle {
        try await send(
            method: "POST",
            path: "/mcp/tools/mind.retrieve_evidence_bundle",
            body: EvidenceBundleRequest(
                clientID: configuration.clientID,
                query: intent.prompt,
                purpose: intent.purpose,
                domains: Self.domains(from: intent.pageURLString),
                maxSensitivity: intent.sensitivityCeiling,
                limit: max(1, min(limit, 20))
            )
        )
    }

    func requestStepUpGrant(
        intent: OpenMindAccessIntent,
        decision: OpenMindAccessDecision,
        justification: String? = nil,
        requestedTtl: String = "PT1H"
    ) async -> OpenMindStepUpRequest? {
        guard configuration.httpBaseURL != nil else {
            return nil
        }

        do {
            return try await send(
                method: "POST",
                path: "/mcp/tools/gateway.request_step_up_grant",
                body: StepUpGrantRequest(
                    clientID: configuration.clientID,
                    intent: StepUpGrantIntent(
                        operation: "memory.search",
                        purpose: intent.purpose,
                        requiredScopes: decision.allowedScopes.isEmpty ? ["mind.read.basic"] : decision.allowedScopes,
                        requestedDomains: Self.domains(from: intent.pageURLString),
                        outputMode: "summary_only",
                        reasonCodes: ["copilot_recall_step_up"],
                        prompt: intent.prompt,
                        pageURLString: intent.pageURLString,
                        snapshotCommitment: intent.snapshotCommitment
                    ),
                    justification: justification ?? decision.stepUpPrompt ?? decision.reason,
                    requestedTtl: requestedTtl
                )
            )
        } catch {
            return nil
        }
    }

    func writeback(_ request: OpenMindWritebackRequest) async -> OpenMindWritebackOutcome {
        guard configuration.httpBaseURL != nil else {
            return OpenMindWritebackOutcome(
                status: .unavailable,
                revisionID: nil,
                message: "OpenMind memory is disabled until an MCP endpoint is configured."
            )
        }

        do {
            return try await send(
                method: "POST",
                path: "/mcp/tools/mind.add_memory",
                body: WritebackEnvelope(clientID: configuration.clientID, request: request)
            )
        } catch {
            return OpenMindWritebackOutcome(
                status: .unavailable,
                revisionID: nil,
                message: error.localizedDescription
            )
        }
    }

    nonisolated static func accessIntent(
        prompt: String,
        pageURLString: String?,
        pageSnapshot: PageSnapshot?
    ) -> OpenMindAccessIntent {
        OpenMindAccessIntent(
            prompt: prompt,
            pageURLString: pageURLString,
            pageTitle: pageSnapshot?.title,
            snapshotCommitment: snapshotCommitment(for: pageSnapshot),
            purpose: "copilot_recall",
            sensitivityCeiling: "normal"
        )
    }

    nonisolated static func snapshotCommitment(for snapshot: PageSnapshot?) -> String? {
        guard let snapshot else { return nil }
        let text = [
            snapshot.urlString,
            snapshot.title,
            snapshot.visibleText,
            snapshot.headings.joined(separator: "\n")
        ].joined(separator: "\n")

        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return "fnv1a64:\(String(hash, radix: 16))"
    }

    private static func domains(from pageURLString: String?) -> [String] {
        guard let pageURLString,
              let host = URL(string: pageURLString)?.host,
              !host.isEmpty else {
            return []
        }
        return [host]
    }

    private static func mergedMemories(
        _ memories: [OpenMindMemoryRecord],
        evidenceBundle: OpenMindEvidenceBundle?
    ) -> [OpenMindMemoryRecord] {
        var seen = Set(memories.map(\.id))
        var merged = memories
        guard let evidenceBundle else { return merged }

        for item in evidenceBundle.items where seen.insert(item.id).inserted {
            merged.append(
                OpenMindMemoryRecord(
                    id: item.id,
                    summary: item.summary,
                    source: "OpenMind evidence bundle \(evidenceBundle.bundleID)",
                    sensitivity: item.sensitivity,
                    evidenceURLString: "mind://evidence/bundle/\(evidenceBundle.bundleID)"
                )
            )
        }
        return merged
    }

    private func send<Response: Decodable>(method: String, path: String) async throws -> Response {
        var request = try makeRequest(path: path)
        request.httpMethod = method
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(path: path)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let baseURL = configuration.httpBaseURL else {
            throw OpenMindMemoryClientError.disabled
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else {
            throw OpenMindMemoryClientError.invalidResponse
        }
        return URLRequest(url: url)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenMindMemoryClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenMindMemoryClientError.httpStatus(http.statusCode)
        }
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.75
        configuration.timeoutIntervalForResource = 0.75
        return URLSession(configuration: configuration)
    }
}
