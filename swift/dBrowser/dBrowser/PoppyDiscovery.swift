import Foundation

nonisolated struct PoppyManifest: Decodable, Equatable {
    struct Organization: Decodable, Equatable {
        let name: String
        let domain: String
    }

    struct API: Decodable, Equatable {
        let type: String
        let url: URL
    }

    struct CompanyAgent: Decodable, Equatable {
        struct Channel: Decodable, Equatable {
            let type: String
            let endpoint: URL
        }

        let protocols: [Channel]
    }

    struct Website: Decodable, Equatable {
        let disabled: Bool?
        let browserSessionEndpoint: URL?

        enum CodingKeys: String, CodingKey {
            case disabled
            case browserSessionEndpoint = "browser_session_endpoint"
        }
    }

    let protocolVersion: String
    let organization: Organization
    let apis: [API]?
    let agent: CompanyAgent?
    let web: Website?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case organization, apis, agent, web
    }

    var capabilities: [String] {
        var names = (apis ?? []).compactMap { api in
            switch api.type {
            case "openapi": return "OpenAPI"
            case "mcp": return "MCP"
            default: return nil
            }
        }
        if agent?.protocols.isEmpty == false { names.append("Company agent") }
        if let web, web.disabled != true {
            names.append(web.browserSessionEndpoint == nil ? "Website" : "Website session")
        }
        return names
    }
}

nonisolated struct PoppyDiscovery {
    static let manifestPath = "/.well-known/poppy.json"
    static let manifestLimit = 128 * 1024

    enum Failure: LocalizedError, Equatable {
        case unsupportedSite
        case notPublished
        case invalidManifest
        case unsupportedVersion
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedSite: "Poppy discovery needs a public HTTPS website."
            case .notPublished: "This site has no published Poppy manifest."
            case .invalidManifest: "This site returned an invalid Poppy manifest."
            case .unsupportedVersion: "This site requires an unsupported Poppy version."
            case .unavailable: "Poppy discovery could not reach this site."
            }
        }
    }

    static func discoveryURL(for page: URL) -> URL? {
        guard publicHTTPS(page), var target = URLComponents(url: page, resolvingAgainstBaseURL: false) else {
            return nil
        }
        target.path = manifestPath
        target.query = nil
        target.fragment = nil
        return target.url
    }

    static func publicHTTPS(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(), host.contains("."),
              let lastLabel = host.split(separator: ".", omittingEmptySubsequences: false).last,
              lastLabel.first?.isLetter == true else { return false }
        return !host.hasSuffix(".local") && !host.hasSuffix(".localhost")
            && !host.hasSuffix(".internal") && !host.hasSuffix(".onion")
    }

    static func allowsRedirect(to target: URL, from origin: URL) -> Bool {
        guard let originalHost = origin.host?.lowercased(),
              let targetHost = target.host?.lowercased(),
              discoveryURL(for: target) == target else { return false }
        // Restrict automatic discovery redirects to the site's canonical www variant.
        return originalHost == targetHost || "www." + originalHost == targetHost
            || originalHost == "www." + targetHost
    }

    static func manifest(from data: Data, servedAt url: URL) throws -> PoppyManifest {
        guard data.count <= manifestLimit, discoveryURL(for: url) == url,
              let host = url.host,
              let manifest = try? JSONDecoder().decode(PoppyManifest.self, from: data),
              manifest.organization.domain.caseInsensitiveCompare(host) == .orderedSame,
              !manifest.organization.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.apis?.isEmpty == false || manifest.agent?.protocols.isEmpty == false || manifest.web != nil,
              (manifest.apis ?? []).allSatisfy({ publicHTTPS($0.url) }),
              (manifest.agent?.protocols ?? []).allSatisfy({ publicHTTPS($0.endpoint) }),
              manifest.web?.browserSessionEndpoint.map(publicHTTPS) ?? true else {
            throw Failure.invalidManifest
        }

        let version = manifest.protocolVersion.split(separator: ".", omittingEmptySubsequences: false)
        guard version.count == 2, version[0] == "1", UInt(version[1]) != nil else {
            throw Failure.unsupportedVersion
        }
        return manifest
    }

    func discover(
        page: URL, configuration: URLSessionConfiguration = .ephemeral
    ) async throws -> PoppyManifest {
        guard let url = Self.discoveryURL(for: page) else { throw Failure.unsupportedSite }
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: PoppyDiscoveryRedirects(origin: url), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let finalURL = http.url,
              Self.allowsRedirect(to: finalURL, from: url) else { throw Failure.unavailable }
        if http.statusCode == 404 { throw Failure.notPublished }
        guard http.statusCode == 200 else { throw Failure.unavailable }

        var body = Data()
        for try await byte in bytes {
            guard body.count < Self.manifestLimit else { throw Failure.invalidManifest }
            body.append(byte)
        }
        return try Self.manifest(from: body, servedAt: finalURL)
    }
}

private nonisolated final class PoppyDiscoveryRedirects: NSObject, URLSessionTaskDelegate {
    let origin: URL

    init(origin: URL) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, PoppyDiscovery.allowsRedirect(to: url, from: origin) else { return nil }
        return request
    }
}
