import Contracts
import Foundation

public final class ControlPlaneClient: Sendable {
    public let baseURL: URL
    public let apiKey: String?

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8400")!, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    public func fetchOverview() async throws -> AppOverview {
        try await request(path: "/app/v1/overview", method: "GET")
    }

    public func importModel(_ payload: ImportModelRequest) async throws -> ModelRecord {
        try await request(path: "/app/v1/models/import", method: "POST", body: payload)
    }

    public func searchModels(query: String, limit: Int = 12) async throws -> ModelSearchResponse {
        let url = url(path: "/app/v1/models/search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, url: url)
    }

    public func fetchModelCard(id: String) async throws -> ModelCatalogCard {
        let url = url(path: "/app/v1/models/search/card", queryItems: [
            URLQueryItem(name: "id", value: id)
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, url: url)
    }

    public func inspectModel(id: String) async throws -> ModelRecord {
        try await request(path: "/app/v1/models/\(id)/inspect", method: "POST")
    }

    public func validateModel(id: String) async throws -> ValidationReport {
        try await request(path: "/app/v1/models/\(id)/validate", method: "POST")
    }

    public func installBackend(id: String) async throws -> BackendDetection {
        try await request(path: "/app/v1/backends/\(id)/install", method: "POST")
    }

    public func createConversation(title: String, modelId: String?) async throws -> ConversationRecord {
        try await request(
            path: "/app/v1/conversations",
            method: "POST",
            body: CreateConversationRequest(title: title, modelId: modelId)
        )
    }

    public func sendMessage(conversationID: String, content: String) async throws -> ConversationRecord {
        try await request(
            path: "/app/v1/conversations/\(conversationID)/messages",
            method: "POST",
            body: AddConversationMessageRequest(role: "user", content: content)
        )
    }

    public func runBenchmark(_ payload: BenchmarkRequest) async throws -> BenchmarkRecord {
        try await request(path: "/app/v1/benchmarks/run", method: "POST", body: payload)
    }

    public func launch(_ payload: LaunchSpec) async throws -> EngineInstanceRef {
        try await request(path: "/app/v1/engines/launch", method: "POST", body: payload)
    }

    public func stopEngine(id: String) async throws -> EngineInstanceRef {
        try await request(path: "/app/v1/engines/\(id)/stop", method: "POST")
    }

    public func fetchChatCompletion(_ payload: OpenAIChatCompletionRequest) async throws -> OpenAIChatCompletionResponse {
        try await request(path: "/v1/chat/completions", method: "POST", body: payload, useAPIKey: true)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        useAPIKey: Bool = false
    ) async throws -> Response {
        let url = url(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if useAPIKey, let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request, url: url)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        body: Body,
        useAPIKey: Bool = false
    ) async throws -> Response {
        let url = url(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if useAPIKey, let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request, url: url)
    }

    private func url(path: String, queryItems: [URLQueryItem] = []) -> URL {
        let url = baseURL.appending(path: path)
        guard queryItems.isEmpty == false else {
            return url
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? url
    }

    private func send<Response: Decodable>(_ request: URLRequest, url: URL) async throws -> Response {
        let method = request.httpMethod ?? "GET"
        log("Request started \(method) \(url.absoluteString)")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                log("Response received \(method) \(url.absoluteString) status=\(httpResponse.statusCode) bytes=\(data.count)")
            } else {
                log("Response received \(method) \(url.absoluteString) with non-HTTP response")
            }
            return try decodeResponse(data: data, response: response, method: method, url: url)
        } catch {
            log("Request failed \(method) \(url.absoluteString): \(describe(error))")
            throw error
        }
    }

    private func decodeResponse<Response: Decodable>(
        data: Data,
        response: URLResponse,
        method: String,
        url: URL
    ) throws -> Response {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let bodySnippet = responseSnippet(from: data)
            log("Non-success response \(method) \(url.absoluteString) status=\(httpResponse.statusCode) body=\(bodySnippet)")
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw apiError
            }
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func log(_ message: String) {
        print("[SwiftLM.Client] \(message)")
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "type=\(String(describing: type(of: error)))",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)"
        ]
        if let apiError = error as? APIErrorEnvelope {
            parts.append("apiCode=\(apiError.error.code)")
            parts.append("apiMessage=\(apiError.error.message)")
            if apiError.error.details.isEmpty == false {
                let details = apiError.error.details
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ",")
                parts.append("apiDetails=\(details)")
            }
        }
        if let reason = nsError.localizedFailureReason, reason.isEmpty == false {
            parts.append("reason=\(reason)")
        }
        if let suggestion = nsError.localizedRecoverySuggestion, suggestion.isEmpty == false {
            parts.append("suggestion=\(suggestion)")
        }
        return parts.joined(separator: " ")
    }

    private func responseSnippet(from data: Data, limit: Int = 400) -> String {
        guard data.isEmpty == false else {
            return "<empty>"
        }
        let prefix = data.prefix(limit)
        if let text = String(data: prefix, encoding: .utf8) {
            let normalized = text.replacingOccurrences(of: "\n", with: "\\n")
            return data.count > limit ? "\(normalized)..." : normalized
        }
        return "<\(data.count) bytes>"
    }
}
