import Foundation
import ZKLLMGatewaySDK

enum LLMGatewayTokenClass: String, Codable, Equatable, CaseIterable {
    case c256
    case c512
    case c1024
    case c2048
    case c4096

    nonisolated init(parsing raw: String) throws {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "c256", "256": self = .c256
        case "c512", "512": self = .c512
        case "c1024", "1024": self = .c1024
        case "c2048", "2048": self = .c2048
        case "c4096", "4096": self = .c4096
        default:
            throw LLMGatewayServiceClientError.invalidConfiguration("invalid LLM Gateway token class: \(raw)")
        }
    }

    var sdkTokenClass: ZKLLMGatewaySDK.TokenClass {
        switch self {
        case .c256: .c256
        case .c512: .c512
        case .c1024: .c1024
        case .c2048: .c2048
        case .c4096: .c4096
        }
    }

    var maxOutputTokensHint: Int {
        switch self {
        case .c256: 256
        case .c512: 512
        case .c1024: 1_024
        case .c2048: 2_048
        case .c4096: 4_096
        }
    }

    var contextWindowTokens: Int {
        switch self {
        case .c256: 2_048
        case .c512: 4_096
        case .c1024: 8_192
        case .c2048: 16_384
        case .c4096: 32_768
        }
    }
}

enum LLMGatewayTicketSourceConfig: Equatable {
    case dummy
    case file(path: String)

    func sdkTicketSource() throws -> any ZKLLMGatewaySDK.TicketSource {
        switch self {
        case .dummy:
            return ZKLLMGatewaySDK.DummyTicketSource()
        case .file(let path):
            return try ZKLLMGatewaySDK.FileTicketSource(path: path)
        }
    }

    var description: String {
        switch self {
        case .dummy: "dummy tickets"
        case .file(let path): "ticket file \(URL(fileURLWithPath: path).lastPathComponent)"
        }
    }
}

struct LLMGatewayEndpointConfiguration: Equatable {
    var baseURL: URL?
    var inferPath: String
    var gatewayPublicKeyBase64: String?
    var authBearer: String?
    var tickets: LLMGatewayTicketSourceConfig?
    var modelID: String
    var displayName: String
    var tokenClass: LLMGatewayTokenClass
    var temperature: Double?
    var timeout: TimeInterval

    nonisolated init(
        baseURL: URL? = nil,
        inferPath: String = "/v1/infer",
        gatewayPublicKeyBase64: String? = nil,
        authBearer: String? = nil,
        tickets: LLMGatewayTicketSourceConfig? = nil,
        modelID: String = "gpt-4o-mini",
        displayName: String = "LLM Gateway",
        tokenClass: LLMGatewayTokenClass = .c2048,
        temperature: Double? = 0.6,
        timeout: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.inferPath = inferPath
        self.gatewayPublicKeyBase64 = gatewayPublicKeyBase64
        self.authBearer = authBearer
        self.tickets = tickets
        self.modelID = modelID
        self.displayName = displayName
        self.tokenClass = tokenClass
        self.temperature = temperature
        self.timeout = timeout
    }

    nonisolated static let disabled = LLMGatewayEndpointConfiguration(
        baseURL: nil,
        gatewayPublicKeyBase64: nil,
        tickets: nil,
        displayName: "LLM Gateway",
        temperature: nil
    )

    var isConfigured: Bool {
        baseURL != nil && gatewayPublicKeyBase64?.isEmpty == false && tickets != nil
    }

