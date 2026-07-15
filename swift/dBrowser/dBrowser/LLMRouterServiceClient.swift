import Foundation

enum LLMRouterProvider: String, Codable, Equatable, CaseIterable, Sendable {
    case appleFoundation = "apple_foundation"

    nonisolated var modelID: String {
        switch self {
        case .appleFoundation: "apple.foundation"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .appleFoundation: "Apple Foundation via LLM Router"
        }
    }
}

struct LLMRouterStreamingConfiguration: Equatable, Sendable {
    var primaryPath: String
    var fallbackPath: String?
    var maximumLineBytes: Int
    var maximumResponseBytes: Int
    var maximumErrorBytes: Int
    var maximumAssembledTextBytes: Int
    var maximumEvents: Int
    var maximumBufferedEvents: Int
    var maximumToolCalls: Int

    nonisolated init(
        primaryPath: String = "/v1/complete/stream",
        fallbackPath: String? = "/complete/stream",
        maximumLineBytes: Int = 256 * 1_024,
        maximumResponseBytes: Int = 8 * 1_024 * 1_024,
        maximumErrorBytes: Int = 16 * 1_024,
        maximumAssembledTextBytes: Int = 4 * 1_024 * 1_024,
        maximumEvents: Int = 10_000,
        maximumBufferedEvents: Int = 64,
        maximumToolCalls: Int = 64
    ) {
        self.primaryPath = primaryPath
        self.fallbackPath = fallbackPath
        self.maximumLineBytes = max(1, maximumLineBytes)
        self.maximumResponseBytes = max(1, maximumResponseBytes)
        self.maximumErrorBytes = max(1, maximumErrorBytes)
        self.maximumAssembledTextBytes = max(1, maximumAssembledTextBytes)
        self.maximumEvents = max(1, maximumEvents)
        self.maximumBufferedEvents = max(1, maximumBufferedEvents)
        self.maximumToolCalls = max(1, maximumToolCalls)
    }

    nonisolated static let standard = LLMRouterStreamingConfiguration()
}

struct LLMRouterEndpointConfiguration: Equatable, Sendable {
    var baseURL: URL?
    var provider: LLMRouterProvider
    var preferLocal: Bool
    var noEgress: Bool
    var streaming: LLMRouterStreamingConfiguration

    nonisolated init(
        baseURL: URL?,
        provider: LLMRouterProvider,
        preferLocal: Bool,
        noEgress: Bool,
        streaming: LLMRouterStreamingConfiguration = .standard
    ) {
        self.baseURL = baseURL
        self.provider = provider
        self.preferLocal = preferLocal
        self.noEgress = noEgress
        self.streaming = streaming
    }

    nonisolated static let local = LLMRouterEndpointConfiguration(
        baseURL: URL(string: "http://127.0.0.1:4850")!,
        provider: .appleFoundation,
        preferLocal: true,
        noEgress: true
    )

    nonisolated static let disabled = LLMRouterEndpointConfiguration(
        baseURL: nil,
        provider: .appleFoundation,
        preferLocal: true,
        noEgress: true
    )
}

struct LLMRouterModelDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var provider: LLMRouterProvider
    var displayName: String
    var contextWindowTokens: Int?
    var supportsTools: Bool
    var available: Bool
    var detail: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case displayName
        case display_name
        case name
        case contextWindowTokens
        case context_window_tokens
        case supportsTools
        case supports_tools
        case available
        case detail
        case status
    }

    nonisolated init(
        id: String,
        provider: LLMRouterProvider,
        displayName: String,
        contextWindowTokens: Int?,
        supportsTools: Bool,
        available: Bool,
        detail: String?
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.contextWindowTokens = contextWindowTokens
        self.supportsTools = supportsTools
        self.available = available
        self.detail = detail
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(LLMRouterProvider.self, forKey: .provider)?.modelID
            ?? LLMRouterProvider.appleFoundation.modelID
        self.provider = try container.decodeIfPresent(LLMRouterProvider.self, forKey: .provider)
            ?? .appleFoundation
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .display_name)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? provider.displayName
        self.contextWindowTokens = try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .context_window_tokens)
        self.supportsTools = try container.decodeIfPresent(Bool.self, forKey: .supportsTools)
            ?? container.decodeIfPresent(Bool.self, forKey: .supports_tools)
            ?? true
        self.available = try container.decodeIfPresent(Bool.self, forKey: .available)
            ?? ((try? container.decode(String.self, forKey: .status)) == "available")
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(contextWindowTokens, forKey: .contextWindowTokens)
        try container.encode(supportsTools, forKey: .supportsTools)
        try container.encode(available, forKey: .available)
        try container.encodeIfPresent(detail, forKey: .detail)
    }
}

struct LLMRouterServiceSnapshot: Equatable {
    var serviceAvailable: Bool
    var localAvailable: Bool
    var models: [LLMRouterModelDescriptor]
    var message: String

    nonisolated static let disabled = LLMRouterServiceSnapshot(
        serviceAvailable: false,
        localAvailable: false,
        models: [],
        message: "LLM router endpoint is not configured."
    )

