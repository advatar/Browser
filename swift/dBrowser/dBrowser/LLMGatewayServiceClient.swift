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
    var tokenPackagesPath: String
    var tokenPurchasePath: String
    var gatewayPublicKeyBase64: String?
    var authBearer: String?
    var tickets: LLMGatewayTicketSourceConfig?
    var fallbackTokenPackage: LLMGatewayTokenPackage?
    var modelID: String
    var displayName: String
    var tokenClass: LLMGatewayTokenClass
    var temperature: Double?
    var timeout: TimeInterval

    nonisolated init(
        baseURL: URL? = nil,
        inferPath: String = "/v1/infer",
        tokenPackagesPath: String = "/v1/tokens/packages",
        tokenPurchasePath: String = "/v1/tokens/purchases",
        gatewayPublicKeyBase64: String? = nil,
        authBearer: String? = nil,
        tickets: LLMGatewayTicketSourceConfig? = nil,
        fallbackTokenPackage: LLMGatewayTokenPackage? = nil,
        modelID: String = "gpt-4o-mini",
        displayName: String = "LLM Gateway",
        tokenClass: LLMGatewayTokenClass = .c2048,
        temperature: Double? = 0.6,
        timeout: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.inferPath = inferPath
        self.tokenPackagesPath = tokenPackagesPath
        self.tokenPurchasePath = tokenPurchasePath
        self.gatewayPublicKeyBase64 = gatewayPublicKeyBase64
        self.authBearer = authBearer
        self.tickets = tickets
        self.fallbackTokenPackage = fallbackTokenPackage
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
        let tokenClass = try (env["GATEWAY_TOKEN_CLASS"] ?? env["TOKEN_CLASS"]).map(LLMGatewayTokenClass.init(parsing:)) ?? .c2048

        return LLMGatewayEndpointConfiguration(
            baseURL: endpoint,
            inferPath: inferPath,
            tokenPackagesPath: env["GATEWAY_TOKEN_PACKAGES_PATH"] ?? "/v1/tokens/packages",
            tokenPurchasePath: env["GATEWAY_TOKEN_PURCHASE_PATH"] ?? "/v1/tokens/purchases",
            gatewayPublicKeyBase64: publicKey,
            authBearer: env["GATEWAY_AUTH_BEARER"],
            tickets: tickets,
            fallbackTokenPackage: try fallbackTokenPackage(from: env, tokenClass: tokenClass),
            modelID: env["GATEWAY_MODEL"] ?? env["MODEL"] ?? "gpt-4o-mini",
            displayName: env["GATEWAY_DISPLAY_NAME"] ?? "LLM Gateway",
            tokenClass: tokenClass,
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

    private nonisolated static func parseInt(_ raw: String, key: String) throws -> Int {
        guard let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LLMGatewayServiceClientError.invalidConfiguration("\(key) must be an integer")
        }
        return value
    }

    private nonisolated static func fallbackTokenPackage(
        from env: [String: String],
        tokenClass: LLMGatewayTokenClass
    ) throws -> LLMGatewayTokenPackage? {
        guard let payTo = env["GATEWAY_TOKEN_PURCHASE_PAY_TO"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !payTo.isEmpty,
              let amountRaw = env["GATEWAY_TOKEN_PURCHASE_AMOUNT_MINOR"] ?? env["GATEWAY_TOKEN_PRICE_MINOR"]
        else {
            return nil
        }

        return LLMGatewayTokenPackage(
            id: env["GATEWAY_TOKEN_PACKAGE_ID"] ?? "starter-\(tokenClass.rawValue)",
            displayName: env["GATEWAY_TOKEN_PACKAGE_NAME"] ?? "Gateway \(tokenClass.rawValue) starter pack",
            tokenClass: tokenClass,
            ticketCount: try env["GATEWAY_TOKEN_PACKAGE_TICKETS"].map {
                try parseInt($0, key: "GATEWAY_TOKEN_PACKAGE_TICKETS")
            } ?? 10,
            amountMinorUnits: try parseInt(amountRaw, key: "GATEWAY_TOKEN_PURCHASE_AMOUNT_MINOR"),
            asset: env["GATEWAY_TOKEN_PURCHASE_ASSET"] ?? "USDC",
            network: env["GATEWAY_TOKEN_PURCHASE_NETWORK"] ?? "base-mainnet",
            payTo: payTo,
            facilitatorURLString: env["GATEWAY_TOKEN_PURCHASE_FACILITATOR_URL"],
            purchaseURLString: nil,
            detail: env["GATEWAY_TOKEN_PACKAGE_DETAIL"] ?? "Configured gateway token package."
        )
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

struct LLMGatewayTokenPackage: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var tokenClass: LLMGatewayTokenClass
    var ticketCount: Int
    var amountMinorUnits: Int
    var asset: String
    var network: String
    var payTo: String
    var facilitatorURLString: String?
    var purchaseURLString: String?
    var detail: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case display_name
        case name
        case tokenClass
        case token_class
        case ticketCount
        case ticket_count
        case amountMinorUnits
        case amount_minor_units
        case priceMinorUnits
        case price_minor_units
        case asset
        case currency
        case network
        case payTo
        case pay_to
        case recipient
        case facilitatorURLString
        case facilitator_url
        case purchaseURLString
        case purchase_url
        case detail
        case description
    }

    nonisolated init(
        id: String,
        displayName: String,
        tokenClass: LLMGatewayTokenClass,
        ticketCount: Int,
        amountMinorUnits: Int,
        asset: String,
        network: String,
        payTo: String,
        facilitatorURLString: String? = nil,
        purchaseURLString: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.tokenClass = tokenClass
        self.ticketCount = max(0, ticketCount)
        self.amountMinorUnits = max(0, amountMinorUnits)
        self.asset = asset
        self.network = network
        self.payTo = payTo
        self.facilitatorURLString = facilitatorURLString
        self.purchaseURLString = purchaseURLString
        self.detail = detail
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .display_name)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? id
        let rawTokenClass = try container.decodeIfPresent(String.self, forKey: .tokenClass)
            ?? container.decodeIfPresent(String.self, forKey: .token_class)
            ?? LLMGatewayTokenClass.c2048.rawValue
        self.tokenClass = try LLMGatewayTokenClass(parsing: rawTokenClass)
        self.ticketCount = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .ticketCount)
                ?? container.decodeIfPresent(Int.self, forKey: .ticket_count)
                ?? 0
        )
        self.amountMinorUnits = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .amountMinorUnits)
                ?? container.decodeIfPresent(Int.self, forKey: .amount_minor_units)
                ?? container.decodeIfPresent(Int.self, forKey: .priceMinorUnits)
                ?? container.decodeIfPresent(Int.self, forKey: .price_minor_units)
                ?? 0
        )
        self.asset = try container.decodeIfPresent(String.self, forKey: .asset)
            ?? container.decodeIfPresent(String.self, forKey: .currency)
            ?? "USDC"
        self.network = try container.decodeIfPresent(String.self, forKey: .network) ?? "base-mainnet"
        self.payTo = try container.decodeIfPresent(String.self, forKey: .payTo)
            ?? container.decodeIfPresent(String.self, forKey: .pay_to)
            ?? container.decodeIfPresent(String.self, forKey: .recipient)
            ?? ""
        self.facilitatorURLString = try container.decodeIfPresent(String.self, forKey: .facilitatorURLString)
            ?? container.decodeIfPresent(String.self, forKey: .facilitator_url)
        self.purchaseURLString = try container.decodeIfPresent(String.self, forKey: .purchaseURLString)
            ?? container.decodeIfPresent(String.self, forKey: .purchase_url)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .description)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(tokenClass.rawValue, forKey: .tokenClass)
        try container.encode(ticketCount, forKey: .ticketCount)
        try container.encode(amountMinorUnits, forKey: .amountMinorUnits)
        try container.encode(asset, forKey: .asset)
        try container.encode(network, forKey: .network)
        try container.encode(payTo, forKey: .payTo)
        try container.encodeIfPresent(facilitatorURLString, forKey: .facilitatorURLString)
        try container.encodeIfPresent(purchaseURLString, forKey: .purchaseURLString)
        try container.encodeIfPresent(detail, forKey: .detail)
    }

    var amountDecimal: Decimal {
        Decimal(amountMinorUnits) / Decimal(100)
    }

    var amountText: String {
        "\(NSDecimalNumber(decimal: amountDecimal).stringValue) \(asset)"
    }

    var isPurchasable: Bool {
        ticketCount > 0 && amountMinorUnits > 0 && !payTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func x402Requirement(resourceURLString: String, now: Date = Date()) -> X402PaymentRequirement {
        X402PaymentRequirement(
            id: "llm-gateway-token-\(id)",
            resourceURLString: resourceURLString,
            amountMinorUnits: amountMinorUnits,
            asset: asset,
            network: network,
            payTo: payTo,
            facilitatorURLString: facilitatorURLString,
            expiresAt: now.addingTimeInterval(300)
        )
    }
}

