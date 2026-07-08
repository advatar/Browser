import Foundation

enum PrivateOverlayNetwork: String, CaseIterable, Identifiable, Equatable, Sendable {
    case tor
    case i2p
    case hyphanet
    case zeronet
    case lokinet

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .tor: "Tor onion service"
        case .i2p: "I2P eepsite"
        case .hyphanet: "Hyphanet/Freenet freesite"
        case .zeronet: "ZeroNet site"
        case .lokinet: "Lokinet site"
        }
    }

    nonisolated var schemes: [String] {
        switch self {
        case .tor: ["onion", "tor"]
        case .i2p: ["i2p"]
        case .hyphanet: ["freenet", "hyphanet"]
        case .zeronet: ["zero", "zeronet"]
        case .lokinet: ["loki", "lokinet"]
        }
    }

    nonisolated var hostSuffixes: [String] {
        switch self {
        case .tor: ["onion"]
        case .i2p: ["i2p"]
        case .lokinet: ["loki"]
        case .hyphanet, .zeronet: []
        }
    }

    nonisolated var keyPrefixes: [String] {
        switch self {
        case .hyphanet: ["CHK@", "SSK@", "USK@", "KSK@"]
        case .tor, .i2p, .zeronet, .lokinet: []
        }
    }

    nonisolated var adapterID: String {
        switch self {
        case .tor: "tor.onion"
        case .i2p: "i2p.eepproxy"
        case .hyphanet: "hyphanet.fproxy"
        case .zeronet: "zeronet.site"
        case .lokinet: "lokinet.site"
        }
    }

    nonisolated var locatorKind: String {
        switch self {
        case .tor: ".onion hostname or onion:// URI"
        case .i2p: ".i2p hostname or i2p:// URI"
        case .hyphanet: "CHK, SSK, USK, KSK, freenet:, or hyphanet: key"
        case .zeronet: "zero:// or zeronet:// site address"
        case .lokinet: ".loki hostname or lokinet:// URI"
        }
    }

    nonisolated var privacyBoundary: String {
        switch self {
        case .tor:
            "Local adapter must use Tor/Arti routing and must not resolve .onion names through system DNS or clearnet HTTPS."
        case .i2p:
            "Local adapter must use the I2P HTTP proxy or router tunnel and must not resolve .i2p names through system DNS."
        case .hyphanet:
            "Local adapter must use the Hyphanet/Freenet local proxy or FCP boundary and treat keys as private locators."
        case .zeronet:
            "Local adapter must use the ZeroNet runtime boundary and keep site addresses out of browser history."
        case .lokinet:
            "Local adapter must use Lokinet routing and must not resolve .loki names through system DNS or clearnet HTTPS."
        }
    }

    nonisolated static var supportedSchemes: Set<String> {
        Set(allCases.flatMap(\.schemes))
    }

    nonisolated static var supportedHostSuffixes: Set<String> {
        Set(allCases.flatMap(\.hostSuffixes))
    }

    nonisolated static func profile(forScheme scheme: String) -> PrivateOverlayNetwork? {
        let normalizedScheme = scheme.lowercased()
        return allCases.first { $0.schemes.contains(normalizedScheme) }
    }

    nonisolated static func profile(forHost host: String) -> PrivateOverlayNetwork? {
        let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalizedHost.isEmpty else { return nil }
        return allCases.first { network in
            network.hostSuffixes.contains { suffix in
                normalizedHost == suffix || normalizedHost.hasSuffix(".\(suffix)")
            }
        }
    }

    nonisolated static func profile(forInput rawInput: String) -> PrivateOverlayNetwork? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased() {
            if let network = profile(forScheme: scheme) {
                return network
            }
            if ["http", "https"].contains(scheme),
               let host = url.host,
               let network = profile(forHost: host) {
                return network
            }
        }

        if let hostCandidate = hostCandidate(from: input),
           let network = profile(forHost: hostCandidate) {
            return network
        }

        let uppercasedInput = input.uppercased()
        return allCases.first { network in
            network.keyPrefixes.contains { uppercasedInput.hasPrefix($0) }
        }
    }

    nonisolated static func isPrivateOverlayAddress(_ rawInput: String) -> Bool {
        profile(forInput: rawInput) != nil || isPrivateOverlayAdapterURL(rawInput)
    }

    nonisolated static func isPrivateOverlayAdapterURL(_ rawInput: String) -> Bool {
        guard let url = URL(string: rawInput),
              let host = url.host?.lowercased(),
              host == "127.0.0.1" || host == "localhost" else {
            return false
        }
        return url.path.contains("/private-overlay/")
    }

    nonisolated func canonicalURI(for rawInput: String) -> String {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return input }
        if let url = URL(string: input), let scheme = url.scheme?.lowercased() {
            if PrivateOverlayNetwork.supportedSchemes.contains(scheme) || ["http", "https"].contains(scheme) {
                return input
            }
        }
        if keyPrefixes.contains(where: { input.uppercased().hasPrefix($0) }) {
            return "hyphanet:\(input)"
        }
        if PrivateOverlayNetwork.hostCandidate(from: input).flatMap(PrivateOverlayNetwork.profile(forHost:)) == self {
            return "http://\(input)"
        }
        return input
    }

    nonisolated func localAdapterURL(
        for rawInput: String,
        endpoint: PrivateOverlayAdapterEndpoint
    ) -> URL? {
        guard var components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let routePath = endpoint.routePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, routePath].filter { !$0.isEmpty }.joined(separator: "/")
        let canonicalURI = canonicalURI(for: rawInput)
        components.queryItems = [
            URLQueryItem(name: "network", value: rawValue),
            URLQueryItem(name: "adapter", value: adapterID),
            URLQueryItem(name: "locator_kind", value: locatorKind),
            URLQueryItem(name: "uri", value: canonicalURI),
            URLQueryItem(name: "privacy", value: "ephemeral")
        ]
        return components.url
    }

    nonisolated private static func hostCandidate(from input: String) -> String? {
        let withoutFragment = input.split(separator: "#", maxSplits: 1).first.map(String.init) ?? input
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
        let firstPathComponent = withoutQuery.split(separator: "/", maxSplits: 1).first.map(String.init) ?? withoutQuery
        let withoutCredentials = firstPathComponent.split(separator: "@", maxSplits: 1).last.map(String.init) ?? firstPathComponent
        let host = withoutCredentials.split(separator: ":", maxSplits: 1).first.map(String.init) ?? withoutCredentials
        return host.isEmpty ? nil : host
    }
}