    nonisolated static let unknown = LLMRouterServiceSnapshot(
        serviceAvailable: true,
        localAvailable: true,
        models: [],
        message: "LLM router pending health check."
    )

    func model(provider: LLMRouterProvider) -> LLMRouterModelDescriptor? {
        models.first { $0.provider == provider || $0.id == provider.modelID }
    }

    func isModelAvailable(provider: LLMRouterProvider) -> Bool {
        guard serviceAvailable else { return false }
        if let model = model(provider: provider) {
            return model.available
        }
        return localAvailable && provider == .appleFoundation
    }

    var serviceStatusText: String {
        serviceAvailable ? message : "offline: \(message)"
    }
}

struct LLMRouterRoutingPolicy: Codable, Equatable {
    var preferLocal: Bool
    var noEgress: Bool
    var forceProvider: LLMRouterProvider?

    private enum CodingKeys: String, CodingKey {
        case preferLocal = "prefer_local"
        case noEgress = "no_egress"
        case forceProvider = "force_provider"
    }
}

struct LLMRouterCompletionOptions: Codable, Equatable {
    var temperature: Double
    var maxTokens: Int
    var systemPrompt: String?

    private enum CodingKeys: String, CodingKey {
        case temperature
        case maxTokens = "max_tokens"
        case systemPrompt = "system_prompt"
    }
}

struct LLMRouterCompletionContext: Codable, Equatable {
    var conversationID: UUID?
    var runID: UUID?
    var pageURLString: String?
    var snapshotCommitment: String?
    var memoryContextIDs: [String]
    var estimatedPromptTokens: Int?
    var includedMessageIDs: [UUID]
    var compressedMessageIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case runID = "run_id"
        case pageURLString = "page_url"
        case snapshotCommitment = "snapshot_commitment"
        case memoryContextIDs = "memory_context_ids"
        case estimatedPromptTokens = "estimated_prompt_tokens"
        case includedMessageIDs = "included_message_ids"
        case compressedMessageIDs = "compressed_message_ids"
    }
}

struct LLMRouterCompletionRequest: Codable, Equatable {
    var prompt: String
    var modelID: String
    var policy: LLMRouterRoutingPolicy
    var options: LLMRouterCompletionOptions
    var context: LLMRouterCompletionContext
    var stream: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case prompt
        case modelID = "model_id"
        case policy
        case options
        case context
        case stream
    }
}

struct LLMRouterUsage: Codable, Equatable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens
        case prompt_tokens
        case completionTokens
        case completion_tokens
        case totalTokens
        case total_tokens
    }

    nonisolated init(promptTokens: Int?, completionTokens: Int?, totalTokens: Int?) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .prompt_tokens)
        self.completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .completion_tokens)
        self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .total_tokens)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(promptTokens, forKey: .prompt_tokens)
        try container.encodeIfPresent(completionTokens, forKey: .completion_tokens)
        try container.encodeIfPresent(totalTokens, forKey: .total_tokens)
    }
}

struct LLMRouterToolCall: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var arguments: [String: String]
    var approvalRequired: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case arguments
        case approvalRequired
        case approval_required
    }

    nonisolated init(id: String, name: String, arguments: [String: String], approvalRequired: Bool) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.approvalRequired = approvalRequired
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? name
        self.arguments = try container.decodeIfPresent([String: String].self, forKey: .arguments) ?? [:]
        self.approvalRequired = try container.decodeIfPresent(Bool.self, forKey: .approvalRequired)
            ?? container.decodeIfPresent(Bool.self, forKey: .approval_required)
            ?? true
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(approvalRequired, forKey: .approval_required)
    }
}

struct LLMRouterCompletionResponse: Codable, Equatable, Sendable {
    var text: String
    var provider: LLMRouterProvider
    var modelID: String
    var usage: LLMRouterUsage?
    var toolCalls: [LLMRouterToolCall]
    var route: String?

    private enum CodingKeys: String, CodingKey {
        case text
        case content
        case provider
        case modelID
        case model_id
        case usage
        case toolCalls
        case tool_calls
        case route
    }

    nonisolated init(
        text: String,
        provider: LLMRouterProvider,
        modelID: String,
        usage: LLMRouterUsage?,
        toolCalls: [LLMRouterToolCall],
        route: String?
    ) {
        self.text = text
        self.provider = provider
        self.modelID = modelID
        self.usage = usage
        self.toolCalls = toolCalls
        self.route = route
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decode(String.self, forKey: .content)
        self.provider = try container.decodeIfPresent(LLMRouterProvider.self, forKey: .provider)
            ?? .appleFoundation
        self.modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
            ?? container.decodeIfPresent(String.self, forKey: .model_id)
            ?? provider.modelID
        self.usage = try container.decodeIfPresent(LLMRouterUsage.self, forKey: .usage)
        self.toolCalls = try container.decodeIfPresent([LLMRouterToolCall].self, forKey: .toolCalls)
            ?? container.decodeIfPresent([LLMRouterToolCall].self, forKey: .tool_calls)
            ?? []
        self.route = try container.decodeIfPresent(String.self, forKey: .route)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(provider, forKey: .provider)
        try container.encode(modelID, forKey: .model_id)
        try container.encodeIfPresent(usage, forKey: .usage)
        try container.encode(toolCalls, forKey: .tool_calls)
        try container.encodeIfPresent(route, forKey: .route)
    }
}

