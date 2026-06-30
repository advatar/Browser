import Foundation

public enum BrowserAutomationMCPTransport: String, Codable, Equatable {
    case stdio
    case localhostHTTP
}

public struct BrowserAutomationMCPServerDescriptor: Codable, Equatable {
    public var transport: BrowserAutomationMCPTransport
    public var binding: String
    public var allowedHosts: [String]
    public var methods: [String]

    public init(
        transport: BrowserAutomationMCPTransport,
        binding: String,
        allowedHosts: [String],
        methods: [String]
    ) {
        self.transport = transport
        self.binding = binding
        self.allowedHosts = allowedHosts
        self.methods = methods
    }
}

public struct BrowserAutomationMCPServerConfiguration: Codable, Equatable {
    public static let allowedLocalHosts = ["localhost", "127.0.0.1", "::1"]

    public var transport: BrowserAutomationMCPTransport
    public var host: String?
    public var port: UInt16?

    public init(
        transport: BrowserAutomationMCPTransport = .stdio,
        host: String? = nil,
        port: UInt16? = nil
    ) throws {
        if let host {
            try Self.validateLocalHost(host)
        }
        self.transport = transport
        self.host = host
        self.port = port
    }

    public var descriptor: BrowserAutomationMCPServerDescriptor {
        BrowserAutomationMCPServerDescriptor(
            transport: transport,
            binding: transport == .stdio ? "localProcess" : (host ?? "127.0.0.1"),
            allowedHosts: Self.allowedLocalHosts,
            methods: BrowserAutomationMCPServer.methods
        )
    }

    public static func validateLocalHost(_ host: String) throws {
        guard allowedLocalHosts.contains(host) else {
            throw BrowserAutomationKitError.invalidLocalHost(host)
        }
    }
}

public final class BrowserAutomationMCPServer {
    public static let methods = [
        "browserAutomation/descriptor",
        "browserAutomation/listTemplates",
        "browserAutomation/listRuns",
        "browserAutomation/startRun",
        "browserAutomation/appendEvidence",
        "browserAutomation/proposeMutation"
    ]

    private let service: BrowserAutomationService
    private let configuration: BrowserAutomationMCPServerConfiguration

    public init(
        service: BrowserAutomationService,
        configuration: BrowserAutomationMCPServerConfiguration = try! BrowserAutomationMCPServerConfiguration()
    ) {
        self.service = service
        self.configuration = configuration
    }

    public func handleJSONRPCLine(_ line: String) -> String {
        do {
            let request = try parseRequest(line)
            let result = try handle(method: request.method, params: request.params)
            return try makeResponse(id: request.id, result: result)
        } catch let error as JSONRPCError {
            return makeErrorResponse(id: error.id, code: error.code, message: error.message)
        } catch {
            return makeErrorResponse(id: nil, code: -32603, message: error.localizedDescription)
        }
    }

    private func handle(method: String, params: [String: Any]) throws -> Any {
        switch method {
        case "browserAutomation/descriptor":
            return try jsonObject(configuration.descriptor)
        case "browserAutomation/listTemplates":
            return ["templates": try service.listTemplates().map(jsonObject)]
        case "browserAutomation/listRuns":
            return ["runs": try service.listRuns().map(jsonObject)]
        case "browserAutomation/startRun":
            let templateID = try requiredString("templateID", in: params)
            let entryPoint = try optionalEntryPoint(params["entryPoint"] as? String) ?? .mcp
            let run = try service.startRun(
                templateID: templateID,
                entryPoint: entryPoint,
                sourceURLString: params["sourceURLString"] as? String,
                snapshotSummary: params["snapshotSummary"] as? String
            )
            return ["run": try jsonObject(run)]
        case "browserAutomation/appendEvidence":
            let runID = try requiredUUID("runID", in: params)
            let evidence = BrowserDeveloperEvidenceItem(
                kind: try requiredEvidenceKind("kind", in: params),
                title: try requiredString("title", in: params),
                summary: try requiredString("summary", in: params),
                sourceURLString: params["sourceURLString"] as? String,
                localFilePath: params["localFilePath"] as? String,
                externalURLString: params["externalURLString"] as? String,
                redactionState: optionalRedactionState(params["redactionState"] as? String) ?? .none,
                privacyBoundary: optionalPrivacyBoundary(params["privacyBoundary"] as? String) ?? .localOnly,
                metadata: params["metadata"] as? [String: String] ?? [:]
            )
            let run = try service.appendEvidence(evidence, to: runID)
            return ["run": try jsonObject(run)]
        case "browserAutomation/proposeMutation":
            let runID = try requiredUUID("runID", in: params)
            let action = try requiredProtectedAction("action", in: params)
            let summary = params["summary"] as? String ?? "Protected mutation requested through local automation."
            let run = try service.proposeProtectedMutation(runID: runID, action: action, summary: summary)
            return ["run": try jsonObject(run)]
        default:
            throw JSONRPCError(id: nil, code: -32601, message: "Unknown method: \(method)")
        }
    }