    nonisolated static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LLMGatewayEndpointConfiguration {
        let endpointRaw = try requiredEnv(env, keys: ["GATEWAY_BASE_URL", "GATEWAY_URL"])
        guard let endpoint = URL(string: endpointRaw) else {
            throw LLMGatewayServiceClientError.invalidConfiguration("invalid LLM Gateway URL: \(endpointRaw)")
        }

        let publicKey = try requiredEnv(env, keys: ["GATEWAY_PUBLIC_KEY_B64"])
        let useRelay = try env["GATEWAY_USE_RELAY"].map {
            try parseBool($0, key: "GATEWAY_USE_RELAY")
        } ?? false
        let inferPath = env["GATEWAY_INFER_PATH"] ?? (useRelay ? "/relay" : "/v1/infer")
        let tickets: LLMGatewayTicketSourceConfig
        if let ticketPath = env["GATEWAY_TICKETS_JSON"] ?? env["TICKETS_JSON"],
           !ticketPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tickets = .file(path: ticketPath)
        } else if let rawDummy = env["GATEWAY_USE_DUMMY_TICKETS"],
                  try parseBool(rawDummy, key: "GATEWAY_USE_DUMMY_TICKETS") {
            tickets = .dummy
        } else {
            throw LLMGatewayServiceClientError.invalidConfiguration(
                "set GATEWAY_TICKETS_JSON or GATEWAY_USE_DUMMY_TICKETS=true"
            )
        }

        return LLMGatewayEndpointConfiguration(
            baseURL: endpoint,
            inferPath: inferPath,
            gatewayPublicKeyBase64: publicKey,
            authBearer: env["GATEWAY_AUTH_BEARER"],
            tickets: tickets,
            modelID: env["GATEWAY_MODEL"] ?? env["MODEL"] ?? "gpt-4o-mini",
            displayName: env["GATEWAY_DISPLAY_NAME"] ?? "LLM Gateway",
            tokenClass: try (env["GATEWAY_TOKEN_CLASS"] ?? env["TOKEN_CLASS"]).map(LLMGatewayTokenClass.init(parsing:)) ?? .c2048,
            temperature: try env["GATEWAY_TEMPERATURE"].map {
                try parseDouble($0, key: "GATEWAY_TEMPERATURE")
            } ?? 0.6,
            timeout: try env["GATEWAY_TIMEOUT_SECS"].map {
                try parseDouble($0, key: "GATEWAY_TIMEOUT_SECS")
            } ?? 60
        )
    }

    nonisolated static func fromEnvironmentOrDisabled(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> LLMGatewayEndpointConfiguration {
        (try? fromEnvironment(env)) ?? .disabled
    }

    private nonisolated static func requiredEnv(_ env: [String: String], keys: [String]) throws -> String {
        for key in keys {
            if let value = env[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        throw LLMGatewayServiceClientError.invalidConfiguration(
            "missing environment variable; set one of \(keys.joined(separator: ", "))"
        )
    }

    private nonisolated static func parseBool(_ raw: String, key: String) throws -> Bool {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            throw LLMGatewayServiceClientError.invalidConfiguration(
                "\(key) must be one of true/false/1/0/yes/no/on/off"
            )
        }
    }

    private nonisolated static func parseDouble(_ raw: String, key: String) throws -> Double {
        guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LLMGatewayServiceClientError.invalidConfiguration("\(key) must be numeric")
        }
        return value
    }
}

struct LLMGatewayModelDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var contextWindowTokens: Int?
    var supportsTools: Bool
    var available: Bool
    var detail: String?

    private enum CodingKeys: String, CodingKey {
        case id
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
        displayName: String,
        contextWindowTokens: Int?,
        supportsTools: Bool,
        available: Bool,
        detail: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.contextWindowTokens = contextWindowTokens
        self.supportsTools = supportsTools
        self.available = available
        self.detail = detail
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .display_name)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? id
        self.contextWindowTokens = try container.decodeIfPresent(Int.self, forKey: .contextWindowTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .context_window_tokens)
        self.supportsTools = try container.decodeIfPresent(Bool.self, forKey: .supportsTools)
            ?? container.decodeIfPresent(Bool.self, forKey: .supports_tools)
            ?? true
        self.available = try container.decodeIfPresent(Bool.self, forKey: .available)
            ?? ((try? container.decode(String.self, forKey: .status)) != "unavailable")
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(contextWindowTokens, forKey: .contextWindowTokens)
        try container.encode(supportsTools, forKey: .supportsTools)
        try container.encode(available, forKey: .available)
        try container.encodeIfPresent(detail, forKey: .detail)
    }
}

