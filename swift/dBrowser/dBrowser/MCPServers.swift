import Foundation

enum MCPServerTransport: String, Codable, CaseIterable, Equatable, Identifiable {
    case http
    case websocket
    case stdio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http: "HTTP"
        case .websocket: "WebSocket"
        case .stdio: "STDIO"
        }
    }

    var requiresEndpoint: Bool {
        switch self {
        case .http, .websocket: true
        case .stdio: false
        }
    }

    var requiresProgram: Bool {
        switch self {
        case .http, .websocket: false
        case .stdio: true
        }
    }
}

enum MCPServerConnectionState: String, Codable, Equatable {
    case disabled
    case disconnected
    case connected
    case failed

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .disconnected: "Disconnected"
        case .connected: "Connected"
        case .failed: "Failed"
        }
    }

    var isConnected: Bool {
        self == .connected
    }
}

struct MCPServerStatus: Codable, Equatable {
    var state: MCPServerConnectionState
    var message: String
    var checkedAt: Date?
    var discoveredTools: [String]

    static let disabled = MCPServerStatus(
        state: .disabled,
        message: "Enable this MCP server before connecting.",
        checkedAt: nil,
        discoveredTools: []
    )
}

struct MCPServerConfiguration: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var transport: MCPServerTransport
    var endpoint: String
    var program: String
    var argumentsText: String
    var headersText: String
    var environmentText: String
    var enabled: Bool
    var timeoutMS: Int
    var defaultCapability: String?
    var blockchainAccess: BlockchainCapabilityGrant
    var status: MCPServerStatus

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case transport
        case endpoint
        case program
        case argumentsText
        case headersText
        case environmentText
        case enabled
        case timeoutMS
        case defaultCapability
        case blockchainAccess
        case status
    }

    init(
        id: String,
        name: String,
        transport: MCPServerTransport,
        endpoint: String = "",
        program: String = "",
        argumentsText: String = "",
        headersText: String = "",
        environmentText: String = "",
        enabled: Bool = false,
        timeoutMS: Int = 20_000,
        defaultCapability: String? = nil,
        blockchainAccess: BlockchainCapabilityGrant = .defaultForMCPServer(),
        status: MCPServerStatus? = nil
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.endpoint = endpoint
        self.program = program
        self.argumentsText = argumentsText
        self.headersText = headersText
        self.environmentText = environmentText
        self.enabled = enabled
        self.timeoutMS = timeoutMS
        self.defaultCapability = defaultCapability
        self.blockchainAccess = blockchainAccess
        self.status = status ?? (enabled ? MCPServerStatus(state: .disconnected, message: "Ready to connect.", checkedAt: nil, discoveredTools: []) : .disabled)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let status = try container.decodeIfPresent(MCPServerStatus.self, forKey: .status)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            transport: try container.decode(MCPServerTransport.self, forKey: .transport),
            endpoint: try container.decodeIfPresent(String.self, forKey: .endpoint) ?? "",
            program: try container.decodeIfPresent(String.self, forKey: .program) ?? "",
            argumentsText: try container.decodeIfPresent(String.self, forKey: .argumentsText) ?? "",
            headersText: try container.decodeIfPresent(String.self, forKey: .headersText) ?? "",
            environmentText: try container.decodeIfPresent(String.self, forKey: .environmentText) ?? "",
            enabled: enabled,
            timeoutMS: try container.decodeIfPresent(Int.self, forKey: .timeoutMS) ?? 20_000,
            defaultCapability: try container.decodeIfPresent(String.self, forKey: .defaultCapability),
            blockchainAccess: try container.decodeIfPresent(BlockchainCapabilityGrant.self, forKey: .blockchainAccess) ?? .defaultForMCPServer(),
            status: status
        )
    }

    var connectionTarget: String {
        switch transport {
        case .http, .websocket:
            endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        case .stdio:
            program.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var summary: String {
        "\(transport.title) - \(connectionTarget.isEmpty ? "not configured" : connectionTarget)"
    }

    var sanitizedForSave: MCPServerConfiguration {
        var copy = self
        copy.id = copy.id.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.endpoint = copy.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.program = copy.program.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.argumentsText = copy.argumentsText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.headersText = copy.headersText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.environmentText = copy.environmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.blockchainAccess = copy.blockchainAccess.sanitized()
        if !copy.enabled {
            copy.status = .disabled
        } else if copy.status.state == .disabled {
            copy.status = MCPServerStatus(state: .disconnected, message: "Ready to connect.", checkedAt: nil, discoveredTools: [])
        }
        return copy
    }

    func validationError() -> String? {
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Server ID is required."
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name is required."
        }
        if timeoutMS < 500 {
            return "Timeout must be at least 500 ms."
        }
        if !enabled {
            return "Enable this MCP server before connecting."
        }
        if transport == .http {
            guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                return "Enter a valid HTTP or HTTPS endpoint."
            }
        }
        if transport == .websocket {
            guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(),
                  ["ws", "wss"].contains(scheme),
                  url.host != nil else {
                return "Enter a valid WS or WSS endpoint."
            }
        }
        if transport.requiresProgram && program.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the STDIO server program path."
        }
        return nil
    }

    func connectedStatus(now: Date = Date()) -> MCPServerStatus {
        let baseTools = defaultCapability.map { [$0] } ?? Self.defaultTools(for: transport)
        let tools = Array(Set(baseTools + blockchainAccess.hostTools)).sorted()
        return MCPServerStatus(
            state: .connected,
            message: "Connected to \(name) over \(transport.title). Capability negotiation is ready. \(blockchainAccess.installSummary)",
            checkedAt: now,
            discoveredTools: tools
        )
    }

    static func failedStatus(_ message: String, now: Date = Date()) -> MCPServerStatus {
        MCPServerStatus(state: .failed, message: message, checkedAt: now, discoveredTools: [])
    }

    static func disconnectedStatus(now: Date = Date()) -> MCPServerStatus {
        MCPServerStatus(state: .disconnected, message: "Disconnected by user.", checkedAt: now, discoveredTools: [])
    }

    nonisolated static let defaultServers: [MCPServerConfiguration] = [
        MCPServerConfiguration(
            id: "demo-weather",
            name: "Local Demo MCP",
            transport: .http,
            endpoint: "http://127.0.0.1:7410/mcp",
            enabled: false
        ),
        MCPServerConfiguration(
            id: "local-stdio",
            name: "Local STDIO MCP",
            transport: .stdio,
            program: "./bin/mcp-server",
            argumentsText: "--stdio",
            environmentText: "API_KEY=set-me",
            enabled: false
        )
    ]

    static func newServer(transport: MCPServerTransport) -> MCPServerConfiguration {
        let id = "mcp-\(UUID().uuidString.lowercased())"
        switch transport {
        case .http:
            return MCPServerConfiguration(id: id, name: "New HTTP MCP", transport: .http, endpoint: "http://127.0.0.1:7410/mcp")
        case .websocket:
            return MCPServerConfiguration(id: id, name: "New WebSocket MCP", transport: .websocket, endpoint: "ws://127.0.0.1:7410/mcp")
        case .stdio:
            return MCPServerConfiguration(id: id, name: "New STDIO MCP", transport: .stdio, program: "./bin/mcp-server", argumentsText: "--stdio")
        }
    }

    private static func defaultTools(for transport: MCPServerTransport) -> [String] {
        switch transport {
        case .http: ["tools/list", "resources/list"]
        case .websocket: ["tools/list", "prompts/list"]
        case .stdio: ["tools/list", "stdio/session"]
        }
    }
}

struct MCPServerInventory: Equatable {
    var servers: [MCPServerConfiguration]

    var enabledCount: Int {
        servers.filter(\.enabled).count
    }

    var connectedCount: Int {
        servers.filter { $0.status.state.isConnected }.count
    }

    var summary: String {
        if servers.isEmpty {
            return "No MCP servers configured."
        }
        return "\(connectedCount) connected, \(enabledCount) enabled, \(servers.count) configured."
    }
}
