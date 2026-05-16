import Foundation

enum LLMRouterProvider: String, Codable, Equatable, CaseIterable {
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

struct LLMRouterEndpointConfiguration: Equatable {
    var baseURL: URL?
    var provider: LLMRouterProvider
    var preferLocal: Bool
    var noEgress: Bool

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

    private enum CodingKeys: String, CodingKey {
        case prompt
        case modelID = "model_id"
        case policy
        case options
        case context
    }
}

struct LLMRouterUsage: Codable, Equatable {
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

struct LLMRouterToolCall: Codable, Equatable, Identifiable {
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

struct LLMRouterCompletionResponse: Codable, Equatable {
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

enum LLMRouterServiceClientError: Error, LocalizedError {
    case disabled
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .disabled: "LLM router endpoint is not configured."
        case .invalidResponse: "LLM router returned an invalid response."
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
            return try await post(path: "/v1/complete", body: request)
        } catch {
            return try await post(path: "/complete", body: request)
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
                maxTokens: 768,
                systemPrompt: "You are dBrowser Copilot. Use only the provided conversation, page, and approved memory context."
            ),
            context: LLMRouterCompletionContext(
                conversationID: conversationID,
                runID: runID,
                pageURLString: pageURLString,
                snapshotCommitment: renderedContext?.snapshotCommitment,
                memoryContextIDs: renderedContext?.memoryContextIDs ?? memoryRecall?.memories.map(\.id) ?? [],
                estimatedPromptTokens: renderedContext?.estimatedPromptTokens,
                includedMessageIDs: renderedContext?.includedMessageIDs ?? [],
                compressedMessageIDs: renderedContext?.compressedMessageIDs ?? []
            )
        )
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
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMRouterServiceClientError.invalidResponse
        }
        return try decoder.decode(Response.self, from: data)
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
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMRouterServiceClientError.invalidResponse
        }
        return try decoder.decode(Response.self, from: data)
    }

    private static func url(baseURL: URL, path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    }
}