struct PrivateOverlayAdapterEndpoint: Equatable, Sendable {
    let baseURL: URL
    let routePath: String
    let displayName: String
    let trustBoundary: String
}

struct PrivateOverlayAdapterConfiguration: Equatable, Sendable {
    var endpoints: [String: PrivateOverlayAdapterEndpoint]

    nonisolated static let disabled = PrivateOverlayAdapterConfiguration(endpoints: [:])

    nonisolated static let localDefaults = PrivateOverlayAdapterConfiguration(
        endpoints: [
            "tor": PrivateOverlayAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4893")!,
                routePath: "/private-overlay/tor/native",
                displayName: "Local Tor onion adapter",
                trustBoundary: PrivateOverlayNetwork.tor.privacyBoundary
            ),
            "i2p": PrivateOverlayAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4894")!,
                routePath: "/private-overlay/i2p/native",
                displayName: "Local I2P eepsite adapter",
                trustBoundary: PrivateOverlayNetwork.i2p.privacyBoundary
            ),
            "hyphanet": PrivateOverlayAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4895")!,
                routePath: "/private-overlay/hyphanet/native",
                displayName: "Local Hyphanet/Freenet adapter",
                trustBoundary: PrivateOverlayNetwork.hyphanet.privacyBoundary
            ),
            "zeronet": PrivateOverlayAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4896")!,
                routePath: "/private-overlay/zeronet/native",
                displayName: "Local ZeroNet adapter",
                trustBoundary: PrivateOverlayNetwork.zeronet.privacyBoundary
            ),
            "lokinet": PrivateOverlayAdapterEndpoint(
                baseURL: URL(string: "http://127.0.0.1:4897")!,
                routePath: "/private-overlay/lokinet/native",
                displayName: "Local Lokinet adapter",
                trustBoundary: PrivateOverlayNetwork.lokinet.privacyBoundary
            )
        ]
    )

    nonisolated var enabledNetworkIDs: Set<String> {
        Set(endpoints.keys)
    }

    nonisolated func endpoint(for networkID: String) -> PrivateOverlayAdapterEndpoint? {
        endpoints[networkID]
    }

    nonisolated func disabling(_ networkIDs: Set<String>) -> PrivateOverlayAdapterConfiguration {
        var copy = self
        for networkID in networkIDs {
            copy.endpoints.removeValue(forKey: networkID)
        }
        return copy
    }
}