    private struct ParsedRequest {
        var id: Any?
        var method: String
        var params: [String: Any]
    }

    private struct JSONRPCError: Error {
        var id: Any?
        var code: Int
        var message: String
    }

    private func parseRequest(_ line: String) throws -> ParsedRequest {
        guard let data = line.data(using: .utf8) else {
            throw JSONRPCError(id: nil, code: -32700, message: "Request is not UTF-8.")
        }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let method = object["method"] as? String
        else {
            throw JSONRPCError(id: nil, code: -32600, message: "Invalid JSON-RPC request.")
        }
        return ParsedRequest(
            id: object["id"],
            method: method,
            params: object["params"] as? [String: Any] ?? [:]
        )
    }

    private func makeResponse(id: Any?, result: Any) throws -> String {
        try serialize([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result
        ])
    }

    private func makeErrorResponse(id: Any?, code: Int, message: String) -> String {
        (try? serialize([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ])) ?? #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Serialization failed"}}"#
    }

    private func serialize(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func requiredString(_ name: String, in params: [String: Any]) throws -> String {
        guard let value = params[name] as? String, !value.isEmpty else {
            throw BrowserAutomationKitError.missingArgument(name)
        }
        return value
    }

    private func requiredUUID(_ name: String, in params: [String: Any]) throws -> UUID {
        let value = try requiredString(name, in: params)
        guard let uuid = UUID(uuidString: value) else {
            throw BrowserAutomationKitError.invalidArgument("\(name)=\(value)")
        }
        return uuid
    }

    private func requiredEvidenceKind(_ name: String, in params: [String: Any]) throws -> BrowserDeveloperEvidenceKind {
        let value = try requiredString(name, in: params)
        guard let kind = BrowserDeveloperEvidenceKind(rawValue: value) else {
            throw BrowserAutomationKitError.invalidArgument("\(name)=\(value)")
        }
        return kind
    }

    private func requiredProtectedAction(_ name: String, in params: [String: Any]) throws -> BrowserDeveloperProtectedAction {
        let value = try requiredString(name, in: params)
        guard let action = BrowserDeveloperProtectedAction(rawValue: value) else {
            throw BrowserAutomationKitError.invalidArgument("\(name)=\(value)")
        }
        return action
    }

    private func optionalEntryPoint(_ value: String?) throws -> BrowserDeveloperWorkflowEntryPoint? {
        guard let value else { return nil }
        guard let entryPoint = BrowserDeveloperWorkflowEntryPoint(rawValue: value) else {
            throw BrowserAutomationKitError.invalidArgument("entryPoint=\(value)")
        }
        return entryPoint
    }

    private func optionalRedactionState(_ value: String?) -> BrowserDeveloperEvidenceRedactionState? {
        value.flatMap(BrowserDeveloperEvidenceRedactionState.init(rawValue:))
    }

    private func optionalPrivacyBoundary(_ value: String?) -> BrowserDeveloperEvidencePrivacyBoundary? {
        value.flatMap(BrowserDeveloperEvidencePrivacyBoundary.init(rawValue:))
    }
}
