import Foundation

enum LLMModelProviderKind: String, Codable, Equatable, CaseIterable {
    case localMLX
    case llmRouter
    case afMarket
    case llmGateway

    var title: String {
        switch self {
        case .localMLX: "Local MLX"
        case .llmRouter: "LLM Router"
        case .afMarket: "AFMarket"
        case .llmGateway: "LLM Gateway"
        }
    }
}

enum LLMTrustBoundary: String, Codable, Equatable {
    case onDevice
    case serviceBacked
    case remoteGateway

    var title: String {
        switch self {
        case .onDevice: "On-device"
        case .serviceBacked: "Service-backed"
        case .remoteGateway: "Remote gateway"
        }
    }
}

enum LLMModelAvailabilityStatus: String, Codable, Equatable {
    case available
    case degraded
    case unavailable
}

struct LLMModelAvailability: Codable, Equatable {
    var status: LLMModelAvailabilityStatus
    var message: String

    var isRunnable: Bool {
        status == .available || status == .degraded
    }

    nonisolated init(status: LLMModelAvailabilityStatus, message: String) {
        self.status = status
        self.message = message
    }

    nonisolated static let available = LLMModelAvailability(
        status: .available,
        message: "Ready"
    )

    nonisolated static func unavailable(_ message: String) -> LLMModelAvailability {
        LLMModelAvailability(status: .unavailable, message: message)
    }

    nonisolated static func degraded(_ message: String) -> LLMModelAvailability {
        LLMModelAvailability(status: .degraded, message: message)
    }
}

struct LLMModelProfile: Equatable, Identifiable {
    var id: String
    var displayName: String
    var providerKind: LLMModelProviderKind
    var trustBoundary: LLMTrustBoundary
    var contextWindowTokens: Int
    var supportsTools: Bool
    var supportsMemoryCitations: Bool
    var runtimeMode: RuntimeBridgeMode
    var availability: LLMModelAvailability
    var detail: String

    var statusText: String {
        "\(trustBoundary.title) / \(availability.message)"
    }

    nonisolated init(
        id: String,
        displayName: String,
        providerKind: LLMModelProviderKind,
        trustBoundary: LLMTrustBoundary,
        contextWindowTokens: Int,
        supportsTools: Bool,
        supportsMemoryCitations: Bool,
        runtimeMode: RuntimeBridgeMode,
        availability: LLMModelAvailability,
        detail: String
    ) {
        self.id = id
        self.displayName = displayName
        self.providerKind = providerKind
        self.trustBoundary = trustBoundary
        self.contextWindowTokens = max(512, contextWindowTokens)
        self.supportsTools = supportsTools
        self.supportsMemoryCitations = supportsMemoryCitations
        self.runtimeMode = runtimeMode
        self.availability = availability
        self.detail = detail
    }
}

enum LLMModelRegistry {
    nonisolated static let localGemmaID = "local.gemma4-e2b-mlx"
    nonisolated static let llmRouterAppleFoundationID = "services.llm-router.apple-foundation"
    nonisolated static let afMarketRouterID = "afmarket.router"
    nonisolated static let llmGatewayID = "llm.gateway"
    nonisolated static let defaultModelID = localGemmaID

    static func models(
        afmSnapshot: AFMServiceSnapshot = .unknown,
        llmRouterSnapshot: LLMRouterServiceSnapshot = .unknown
    ) -> [LLMModelProfile] {
        let localProfile = BundledLLMSelection.recommended.profile
        let localAvailability: LLMModelAvailability = localProfile.loaderSupport.isRunnableWithCurrentSwiftLoader
            ? .available
            : .degraded(localProfile.readinessSummary)
        let afmAvailability: LLMModelAvailability = afmSnapshot.coreCopilotServicesAvailable
            ? .available
            : .unavailable(afmSnapshot.serviceStatusText)
        let routerModel = llmRouterSnapshot.model(provider: .appleFoundation)
        let routerAvailability: LLMModelAvailability = llmRouterSnapshot.isModelAvailable(provider: .appleFoundation)
            ? .available
            : .unavailable(llmRouterSnapshot.serviceStatusText)

        return [
            LLMModelProfile(
                id: localGemmaID,
                displayName: localProfile.displayName,
                providerKind: .localMLX,
                trustBoundary: .onDevice,
                contextWindowTokens: 8_192,
                supportsTools: false,
                supportsMemoryCitations: true,
                runtimeMode: .local,
                availability: localAvailability,
                detail: localProfile.readinessSummary
            ),
            LLMModelProfile(
                id: llmRouterAppleFoundationID,
                displayName: routerModel?.displayName ?? LLMRouterProvider.appleFoundation.displayName,
                providerKind: .llmRouter,
                trustBoundary: .serviceBacked,
                contextWindowTokens: routerModel?.contextWindowTokens ?? 16_384,
                supportsTools: routerModel?.supportsTools ?? true,
                supportsMemoryCitations: true,
                runtimeMode: .service,
                availability: routerAvailability,
                detail: routerModel?.detail ?? "Routes Swift conversation context through ./services/llm-router with local-first, no-egress policy."
            ),
            LLMModelProfile(
                id: afMarketRouterID,
                displayName: "AFMarket Router",
                providerKind: .afMarket,
                trustBoundary: .serviceBacked,
                contextWindowTokens: 32_768,
                supportsTools: true,
                supportsMemoryCitations: true,
                runtimeMode: .service,
                availability: afmAvailability,
                detail: "Routes conversation work through AFM router, registry, pipelines, and node evidence when available."
            ),
            LLMModelProfile(
                id: llmGatewayID,
                displayName: "LLM Gateway",
                providerKind: .llmGateway,
                trustBoundary: .remoteGateway,
                contextWindowTokens: 128_000,
                supportsTools: true,
                supportsMemoryCitations: true,
                runtimeMode: .remote,
                availability: .unavailable("No LLM Gateway endpoint is configured for the Swift runtime."),
                detail: "Reserved provider slot for a remote LLM Gateway adapter."
            )
        ]
    }