struct PrivateOverlaySmokeFixture: Equatable, Identifiable, Sendable {
    var id: String
    var network: PrivateOverlayNetwork
    var uri: String
    var expectedPayloadSHA256: String

    nonisolated static func fixture(for network: PrivateOverlayNetwork) -> PrivateOverlaySmokeFixture {
        switch network {
        case .tor:
            PrivateOverlaySmokeFixture(
                id: "dbrowser-smoke-tor-v1",
                network: network,
                uri: "http://dbrowser-smoke-test.onion/.well-known/dbrowser-private-overlay-smoke.json",
                expectedPayloadSHA256: "498fc305f7d4e17578ed598dd6db4682878ff7df911c1e6a80dbd51baa98e035"
            )
        case .i2p:
            PrivateOverlaySmokeFixture(
                id: "dbrowser-smoke-i2p-v1",
                network: network,
                uri: "http://dbrowser-smoke-test.i2p/.well-known/dbrowser-private-overlay-smoke.json",
                expectedPayloadSHA256: "cded6aed04854042cbb1a1a0aa1a119f524f5b2c1052f861872584f8e7b80d4b"
            )
        case .hyphanet:
            PrivateOverlaySmokeFixture(
                id: "dbrowser-smoke-hyphanet-v1",
                network: network,
                uri: "hyphanet:KSK@dbrowser-private-overlay-smoke",
                expectedPayloadSHA256: "a6cee122a43023ffd0955e5e8e0d0bbc53d707664662cdd1450140bb54ecad81"
            )
        case .zeronet:
            PrivateOverlaySmokeFixture(
                id: "dbrowser-smoke-zeronet-v1",
                network: network,
                uri: "zeronet://1DBrowserSmokeFixture111111111111111111111",
                expectedPayloadSHA256: "394d2c9be456492a8d2113403fa9e3f943746b4397db03f9bfc27785ab15f4a9"
            )
        case .lokinet:
            PrivateOverlaySmokeFixture(
                id: "dbrowser-smoke-lokinet-v1",
                network: network,
                uri: "http://dbrowser-smoke-test.loki/.well-known/dbrowser-private-overlay-smoke.json",
                expectedPayloadSHA256: "20b27913c01c783080263408cf3e559ee83ac50fbb03e5041e2ffacdee26036b"
            )
        }
    }
}

extension PrivateOverlayNetwork {
    nonisolated var smokeFixture: PrivateOverlaySmokeFixture {
        PrivateOverlaySmokeFixture.fixture(for: self)
    }
}

enum PrivateOverlayRuntimeReadiness: String, CaseIterable, Codable, Equatable, Sendable {
    case notInstalled
    case installed
    case running
    case reachable
    case misconfigured
    case blocked
    case verified

    nonisolated var allowsLocalNavigation: Bool {
        switch self {
        case .installed, .running, .reachable, .verified:
            return true
        case .notInstalled, .misconfigured, .blocked:
            return false
        }
    }

    nonisolated var isOperational: Bool {
        switch self {
        case .running, .reachable, .verified:
            return true
        case .notInstalled, .installed, .misconfigured, .blocked:
            return false
        }
    }

    nonisolated var statusText: String {
        switch self {
        case .notInstalled: "adapter required"
        case .installed: "health unchecked"
        case .running: "adapter running"
        case .reachable: "adapter reachable"
        case .misconfigured: "adapter misconfigured"
        case .blocked: "adapter blocked"
        case .verified: "network verified"
        }
    }
}

struct PrivateOverlayRuntimeProbeResult: Equatable, Sendable {
    var readiness: PrivateOverlayRuntimeReadiness
    var message: String

    nonisolated static func notInstalled(_ message: String) -> PrivateOverlayRuntimeProbeResult {
        PrivateOverlayRuntimeProbeResult(readiness: .notInstalled, message: message)
    }

    nonisolated static func installed(_ message: String) -> PrivateOverlayRuntimeProbeResult {
        PrivateOverlayRuntimeProbeResult(readiness: .installed, message: message)
    }

