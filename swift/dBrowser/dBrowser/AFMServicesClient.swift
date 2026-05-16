import Foundation

struct AFMServiceEndpointConfiguration: Equatable {
    var routerBaseURL: URL
    var registryBaseURL: URL
    var pipelinesBaseURL: URL

    nonisolated static let local = AFMServiceEndpointConfiguration(
        routerBaseURL: URL(string: "http://127.0.0.1:4810")!,
        registryBaseURL: URL(string: "http://127.0.0.1:4820")!,
        pipelinesBaseURL: URL(string: "http://127.0.0.1:4830")!
    )
}

struct AFMServiceSnapshot: Equatable {
    var routerAvailable: Bool
    var registryAvailable: Bool
    var pipelinesAvailable: Bool
    var routerPacks: [AFMPackSummary]
    var registryPacks: [AFMPackSummary]

    static let unknown = AFMServiceSnapshot(
        routerAvailable: true,
        registryAvailable: true,
        pipelinesAvailable: true,
        routerPacks: [],
        registryPacks: []
    )

    var allServicesAvailable: Bool {
        routerAvailable && registryAvailable && pipelinesAvailable
    }

    var serviceStatusText: String {
        let states = [
            "router \(routerAvailable ? "online" : "offline")",
            "registry \(registryAvailable ? "online" : "offline")",
            "pipelines \(pipelinesAvailable ? "online" : "offline")"
        ]
        return states.joined(separator: ", ")
    }
}

struct AFMPackSummary: Codable, Equatable {
    var id: String
    var name: String?
    var maintainer: String?
    var version: String?
    var checksum: String?
    var skills: [String]?
    var status: String?

    var displayName: String {
        name ?? id
    }
}

struct AFMRouteResult: Codable, Equatable {
    var selection: AFMPackSummary?
    var requestedSkill: String?
}

struct AFMPipelineJobResult: Codable, Equatable {
    var ok: Bool
    var id: String
    var status: String
}

enum AFMServicesClientError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "AFM service returned an invalid response."
        case .httpStatus(let status):
            return "AFM service returned HTTP \(status)."
        }
    }
}

final class AFMServicesClient {
    private struct HealthResponse: Decodable {
        let ok: Bool
    }

    private struct PacksResponse: Decodable {
        let data: [AFMPackSummary]
    }

    private struct RouteRequest: Encodable {
        let skill: String
        let prompt: String
        let pageURLString: String?
    }

    private struct PipelineJobRequest: Encodable {
        let name: String
        let payload: PipelineJobPayload
    }

    private struct PipelineJobPayload: Encodable {
        let prompt: String
        let pageURLString: String?
        let selectedPackID: String?
    }

    private let configuration: AFMServiceEndpointConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        configuration: AFMServiceEndpointConfiguration = .local,
        session: URLSession = AFMServicesClient.makeDefaultSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func snapshot() async -> AFMServiceSnapshot {
        let routerAvailable = (try? await health(baseURL: configuration.routerBaseURL)) ?? false
        let registryAvailable = (try? await health(baseURL: configuration.registryBaseURL)) ?? false
        let pipelinesAvailable = (try? await health(baseURL: configuration.pipelinesBaseURL)) ?? false
        let routerPacks = routerAvailable ? ((try? await packs(baseURL: configuration.routerBaseURL)) ?? []) : []
        let registryPacks = registryAvailable ? ((try? await packs(baseURL: configuration.registryBaseURL)) ?? []) : []

        return AFMServiceSnapshot(
            routerAvailable: routerAvailable,
            registryAvailable: registryAvailable,
            pipelinesAvailable: pipelinesAvailable,
            routerPacks: routerPacks,
            registryPacks: registryPacks
        )
    }

    func route(skill: String, prompt: String, pageURLString: String?) async throws -> AFMRouteResult {
        let body = RouteRequest(skill: skill, prompt: prompt, pageURLString: pageURLString)
        return try await send(
            method: "POST",
            baseURL: configuration.routerBaseURL,
            path: "/route",
            body: body
        )
    }

    func enqueueCopilotJob(
        prompt: String,
        pageURLString: String?,
        selectedPackID: String?
    ) async throws -> AFMPipelineJobResult {
        let body = PipelineJobRequest(
            name: "swift-copilot",
            payload: PipelineJobPayload(
                prompt: prompt,
                pageURLString: pageURLString,
                selectedPackID: selectedPackID
            )
        )
        return try await send(
            method: "POST",
            baseURL: configuration.pipelinesBaseURL,
            path: "/jobs",
            body: body
        )
    }

    private func health(baseURL: URL) async throws -> Bool {
        let response: HealthResponse = try await send(method: "GET", baseURL: baseURL, path: "/health")
        return response.ok
    }

    private func packs(baseURL: URL) async throws -> [AFMPackSummary] {
        let response: PacksResponse = try await send(method: "GET", baseURL: baseURL, path: "/packs")
        return response.data
    }

    private func send<Response: Decodable>(
        method: String,
        baseURL: URL,
        path: String
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(baseURL: baseURL, path: path))
        request.httpMethod = method
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        baseURL: URL,
        path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(baseURL: baseURL, path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func endpoint(baseURL: URL, path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url!
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AFMServicesClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AFMServicesClientError.httpStatus(http.statusCode)
        }
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.75
        configuration.timeoutIntervalForResource = 0.75
        return URLSession(configuration: configuration)
    }
}
