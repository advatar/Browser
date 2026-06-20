import Foundation

enum PrivateOverlayNetwork: String, CaseIterable, Identifiable, Equatable {
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

struct PrivateOverlayAdapterEndpoint: Equatable {
    let baseURL: URL
    let routePath: String
    let displayName: String
    let trustBoundary: String
}

struct PrivateOverlayAdapterConfiguration: Equatable {
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