    nonisolated static func running(_ message: String) -> PrivateOverlayRuntimeProbeResult {
        PrivateOverlayRuntimeProbeResult(readiness: .running, message: message)
    }

    nonisolated static func reachable(_ message: String) -> PrivateOverlayRuntimeProbeResult {
        PrivateOverlayRuntimeProbeResult(readiness: .reachable, message: message)
    }

    nonisolated static func misconfigured(_ message: String) -> PrivateOverlayRuntimeProbeResult {
        PrivateOverlayRuntimeProbeResult(readiness: .misconfigured, message: message)
    }

    nonisolated static func blocked(_ message: String) -> PrivateOverlayRuntimeProbeResult {
        PrivateOverlayRuntimeProbeResult(readiness: .blocked, message: message)
    }

    nonisolated static func verified(_ message: String) -> PrivateOverlayRuntimeProbeResult {
        PrivateOverlayRuntimeProbeResult(readiness: .verified, message: message)
    }
}

struct PrivateOverlayRuntimeStatus: Equatable, Identifiable, Sendable {
    var network: PrivateOverlayNetwork
    var endpoint: PrivateOverlayAdapterEndpoint?
    var readiness: PrivateOverlayRuntimeReadiness
    var message: String

    nonisolated var id: String { network.id }

    nonisolated var displayName: String {
        endpoint?.displayName ?? network.title
    }

    nonisolated var statusText: String {
        "\(network.id): \(readiness.statusText)"
    }

    nonisolated var blocksNavigation: Bool {
        !readiness.allowsLocalNavigation
    }
}

struct PrivateOverlayRuntimeSnapshot: Equatable, Sendable {
    var statuses: [PrivateOverlayRuntimeStatus]

    nonisolated static func unchecked(configuration: PrivateOverlayAdapterConfiguration) -> PrivateOverlayRuntimeSnapshot {
        PrivateOverlayRuntimeSnapshot(
            statuses: PrivateOverlayNetwork.allCases.map { network in
                if let endpoint = configuration.endpoint(for: network.id) {
                    return PrivateOverlayRuntimeStatus(
                        network: network,
                        endpoint: endpoint,
                        readiness: .installed,
                        message: "\(endpoint.displayName) is configured; runtime health has not been checked yet."
                    )
                }
                return PrivateOverlayRuntimeStatus(
                    network: network,
                    endpoint: nil,
                    readiness: .notInstalled,
                    message: "\(network.title) has no configured local adapter endpoint."
                )
            }
        )
    }

    static func checking(
        configuration: PrivateOverlayAdapterConfiguration,
        healthChecker: any PrivateOverlayRuntimeHealthChecking,
        managedRuntimes: PrivateOverlayManagedRuntimeSnapshot = .empty
    ) async -> PrivateOverlayRuntimeSnapshot {
        var checkedStatuses: [PrivateOverlayRuntimeStatus] = []
        for network in PrivateOverlayNetwork.allCases {
            guard let endpoint = configuration.endpoint(for: network.id) else {
                checkedStatuses.append(
                    PrivateOverlayRuntimeStatus(
                        network: network,
                        endpoint: nil,
                        readiness: .notInstalled,
                        message: "\(network.title) has no configured local adapter endpoint."
                    )
                )
                continue
            }

            let managedStatus = managedRuntimes.status(for: network)
            if let managedStatus,
               managedStatus.readiness == .blocked || managedStatus.readiness == .misconfigured {
                checkedStatuses.append(
                    PrivateOverlayRuntimeStatus(
                        network: network,
                        endpoint: endpoint,
                        readiness: managedStatus.readiness,
                        message: managedStatus.message
                    )
                )
                continue
            }

            let healthResult = await healthChecker.check(network: network, endpoint: endpoint)
            let result = combinedProbeResult(
                healthResult: healthResult,
                managedStatus: managedStatus,
                endpoint: endpoint
            )
            checkedStatuses.append(
                PrivateOverlayRuntimeStatus(
                    network: network,
                    endpoint: endpoint,
                    readiness: result.readiness,
                    message: result.message
                )
            )
        }
        return PrivateOverlayRuntimeSnapshot(statuses: checkedStatuses)
    }