enum LLMRouterStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case completed(LLMRouterCompletionResponse)
    case bufferedCompleted(LLMRouterCompletionResponse)
}

enum LLMRouterServiceClientError: Error, Equatable, LocalizedError, Sendable {
    case disabled
    case invalidResponse
    case unsupportedStreaming
    case invalidStreamingContentType(String?)
    case httpStatus(Int, String?)
    case streamLimitExceeded(String)
    case malformedStreamEvent
    case streamServerError(String)
    case missingTerminalResponse
    case consumerTooSlow

    var errorDescription: String? {
        switch self {
        case .disabled: "LLM router endpoint is not configured."
        case .invalidResponse: "LLM router returned an invalid response."
        case .unsupportedStreaming:
            "LLM router does not expose a supported streaming transport."
        case .invalidStreamingContentType(let contentType):
            "LLM router returned unsupported streaming content type \(contentType ?? "without a Content-Type header")."
        case .httpStatus(let status, let message):
            message.map { "LLM router stream returned HTTP \(status): \($0)" }
                ?? "LLM router stream returned HTTP \(status)."
        case .streamLimitExceeded(let limit):
            "LLM router stream exceeded the \(limit) limit."
        case .malformedStreamEvent:
            "LLM router returned a malformed streaming event."
        case .streamServerError(let message):
            "LLM router stream failed: \(message)"
        case .missingTerminalResponse:
            "LLM router stream ended without a terminal response."
        case .consumerTooSlow:
            "LLM router stream consumer could not keep up with bounded buffering."
        }
    }
}

final class LLMRouterServiceClient {
    private struct HealthResponse: Decodable {
        var ok: Bool
        var localAvailable: Bool?
        var message: String?

        private enum CodingKeys: String, CodingKey {
            case ok
            case localAvailable
            case local_available
            case message
            case status
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
            self.localAvailable = try container.decodeIfPresent(Bool.self, forKey: .localAvailable)
                ?? container.decodeIfPresent(Bool.self, forKey: .local_available)
            self.message = try container.decodeIfPresent(String.self, forKey: .message)
                ?? container.decodeIfPresent(String.self, forKey: .status)
        }
    }

    private struct ModelsResponse: Decodable {
        var data: [LLMRouterModelDescriptor]

        private enum CodingKeys: String, CodingKey {
            case data
            case models
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.data = try container.decodeIfPresent([LLMRouterModelDescriptor].self, forKey: .data)
                ?? container.decodeIfPresent([LLMRouterModelDescriptor].self, forKey: .models)
                ?? []
        }
    }

    private let configuration: LLMRouterEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: LLMRouterEndpointConfiguration = .local,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> LLMRouterServiceSnapshot {
        guard configuration.baseURL != nil else {
            return .disabled
        }

        do {
            let resolvedHealth: HealthResponse = try await get(path: "/health")
            let resolvedModels = await optionalModels()
            let localAvailable = resolvedHealth.localAvailable
                ?? resolvedModels.contains { $0.provider == configuration.provider && $0.available }
            return LLMRouterServiceSnapshot(
                serviceAvailable: resolvedHealth.ok,
                localAvailable: localAvailable,
                models: resolvedModels,
                message: resolvedHealth.message ?? "LLM router online"
            )
        } catch {
            return LLMRouterServiceSnapshot(
                serviceAvailable: false,
                localAvailable: false,
                models: [],
                message: error.localizedDescription
            )
        }
    }

    func complete(_ request: LLMRouterCompletionRequest) async throws -> LLMRouterCompletionResponse {
        do {
            return try await postCompletion(path: "/v1/complete", body: request)
        } catch LLMRouterServiceClientError.httpStatus(let status, _)
            where Self.unsupportedStreamingStatusCodes.contains(status) {
            return try await postCompletion(path: "/complete", body: request)
        }
    }