    static func model(
        withID id: String,
        afmSnapshot: AFMServiceSnapshot = .unknown,
        llmRouterSnapshot: LLMRouterServiceSnapshot = .unknown
    ) -> LLMModelProfile? {
        models(afmSnapshot: afmSnapshot, llmRouterSnapshot: llmRouterSnapshot).first { $0.id == id }
    }
}

enum LLMConversationRole: String, Codable, Equatable {
    case user
    case assistant
    case tool
    case system
}

enum LLMConversationEventKind: String, Codable, Equatable {
    case conversationCreated
    case modelSwitched
    case userMessageAdded
    case assistantRunStarted
    case assistantMessageAdded
    case pageSnapshotAttached
    case memoryContextAttached
    case contextCompressed
    case providerFallback
}

struct LLMPageSnapshotAttachment: Codable, Equatable {
    var urlString: String
    var title: String
    var textCharacterCount: Int
    var linkCount: Int
    var formControlCount: Int
    var redactionCount: Int
    var commitment: String?
    var excerpt: String

    nonisolated init(
        urlString: String,
        title: String,
        textCharacterCount: Int,
        linkCount: Int,
        formControlCount: Int,
        redactionCount: Int,
        commitment: String?,
        excerpt: String
    ) {
        self.urlString = urlString
        self.title = title
        self.textCharacterCount = textCharacterCount
        self.linkCount = linkCount
        self.formControlCount = formControlCount
        self.redactionCount = redactionCount
        self.commitment = commitment
        self.excerpt = excerpt
    }

    init(snapshot: PageSnapshot) {
        self.init(
            urlString: snapshot.urlString,
            title: snapshot.title,
            textCharacterCount: snapshot.visibleText.count,
            linkCount: snapshot.links.count,
            formControlCount: snapshot.formControls.count,
            redactionCount: snapshot.redactionCount,
            commitment: OpenMindMemoryClient.snapshotCommitment(for: snapshot),
            excerpt: SmartHistoryIndexer.boundedText(snapshot.modelContextSummary, limit: 800)
        )
    }
}

struct LLMMemoryCitation: Codable, Equatable, Identifiable {
    var id: String
    var summary: String
    var source: String
    var sensitivity: String?

    nonisolated init(id: String, summary: String, source: String, sensitivity: String?) {
        self.id = id
        self.summary = summary
        self.source = source
        self.sensitivity = sensitivity
    }

    nonisolated init(memory: OpenMindMemoryRecord) {
        self.init(
            id: memory.id,
            summary: memory.summary,
            source: memory.source,
            sensitivity: memory.sensitivity
        )
    }
}

struct LLMConversationMessage: Codable, Equatable, Identifiable {
    let id: UUID
    var role: LLMConversationRole
    var text: String
    var createdAt: Date
    var modelID: String?
    var pageURLString: String?
    var snapshotAttachment: LLMPageSnapshotAttachment?
    var memoryCitations: [LLMMemoryCitation]
    var usage: CopilotCreditUsage?
    var sourceRunID: UUID?

    nonisolated init(
        id: UUID = UUID(),
        role: LLMConversationRole,
        text: String,
        createdAt: Date = Date(),
        modelID: String? = nil,
        pageURLString: String? = nil,
        snapshotAttachment: LLMPageSnapshotAttachment? = nil,
        memoryCitations: [LLMMemoryCitation] = [],
        usage: CopilotCreditUsage? = nil,
        sourceRunID: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.modelID = modelID
        self.pageURLString = pageURLString
        self.snapshotAttachment = snapshotAttachment
        self.memoryCitations = memoryCitations
        self.usage = usage
        self.sourceRunID = sourceRunID
    }
}