    nonisolated private static func combinedProbeResult(
        healthResult: PrivateOverlayRuntimeProbeResult,
        managedStatus: PrivateOverlayManagedRuntimeStatus?,
        endpoint: PrivateOverlayAdapterEndpoint
    ) -> PrivateOverlayRuntimeProbeResult {
        guard let managedStatus else {
            return healthResult
        }

        switch healthResult.readiness {
        case .verified, .reachable, .running:
            return PrivateOverlayRuntimeProbeResult(
                readiness: healthResult.readiness,
                message: "\(managedStatus.summary). \(healthResult.message)"
            )
        case .notInstalled:
            switch managedStatus.lifecycle {
            case .launchReady:
                return .notInstalled("\(managedStatus.message) \(endpoint.displayName) is not responding yet; start the managed runtime before navigation.")
            case .running, .starting, .stopping:
                return .misconfigured("\(managedStatus.message) \(endpoint.displayName) did not answer health checks.")
            case .notInstalled, .disabled, .stopped:
                return .notInstalled("\(managedStatus.message) \(healthResult.message)")
            case .misconfigured, .failed:
                return .misconfigured("\(managedStatus.message) \(healthResult.message)")
            case .blocked:
                return .blocked(managedStatus.message)
            }
        case .installed:
            return .installed("\(managedStatus.summary). \(healthResult.message)")
        case .misconfigured:
            return .misconfigured("\(managedStatus.summary). \(healthResult.message)")
        case .blocked:
            return .blocked("\(managedStatus.summary). \(healthResult.message)")
        }
    }

    nonisolated func status(for network: PrivateOverlayNetwork) -> PrivateOverlayRuntimeStatus? {
        statuses.first { $0.network == network }
    }

    nonisolated var operationalStatuses: [PrivateOverlayRuntimeStatus] {
        statuses.filter { $0.readiness.isOperational }
    }

    nonisolated var verifiedStatuses: [PrivateOverlayRuntimeStatus] {
        statuses.filter { $0.readiness == .verified }
    }

    nonisolated var hasOperationalRuntime: Bool {
        !operationalStatuses.isEmpty
    }

    nonisolated var summary: String {
        if statuses.isEmpty {
            return "Private-overlay adapters unavailable"
        }
        let verifiedCount = verifiedStatuses.count
        let operationalCount = operationalStatuses.count
        if verifiedCount == statuses.count {
            return "All private-overlay runtimes verified"
        }
        if verifiedCount > 0 {
            return "\(verifiedCount) verified, \(operationalCount) operational private-overlay runtime\(operationalCount == 1 ? "" : "s")"
        }
        if operationalCount > 0 {
            return "\(operationalCount) operational private-overlay runtime\(operationalCount == 1 ? "" : "s"); smoke tests pending"
        }
        let configuredStatuses = statuses.filter { $0.endpoint != nil }
        let configuredCount = configuredStatuses.count
        if configuredCount > 0 {
            let blockedCount = configuredStatuses.filter { $0.readiness == .blocked }.count
            let misconfiguredCount = configuredStatuses.filter { $0.readiness == .misconfigured }.count
            let notRespondingCount = configuredStatuses.filter { $0.readiness == .notInstalled }.count
            if blockedCount > 0 || misconfiguredCount > 0 || notRespondingCount > 0 {
                var fragments: [String] = []
                if notRespondingCount > 0 {
                    fragments.append("\(notRespondingCount) not responding")
                }
                if blockedCount > 0 {
                    fragments.append("\(blockedCount) blocked")
                }
                if misconfiguredCount > 0 {
                    fragments.append("\(misconfiguredCount) misconfigured")
                }
                return "\(fragments.joined(separator: ", ")) private-overlay runtime\(configuredCount == 1 ? "" : "s")"
            }
            return "\(configuredCount) private-overlay adapter\(configuredCount == 1 ? "" : "s") configured; health not verified"
        }
        return "Private-overlay runtime adapters required"
    }
}

protocol PrivateOverlayRuntimeHealthChecking: Sendable {
    func check(
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint
    ) async -> PrivateOverlayRuntimeProbeResult
}

private struct PrivateOverlayRuntimeHealthPayload: Decodable, Sendable {
    var network: String?
    var status: String?
    var message: String?
    var verified: Bool?
    var clearnetFallback: Bool?
}

protocol PrivateOverlayRuntimeSmokeVerifying: Sendable {
    func verify(
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint
    ) async -> PrivateOverlayRuntimeProbeResult
}

