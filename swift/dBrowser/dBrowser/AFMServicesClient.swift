import Foundation

struct AFMServiceEndpointConfiguration: Equatable {
    var routerBaseURL: URL
    var registryBaseURL: URL
    var pipelinesBaseURL: URL
    var nodeBaseURL: URL

    nonisolated static let local = AFMServiceEndpointConfiguration(
        routerBaseURL: URL(string: "http://127.0.0.1:4810")!,
        registryBaseURL: URL(string: "http://127.0.0.1:4820")!,
        pipelinesBaseURL: URL(string: "http://127.0.0.1:4830")!,
        nodeBaseURL: URL(string: "http://127.0.0.1:4840")!
    )
}

struct AFMServiceSnapshot: Equatable {
    var routerAvailable: Bool
    var registryAvailable: Bool
    var pipelinesAvailable: Bool
    var nodeAvailable: Bool
    var routerPacks: [AFMPackSummary]
    var registryPacks: [AFMPackSummary]

    static let unknown = AFMServiceSnapshot(
        routerAvailable: true,
        registryAvailable: true,
        pipelinesAvailable: true,
        nodeAvailable: true,
        routerPacks: [],
        registryPacks: []
    )

    var allServicesAvailable: Bool {
        routerAvailable && registryAvailable && pipelinesAvailable && nodeAvailable
    }

    var coreCopilotServicesAvailable: Bool {
        routerAvailable && pipelinesAvailable
    }

    var serviceStatusText: String {
        let states = [
            "router \(routerAvailable ? "online" : "offline")",
            "registry \(registryAvailable ? "online" : "offline")",
            "pipelines \(pipelinesAvailable ? "online" : "offline")",
            "node \(nodeAvailable ? "online" : "offline")"
        ]
        return states.joined(separator: ", ")
    }

    var availablePacks: [AFMPackSummary] {
        var packsByID: [String: AFMPackSummary] = [:]
        for pack in routerPacks + registryPacks {
            packsByID[pack.id] = packsByID[pack.id]?.merged(with: pack) ?? pack
        }
        return packsByID.values.sorted { $0.displayName < $1.displayName }
    }
}

struct AFMPackSummary: Codable, Equatable, Identifiable {
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