struct LLMConversationEvent: Codable, Equatable, Identifiable {
    let id: UUID
    var kind: LLMConversationEventKind
    var message: String
    var timestamp: Date
    var fromModelID: String?
    var toModelID: String?
    var relatedRunID: UUID?
    var relatedMessageID: UUID?

    nonisolated init(
        id: UUID = UUID(),
        kind: LLMConversationEventKind,
        message: String,
        timestamp: Date = Date(),
        fromModelID: String? = nil,
        toModelID: String? = nil,
        relatedRunID: UUID? = nil,
        relatedMessageID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.timestamp = timestamp
        self.fromModelID = fromModelID
        self.toModelID = toModelID
        self.relatedRunID = relatedRunID
        self.relatedMessageID = relatedMessageID
    }
}

struct LLMConversation: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var messages: [LLMConversationMessage]
    var events: [LLMConversationEvent]
    var activeModelID: String
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        title: String = "New conversation",
        messages: [LLMConversationMessage] = [],
        events: [LLMConversationEvent] = [],
        activeModelID: String = LLMModelRegistry.defaultModelID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.events = events.isEmpty
            ? [
                LLMConversationEvent(
                    kind: .conversationCreated,
                    message: "Conversation started with \(activeModelID).",
                    toModelID: activeModelID
                )
            ]
            : events
        self.activeModelID = activeModelID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var latestAssistantMessage: LLMConversationMessage? {
        messages.last { $0.role == .assistant }
    }

    mutating func appendMessage(_ message: LLMConversationMessage) {
        messages.append(message)
        if title == "New conversation", message.role == .user {
            title = SmartHistoryIndexer.boundedText(message.text, limit: 64)
        }
        updatedAt = Date()
    }

    mutating func appendEvent(_ event: LLMConversationEvent) {
        events.append(event)
        updatedAt = Date()
    }

    mutating func switchModel(to modelID: String, displayName: String) {
        guard activeModelID != modelID else { return }
        let previous = activeModelID
        activeModelID = modelID
        appendEvent(
            LLMConversationEvent(
                kind: .modelSwitched,
                message: "Switched model from \(previous) to \(displayName).",
                fromModelID: previous,
                toModelID: modelID
            )
        )
    }
}

struct LLMConversationStorePayload: Codable, Equatable {
    var conversation: LLMConversation
    var selectedModelID: String

    nonisolated init(
        conversation: LLMConversation = LLMConversation(activeModelID: LLMModelRegistry.defaultModelID),
        selectedModelID: String = LLMModelRegistry.defaultModelID
    ) {
        self.conversation = conversation
        self.selectedModelID = selectedModelID
    }
}

final class LLMConversationStore {
    private let fileURL: URL?
    private var memoryPayload: LLMConversationStorePayload
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    nonisolated init(
        fileURL: URL? = LLMConversationStore.defaultFileURL(),
        seed: LLMConversationStorePayload = LLMConversationStorePayload()
    ) {
        self.fileURL = fileURL
        self.memoryPayload = seed
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    nonisolated static func ephemeral(seed: LLMConversationStorePayload = LLMConversationStorePayload()) -> LLMConversationStore {
        LLMConversationStore(fileURL: nil, seed: seed)
    }

    func load() -> LLMConversationStorePayload {
        guard let fileURL else { return memoryPayload }
        guard let data = try? Data(contentsOf: fileURL) else {
            return LLMConversationStorePayload()
        }
        return (try? decoder.decode(LLMConversationStorePayload.self, from: data)) ?? LLMConversationStorePayload()
    }

    func save(_ payload: LLMConversationStorePayload) {
        guard let fileURL else {
            memoryPayload = payload
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save LLM conversation: \(error.localizedDescription)")
        }
    }

    nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dBrowser", isDirectory: true)
            .appendingPathComponent("llm-conversation.json")
    }
}

struct LLMRenderedConversationContext: Codable, Equatable {
    var prompt: String
    var includedMessageIDs: [UUID]
    var compressedMessageIDs: [UUID]
    var estimatedPromptTokens: Int
    var wasCompressed: Bool
    var snapshotCommitment: String?
    var memoryContextIDs: [String]

    nonisolated init(
        prompt: String,
        includedMessageIDs: [UUID],
        compressedMessageIDs: [UUID],
        estimatedPromptTokens: Int,
        wasCompressed: Bool,
        snapshotCommitment: String?,
        memoryContextIDs: [String]
    ) {
        self.prompt = prompt
        self.includedMessageIDs = includedMessageIDs
        self.compressedMessageIDs = compressedMessageIDs
        self.estimatedPromptTokens = estimatedPromptTokens
        self.wasCompressed = wasCompressed
        self.snapshotCommitment = snapshotCommitment
        self.memoryContextIDs = memoryContextIDs
    }
}