struct LLMGatewayServiceSnapshot: Equatable {
    var serviceAvailable: Bool
    var configured: Bool
    var models: [LLMGatewayModelDescriptor]
    var selectedModelID: String
    var tokenClass: LLMGatewayTokenClass
    var message: String

    nonisolated static let disabled = LLMGatewayServiceSnapshot(
        serviceAvailable: false,
        configured: false,
        models: [],
        selectedModelID: "gpt-4o-mini",
        tokenClass: .c2048,
        message: "LLM Gateway endpoint is not configured."
    )

    nonisolated static let unknown = LLMGatewayServiceSnapshot(
        serviceAvailable: false,
        configured: false,
        models: [],
        selectedModelID: "gpt-4o-mini",
        tokenClass: .c2048,
        message: "LLM Gateway pending health check."
    )

    func model(id: String? = nil) -> LLMGatewayModelDescriptor? {
        let target = id ?? selectedModelID
        return models.first { $0.id == target }
    }

    var selectedModel: LLMGatewayModelDescriptor? {
        model()
    }

    var isModelAvailable: Bool {
        guard configured, serviceAvailable else { return false }
        return model()?.available ?? true
    }

    var serviceStatusText: String {
        serviceAvailable ? message : "offline: \(message)"
    }
}

struct LLMGatewayUsage: Equatable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
}

struct LLMGatewayCompletionContext: Equatable {
    var conversationID: UUID?
    var runID: UUID?
    var pageURLString: String?
    var snapshotCommitment: String?
    var memoryContextIDs: [String]
    var estimatedPromptTokens: Int?
    var includedMessageIDs: [UUID]
    var compressedMessageIDs: [UUID]
}

struct LLMGatewayCompletionRequest: Equatable {
    var prompt: String
    var modelID: String
    var tokenClass: LLMGatewayTokenClass
    var temperature: Double?
    var maxTokens: Int
    var systemPrompt: String
    var context: LLMGatewayCompletionContext
}

struct LLMGatewayCompletionResponse: Equatable {
    var text: String
    var modelID: String
    var tokenClass: LLMGatewayTokenClass
    var billedTokenClass: LLMGatewayTokenClass?
    var usage: LLMGatewayUsage?
    var boundarySummary: String
}

enum LLMGatewayServiceClientError: Error, LocalizedError, Equatable {
    case disabled
    case invalidConfiguration(String)
    case invalidResponse(String)
    case gateway(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "LLM Gateway endpoint is not configured."
        case .invalidConfiguration(let message),
             .invalidResponse(let message),
             .gateway(let message):
            message
        }
    }
}

@MainActor
protocol LLMGatewayServicing: AnyObject {
    func snapshot() async -> LLMGatewayServiceSnapshot
    func complete(_ request: LLMGatewayCompletionRequest) async throws -> LLMGatewayCompletionResponse
    func completionRequest(
        prompt: String,
        conversationID: UUID?,
        runID: UUID?,
        pageURLString: String?,
        renderedContext: LLMRenderedConversationContext?,
        memoryRecall: OpenMindMemoryRecallResult?
    ) -> LLMGatewayCompletionRequest
}

@MainActor
final class LLMGatewayServiceClient: LLMGatewayServicing {
    private struct HealthResponse: Decodable {
        var ok: Bool
        var message: String?

        private enum CodingKeys: String, CodingKey {
            case ok
            case message
            case status
        }

        init(ok: Bool, message: String?) {
            self.ok = ok
            self.message = message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? true
            self.message = try container.decodeIfPresent(String.self, forKey: .message)
                ?? container.decodeIfPresent(String.self, forKey: .status)
        }
    }