private struct PrivateOverlayRuntimeSmokePayload: Decodable, Sendable {
    var network: String?
    var fixtureID: String?
    var status: String?
    var message: String?
    var verified: Bool?
    var payloadSHA256: String?
    var clearnetFallback: Bool?
    var dnsResolution: Bool?
    var searchFallback: Bool?
    var publicGateway: Bool?

    private enum CodingKeys: String, CodingKey {
        case network
        case fixtureID
        case fixtureId
        case fixture_id
        case status
        case message
        case verified
        case payloadSHA256
        case payloadSha256
        case payload_sha256
        case clearnetFallback
        case clearnet_fallback
        case dnsResolution
        case dns_resolution
        case searchFallback
        case search_fallback
        case publicGateway
        case public_gateway
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decodeIfPresent(String.self, forKey: .network)
        fixtureID = try container.decodeIfPresent(String.self, forKey: .fixtureID)
            ?? container.decodeIfPresent(String.self, forKey: .fixtureId)
            ?? container.decodeIfPresent(String.self, forKey: .fixture_id)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified)
        payloadSHA256 = try container.decodeIfPresent(String.self, forKey: .payloadSHA256)
            ?? container.decodeIfPresent(String.self, forKey: .payloadSha256)
            ?? container.decodeIfPresent(String.self, forKey: .payload_sha256)
        clearnetFallback = try container.decodeIfPresent(Bool.self, forKey: .clearnetFallback)
            ?? container.decodeIfPresent(Bool.self, forKey: .clearnet_fallback)
        dnsResolution = try container.decodeIfPresent(Bool.self, forKey: .dnsResolution)
            ?? container.decodeIfPresent(Bool.self, forKey: .dns_resolution)
        searchFallback = try container.decodeIfPresent(Bool.self, forKey: .searchFallback)
            ?? container.decodeIfPresent(Bool.self, forKey: .search_fallback)
        publicGateway = try container.decodeIfPresent(Bool.self, forKey: .publicGateway)
            ?? container.decodeIfPresent(Bool.self, forKey: .public_gateway)
    }
}

struct URLSessionPrivateOverlayRuntimeSmokeVerifier: PrivateOverlayRuntimeSmokeVerifying, Sendable {
    var timeout: TimeInterval = 0.75

    func verify(
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint
    ) async -> PrivateOverlayRuntimeProbeResult {
        let fixture = network.smokeFixture
        guard endpoint.baseURL.isPrivateOverlayLoopbackHTTPURL else {
            return .blocked("\(endpoint.displayName) smoke verification must use a loopback HTTP adapter endpoint.")
        }
        guard let url = smokeURL(for: network, endpoint: endpoint, fixture: fixture) else {
            return .misconfigured("\(endpoint.displayName) could not build a smoke fixture URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .misconfigured("\(endpoint.displayName) returned a non-HTTP smoke response.")
            }
            return probeResult(
                network: network,
                endpoint: endpoint,
                fixture: fixture,
                statusCode: httpResponse.statusCode,
                data: data
            )
        } catch {
            return .reachable("\(endpoint.displayName) health endpoint is reachable; smoke fixture \(fixture.id) has not verified yet.")
        }
    }

    func smokeURL(
        for network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint,
        fixture: PrivateOverlaySmokeFixture
    ) -> URL? {
        guard fixture.network == network,
              var components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/private-overlay/\(network.id)/smoke"
        components.queryItems = [
            URLQueryItem(name: "network", value: network.id),
            URLQueryItem(name: "adapter", value: network.adapterID),
            URLQueryItem(name: "fixture_id", value: fixture.id),
            URLQueryItem(name: "uri", value: fixture.uri),
            URLQueryItem(name: "expected_sha256", value: fixture.expectedPayloadSHA256),
            URLQueryItem(name: "no_dns", value: "1"),
            URLQueryItem(name: "no_search", value: "1"),
            URLQueryItem(name: "no_public_gateway", value: "1"),
            URLQueryItem(name: "no_clearnet", value: "1")
        ]
        return components.url
    }