@MainActor
enum LLMConversationContextRenderer {
    static func render(
        conversation: LLMConversation,
        model: LLMModelProfile,
        latestPageSnapshot: PageSnapshot?,
        memoryRecall: OpenMindMemoryRecallResult? = nil
    ) -> LLMRenderedConversationContext {
        let memoryCitations = memoryRecall?.memories.map(LLMMemoryCitation.init(memory:)) ?? []
        let snapshotAttachment = latestPageSnapshot.map(LLMPageSnapshotAttachment.init(snapshot:))
        let switchEvents = conversation.events
            .filter { $0.kind == .modelSwitched }
            .suffix(4)
            .map { "- \($0.message)" }
            .joined(separator: "\n")
        var renderedMessages = conversation.messages.map(renderMessage)
        var compressedMessages: [(id: UUID, text: String)] = []
        let tokenBudget = max(256, model.contextWindowTokens - 512)

        while estimatedTokens(for: prompt(
            model: model,
            switchEvents: switchEvents,
            compressedSummary: compressedSummary(for: compressedMessages),
            renderedMessages: renderedMessages.map(\.text),
            snapshotAttachment: snapshotAttachment,
            memoryCitations: memoryCitations
        )) > tokenBudget, renderedMessages.count > 2 {
            compressedMessages.append(renderedMessages.removeFirst())
        }

        let renderedPrompt = prompt(
            model: model,
            switchEvents: switchEvents,
            compressedSummary: compressedSummary(for: compressedMessages),
            renderedMessages: renderedMessages.map(\.text),
            snapshotAttachment: snapshotAttachment,
            memoryCitations: memoryCitations
        )

        return LLMRenderedConversationContext(
            prompt: renderedPrompt,
            includedMessageIDs: renderedMessages.map(\.id),
            compressedMessageIDs: compressedMessages.map(\.id),
            estimatedPromptTokens: estimatedTokens(for: renderedPrompt),
            wasCompressed: !compressedMessages.isEmpty,
            snapshotCommitment: snapshotAttachment?.commitment,
            memoryContextIDs: memoryCitations.map(\.id)
        )
    }

    private static func renderMessage(_ message: LLMConversationMessage) -> (id: UUID, text: String) {
        var lines = ["\(message.role.rawValue.uppercased()): \(message.text)"]
        if let modelID = message.modelID {
            lines.append("model: \(modelID)")
        }
        if let pageURLString = message.pageURLString {
            lines.append("page: \(pageURLString)")
        }
        if let attachment = message.snapshotAttachment {
            lines.append("snapshot: \(attachment.title) \(attachment.commitment ?? "uncommitted")")
        }
        if !message.memoryCitations.isEmpty {
            lines.append("memory citations: \(message.memoryCitations.map(\.id).joined(separator: ", "))")
        }
        return (message.id, lines.joined(separator: "\n"))
    }

    private static func prompt(
        model: LLMModelProfile,
        switchEvents: String,
        compressedSummary: String?,
        renderedMessages: [String],
        snapshotAttachment: LLMPageSnapshotAttachment?,
        memoryCitations: [LLMMemoryCitation]
    ) -> String {
        var sections = [
            "Active model: \(model.displayName) (\(model.providerKind.title), \(model.trustBoundary.title)).",
            "Use the canonical conversation ledger below. Do not assume hidden context."
        ]
        if !switchEvents.isEmpty {
            sections.append("Model switch events:\n\(switchEvents)")
        }
        if let compressedSummary {
            sections.append(compressedSummary)
        }
        if let snapshotAttachment {
            sections.append(
                """
                Active page snapshot:
                URL: \(snapshotAttachment.urlString)
                Title: \(snapshotAttachment.title)
                Commitment: \(snapshotAttachment.commitment ?? "uncommitted")
                Excerpt: \(snapshotAttachment.excerpt)
                """
            )
        }
        if !memoryCitations.isEmpty {
            let memories = memoryCitations
                .map { "- \($0.id) [\($0.source)]: \($0.summary)" }
                .joined(separator: "\n")
            sections.append("Approved memory citations:\n\(memories)")
        }
        sections.append("Conversation messages:\n\(renderedMessages.joined(separator: "\n\n"))")
        return sections.joined(separator: "\n\n")
    }

    private static func compressedSummary(for messages: [(id: UUID, text: String)]) -> String? {
        guard !messages.isEmpty else { return nil }
        let summary = messages
            .map(\.text)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "Compressed prior context (\(messages.count) message\(messages.count == 1 ? "" : "s")):\n\(SmartHistoryIndexer.boundedText(summary, limit: 1_200))"
    }

    static func estimatedTokens(for text: String) -> Int {
        max(1, (text.count + 3) / 4)
    }
}