    /// Opens a real router transport stream. The sequence yields only deltas
    /// received from SSE or NDJSON and one terminal, fully assembled response.
    /// A successful buffered JSON response is surfaced as one buffered terminal
    /// event; it is never split into synthetic chunks or retried.
    func streamCompletion(
        _ request: LLMRouterCompletionRequest
    ) -> AsyncThrowingStream<LLMRouterStreamEvent, Error> {
        let streamingConfiguration = configuration.streaming
        return AsyncThrowingStream(
            bufferingPolicy: .bufferingOldest(streamingConfiguration.maximumBufferedEvents)
        ) { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                do {
                    try await performStreamingCompletion(
                        request,
                        configuration: streamingConfiguration,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func completionRequest(
        prompt: String,
        conversationID: UUID?,
        runID: UUID?,
        preferredModelID: String?,
        pageURLString: String?,
        renderedContext: LLMRenderedConversationContext?,
        memoryRecall: OpenMindMemoryRecallResult?
    ) -> LLMRouterCompletionRequest {
        LLMRouterCompletionRequest(
            prompt: renderedContext?.prompt ?? prompt,
            modelID: configuration.provider.modelID,
            policy: LLMRouterRoutingPolicy(
                preferLocal: configuration.preferLocal,
                noEgress: configuration.noEgress,
                forceProvider: configuration.provider
            ),
            options: LLMRouterCompletionOptions(
                temperature: 0.6,
                maxTokens: LLMConversationContextRenderer.routerMaximumOutputTokens,
                systemPrompt: LLMConversationContextRenderer.routerCompletionSystemPrompt
            ),
            context: LLMRouterCompletionContext(
                conversationID: conversationID,
                runID: runID,
                pageURLString: pageURLString,
                snapshotCommitment: renderedContext?.snapshotCommitment,
                memoryContextIDs: renderedContext.map {
                    LLMMemoryContextPolicy.boundedIDs(from: $0.memoryContextIDs)
                }
                    ?? memoryRecall.map { LLMMemoryContextPolicy.boundedIDs(from: $0.memories) }
                    ?? [],
                estimatedPromptTokens: renderedContext?.estimatedPromptTokens,
                includedMessageIDs: renderedContext?.includedMessageIDs ?? [],
                compressedMessageIDs: renderedContext?.compressedMessageIDs ?? []
            )
        )
    }

    private enum StreamingWireFormat {
        case serverSentEvents
        case newlineDelimitedJSON
        case bufferedJSON
    }

    private struct StreamPayload {
        var deltaText: String?
        var terminalText: String?
        var provider: LLMRouterProvider?
        var modelID: String?
        var usage: LLMRouterUsage?
        var toolCalls: [LLMRouterToolCall]?
        var route: String?
        var response: LLMRouterCompletionResponse?
        var errorMessage: String?
        var isTerminal: Bool
    }

    private struct StreamAccumulator {
        var text = ""
        var textBytes = 0
        var provider: LLMRouterProvider
        var modelID: String
        var usage: LLMRouterUsage?
        var toolCalls: [LLMRouterToolCall] = []
        var route: String?
        var eventCount = 0

        mutating func recordEvent(limit: Int) throws {
            eventCount += 1
            guard eventCount <= limit else {
                throw LLMRouterServiceClientError.streamLimitExceeded("event count")
            }
        }

        mutating func appendText(_ delta: String, byteLimit: Int) throws {
            let deltaBytes = delta.utf8.count
            guard deltaBytes <= byteLimit, textBytes <= byteLimit - deltaBytes else {
                throw LLMRouterServiceClientError.streamLimitExceeded("assembled text")
            }
            text.append(delta)
            textBytes += deltaBytes
        }

        mutating func replaceText(_ replacement: String, byteLimit: Int) throws {
            let byteCount = replacement.utf8.count
            guard byteCount <= byteLimit else {
                throw LLMRouterServiceClientError.streamLimitExceeded("assembled text")
            }
            text = replacement
            textBytes = byteCount
        }

        mutating func absorb(
            _ payload: StreamPayload,
            configuration: LLMRouterStreamingConfiguration
        ) throws {
            if let response = payload.response {
                provider = response.provider
                try setModelID(response.modelID)
                mergeUsage(response.usage)
                try mergeToolCalls(response.toolCalls, configuration: configuration)
                if let responseRoute = response.route {
                    try setRoute(responseRoute)
                }
            }
            if let payloadProvider = payload.provider {
                provider = payloadProvider
            }
            if let payloadModelID = payload.modelID {
                try setModelID(payloadModelID)
            }
            mergeUsage(payload.usage)
            if let payloadToolCalls = payload.toolCalls {
                try mergeToolCalls(payloadToolCalls, configuration: configuration)
            }
            if let payloadRoute = payload.route {
                try setRoute(payloadRoute)
            }
        }

        func response() -> LLMRouterCompletionResponse {
            LLMRouterCompletionResponse(
                text: text,
                provider: provider,
                modelID: modelID,
                usage: usage,
                toolCalls: toolCalls,
                route: route
            )
        }

        private mutating func mergeUsage(_ newUsage: LLMRouterUsage?) {
            guard let newUsage else { return }
            usage = LLMRouterUsage(
                promptTokens: newUsage.promptTokens ?? usage?.promptTokens,
                completionTokens: newUsage.completionTokens ?? usage?.completionTokens,
                totalTokens: newUsage.totalTokens ?? usage?.totalTokens
            )
        }

        private mutating func setModelID(_ value: String) throws {
            guard !value.isEmpty, value.utf8.count <= 512 else {
                throw LLMRouterServiceClientError.streamLimitExceeded("model identifier")
            }
            modelID = value
        }

        private mutating func setRoute(_ value: String) throws {
            guard value.utf8.count <= 2_048 else {
                throw LLMRouterServiceClientError.streamLimitExceeded("route metadata")
            }
            route = value
        }

        private mutating func mergeToolCalls(
            _ calls: [LLMRouterToolCall],
            configuration: LLMRouterStreamingConfiguration
        ) throws {
            for call in calls {
                guard
                    !call.id.isEmpty,
                    !call.name.isEmpty,
                    call.id.utf8.count <= 512,
                    call.name.utf8.count <= 512,
                    call.arguments.count <= 64,
                    call.arguments.allSatisfy({ key, value in
                        !key.isEmpty && key.utf8.count <= 256 && value.utf8.count <= 8_192
                    })
                else {
                    throw LLMRouterServiceClientError.malformedStreamEvent
                }
                if let index = toolCalls.firstIndex(where: { $0.id == call.id }) {
                    toolCalls[index] = call
                } else {
                    guard toolCalls.count < configuration.maximumToolCalls else {
                        throw LLMRouterServiceClientError.streamLimitExceeded("tool call count")
                    }
                    toolCalls.append(call)
                }
            }
        }
    }

    private func performStreamingCompletion(
        _ request: LLMRouterCompletionRequest,
        configuration: LLMRouterStreamingConfiguration,
        continuation: AsyncThrowingStream<LLMRouterStreamEvent, Error>.Continuation
    ) async throws {
        var streamingRequest = request
        streamingRequest.stream = true
        do {
            try await consumeStreamingResponse(
                path: configuration.primaryPath,
                request: streamingRequest,
                configuration: configuration,
                continuation: continuation
            )
        } catch LLMRouterServiceClientError.unsupportedStreaming {
            guard
                let fallbackPath = configuration.fallbackPath,
                fallbackPath != configuration.primaryPath
            else {
                throw LLMRouterServiceClientError.unsupportedStreaming
            }
            try await consumeStreamingResponse(
                path: fallbackPath,
                request: streamingRequest,
                configuration: configuration,
                continuation: continuation
            )
        }
    }

    private func consumeStreamingResponse(
        path: String,
        request body: LLMRouterCompletionRequest,
        configuration: LLMRouterStreamingConfiguration,
        continuation: AsyncThrowingStream<LLMRouterStreamEvent, Error>.Continuation
    ) async throws {
        let (bytes, format) = try await openStreamingResponse(
            path: path,
            body: body,
            configuration: configuration
        )
        var accumulator = StreamAccumulator(
            provider: configurationProvider,
            modelID: body.modelID
        )
        switch format {
        case .serverSentEvents:
            try await consumeServerSentEvents(
                bytes,
                accumulator: &accumulator,
                configuration: configuration,
                continuation: continuation
            )
        case .newlineDelimitedJSON:
            try await consumeNewlineDelimitedJSON(
                bytes,
                accumulator: &accumulator,
                configuration: configuration,
                continuation: continuation
            )
        case .bufferedJSON:
            try await consumeBufferedJSON(
                bytes,
                accumulator: &accumulator,
                configuration: configuration,
                continuation: continuation
            )
        }
    }

    private var configurationProvider: LLMRouterProvider {
        configuration.provider
    }

    private func openStreamingResponse(
        path: String,
        body: LLMRouterCompletionRequest,
        configuration: LLMRouterStreamingConfiguration
    ) async throws -> (URLSession.AsyncBytes, StreamingWireFormat) {
        guard let baseURL = self.configuration.baseURL else {
            throw LLMRouterServiceClientError.disabled
        }
        guard Self.isValidStreamingPath(path) else {
            throw LLMRouterServiceClientError.invalidResponse
        }
        var request = URLRequest(url: Self.url(baseURL: baseURL, path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "text/event-stream, application/x-ndjson, application/ndjson",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try encoder.encode(body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMRouterServiceClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if Self.unsupportedStreamingStatusCodes.contains(http.statusCode) {
                throw LLMRouterServiceClientError.unsupportedStreaming
            }
            let message = try await boundedErrorMessage(
                from: bytes,
                limit: configuration.maximumErrorBytes
            )
            throw LLMRouterServiceClientError.httpStatus(http.statusCode, message)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        let mimeType = contentType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch mimeType {
        case "text/event-stream":
            return (bytes, .serverSentEvents)
        case "application/x-ndjson", "application/ndjson":
            return (bytes, .newlineDelimitedJSON)
        case "application/json":
            return (bytes, .bufferedJSON)
        case let value? where value.hasSuffix("+json"):
            return (bytes, .bufferedJSON)
        default:
            throw LLMRouterServiceClientError.invalidStreamingContentType(contentType)
        }
    }

    private func consumeServerSentEvents(
        _ bytes: URLSession.AsyncBytes,
        accumulator: inout StreamAccumulator,
        configuration: LLMRouterStreamingConfiguration,
        continuation: AsyncThrowingStream<LLMRouterStreamEvent, Error>.Continuation
    ) async throws {
        var eventName: String?
        var dataLines: [String] = []
        var eventDataBytes = 0

        func dispatchEvent() throws -> Bool {
            guard !dataLines.isEmpty || eventName != nil else { return false }
            let data = dataLines.joined(separator: "\n")
            let name = eventName
            dataLines.removeAll(keepingCapacity: true)
            eventName = nil
            eventDataBytes = 0
            return try processStreamPayload(
                data,
                eventName: name,
                accumulator: &accumulator,
                configuration: configuration,
                continuation: continuation
            )
        }

        let reachedTerminal = try await consumeLines(bytes, configuration: configuration) { line in
            if line.isEmpty {
                return try dispatchEvent()
            }
            if line.first == ":" {
                return false
            }
            let field: Substring
            var value: Substring
            if let colon = line.firstIndex(of: ":") {
                field = line[..<colon]
                value = line[line.index(after: colon)...]
                if value.first == " " {
                    value = value.dropFirst()
                }
            } else {
                field = Substring(line)
                value = ""
            }
            switch field {
            case "event":
                eventName = String(value)
            case "data":
                eventDataBytes += value.utf8.count + (dataLines.isEmpty ? 0 : 1)
                guard eventDataBytes <= configuration.maximumLineBytes else {
                    throw LLMRouterServiceClientError.streamLimitExceeded("event buffer")
                }
                dataLines.append(String(value))
            case "id", "retry":
                break
            default:
                break
            }
            return false
        }
        if reachedTerminal { return }
        if try dispatchEvent() { return }
        throw LLMRouterServiceClientError.missingTerminalResponse
    }

    private func consumeNewlineDelimitedJSON(
        _ bytes: URLSession.AsyncBytes,
        accumulator: inout StreamAccumulator,
        configuration: LLMRouterStreamingConfiguration,
        continuation: AsyncThrowingStream<LLMRouterStreamEvent, Error>.Continuation
    ) async throws {
        let reachedTerminal = try await consumeLines(bytes, configuration: configuration) { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return try processStreamPayload(
                line,
                eventName: nil,
                accumulator: &accumulator,
                configuration: configuration,
                continuation: continuation
            )
        }
        guard reachedTerminal else {
            throw LLMRouterServiceClientError.missingTerminalResponse
        }
    }

    private func consumeBufferedJSON(
        _ bytes: URLSession.AsyncBytes,
        accumulator: inout StreamAccumulator,
        configuration: LLMRouterStreamingConfiguration,
        continuation: AsyncThrowingStream<LLMRouterStreamEvent, Error>.Continuation
    ) async throws {
        var data = Data()
        data.reserveCapacity(min(configuration.maximumResponseBytes, 64 * 1_024))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < configuration.maximumResponseBytes else {
                throw LLMRouterServiceClientError.streamLimitExceeded("response byte")
            }
            data.append(byte)
        }
        let response: LLMRouterCompletionResponse
        do {
            response = try decoder.decode(LLMRouterCompletionResponse.self, from: data)
        } catch {
            throw LLMRouterServiceClientError.malformedStreamEvent
        }
        let normalized = try normalizeTerminalResponse(
            response,
            accumulator: &accumulator,
            configuration: configuration
        )
        try yield(.bufferedCompleted(normalized), to: continuation)
    }

    private func normalizeTerminalResponse(
        _ response: LLMRouterCompletionResponse,
        accumulator: inout StreamAccumulator,
        configuration: LLMRouterStreamingConfiguration
    ) throws -> LLMRouterCompletionResponse {
        try accumulator.recordEvent(limit: configuration.maximumEvents)
        try accumulator.absorb(
            StreamPayload(
                deltaText: nil,
                terminalText: response.text,
                provider: nil,
                modelID: nil,
                usage: nil,
                toolCalls: nil,
                route: nil,
                response: response,
                errorMessage: nil,
                isTerminal: true
            ),
            configuration: configuration
        )
        try accumulator.replaceText(
            response.text,
            byteLimit: configuration.maximumAssembledTextBytes
        )
        return accumulator.response()
    }

    private func consumeLines(
        _ bytes: URLSession.AsyncBytes,
        configuration: LLMRouterStreamingConfiguration,
        onLine: (String) throws -> Bool
    ) async throws -> Bool {
        var totalBytes = 0
        var line = Data()
        var previousByteWasCarriageReturn = false
        var isFirstLine = true

        func emitLine() throws -> Bool {
            guard var decoded = String(data: line, encoding: .utf8) else {
                throw LLMRouterServiceClientError.malformedStreamEvent
            }
            line.removeAll(keepingCapacity: true)
            if isFirstLine {
                isFirstLine = false
                if decoded.hasPrefix("\u{feff}") {
                    decoded.removeFirst()
                }
            }
            return try onLine(decoded)
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            totalBytes += 1
            guard totalBytes <= configuration.maximumResponseBytes else {
                throw LLMRouterServiceClientError.streamLimitExceeded("response byte")
            }

            if previousByteWasCarriageReturn {
                previousByteWasCarriageReturn = false
                if byte == 0x0A {
                    continue
                }
            }
            if byte == 0x0D {
                if try emitLine() { return true }
                previousByteWasCarriageReturn = true
            } else if byte == 0x0A {
                if try emitLine() { return true }
            } else {
                line.append(byte)
                guard line.count <= configuration.maximumLineBytes else {
                    throw LLMRouterServiceClientError.streamLimitExceeded("line buffer")
                }
            }
        }
        try Task.checkCancellation()
        if !line.isEmpty {
            return try emitLine()
        }
        return false
    }

    private func processStreamPayload(
        _ rawPayload: String,
        eventName: String?,
        accumulator: inout StreamAccumulator,
        configuration: LLMRouterStreamingConfiguration,
        continuation: AsyncThrowingStream<LLMRouterStreamEvent, Error>.Continuation
    ) throws -> Bool {
        try accumulator.recordEvent(limit: configuration.maximumEvents)
        let trimmed = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEventName = eventName?.lowercased()
        if normalizedEventName == "error" {
            throw LLMRouterServiceClientError.streamServerError(
                Self.serverErrorMessage(from: trimmed)
            )
        }
        if trimmed == "[DONE]" || (trimmed.isEmpty && Self.terminalEventNames.contains(normalizedEventName ?? "")) {
            try yield(.completed(accumulator.response()), to: continuation)
            return true
        }
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw LLMRouterServiceClientError.malformedStreamEvent
        }

        let payload = try decodeStreamPayload(data, eventName: normalizedEventName)
        if let errorMessage = payload.errorMessage {
            throw LLMRouterServiceClientError.streamServerError(errorMessage)
        }
        try accumulator.absorb(payload, configuration: configuration)

        if let terminalText = payload.terminalText {
            try accumulator.replaceText(
                terminalText,
                byteLimit: configuration.maximumAssembledTextBytes
            )
        } else if let delta = payload.deltaText, !delta.isEmpty {
            try accumulator.appendText(
                delta,
                byteLimit: configuration.maximumAssembledTextBytes
            )
            try yield(.textDelta(delta), to: continuation)
        }

        if payload.isTerminal {
            try yield(.completed(accumulator.response()), to: continuation)
            return true
        }
        return false
    }

    private func decodeStreamPayload(
        _ data: Data,
        eventName: String?
    ) throws -> StreamPayload {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LLMRouterServiceClientError.malformedStreamEvent
        }
        guard let object = json as? [String: Any] else {
            throw LLMRouterServiceClientError.malformedStreamEvent
        }

        let type = Self.string(in: object, keys: ["type", "event"])?.lowercased()
        let choices = object["choices"] as? [[String: Any]] ?? []
        let finishReasonPresent = choices.contains { choice in
            if let value = choice["finish_reason"] {
                return !(value is NSNull)
            }
            if let value = choice["finishReason"] {
                return !(value is NSNull)
            }
            return false
        }
        let terminalName = type ?? eventName ?? ""
        let isTerminal = Self.terminalEventNames.contains(terminalName)
            || (object["done"] as? Bool) == true
            || (object["completed"] as? Bool) == true
            || finishReasonPresent
            || object["response"] is [String: Any]
            || object["final"] is [String: Any]

        let responseObject = (object["response"] as? [String: Any])
            ?? (object["final"] as? [String: Any])
        let response: LLMRouterCompletionResponse? = try responseObject.map {
            try Self.decode(LLMRouterCompletionResponse.self, fromJSONObject: $0)
        }

        let provider: LLMRouterProvider? = try Self.string(in: object, keys: ["provider"]).map {
            guard let provider = LLMRouterProvider(rawValue: $0) else {
                throw LLMRouterServiceClientError.malformedStreamEvent
            }
            return provider
        }
        let usage: LLMRouterUsage? = try Self.object(in: object, keys: ["usage"]).map {
            try Self.decode(LLMRouterUsage.self, fromJSONObject: $0)
        }
        let toolCalls: [LLMRouterToolCall]? = try Self.array(in: object, keys: ["tool_calls", "toolCalls"]).map {
            try Self.decode([LLMRouterToolCall].self, fromJSONObject: $0)
        }

        var deltaParts: [String] = []
        if let directDelta = object["delta"] as? String {
            deltaParts.append(directDelta)
        } else if let deltaObject = object["delta"] as? [String: Any],
                  let delta = Self.string(in: deltaObject, keys: ["text", "content"]) {
            deltaParts.append(delta)
        }
        if let textDelta = Self.string(in: object, keys: ["text_delta", "textDelta", "token"]) {
            deltaParts.append(textDelta)
        }
        for choice in choices {
            if let choiceDelta = choice["delta"] as? [String: Any],
               let text = Self.string(in: choiceDelta, keys: ["content", "text"]) {
                deltaParts.append(text)
            }
        }

        let topLevelText = Self.string(in: object, keys: ["text", "content"])
        if !isTerminal, deltaParts.isEmpty, let topLevelText {
            deltaParts.append(topLevelText)
        }
        let messageText = choices.lazy.compactMap { choice -> String? in
            guard let message = choice["message"] as? [String: Any] else { return nil }
            return Self.string(in: message, keys: ["content", "text"])
        }.first
        let terminalText = isTerminal
            ? (response?.text ?? topLevelText ?? messageText)
            : nil

        let errorMessage: String? = {
            guard let error = object["error"], !(error is NSNull) else {
                if type == "error" {
                    return Self.string(in: object, keys: ["message", "detail"]) ?? "Unknown streaming error."
                }
                return nil
            }
            if let message = error as? String {
                return Self.boundedServerMessage(message)
            }
            if let errorObject = error as? [String: Any] {
                return Self.boundedServerMessage(
                    Self.string(in: errorObject, keys: ["message", "detail", "error"])
                        ?? "Unknown streaming error."
                )
            }
            return "Unknown streaming error."
        }()

        return StreamPayload(
            deltaText: deltaParts.isEmpty ? nil : deltaParts.joined(),
            terminalText: terminalText,
            provider: provider,
            modelID: Self.string(in: object, keys: ["model_id", "modelID", "model"]),
            usage: usage,
            toolCalls: toolCalls,
            route: Self.string(in: object, keys: ["route"]),
            response: response,
            errorMessage: errorMessage,
            isTerminal: isTerminal
        )
    }

    private func boundedErrorMessage(
        from bytes: URLSession.AsyncBytes,
        limit: Int
    ) async throws -> String? {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { break }
            data.append(byte)
        }
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Self.serverErrorMessage(from: text)
    }

    private func yield(
        _ event: LLMRouterStreamEvent,
        to continuation: AsyncThrowingStream<LLMRouterStreamEvent, Error>.Continuation
    ) throws {
        switch continuation.yield(event) {
        case .enqueued:
            return
        case .dropped:
            throw LLMRouterServiceClientError.consumerTooSlow
        case .terminated:
            throw CancellationError()
        @unknown default:
            throw LLMRouterServiceClientError.consumerTooSlow
        }
    }

    private static let unsupportedStreamingStatusCodes: Set<Int> = [404, 405, 406, 415, 501]
    private static let terminalEventNames: Set<String> = [
        "complete",
        "completed",
        "completion",
        "done",
        "final",
        "message_stop",
        "response",
        "response.completed"
    ]

    private static func isValidStreamingPath(_ path: String) -> Bool {
        path.hasPrefix("/")
            && !path.contains("://")
            && !path.contains("?")
            && !path.contains("#")
            && path.utf8.count <= 512
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func object(in object: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = object[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private static func array(in object: [String: Any], keys: [String]) -> [Any]? {
        for key in keys {
            if let value = object[key] as? [Any] {
                return value
            }
        }
        return nil
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        fromJSONObject object: Any
    ) throws -> Value {
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LLMRouterServiceClientError.malformedStreamEvent
        }
    }

    private static func serverErrorMessage(from raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? String {
                return boundedServerMessage(error)
            }
            if let error = object["error"] as? [String: Any],
               let message = string(in: error, keys: ["message", "detail", "error"]) {
                return boundedServerMessage(message)
            }
            if let message = string(in: object, keys: ["message", "detail"]) {
                return boundedServerMessage(message)
            }
        }
        return boundedServerMessage(raw)
    }

    private static func boundedServerMessage(_ message: String) -> String {
        let compact = message
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "Unknown streaming error." : String(compact.prefix(512))
    }

    private func optionalModels() async -> [LLMRouterModelDescriptor] {
        do {
            let response: ModelsResponse = try await get(path: "/models")
            return response.data
        } catch {
            return []
        }
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        guard let baseURL = configuration.baseURL else {
            throw LLMRouterServiceClientError.disabled
        }
        let url = Self.url(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMRouterServiceClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMRouterServiceClientError.httpStatus(http.statusCode, nil)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func postCompletion(
        path: String,
        body: LLMRouterCompletionRequest
    ) async throws -> LLMRouterCompletionResponse {
        let decoded: LLMRouterCompletionResponse = try await post(path: path, body: body)
        var accumulator = StreamAccumulator(
            provider: configuration.provider,
            modelID: body.modelID
        )
        return try normalizeTerminalResponse(
            decoded,
            accumulator: &accumulator,
            configuration: configuration.streaming
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        guard let baseURL = configuration.baseURL else {
            throw LLMRouterServiceClientError.disabled
        }
        let url = Self.url(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMRouterServiceClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMRouterServiceClientError.httpStatus(http.statusCode, nil)
        }
        var data = Data()
        let limit = configuration.streaming.maximumResponseBytes
        data.reserveCapacity(min(limit, 64 * 1_024))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else {
                throw LLMRouterServiceClientError.streamLimitExceeded("response byte")
            }
            data.append(byte)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private static func url(baseURL: URL, path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    }
}