struct LLMGatewayTokenPurchaseReceipt: Codable, Equatable, Identifiable {
    var id: String
    var packageID: String
    var tokenClass: LLMGatewayTokenClass
    var ticketCount: Int
    var amountMinorUnits: Int
    var asset: String
    var network: String
    var payTo: String
    var requirementHash: String
    var walletAccount: String
    var transactionReference: String?
    var storedTicketCount: Int
    var message: String
    var createdAt: Date
}

struct LLMGatewayServiceSnapshot: Equatable {
    var serviceAvailable: Bool
    var configured: Bool
    var models: [LLMGatewayModelDescriptor]
    var selectedModelID: String
    var tokenClass: LLMGatewayTokenClass
    var message: String
    var tokenPackages: [LLMGatewayTokenPackage]
    var tokenPurchaseMessage: String?

    nonisolated init(
        serviceAvailable: Bool,
        configured: Bool,
        models: [LLMGatewayModelDescriptor],
        selectedModelID: String,
        tokenClass: LLMGatewayTokenClass,
        message: String,
        tokenPackages: [LLMGatewayTokenPackage] = [],
        tokenPurchaseMessage: String? = nil
    ) {
        self.serviceAvailable = serviceAvailable
        self.configured = configured
        self.models = models
        self.selectedModelID = selectedModelID
        self.tokenClass = tokenClass
        self.message = message
        self.tokenPackages = tokenPackages
        self.tokenPurchaseMessage = tokenPurchaseMessage
    }

