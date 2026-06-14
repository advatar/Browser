import Foundation
import UniversalInteractionKit

/// Builds Hyperactive Web adapters from dBrowser's configured surfaces, so
/// capabilities resolve to real invocations. Slice 2 of #149.
enum HyperactiveAdapters {
    /// One UIK `MCPAdapter` per enabled HTTP MCP server (CapabilityMethod.invoke).
    static func make(from servers: [MCPServerConfiguration]) -> [any UniversalAdapter] {
        servers.compactMap { server in
            guard server.enabled, server.transport == .http,
                  let url = URL(string: server.endpoint) else { return nil }
            return MCPAdapter(id: server.id, endpoint: url, headers: parseHeaders(server.headersText))
        }
    }

    private static func parseHeaders(_ text: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty { headers[parts[0]] = parts[1] }
        }
        return headers
    }
}