    private struct ModelsResponse: Decodable {
        var data: [LLMGatewayModelDescriptor]

        private enum CodingKeys: String, CodingKey {
            case data
            case models
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.data = try container.decodeIfPresent([LLMGatewayModelDescriptor].self, forKey: .data)
                ?? container.decodeIfPresent([LLMGatewayModelDescriptor].self, forKey: .models)
                ?? []
        }
    }

    private let configuration: LLMGatewayEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(
        configuration: LLMGatewayEndpointConfiguration = .disabled,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> LLMGatewayServiceSnapshot {
        guard configuration.isConfigured else {
            return .disabled
        }

        do {
            let health = try await health()
            let models = await optionalModels()
            let configuredModel = LLMGatewayModelDescriptor(
                id: configuration.modelID,
                displayName: configuration.displayName,
                contextWindowTokens: configuration.tokenClass.contextWindowTokens,
                supportsTools: true,
                available: health.ok,
                detail: "Encrypted ZeroK gateway route using \(configuration.tokenClass.rawValue) token-class padding and \(configuration.tickets?.description ?? "configured tickets")."
            )
            let mergedModels = Self.mergedModels(models, configuredModel: configuredModel)
            return LLMGatewayServiceSnapshot(
                serviceAvailable: health.ok,
                configured: true,
                models: mergedModels,
                selectedModelID: configuration.modelID,
                tokenClass: configuration.tokenClass,
                message: health.message ?? "LLM Gateway online"
            )
        } catch {
            return LLMGatewayServiceSnapshot(
                serviceAvailable: false,
                configured: true,
                models: [
                    LLMGatewayModelDescriptor(
                        id: configuration.modelID,
                        displayName: configuration.displayName,
                        contextWindowTokens: configuration.tokenClass.contextWindowTokens,
                        supportsTools: true,
                        available: false,
                        detail: "Encrypted ZeroK gateway route is configured but offline."
                    ),
                ],
                selectedModelID: configuration.modelID,
                tokenClass: configuration.tokenClass,
                message: error.localizedDescription
            )
        }
    }

    func complete(_ request: LLMGatewayCompletionRequest) async throws -> LLMGatewayCompletionResponse {
        guard let baseURL = configuration.baseURL,
              let publicKeyBase64 = configuration.gatewayPublicKeyBase64,
              let tickets = configuration.tickets
        else {
            throw LLMGatewayServiceClientError.disabled
        }

        do {
            let gatewayPublicKey = try ZKLLMGatewaySDK.GatewayPublicKey(base64: publicKeyBase64)
            let client = ZKLLMGatewaySDK.GatewayClient(
                endpoint: baseURL,
                gatewayPublicKey: gatewayPublicKey,
                tickets: try tickets.sdkTicketSource(),
                config: ZKLLMGatewaySDK.GatewayClientConfig(
                    inferPath: configuration.inferPath,
                    authBearer: configuration.authBearer,
                    timeout: configuration.timeout
                ),
                urlSession: session
            )
            let response = try await client.chatCompletions(
                tokenClass: request.tokenClass.sdkTokenClass,
                request: ZKLLMGatewaySDK.ChatCompletionsRequest(
                    model: request.modelID,
                    messages: [
                        .system(request.systemPrompt),
                        .user(request.prompt),
                    ],
                    temperature: request.temperature,
                    maxTokens: request.maxTokens,
                    stream: false
                )
            )
            return LLMGatewayCompletionResponse(
                text: response.firstText() ?? "",
                modelID: response.model ?? request.modelID,
                tokenClass: request.tokenClass,
                billedTokenClass: billedTokenClass(from: response),
                usage: response.usage.map {
                    LLMGatewayUsage(
                        promptTokens: $0.promptTokens,
                        completionTokens: $0.completionTokens,
                        totalTokens: $0.totalTokens
                    )
                },
                boundarySummary: "Gateway decrypts only the minimized prompt envelope; upstream provider may still see decrypted prompt content and timing."
            )
        } catch let error as ZKLLMGatewaySDK.ZKLLMGatewayError {
            throw LLMGatewayServiceClientError.gateway(error.localizedDescription)
        } catch let error as LLMGatewayServiceClientError {
            throw error
        } catch {
            throw LLMGatewayServiceClientError.gateway(error.localizedDescription)
        }
    }

    func completionRequest(
        prompt: String,
        conversationID: UUID?,
        runID: UUID?,
        pageURLString: String?,
        renderedContext: LLMRenderedConversationContext?,
        memoryRecall: OpenMindMemoryRecallResult?
    ) -> LLMGatewayCompletionRequest {
        LLMGatewayCompletionRequest(
            prompt: providerPrompt(prompt: prompt, renderedContext: renderedContext, memoryRecall: memoryRecall),
            modelID: configuration.modelID,
            tokenClass: configuration.tokenClass,
            temperature: configuration.temperature,
            maxTokens: configuration.tokenClass.maxOutputTokensHint,
            systemPrompt: "You are dBrowser Copilot. Use only the provided minimized conversation, page, and approved memory context. Do not assume hidden browser history, wallet state, or private memory.",
            context: LLMGatewayCompletionContext(
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

    private func providerPrompt(
        prompt: String,
        renderedContext: LLMRenderedConversationContext?,
        memoryRecall: OpenMindMemoryRecallResult?
    ) -> String {
        var providerPrompt = renderedContext?.prompt ?? prompt
        let memoryIDs = renderedContext?.memoryContextIDs ?? memoryRecall?.memories.map(\.id) ?? []
        for (index, id) in memoryIDs.enumerated() where !id.isEmpty {
            providerPrompt = providerPrompt.replacingOccurrences(of: id, with: "approved-memory-\(index + 1)")
        }
        return providerPrompt
    }

    private func health() async throws -> HealthResponse {
        let data = try await getData(path: "/healthz")
        if let decoded = try? decoder.decode(HealthResponse.self, from: data) {
            return decoded
        }
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if text == "ok" {
            return HealthResponse(ok: true, message: "LLM Gateway online")
        }
        throw LLMGatewayServiceClientError.invalidResponse("LLM Gateway health check returned \(text)")
    }

    private func optionalModels() async -> [LLMGatewayModelDescriptor] {
        do {
            let response: ModelsResponse = try await get(path: "/v1/models")
            return response.data
        } catch {
            return []
        }
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        let data = try await getData(path: path)
        return try decoder.decode(Response.self, from: data)
    }

    private func getData(path: String) async throws -> Data {
        guard let baseURL = configuration.baseURL else {
            throw LLMGatewayServiceClientError.disabled
        }
        let url = Self.url(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMGatewayServiceClientError.invalidResponse("LLM Gateway returned an invalid response.")
        }
        return data
    }

    private func billedTokenClass(from response: ZKLLMGatewaySDK.ChatCompletionsResponse) -> LLMGatewayTokenClass? {
        guard let raw = response.extra["billed_token_class"]?.stringValue else { return nil }
        return try? LLMGatewayTokenClass(parsing: raw)
    }

    private static func url(baseURL: URL, path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    }

    private static func mergedModels(
        _ models: [LLMGatewayModelDescriptor],
        configuredModel: LLMGatewayModelDescriptor
    ) -> [LLMGatewayModelDescriptor] {
        var merged = models
        if let index = merged.firstIndex(where: { $0.id == configuredModel.id }) {
            var existing = merged[index]
            existing.contextWindowTokens = existing.contextWindowTokens ?? configuredModel.contextWindowTokens
            existing.available = existing.available && configuredModel.available
            existing.detail = existing.detail ?? configuredModel.detail
            merged[index] = existing
        } else {
            merged.insert(configuredModel, at: 0)
        }
        return merged
    }
}
