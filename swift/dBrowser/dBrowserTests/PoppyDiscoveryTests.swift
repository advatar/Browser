import Foundation
import Testing
@testable import dBrowser

struct PoppyDiscoveryTests {
    private let servedAt = URL(string: "https://example.com/.well-known/poppy.json")!

    @Test func discoverySendsOnlyTheCompanyOrigin() throws {
        let page = try #require(URL(string: "https://example.com/account?secret=value#fragment"))
        #expect(PoppyDiscovery.discoveryURL(for: page) == servedAt)
        #expect(PoppyDiscovery.discoveryURL(for: URL(string: "https://127.0.0.1/account")!) == nil)
        #expect(PoppyDiscovery.discoveryURL(for: URL(string: "https://user@example.com/account")!) == nil)
    }

    @Test func redirectKeepsCanonicalSiteAndManifestPath() {
        #expect(PoppyDiscovery.allowsRedirect(
            to: URL(string: "https://www.example.com/.well-known/poppy.json")!, from: servedAt
        ))
        #expect(!PoppyDiscovery.allowsRedirect(
            to: URL(string: "https://example.com/upload/poppy.json")!, from: servedAt
        ))
        #expect(!PoppyDiscovery.allowsRedirect(
            to: URL(string: "https://other.example/.well-known/poppy.json")!, from: servedAt
        ))
    }

    @Test func manifestReportsOnlyRecognizedChannels() throws {
        let manifest = try PoppyDiscovery.manifest(from: fixture(), servedAt: servedAt)
        #expect(manifest.organization.domain == "example.com")
        #expect(manifest.capabilities == ["OpenAPI", "Website"])
    }

    @Test func rejectsWrongIdentityUnsupportedVersionAndInsecureEndpoint() {
        #expect(throws: PoppyDiscovery.Failure.invalidManifest) {
            try PoppyDiscovery.manifest(from: fixture(domain: "other.example"), servedAt: servedAt)
        }
        #expect(throws: PoppyDiscovery.Failure.unsupportedVersion) {
            try PoppyDiscovery.manifest(from: fixture(version: "2.0"), servedAt: servedAt)
        }
        #expect(throws: PoppyDiscovery.Failure.invalidManifest) {
            try PoppyDiscovery.manifest(from: fixture(scheme: "http"), servedAt: servedAt)
        }
    }

    @Test func fetchesManifestWithoutForwardingPageContext() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PoppyManifestFixtureProtocol.self]
        let page = try #require(URL(string: "https://example.com/account?secret=value#fragment"))
        let manifest = try await PoppyDiscovery().discover(page: page, configuration: configuration)
        #expect(manifest.organization.domain == "example.com")
        #expect(manifest.capabilities == ["Website"])
    }

    private func fixture(
        domain: String = "example.com", version: String = "1.0", scheme: String = "https"
    ) -> Data {
        Data("""
        {
          "protocol_version": "\(version)",
          "organization": {"name": "Example", "domain": "\(domain)"},
          "apis": [
            {"type": "openapi", "url": "\(scheme)://api.example.com/spec.json"},
            {"type": "future", "url": "https://example.com/future"}
          ],
          "web": {}
        }
        """.utf8)
    }
}

private final class PoppyManifestFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              url.absoluteString == "https://example.com/.well-known/poppy.json",
              request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "Referer") == nil,
              request.value(forHTTPHeaderField: "Poppy-Session") == nil,
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("""
        {"protocol_version":"1.0","organization":{"name":"Example","domain":"example.com"},"web":{}}
        """.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
