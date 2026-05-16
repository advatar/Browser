import Foundation

enum OpenMindHTTPTransportPreference: String, Codable, Equatable {
    case auto
    case directHTTP
    case jsonRPCBridge
}

enum OpenMindMemoryTransportKind: String, Codable, Equatable {
    case directHTTP
    case jsonRPCHTTPBridge
    case stdio
    case inProcess
}

struct OpenMindNegotiatedTransport: Codable, Equatable {
    var kind: OpenMindMemoryTransportKind
    var protocolVersion: String?
    var serverName: String?
    var serverVersion: String?
    var toolNames: [String]
    var resourceURIs: [String]
    var message: String

    var displaySummary: String {
        switch kind {
        case .directHTTP:
            return "Direct HTTP"
        case .jsonRPCHTTPBridge:
            let server = [serverName, serverVersion]
                .compactMap { $0 }
                .joined(separator: " ")
            return server.isEmpty ? "JSON-RPC HTTP bridge" : "JSON-RPC HTTP bridge (\(server))"
        case .stdio:
            return "stdio"
        case .inProcess:
            return "in-process"
        }
    }
}

struct OpenMindMemoryEndpointConfiguration: Equatable {
    var httpBaseURL: URL?
    var clientID: String
    var httpTransportPreference: OpenMindHTTPTransportPreference
    var stdioCommand: [String]?
    var inProcessIdentifier: String?

    nonisolated static let disabled = OpenMindMemoryEndpointConfiguration(httpBaseURL: nil)

    nonisolated static let localHTTP = OpenMindMemoryEndpointConfiguration(
        httpBaseURL: URL(string: "http://127.0.0.1:4840")!
    )