    func probeResult(
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint,
        fixture: PrivateOverlaySmokeFixture,
        statusCode: Int,
        data: Data
    ) -> PrivateOverlayRuntimeProbeResult {
        switch statusCode {
        case 200:
            guard !data.isEmpty,
                  let payload = try? JSONDecoder().decode(PrivateOverlayRuntimeSmokePayload.self, from: data) else {
                return .reachable("\(endpoint.displayName) smoke endpoint is reachable but did not return fixture proof.")
            }
            return probeResult(network: network, endpoint: endpoint, fixture: fixture, payload: payload)
        case 204:
            return .reachable("\(endpoint.displayName) smoke endpoint is reachable but did not return fixture proof.")
        case 401, 403:
            return .blocked("\(endpoint.displayName) rejected smoke checks; user permission or platform policy is required.")
        case 404, 405, 501:
            return .reachable("\(endpoint.displayName) does not expose the dBrowser smoke contract yet; network smoke verification is still pending.")
        case 400, 409, 422, 500...599:
            return .misconfigured("\(endpoint.displayName) reported HTTP \(statusCode) for smoke verification.")
        default:
            return .misconfigured("\(endpoint.displayName) returned unexpected smoke HTTP \(statusCode).")
        }
    }

    private func probeResult(
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint,
        fixture: PrivateOverlaySmokeFixture,
        payload: PrivateOverlayRuntimeSmokePayload
    ) -> PrivateOverlayRuntimeProbeResult {
        guard let payloadNetwork = payload.network else {
            return .reachable("\(endpoint.displayName) smoke response did not include a network proof.")
        }
        if payloadNetwork.caseInsensitiveCompare(network.id) != .orderedSame {
            return .misconfigured("\(endpoint.displayName) smoke response identified \(payloadNetwork), expected \(network.id).")
        }
        guard let fixtureID = payload.fixtureID else {
            return .reachable("\(endpoint.displayName) smoke response did not include a fixture id.")
        }
        if fixtureID != fixture.id {
            return .misconfigured("\(endpoint.displayName) smoke response identified fixture \(fixtureID), expected \(fixture.id).")
        }
        guard let digest = payload.payloadSHA256?.lowercased() else {
            return .reachable("\(endpoint.displayName) smoke response did not include a fixture digest.")
        }
        guard payload.clearnetFallback != nil,
              payload.dnsResolution != nil,
              payload.searchFallback != nil,
              payload.publicGateway != nil else {
            return .reachable("\(endpoint.displayName) smoke response did not include all fallback assertions.")
        }
        if payload.clearnetFallback == true || payload.dnsResolution == true || payload.searchFallback == true || payload.publicGateway == true {
            return .blocked("\(endpoint.displayName) smoke response reported DNS, search, public gateway, or clearnet fallback.")
        }
        if digest != fixture.expectedPayloadSHA256.lowercased() {
            return .misconfigured("\(endpoint.displayName) smoke response digest \(digest) did not match expected fixture digest.")
        }

        let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackMessage = "\(endpoint.displayName) smoke fixture \(fixture.id) verified without DNS, search, public gateway, or clearnet fallback."
        let resolvedMessage = message?.isEmpty == false ? message! : fallbackMessage
        if payload.verified == true || payload.status?.lowercased() == "verified" {
            return .verified(resolvedMessage)
        }
        return .reachable("\(endpoint.displayName) smoke endpoint is reachable but fixture \(fixture.id) is not verified yet.")
    }
}

struct URLSessionPrivateOverlayRuntimeHealthChecker: PrivateOverlayRuntimeHealthChecking, Sendable {
    var timeout: TimeInterval = 0.35
    var smokeVerifier: (any PrivateOverlayRuntimeSmokeVerifying)? = URLSessionPrivateOverlayRuntimeSmokeVerifier()

    func check(
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint
    ) async -> PrivateOverlayRuntimeProbeResult {
        guard let url = healthURL(for: network, endpoint: endpoint) else {
            return .misconfigured("\(endpoint.displayName) has an invalid health-check URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .misconfigured("\(endpoint.displayName) returned a non-HTTP health response.")
            }
            let healthResult = probeResult(
                network: network,
                endpoint: endpoint,
                statusCode: httpResponse.statusCode,
                data: data
            )
            return await probeResultAfterSmokeVerification(
                healthResult: healthResult,
                network: network,
                endpoint: endpoint
            )
        } catch {
            return .notInstalled("\(endpoint.displayName) did not respond on \(endpoint.baseURL.absoluteString); runtime may be missing or stopped.")
        }
    }

    private func healthURL(
        for network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint
    ) -> URL? {
        guard var components = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/private-overlay/\(network.id)/health"
        components.queryItems = [
            URLQueryItem(name: "network", value: network.id),
            URLQueryItem(name: "adapter", value: network.adapterID)
        ]
        return components.url
    }