    func merged(with other: AFMPackSummary) -> AFMPackSummary {
        AFMPackSummary(
            id: id,
            name: name ?? other.name,
            maintainer: maintainer ?? other.maintainer,
            version: version ?? other.version,
            checksum: checksum ?? other.checksum,
            skills: skills ?? other.skills,
            status: status ?? other.status
        )
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

struct AFMNodeInstallReceipt: Codable, Equatable {
    var mode: String
    var installCommitment: String
    var verifier: String
}

struct AFMNodeInstallResult: Codable, Equatable, Identifiable {
    var ok: Bool?
    var id: String
    var packID: String
    var checksum: String?
    var bundleURL: String?
    var requestedBy: String?
    var status: String
    var mode: String
    var installedAt: String?
    var receipt: AFMNodeInstallReceipt?
}

struct AFMNodeTaskOutput: Codable, Equatable {
    var summary: String
    var outputCommitment: String
    var completedAt: String?
}

struct AFMAttestedRun: Codable, Equatable {
    var mode: String
    var taskID: String
    var outputCommitment: String
    var nonce: String
    var tokenCount: Int
    var contextPassages: Int
    var attestationToken: String?
}

struct AFMProofState: Codable, Equatable {
    var id: String?
    var proofID: String?
    var status: String
    var verifier: String
    var publicInputs: [String: String]?
}

struct AFMSettlementState: Codable, Equatable {
    var id: String?
    var status: String
    var chainRef: String?
    var escrowID: String?
    var verifier: String?
    var mode: String?
    var settledAt: String?
}

struct AFMNodeTaskResult: Codable, Equatable, Identifiable {
    var ok: Bool?
    var id: String
    var taskID: String
    var packID: String
    var installID: String?
    var status: String
    var mode: String
    var result: AFMNodeTaskOutput
    var attestation: AFMAttestedRun
    var proof: AFMProofState
    var settlement: AFMSettlementState
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
        let preferredPackID: String?
        let pageSnapshotCommitment: String?
        let memoryContextIDs: [String]
    }

    private struct PipelineJobRequest: Encodable {
        let name: String
        let payload: PipelineJobPayload
    }

    private struct PipelineJobPayload: Encodable {
        let prompt: String
        let pageURLString: String?
        let selectedPackID: String?
        let preferredPackID: String?
        let pageSnapshotCommitment: String?
        let memoryContextIDs: [String]
    }

    private struct NodeInstallRequest: Encodable {
        let packID: String
        let checksum: String?
        let bundleURL: String?
        let requestedBy: String
    }

    private struct NodeTaskRequest: Encodable {
        let prompt: String
        let pageURLString: String?
        let selectedPackID: String?
        let pageSnapshotCommitment: String?
        let memoryContextIDs: [String]
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
        let nodeAvailable = (try? await health(baseURL: configuration.nodeBaseURL)) ?? false
        let routerPacks = routerAvailable ? ((try? await packs(baseURL: configuration.routerBaseURL)) ?? []) : []
        let registryPacks = registryAvailable ? ((try? await packs(baseURL: configuration.registryBaseURL)) ?? []) : []

        return AFMServiceSnapshot(
            routerAvailable: routerAvailable,
            registryAvailable: registryAvailable,
            pipelinesAvailable: pipelinesAvailable,
            nodeAvailable: nodeAvailable,
            routerPacks: routerPacks,
            registryPacks: registryPacks
        )
    }

    func route(
        skill: String,
        prompt: String,
        pageURLString: String?,
        preferredPackID: String? = nil,
        pageSnapshotCommitment: String? = nil,
        memoryContextIDs: [String] = []
    ) async throws -> AFMRouteResult {
        let body = RouteRequest(
            skill: skill,
            prompt: prompt,
            pageURLString: pageURLString,
            preferredPackID: preferredPackID,
            pageSnapshotCommitment: pageSnapshotCommitment,
            memoryContextIDs: memoryContextIDs
        )
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
        selectedPackID: String?,
        preferredPackID: String? = nil,
        pageSnapshotCommitment: String? = nil,
        memoryContextIDs: [String] = []
    ) async throws -> AFMPipelineJobResult {
        let body = PipelineJobRequest(
            name: "swift-copilot",
            payload: PipelineJobPayload(
                prompt: prompt,
                pageURLString: pageURLString,
                selectedPackID: selectedPackID,
                preferredPackID: preferredPackID,
                pageSnapshotCommitment: pageSnapshotCommitment,
                memoryContextIDs: memoryContextIDs
            )
        )
        return try await send(
            method: "POST",
            baseURL: configuration.pipelinesBaseURL,
            path: "/jobs",
            body: body
        )
    }

    func installPack(
        packID: String,
        checksum: String?,
        bundleURL: String? = nil,
        requestedBy: String = "swift-copilot"
    ) async throws -> AFMNodeInstallResult {
        let body = NodeInstallRequest(
            packID: packID,
            checksum: checksum,
            bundleURL: bundleURL,
            requestedBy: requestedBy
        )
        return try await send(
            method: "POST",
            baseURL: configuration.nodeBaseURL,
            path: "/packs/install",
            body: body
        )
    }

    func dispatchTask(
        prompt: String,
        pageURLString: String?,
        selectedPackID: String?,
        pageSnapshotCommitment: String?,
        memoryContextIDs: [String] = []
    ) async throws -> AFMNodeTaskResult {
        let body = NodeTaskRequest(
            prompt: prompt,
            pageURLString: pageURLString,
            selectedPackID: selectedPackID,
            pageSnapshotCommitment: pageSnapshotCommitment,
            memoryContextIDs: memoryContextIDs
        )
        return try await send(
            method: "POST",
            baseURL: configuration.nodeBaseURL,
            path: "/tasks",
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