    nonisolated init(
        httpBaseURL: URL?,
        clientID: String = "dBrowser.swift",
        httpTransportPreference: OpenMindHTTPTransportPreference = .auto,
        stdioCommand: [String]? = nil,
        inProcessIdentifier: String? = nil
    ) {
        self.httpBaseURL = httpBaseURL
        self.clientID = clientID
        self.httpTransportPreference = httpTransportPreference
        self.stdioCommand = stdioCommand
        self.inProcessIdentifier = inProcessIdentifier
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
    var transport: OpenMindNegotiatedTransport? = nil

    nonisolated static let disabled = OpenMindMemoryCapabilityState(
        status: .disabled,
        capabilities: [],
        posture: nil,
        message: "OpenMind memory is disabled until an MCP endpoint is configured.",
        transport: nil
    )

    nonisolated static func unavailable(_ message: String) -> OpenMindMemoryCapabilityState {
        OpenMindMemoryCapabilityState(
            status: .unavailable,
            capabilities: [],
            posture: nil,
            message: message,
            transport: nil
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

struct OpenMindReviewTask: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var summary: String?
    var state: String?
    var taskType: String?
    var entityID: String?
    var entityType: String?
    var priority: Int?
    var recommendedDecision: String?
    var createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case reviewTaskID
        case reviewTaskId
        case taskID
        case taskId
        case title
        case summary
        case state
        case status
        case taskType
        case type
        case entityID
        case entityId
        case targetID
        case targetId
        case entityType
        case priority
        case recommendedDecision
        case createdAt
    }

    nonisolated init(
        id: String,
        title: String,
        summary: String?,
        state: String?,
        taskType: String?,
        entityID: String?,
        entityType: String?,
        priority: Int?,
        recommendedDecision: String?,
        createdAt: String?
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.state = state
        self.taskType = taskType
        self.entityID = entityID
        self.entityType = entityType
        self.priority = priority
        self.recommendedDecision = recommendedDecision
        self.createdAt = createdAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .reviewTaskID)
            ?? container.decodeIfPresent(String.self, forKey: .reviewTaskId)
            ?? container.decodeIfPresent(String.self, forKey: .taskID)
            ?? container.decode(String.self, forKey: .taskId)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? "OpenMind review task"
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.state = try container.decodeIfPresent(String.self, forKey: .state)
            ?? container.decodeIfPresent(String.self, forKey: .status)
        self.taskType = try container.decodeIfPresent(String.self, forKey: .taskType)
            ?? container.decodeIfPresent(String.self, forKey: .type)
        self.entityID = try container.decodeIfPresent(String.self, forKey: .entityID)
            ?? container.decodeIfPresent(String.self, forKey: .entityId)
            ?? container.decodeIfPresent(String.self, forKey: .targetID)
            ?? container.decodeIfPresent(String.self, forKey: .targetId)
        self.entityType = try container.decodeIfPresent(String.self, forKey: .entityType)
        self.priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        self.recommendedDecision = try container.decodeIfPresent(String.self, forKey: .recommendedDecision)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(taskType, forKey: .taskType)
        try container.encodeIfPresent(entityID, forKey: .entityID)
        try container.encodeIfPresent(entityType, forKey: .entityType)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(recommendedDecision, forKey: .recommendedDecision)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

struct OpenMindActionSource: Codable, Equatable {
    var product: String
    var runID: UUID?
    var pageURLString: String?
    var snapshotCommitment: String?
    var prompt: String?
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

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
        {
        case "allowed", "allow":
            self = .allowed
        case "denied", "deny":
            self = .denied
        case "stepuprequired", "step_up_required", "require_step_up", "requires_step_up":
            self = .stepUpRequired
        case "unavailable":
            self = .unavailable
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported OpenMind access decision status: \(rawValue)"
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

    private enum CodingKeys: String, CodingKey {
        case id
        case memoryID
        case memoryId
        case summary
        case text
        case content
        case source
        case origin
        case sensitivity
        case evidenceURLString
        case evidenceUrl
    }

    nonisolated init(
        id: String,
        summary: String,
        source: String,
        sensitivity: String?,
        evidenceURLString: String?
    ) {
        self.id = id
        self.summary = summary
        self.source = source
        self.sensitivity = sensitivity
        self.evidenceURLString = evidenceURLString
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .memoryID)
            ?? container.decode(String.self, forKey: .memoryId)
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decodeIfPresent(String.self, forKey: .content)
            ?? ""
        self.source = (try? container.decodeIfPresent(String.self, forKey: .source))
            ?? (try? container.decodeIfPresent(String.self, forKey: .origin))
            ?? "OpenMind"
        self.sensitivity = try container.decodeIfPresent(String.self, forKey: .sensitivity)
        self.evidenceURLString = try container.decodeIfPresent(String.self, forKey: .evidenceURLString)
            ?? container.decodeIfPresent(String.self, forKey: .evidenceUrl)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(summary, forKey: .summary)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(sensitivity, forKey: .sensitivity)
        try container.encodeIfPresent(evidenceURLString, forKey: .evidenceURLString)
    }
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

    private enum CodingKeys: String, CodingKey {
        case status
        case revisionID
        case revisionId
        case id
        case message
    }

    nonisolated init(status: Status, revisionID: String?, message: String) {
        self.status = status
        self.revisionID = revisionID
        self.message = message
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let revisionID = try container.decodeIfPresent(String.self, forKey: .revisionID)
            ?? container.decodeIfPresent(String.self, forKey: .revisionId)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        self.status = try container.decodeIfPresent(Status.self, forKey: .status)
            ?? (revisionID == nil ? .unavailable : .recorded)
        self.revisionID = revisionID
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? status.rawValue
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(revisionID, forKey: .revisionID)
        try container.encode(message, forKey: .message)
    }
}

struct OpenMindCorrectionRequest: Codable, Equatable {
    var targetID: String
    var correctionText: String
    var actor: String
    var source: OpenMindActionSource
    var idempotencyKey: String

    private enum CodingKeys: String, CodingKey {
        case targetID = "targetId"
        case correctionText
        case actor
        case source
        case idempotencyKey
    }
}

struct OpenMindCorrectionOutcome: Codable, Equatable, Identifiable {
    enum Status: String, Codable, Equatable {
        case recorded
        case proposed
        case denied
        case unavailable

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            switch rawValue
                .replacingOccurrences(of: "-", with: "_")
                .lowercased()
            {
            case "recorded", "created", "ok", "accepted":
                self = .recorded
            case "proposed", "pending", "queued":
                self = .proposed
            case "denied", "rejected":
                self = .denied
            case "unavailable":
                self = .unavailable
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported OpenMind correction status: \(rawValue)"
                )
            }
        }

        nonisolated func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    var correctionID: String?
    var targetID: String?
    var status: Status
    var message: String
    var mode: String?
    var createdAt: String?

    var id: String {
        correctionID ?? targetID ?? message
    }

    private enum CodingKeys: String, CodingKey {
        case correctionID = "correctionId"
        case id
        case eventID
        case eventId
        case targetID = "targetId"
        case status
        case message
        case summary
        case correctionText
        case mode
        case createdAt
    }

    nonisolated init(
        correctionID: String?,
        targetID: String?,
        status: Status,
        message: String,
        mode: String?,
        createdAt: String?
    ) {
        self.correctionID = correctionID
        self.targetID = targetID
        self.status = status
        self.message = message
        self.mode = mode
        self.createdAt = createdAt
    }

    nonisolated static func unavailable(_ message: String) -> OpenMindCorrectionOutcome {
        OpenMindCorrectionOutcome(
            correctionID: nil,
            targetID: nil,
            status: .unavailable,
            message: message,
            mode: nil,
            createdAt: nil
        )
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let correctionID = try container.decodeIfPresent(String.self, forKey: .correctionID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .eventID)
            ?? container.decodeIfPresent(String.self, forKey: .eventId)
        let targetID = try container.decodeIfPresent(String.self, forKey: .targetID)
        self.correctionID = correctionID
        self.targetID = targetID
        self.status = try container.decodeIfPresent(Status.self, forKey: .status)
            ?? (correctionID == nil ? .proposed : .recorded)
        self.mode = try container.decodeIfPresent(String.self, forKey: .mode)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .summary)
            ?? container.decodeIfPresent(String.self, forKey: .correctionText)
            ?? (correctionID.map { "Correction recorded as \($0)." } ?? "Correction submitted for review.")
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(correctionID, forKey: .correctionID)
        try container.encodeIfPresent(targetID, forKey: .targetID)
        try container.encode(status, forKey: .status)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

enum OpenMindMemoryClientError: Error, LocalizedError {
    case disabled
    case invalidResponse
    case httpStatus(Int)
    case jsonRPCError(Int, String)
    case missingJSONRPCResult(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "OpenMind memory is disabled."
        case .invalidResponse:
            return "OpenMind memory service returned an invalid response."
        case .httpStatus(let status):
            return "OpenMind memory service returned HTTP \(status)."
        case .jsonRPCError(let code, let message):
            return "OpenMind MCP JSON-RPC returned \(code): \(message)"
        case .missingJSONRPCResult(let method):
            return "OpenMind MCP JSON-RPC returned no result for \(method)."
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

    private struct ReviewTasksResponse: Decodable {
        var items: [OpenMindReviewTask]

        private enum CodingKeys: String, CodingKey {
            case items
            case reviewTasks
            case tasks
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.items = try container.decodeIfPresent([OpenMindReviewTask].self, forKey: .items)
                ?? container.decodeIfPresent([OpenMindReviewTask].self, forKey: .reviewTasks)
                ?? container.decodeIfPresent([OpenMindReviewTask].self, forKey: .tasks)
                ?? []
        }
    }

    private struct EmptyJSONRPCParams: Codable {}

    private struct JSONRPCRequest<Params: Encodable>: Encodable {
        var jsonrpc = "2.0"
        var id: Int?
        var method: String
        var params: Params?
    }

    private struct JSONRPCResponse<Result: Decodable>: Decodable {
        var jsonrpc: String?
        var id: Int?
        var result: Result?
        var error: JSONRPCError?
    }

    private struct JSONRPCError: Decodable {
        var code: Int
        var message: String
    }

    private struct MCPInitializeParams: Encodable {
        var protocolVersion = "2025-11-25"
        var capabilities = EmptyJSONRPCParams()
        var clientInfo: MCPClientInfo
    }

    private struct MCPClientInfo: Encodable {
        var name: String
        var version: String
    }

    private struct MCPInitializeResult: Decodable {
        var protocolVersion: String?
        var serverInfo: MCPServerInfo?
    }

    private struct MCPServerInfo: Decodable {
        var name: String?
        var version: String?
    }

    private struct MCPToolsListResult: Decodable {
        var tools: [MCPToolDescriptor]
    }

    private struct MCPToolDescriptor: Decodable {
        var name: String
    }

    private struct MCPResourcesListResult: Decodable {
        var resources: [MCPResourceDescriptor]
    }

    private struct MCPResourceDescriptor: Decodable {
        var uri: String
    }

    private struct MCPToolCallParams<Arguments: Encodable>: Encodable {
        var name: String
        var arguments: Arguments
    }

    private struct MCPToolCallResult<StructuredContent: Decodable>: Decodable {
        var structuredContent: StructuredContent?
        var isError: Bool

        private enum CodingKeys: String, CodingKey {
            case structuredContent
            case content
            case isError
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.structuredContent = try container.decodeIfPresent(StructuredContent.self, forKey: .structuredContent)
            self.isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false

            if structuredContent == nil,
               let content = try container.decodeIfPresent([MCPContentItem].self, forKey: .content),
               let text = content.first(where: { $0.text != nil })?.text,
               let data = text.data(using: .utf8) {
                self.structuredContent = try? JSONDecoder().decode(StructuredContent.self, from: data)
            }
        }
    }

    private struct MCPContentItem: Decodable {
        var type: String?
        var text: String?
    }

    private struct MCPResourceReadParams: Encodable {
        var uri: String
    }

    private struct MCPResourceReadResult<Resource: Decodable>: Decodable {
        var resource: Resource

        private enum CodingKeys: String, CodingKey {
            case contents
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let contents = try container.decode([MCPContentItem].self, forKey: .contents)
            guard let text = contents.first(where: { $0.text != nil })?.text,
                  let data = text.data(using: .utf8) else {
                throw OpenMindMemoryClientError.invalidResponse
            }
            self.resource = try JSONDecoder().decode(Resource.self, from: data)
        }
    }

    private struct AccessIntentRequest: Encodable {
        var clientID: String
        var intent: OpenMindAccessIntent
    }

    private struct BridgeAccessIntentRequest: Encodable {
        var operation: String
        var purpose: String
        var requestedDomains: [String]
        var outputMode: String
        var sensitivity: String
        var capability: String
        var prompt: String
        var pageURLString: String?
        var pageTitle: String?
        var snapshotCommitment: String?
    }

    private struct MemorySearchRequest: Encodable {
        var clientID: String
        var intent: OpenMindAccessIntent
        var limit: Int
    }

    private struct BridgeMemorySearchRequest: Encodable {
        var query: String
        var limit: Int
    }

    private struct MemorySearchResponse: Decodable {
        var memories: [OpenMindMemoryRecord]
        var notices: [String]?

        private enum CodingKeys: String, CodingKey {
            case memories
            case results
            case notices
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.memories = try container.decodeIfPresent([OpenMindMemoryRecord].self, forKey: .memories)
                ?? container.decodeIfPresent([OpenMindMemoryRecord].self, forKey: .results)
                ?? []
            self.notices = try container.decodeIfPresent([String].self, forKey: .notices)
        }
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

    private struct BridgeWritebackRequest: Encodable {
        var summary: String
        var type: String
        var sensitivity: String
        var source: BridgeWritebackSource
        var idempotencyKey: String
    }

    private struct BridgeWritebackSource: Encodable {
        var product: String
        var runID: UUID
        var prompt: String
        var pageURLString: String?
        var snapshotCommitment: String?
        var clientSource: String
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
            switch configuration.httpTransportPreference {
            case .directHTTP:
                return try await refreshDirectCapabilities()
            case .jsonRPCBridge:
                return try await refreshJSONRPCCapabilities()
            case .auto:
                do {
                    return try await refreshDirectCapabilities()
                } catch {
                    guard Self.isNotFound(error) else {
                        throw error
                    }
                    return try await refreshJSONRPCCapabilities()
                }
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func refreshContinuity() async -> OpenMindContinuityState {
        guard configuration.httpBaseURL != nil else {
            return .disabled
        }

        do {
            return try await readResource(uri: "mind://continuity", directPath: "/mcp/resources/mind/continuity")
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func refreshPosture() async -> OpenMindPostureState {
        guard configuration.httpBaseURL != nil else {
            return .disabled
        }

        do {
            return try await sendTool(
                name: "posture.get",
                directPath: "/mcp/tools/posture.get",
                directBody: PostureRequest(clientID: configuration.clientID),
                bridgeArguments: EmptyJSONRPCParams()
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

    func refreshReviewTasks() async -> [OpenMindReviewTask] {
        guard configuration.httpBaseURL != nil else {
            return []
        }

        do {
            let response: ReviewTasksResponse = try await readResource(
                uri: "mind://governed-memory/review-tasks",
                directPath: "/mcp/resources/mind/governed-memory/review-tasks"
            )
            return response.items
        } catch {
            return []
        }
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
            let decision: OpenMindAccessDecision = try await sendTool(
                name: "gateway.evaluate_access_intent",
                directPath: "/mcp/tools/gateway.evaluate_access_intent",
                directBody: AccessIntentRequest(clientID: configuration.clientID, intent: intent),
                bridgeArguments: BridgeAccessIntentRequest(
                    operation: "memory.search",
                    purpose: intent.purpose,
                    requestedDomains: Self.domains(from: intent.pageURLString),
                    outputMode: "summary_only",
                    sensitivity: intent.sensitivityCeiling,
                    capability: "read.memories",
                    prompt: intent.prompt,
                    pageURLString: intent.pageURLString,
                    pageTitle: intent.pageTitle,
                    snapshotCommitment: intent.snapshotCommitment
                )
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
            let search: MemorySearchResponse = try await sendTool(
                name: "mind.search_memories",
                directPath: "/mcp/tools/mind.search_memories",
                directBody: MemorySearchRequest(
                    clientID: configuration.clientID,
                    intent: intent,
                    limit: max(1, min(limit, 20))
                ),
                bridgeArguments: BridgeMemorySearchRequest(
                    query: intent.prompt,
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
        try await sendTool(
            name: "mind.retrieve_evidence_bundle",
            directPath: "/mcp/tools/mind.retrieve_evidence_bundle",
            directBody: EvidenceBundleRequest(
                clientID: configuration.clientID,
                query: intent.prompt,
                purpose: intent.purpose,
                domains: Self.domains(from: intent.pageURLString),
                maxSensitivity: intent.sensitivityCeiling,
                limit: max(1, min(limit, 20))
            ),
            bridgeArguments: EvidenceBundleRequest(
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
            let request = StepUpGrantRequest(
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
            return try await sendTool(
                name: "gateway.request_step_up_grant",
                directPath: "/mcp/tools/gateway.request_step_up_grant",
                directBody: request,
                bridgeArguments: request
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
            return try await sendTool(
                name: "mind.add_memory",
                directPath: "/mcp/tools/mind.add_memory",
                directBody: WritebackEnvelope(clientID: configuration.clientID, request: request),
                bridgeArguments: BridgeWritebackRequest(
                    summary: request.summary,
                    type: "copilot_observation",
                    sensitivity: "normal",
                    source: BridgeWritebackSource(
                        product: configuration.clientID,
                        runID: request.runID,
                        prompt: request.prompt,
                        pageURLString: request.pageURLString,
                        snapshotCommitment: request.snapshotCommitment,
                        clientSource: request.source
                    ),
                    idempotencyKey: request.idempotencyKey
                )
            )
        } catch {
            return OpenMindWritebackOutcome(
                status: .unavailable,
                revisionID: nil,
                message: error.localizedDescription
            )
        }
    }

    func createCorrection(_ request: OpenMindCorrectionRequest) async -> OpenMindCorrectionOutcome {
        guard configuration.httpBaseURL != nil else {
            return .unavailable("OpenMind memory is disabled until an MCP endpoint is configured.")
        }

        do {
            return try await sendTool(
                name: "gmem.create_correction",
                directPath: "/mcp/tools/gmem.create_correction",
                directBody: request,
                bridgeArguments: request
            )
        } catch {
            return .unavailable(error.localizedDescription)
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

    private func refreshDirectCapabilities() async throws -> OpenMindMemoryCapabilityState {
        let response: CapabilityResponse = try await send(method: "GET", path: "/mcp/capabilities")
        let available = response.available ?? true
        let capabilities = response.capabilities ?? []
        return OpenMindMemoryCapabilityState(
            status: available ? .available : .unavailable,
            capabilities: capabilities,
            posture: response.posture,
            message: response.message ?? (available ? "OpenMind MCP memory is available." : "OpenMind MCP memory is unavailable."),
            transport: OpenMindNegotiatedTransport(
                kind: .directHTTP,
                protocolVersion: nil,
                serverName: nil,
                serverVersion: nil,
                toolNames: capabilities,
                resourceURIs: [],
                message: "Direct OpenMind HTTP endpoints negotiated."
            )
        )
    }

    private func refreshJSONRPCCapabilities() async throws -> OpenMindMemoryCapabilityState {
        let initialized = try await initializeJSONRPCBridge()
        let tools: MCPToolsListResult = try await jsonRPC(method: "tools/list", params: EmptyJSONRPCParams())
        let resources: MCPResourcesListResult = try await jsonRPC(method: "resources/list", params: EmptyJSONRPCParams())
        let toolNames = tools.tools.map(\.name).sorted()
        let resourceURIs = resources.resources.map(\.uri).sorted()
        let server = [initialized.serverInfo?.name, initialized.serverInfo?.version]
            .compactMap { $0 }
            .joined(separator: " ")
        let transport = OpenMindNegotiatedTransport(
            kind: .jsonRPCHTTPBridge,
            protocolVersion: initialized.protocolVersion,
            serverName: initialized.serverInfo?.name,
            serverVersion: initialized.serverInfo?.version,
            toolNames: toolNames,
            resourceURIs: resourceURIs,
            message: server.isEmpty
                ? "OpenMind MCP JSON-RPC HTTP bridge negotiated."
                : "OpenMind MCP JSON-RPC HTTP bridge negotiated with \(server)."
        )
        return OpenMindMemoryCapabilityState(
            status: .available,
            capabilities: toolNames + resourceURIs,
            posture: nil,
            message: transport.message,
            transport: transport
        )
    }

    private func sendTool<DirectBody: Encodable, BridgeArguments: Encodable, Response: Decodable>(
        name: String,
        directPath: String,
        directBody: DirectBody,
        bridgeArguments: BridgeArguments
    ) async throws -> Response {
        switch configuration.httpTransportPreference {
        case .directHTTP:
            return try await send(method: "POST", path: directPath, body: directBody)
        case .jsonRPCBridge:
            return try await callJSONRPCTool(name: name, arguments: bridgeArguments)
        case .auto:
            do {
                return try await send(method: "POST", path: directPath, body: directBody)
            } catch {
                guard Self.isNotFound(error) else {
                    throw error
                }
                return try await callJSONRPCTool(name: name, arguments: bridgeArguments)
            }
        }
    }

    private func readResource<Response: Decodable>(uri: String, directPath: String) async throws -> Response {
        switch configuration.httpTransportPreference {
        case .directHTTP:
            return try await send(method: "GET", path: directPath)
        case .jsonRPCBridge:
            return try await readJSONRPCResource(uri: uri)
        case .auto:
            do {
                return try await send(method: "GET", path: directPath)
            } catch {
                guard Self.isNotFound(error) else {
                    throw error
                }
                return try await readJSONRPCResource(uri: uri)
            }
        }
    }

    private func initializeJSONRPCBridge() async throws -> MCPInitializeResult {
        let result: MCPInitializeResult = try await jsonRPC(
            method: "initialize",
            params: MCPInitializeParams(
                clientInfo: MCPClientInfo(
                    name: configuration.clientID,
                    version: "0"
                )
            )
        )
        try await jsonRPCNotification(method: "notifications/initialized", params: EmptyJSONRPCParams())
        return result
    }

    private func callJSONRPCTool<Arguments: Encodable, Response: Decodable>(
        name: String,
        arguments: Arguments
    ) async throws -> Response {
        let result: MCPToolCallResult<Response> = try await jsonRPC(
            method: "tools/call",
            params: MCPToolCallParams(name: name, arguments: arguments)
        )
        if result.isError {
            throw OpenMindMemoryClientError.jsonRPCError(-32000, "MCP tool \(name) returned an error.")
        }
        guard let structuredContent = result.structuredContent else {
            throw OpenMindMemoryClientError.missingJSONRPCResult("tools/call \(name)")
        }
        return structuredContent
    }

    private func readJSONRPCResource<Response: Decodable>(uri: String) async throws -> Response {
        let result: MCPResourceReadResult<Response> = try await jsonRPC(
            method: "resources/read",
            params: MCPResourceReadParams(uri: uri)
        )
        return result.resource
    }

    private func jsonRPC<Params: Encodable, Response: Decodable>(
        method: String,
        params: Params
    ) async throws -> Response {
        var request = try makeRequest(path: "/mcp")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.clientID, forHTTPHeaderField: "X-OpenMind-Claimed-Product")
        request.httpBody = try encoder.encode(
            JSONRPCRequest(
                id: 1,
                method: method,
                params: params
            )
        )
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let rpcResponse = try decoder.decode(JSONRPCResponse<Response>.self, from: data)
        if let error = rpcResponse.error {
            throw OpenMindMemoryClientError.jsonRPCError(error.code, error.message)
        }
        guard let result = rpcResponse.result else {
            throw OpenMindMemoryClientError.missingJSONRPCResult(method)
        }
        return result
    }

    private func jsonRPCNotification<Params: Encodable>(
        method: String,
        params: Params
    ) async throws {
        var request = try makeRequest(path: "/mcp")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.clientID, forHTTPHeaderField: "X-OpenMind-Claimed-Product")
        request.httpBody = try encoder.encode(
            JSONRPCRequest(
                id: nil,
                method: method,
                params: params
            )
        )
        let (_, response) = try await session.data(for: request)
        try validate(response)
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

    private static func isNotFound(_ error: Error) -> Bool {
        guard case OpenMindMemoryClientError.httpStatus(404) = error else {
            return false
        }
        return true
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.75
        configuration.timeoutIntervalForResource = 0.75
        return URLSession(configuration: configuration)
    }
}