    func mergedProbeResult(
        healthResult: PrivateOverlayRuntimeProbeResult,
        smokeResult: PrivateOverlayRuntimeProbeResult
    ) -> PrivateOverlayRuntimeProbeResult {
        switch smokeResult.readiness {
        case .verified, .blocked, .misconfigured:
            return smokeResult
        case .notInstalled:
            if healthResult.readiness == .verified {
                return healthResult
            }
            return PrivateOverlayRuntimeProbeResult(
                readiness: healthResult.readiness,
                message: "\(healthResult.message) \(smokeResult.message)"
            )
        case .installed, .running, .reachable:
            if healthResult.readiness == .verified {
                return healthResult
            }
            return PrivateOverlayRuntimeProbeResult(
                readiness: healthResult.readiness,
                message: "\(healthResult.message) \(smokeResult.message)"
            )
        }
    }

    private func probeResultAfterSmokeVerification(
        healthResult: PrivateOverlayRuntimeProbeResult,
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint
    ) async -> PrivateOverlayRuntimeProbeResult {
        guard healthResult.readiness.isOperational,
              let smokeVerifier else {
            return healthResult
        }
        let smokeResult = await smokeVerifier.verify(network: network, endpoint: endpoint)
        return mergedProbeResult(healthResult: healthResult, smokeResult: smokeResult)
    }

    private func probeResult(
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint,
        statusCode: Int,
        data: Data
    ) -> PrivateOverlayRuntimeProbeResult {
        switch statusCode {
        case 200:
            guard !data.isEmpty,
                  let payload = try? JSONDecoder().decode(PrivateOverlayRuntimeHealthPayload.self, from: data) else {
                return .reachable("\(endpoint.displayName) health endpoint is reachable; network smoke verification is still pending.")
            }
            return probeResult(network: network, endpoint: endpoint, payload: payload)
        case 204:
            return .reachable("\(endpoint.displayName) health endpoint is reachable; network smoke verification is still pending.")
        case 401, 403:
            return .blocked("\(endpoint.displayName) rejected health checks; user permission or platform policy is required.")
        case 404, 405, 501:
            return .running("\(endpoint.displayName) responded locally but does not expose the dBrowser health contract yet.")
        case 400, 409, 422, 500...599:
            return .misconfigured("\(endpoint.displayName) reported HTTP \(statusCode); adapter configuration needs attention.")
        default:
            return .misconfigured("\(endpoint.displayName) returned unexpected HTTP \(statusCode).")
        }
    }

    private func probeResult(
        network: PrivateOverlayNetwork,
        endpoint: PrivateOverlayAdapterEndpoint,
        payload: PrivateOverlayRuntimeHealthPayload
    ) -> PrivateOverlayRuntimeProbeResult {
        if let payloadNetwork = payload.network,
           payloadNetwork.caseInsensitiveCompare(network.id) != .orderedSame {
            return .misconfigured("\(endpoint.displayName) health response identified \(payloadNetwork), expected \(network.id).")
        }
        if payload.clearnetFallback == true {
            return .blocked("\(endpoint.displayName) reports clearnet fallback; dBrowser will not use it for private-overlay navigation.")
        }

        let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackMessage = "\(endpoint.displayName) health endpoint is reachable; network smoke verification is still pending."
        let resolvedMessage = message?.isEmpty == false ? message! : fallbackMessage
        if payload.verified == true {
            return .verified(resolvedMessage)
        }

        switch payload.status?.lowercased() {
        case "verified":
            return .verified(resolvedMessage)
        case "reachable", "ready", "ok", "healthy":
            return .reachable(resolvedMessage)
        case "running":
            return .running(resolvedMessage)
        case "installed":
            return .installed(resolvedMessage)
        case "blocked", "permission-required":
            return .blocked(resolvedMessage)
        case "misconfigured", "error", "failed":
            return .misconfigured(resolvedMessage)
        case "not-installed", "missing", "stopped":
            return .notInstalled(resolvedMessage)
        default:
            return .reachable(resolvedMessage)
        }
    }
}

private extension URL {
    var isPrivateOverlayLoopbackHTTPURL: Bool {
        guard scheme?.lowercased() == "http",
              let host = host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }
}