    nonisolated static let disabled = LLMGatewayServiceSnapshot(
        serviceAvailable: false,
        configured: false,
        models: [],
        selectedModelID: "gpt-4o-mini",
        tokenClass: .c2048,
        message: "LLM Gateway endpoint is not configured.",
        tokenPurchaseMessage: "Configure the gateway endpoint and a ticket JSON file before buying tokens."
    )

    nonisolated static let unknown = LLMGatewayServiceSnapshot(
        serviceAvailable: false,
        configured: false,
        models: [],
        selectedModelID: "gpt-4o-mini",
        tokenClass: .c2048,
        message: "LLM Gateway pending health check.",
        tokenPurchaseMessage: "LLM Gateway token purchase availability is pending health check."
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
    func tokenPackages() async -> [LLMGatewayTokenPackage]
    func purchaseTokens(
        package: LLMGatewayTokenPackage,
        paymentPayload: X402PaymentPayload
    ) async throws -> LLMGatewayTokenPurchaseReceipt
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

    private struct TokenPackagesResponse: Decodable {
        var data: [LLMGatewayTokenPackage]

        private enum CodingKeys: String, CodingKey {
            case data
            case packages
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.data = try container.decodeIfPresent([LLMGatewayTokenPackage].self, forKey: .data)
                ?? container.decodeIfPresent([LLMGatewayTokenPackage].self, forKey: .packages)
                ?? []
        }
    }

    private struct TokenPurchaseRequest: Encodable {
        var packageID: String
        var tokenClass: String
        var ticketCount: Int
        var payment: X402PaymentPayload

        private enum CodingKeys: String, CodingKey {
            case packageID = "package_id"
            case tokenClass = "token_class"
            case ticketCount = "ticket_count"
            case payment
        }
    }

    private struct TokenPurchaseResponse: Decodable {
        var receiptID: String?
        var message: String?
        var tickets: [ZKLLMGatewaySDK.ZkTicket]

        private enum CodingKeys: String, CodingKey {
            case receiptID = "receipt_id"
            case id
            case message
            case tickets
            case data
        }

        private enum DataCodingKeys: String, CodingKey {
            case receiptID = "receipt_id"
            case id
            case message
            case tickets
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let dataContainer = try? container.nestedContainer(keyedBy: DataCodingKeys.self, forKey: .data) {
                self.receiptID = try dataContainer.decodeIfPresent(String.self, forKey: .receiptID)
                    ?? dataContainer.decodeIfPresent(String.self, forKey: .id)
                    ?? container.decodeIfPresent(String.self, forKey: .receiptID)
                    ?? container.decodeIfPresent(String.self, forKey: .id)
                self.message = try dataContainer.decodeIfPresent(String.self, forKey: .message)
                    ?? container.decodeIfPresent(String.self, forKey: .message)
                self.tickets = try dataContainer.decodeIfPresent([ZKLLMGatewaySDK.ZkTicket].self, forKey: .tickets) ?? []
            } else {
                self.receiptID = try container.decodeIfPresent(String.self, forKey: .receiptID)
                    ?? container.decodeIfPresent(String.self, forKey: .id)
                self.message = try container.decodeIfPresent(String.self, forKey: .message)
                self.tickets = try container.decodeIfPresent([ZKLLMGatewaySDK.ZkTicket].self, forKey: .tickets) ?? []
            }
        }
    }

    private let configuration: LLMGatewayEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

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
            let packages = await tokenPackages()
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
                message: health.message ?? "LLM Gateway online",
                tokenPackages: packages,
                tokenPurchaseMessage: tokenPurchaseMessage(packages: packages)
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
                message: error.localizedDescription,
                tokenPackages: fallbackTokenPackages(),
                tokenPurchaseMessage: tokenPurchaseMessage(packages: fallbackTokenPackages())
            )
        }
    }

    func tokenPackages() async -> [LLMGatewayTokenPackage] {
        guard configuration.isConfigured else {
            return []
        }

        do {
            let response: TokenPackagesResponse = try await get(path: configuration.tokenPackagesPath)
            let packages = response.data.map(normalizedTokenPackage).filter(\.isPurchasable)
            return packages.isEmpty ? fallbackTokenPackages() : packages
        } catch {
            return fallbackTokenPackages()
        }
    }

    func purchaseTokens(
        package: LLMGatewayTokenPackage,
        paymentPayload: X402PaymentPayload
    ) async throws -> LLMGatewayTokenPurchaseReceipt {
        guard configuration.isConfigured else {
            throw LLMGatewayServiceClientError.disabled
        }
        let normalizedPackage = normalizedTokenPackage(package)
        guard paymentPayload.requirementHash == normalizedPackage.x402Requirement(
            resourceURLString: normalizedPackage.purchaseURLString ?? "llm-gateway://tokens/\(normalizedPackage.id)"
        ).requirementHash else {
            throw LLMGatewayServiceClientError.invalidConfiguration("payment payload is not bound to the selected token package")
        }
        guard let ticketStorePath else {
            throw LLMGatewayServiceClientError.invalidConfiguration(
                "set GATEWAY_TICKETS_JSON to a writable ticket file before buying gateway tokens"
            )
        }

        let request = TokenPurchaseRequest(
            packageID: normalizedPackage.id,
            tokenClass: normalizedPackage.tokenClass.rawValue,
            ticketCount: normalizedPackage.ticketCount,
            payment: paymentPayload
        )
        let response: TokenPurchaseResponse = try await post(path: configuration.tokenPurchasePath, body: request)
        guard !response.tickets.isEmpty else {
            throw LLMGatewayServiceClientError.invalidResponse("LLM Gateway token purchase returned no tickets.")
        }

        let storedTicketCount = try await appendPurchasedTickets(response.tickets, to: ticketStorePath)
        return LLMGatewayTokenPurchaseReceipt(
            id: response.receiptID ?? "llm-gateway-token-\(UUID().uuidString)",
            packageID: normalizedPackage.id,
            tokenClass: normalizedPackage.tokenClass,
            ticketCount: response.tickets.count,
            amountMinorUnits: normalizedPackage.amountMinorUnits,
            asset: normalizedPackage.asset,
            network: normalizedPackage.network,
            payTo: normalizedPackage.payTo,
            requirementHash: paymentPayload.requirementHash,
            walletAccount: paymentPayload.walletAccount,
            transactionReference: paymentPayload.transactionReference,
            storedTicketCount: storedTicketCount,
            message: response.message ?? "Stored \(response.tickets.count) LLM Gateway ticket\(response.tickets.count == 1 ? "" : "s").",
            createdAt: Date()
        )
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
        let memoryIDs = renderedContext.map {
            LLMMemoryContextPolicy.boundedIDs(from: $0.memoryContextIDs)
        }
            ?? memoryRecall.map { LLMMemoryContextPolicy.boundedIDs(from: $0.memories) }
            ?? []
        let memoryAliases = memoryIDs.indices.map { "approved-memory-\($0 + 1)" }
        let minimizedPrompt = providerPrompt(
            prompt: prompt,
            renderedContext: renderedContext,
            memoryIDs: memoryIDs,
            memoryAliases: memoryAliases
        )
        return LLMGatewayCompletionRequest(
            prompt: minimizedPrompt,
            modelID: configuration.modelID,
            tokenClass: configuration.tokenClass,
            temperature: configuration.temperature,
            maxTokens: configuration.tokenClass.maxOutputTokensHint,
            systemPrompt: LLMConversationContextRenderer.gatewayCompletionSystemPrompt,
            context: LLMGatewayCompletionContext(
                conversationID: conversationID,
                runID: runID,
                pageURLString: pageURLString,
                snapshotCommitment: renderedContext?.snapshotCommitment,
                memoryContextIDs: memoryAliases,
                estimatedPromptTokens: LLMConversationContextRenderer.estimatedTokens(for: minimizedPrompt),
                includedMessageIDs: renderedContext?.includedMessageIDs ?? [],
                compressedMessageIDs: renderedContext?.compressedMessageIDs ?? []
            )
        )
    }

    private func providerPrompt(
        prompt: String,
        renderedContext: LLMRenderedConversationContext?,
        memoryIDs: [String],
        memoryAliases: [String]
    ) -> String {
        let providerPrompt = renderedContext?.prompt ?? prompt
        guard !memoryIDs.isEmpty else { return providerPrompt }
        let aliases = Array(zip(memoryIDs, memoryAliases))

        return providerPrompt.components(separatedBy: "\n").map { line in
            for (id, alias) in aliases {
                let citationPrefix = "- \(id) ["
                if line.hasPrefix(citationPrefix) {
                    return "- \(alias) [" + String(line.dropFirst(citationPrefix.count))
                }
            }

            let legacyPrefix = "memory citations: "
            guard line.hasPrefix(legacyPrefix) else { return line }
            let citations = line.dropFirst(legacyPrefix.count).components(separatedBy: ", ")
            let redacted = citations.map { citation in
                aliases.first(where: { $0.0 == citation })?.1 ?? citation
            }
            return legacyPrefix + redacted.joined(separator: ", ")
        }
        .joined(separator: "\n")
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

    private var ticketStorePath: String? {
        guard case .file(let path) = configuration.tickets else {
            return nil
        }
        return path
    }

    private func fallbackTokenPackages() -> [LLMGatewayTokenPackage] {
        configuration.fallbackTokenPackage.map { [normalizedTokenPackage($0)] } ?? []
    }

    private func normalizedTokenPackage(_ package: LLMGatewayTokenPackage) -> LLMGatewayTokenPackage {
        var normalized = package
        if normalized.purchaseURLString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            normalized.purchaseURLString = purchaseResourceURLString(for: normalized)
        }
        return normalized
    }

    private func tokenPurchaseMessage(packages: [LLMGatewayTokenPackage]) -> String? {
        guard configuration.isConfigured else {
            return "Configure the gateway endpoint before buying tokens."
        }
        guard ticketStorePath != nil else {
            return "Gateway token purchases require a writable GATEWAY_TICKETS_JSON file."
        }
        if packages.isEmpty {
            return "No gateway token packages are advertised yet."
        }
        return "Gateway token packages are available through wallet/x402 authorization."
    }

    private func purchaseResourceURLString(for package: LLMGatewayTokenPackage) -> String {
        package.purchaseURLString
            ?? configuration.baseURL.map { Self.url(baseURL: $0, path: configuration.tokenPurchasePath).absoluteString }
            ?? "llm-gateway://tokens/\(package.id)"
    }

    private func appendPurchasedTickets(
        _ tickets: [ZKLLMGatewaySDK.ZkTicket],
        to path: String
    ) async throws -> Int {
        do {
            let source = try ZKLLMGatewaySDK.FileTicketSource(path: path)
            try await source.appendTickets(tickets)
            return await source.remaining()
        } catch let error as ZKLLMGatewaySDK.ZKLLMGatewayError {
            throw LLMGatewayServiceClientError.gateway(error.localizedDescription)
        } catch {
            throw LLMGatewayServiceClientError.gateway(error.localizedDescription)
        }
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        let data = try await getData(path: path)
        return try decoder.decode(Response.self, from: data)
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        guard let baseURL = configuration.baseURL else {
            throw LLMGatewayServiceClientError.disabled
        }
        let url = Self.url(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authBearer = configuration.authBearer, !authBearer.isEmpty {
            request.setValue("Bearer \(authBearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMGatewayServiceClientError.invalidResponse("LLM Gateway returned an invalid response.")
        }
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
        if let authBearer = configuration.authBearer, !authBearer.isEmpty {
            request.setValue("Bearer \(authBearer)", forHTTPHeaderField: "Authorization")
        }
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
