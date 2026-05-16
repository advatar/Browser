//
//  dBrowserTests.swift
//  dBrowserTests
//
//  Created by Johan Sellström on 2026-05-15.
//

import Testing
import Foundation
import MLXLMCommon
@testable import dBrowser

struct dBrowserTests {

    @Test func bareDomainResolvesToHTTPS() {
        let resolved = BrowserURLResolver.resolve("example.com")
        guard case .web(let url) = resolved else {
            Issue.record("Expected HTTPS URL")
            return
        }
        #expect(url == URL(string: "https://example.com")!)
    }

    @Test func searchTermsResolveToDuckDuckGoQuery() {
        let resolved = BrowserURLResolver.resolve("zero knowledge proofs")
        guard case .web(let url) = resolved else {
            Issue.record("Expected search URL")
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "q" }?
            .value
        #expect(url.host == "duckduckgo.com")
        #expect(query == "zero knowledge proofs")
    }

    @Test func decentralizedProtocolsDelegateToRuntimeBridge() {
        let resolved = BrowserURLResolver.resolve("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi")
        guard case .unsupported(let raw, let message) = resolved else {
            Issue.record("Expected runtime bridge delegation")
            return
        }
        #expect(raw.hasPrefix("ipfs://"))
        #expect(message.contains("runtime bridge"))
    }

    @Test func ensNamesDelegateToRuntimeBridgeBeforeHTTPSFallback() {
        let resolved = BrowserURLResolver.resolve("vitalik.eth")
        guard case .unsupported(let raw, let message) = resolved else {
            Issue.record("Expected runtime bridge delegation")
            return
        }
        #expect(raw == "vitalik.eth")
        #expect(message.contains("decentralized name"))
    }

    @Test func runtimeFeaturesExposeDetailedExplanations() {
        for feature in MobileRuntimeFeature.allCases {
            let explanation = feature.explanation
            #expect(!explanation.overview.isEmpty)
            #expect(!explanation.bridgeBehavior.isEmpty)
            #expect(explanation.detailPoints.count >= 3)
            #expect(explanation.detailPoints.allSatisfy { !$0.isEmpty })
        }
    }

    @Test func decentralizedStartingPointsAreRuntimeResolvable() {
        let points = DecentralizedStartingPoint.featured
        #expect(points.count >= 4)

        for point in points {
            #expect(!point.title.isEmpty)
            #expect(point.description.count > 30)
            #expect(!point.systemImage.isEmpty)

            guard let url = URL(string: point.address), let scheme = url.scheme?.lowercased() else {
                Issue.record("Expected URL-like decentralized address for \(point.title)")
                continue
            }

            #expect(["ipfs", "ipns", "ens"].contains(scheme))
        }
    }

    @Test func bundledLLMSelectsIPhoneSizedGemma4Model() {
        let selection = BundledLLMSelection.recommended
        let profile = selection.profile

        #expect(profile.displayName == "Gemma 4 E2B IT 4-bit MLX")
        #expect(profile.isRecommendedForIPhone)
        #expect(profile.localDiskFootprintGB < 4)
        #expect(profile.recommendedMinimumMemoryGB == 8)
        #expect(profile.swiftPackageURL == "https://github.com/ml-explore/mlx-swift-lm")
        #expect(profile.swiftPackageMinimumVersion == "3.31.3")
        #expect(profile.swiftPackageProducts == ["MLXVLM", "MLXLMCommon"])
        #expect(profile.loaderSupport.isRunnableWithCurrentSwiftLoader)
        #expect(profile.readinessSummary.contains("MLXVLM"))
    }

    @Test func bundledLLMUsesLocalMLXArtifactWhenPresent() {
        let selection = BundledLLMSelection.recommended
        let location = selection.modelLocation()

        guard case .localDirectory(let url) = location else {
            Issue.record("Expected the existing local Gemma 4 MLX model to be selected")
            return
        }

        #expect(url.path.hasSuffix("/Broom/diskspace-gemma/models/gemma-4-e2b-it-4bit-mlx"))
    }

    @Test func bundledLLMModelConfigurationUsesMLXVLMRegistry() {
        let selection = BundledLLMSelection.recommended
        let configuration = selection.modelConfiguration()

        guard case .directory(let url) = configuration.id else {
            Issue.record("Expected the existing local Gemma 4 MLX model to back the configuration")
            return
        }

        #expect(url.path.hasSuffix("/Broom/diskspace-gemma/models/gemma-4-e2b-it-4bit-mlx"))
        #expect(configuration.defaultPrompt == "Describe the image in English")
        #expect(configuration.extraEOSTokens.contains("<end_of_turn>"))
    }

    @MainActor
    @Test func decentralizedStartingPointsResolveToRenderableGatewayURLs() async {
        let bridge = MobileRuntimeBridge()

        for point in DecentralizedStartingPoint.featured {
            let resolution = await bridge.resolve(point.address)

            #expect(resolution.resolvedURLString?.hasPrefix("https://") == true)
            #expect(resolution.message?.contains("Resolved") == true)

            guard let resolvedURLString = resolution.resolvedURLString,
                  let resolvedURL = URL(string: resolvedURLString) else {
                Issue.record("Expected gateway URL for \(point.title)")
                continue
            }

            #expect(resolvedURL.host == "dweb.link")
            #expect(resolvedURL.path.hasPrefix("/ipfs/") || resolvedURL.path.hasPrefix("/ipns/"))
        }
    }

    @MainActor
    @Test func runtimeBridgeResolvesDecentralizedAddresses() async {
        let bridge = MobileRuntimeBridge()

        let ipfs = await bridge.resolve("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/index.html")
        #expect(ipfs.source == .ipfsGateway)
        #expect(ipfs.resolvedURLString == "https://dweb.link/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/index.html")

        let ipns = await bridge.resolve("ipns://docs.ipfs.tech/concepts/ipns")
        #expect(ipns.source == .ipnsGateway)
        #expect(ipns.resolvedURLString == "https://dweb.link/ipns/docs.ipfs.tech/concepts/ipns")

        let ens = await bridge.resolve("vitalik.eth")
        #expect(ens.source == .ensGateway)
        #expect(ens.resolvedURLString == "https://vitalik.eth.limo")
    }

    @MainActor
    @Test func runtimeBridgeProvidesCopilotWalletAndDownloadSurfaces() async {
        let bridge = MobileRuntimeBridge()

        let copilot = await bridge.runCopilot(CopilotRunRequest(prompt: "Summarize this page", pageURLString: "https://example.com"))
        #expect(copilot.mode == .local)
        #expect(copilot.summary.contains("Summarize this page"))
        #expect(!copilot.suggestions.isEmpty)

        let wallet = await bridge.connectWallet()
        #expect(wallet.isConnected)
        #expect(wallet.address?.hasPrefix("0x") == true)

        let decision = await bridge.evaluateSpend(
            WalletSpendRequest(amount: Decimal(10), currency: "USDC", destination: "0xabc", reason: "Test spend")
        )
        #expect(decision.status == .approved)

        let download = await bridge.startDownload(URL(string: "https://example.com/archive.zip")!, autoStart: false)
        #expect(download.state == .queued)
        let cancelled = await bridge.cancelDownload(download.id)
        #expect(cancelled?.state == .cancelled)
    }

    @MainActor
    @Test func runtimeBridgeUsesAFMServicesForStatusAndCopilot() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "online") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "name": "Demo Writer",
                            "skills": ["summarize"],
                            "status": "healthy"
                        ]
                    ]
                ])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "maintainer": "core",
                            "version": "0.1.0",
                            "checksum": "0xabc"
                        ]
                    ]
                ])
            }

            if path == "/route" {
                return Self.jsonResponse(for: request, body: [
                    "selection": [
                        "id": "afm://demo-writer",
                        "name": "Demo Writer",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-1",
                    "status": "queued"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let afmServices = states.first { $0.feature == .afmServices }
        #expect(afmServices?.mode == .service)
        #expect(afmServices?.isAvailable == true)
        #expect(afmServices?.status.contains("router online") == true)

        let copilot = await bridge.runCopilot(
            CopilotRunRequest(prompt: "Summarize this page", pageURLString: "https://example.com")
        )
        #expect(copilot.mode == .service)
        #expect(copilot.summary.contains("Demo Writer"))
        #expect(copilot.summary.contains("job-1"))
        #expect(copilot.suggestions.contains { $0.contains("Registry has 1 pack") })
    }

    @MainActor
    @Test func runtimeBridgeFallsBackWhenAFMServicesAreOffline() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "offline") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let afmServices = states.first { $0.feature == .afmServices }
        #expect(afmServices?.mode == .unavailable)
        #expect(afmServices?.isAvailable == false)

        let copilot = await bridge.runCopilot(
            CopilotRunRequest(prompt: "Summarize this page", pageURLString: "https://example.com")
        )
        #expect(copilot.mode == .local)
        #expect(copilot.summary.contains("Summarize this page"))
    }

    @MainActor
    @Test func viewModelLoadsIPFSAddressesThroughRuntimeBridge() async {
        let model = BrowserViewModel()
        model.navigate("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/index.html")

        let resolved = await waitForActiveURL(
            in: model,
            "https://dweb.link/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/index.html"
        )

        #expect(resolved)
        #expect(model.activeTab?.mobileNotice == nil)
    }

    @MainActor
    @Test func viewModelLoadsFeaturedIPFSStartingPointsThroughRuntimeBridge() async {
        for point in DecentralizedStartingPoint.featured {
            let model = BrowserViewModel()
            let resolution = await model.runtimeBridge.resolve(point.address)

            guard let resolvedURLString = resolution.resolvedURLString else {
                Issue.record("Expected resolved URL for \(point.title)")
                continue
            }

            model.navigate(point.address)

            let resolved = await waitForActiveURL(in: model, resolvedURLString)
            #expect(resolved)
            #expect(model.activeTab?.mobileNotice == nil)
            #expect(model.history.first?.urlString == resolvedURLString)
        }
    }

    @MainActor
    @Test func viewModelTracksNavigationAndBookmarks() {
        let model = BrowserViewModel()
        model.navigate("example.com")
        #expect(model.activeTab?.urlString == "https://example.com")
        #expect(model.history.first?.urlString == "https://example.com")

        model.addActivePageBookmark()
        #expect(model.bookmarks.contains { $0.urlString == "https://example.com" })
    }

    @MainActor
    @Test func panelSelectionShowsPanelsAndNavigationReturnsToBrowser() {
        let model = BrowserViewModel()

        model.selectPanel(.history)
        #expect(model.selectedPanel == .history)

        model.selectPanel(.bookmarks)
        #expect(model.selectedPanel == .bookmarks)

        model.navigate("example.com")
        #expect(model.selectedPanel == nil)

        model.selectPanel(.runtime)
        model.newTab()
        #expect(model.selectedPanel == nil)
        #expect(model.activeTab?.urlString == BrowserURLResolver.homeURLString)
    }

    @MainActor
    @Test func closingLastTabReturnsToHome() {
        let model = BrowserViewModel()
        let onlyTab = model.activeTabID
        model.navigate("example.com")
        model.closeTab(onlyTab)
        #expect(model.tabs.count == 1)
        #expect(model.activeTab?.urlString == BrowserURLResolver.homeURLString)
    }

    @MainActor
    private func waitForActiveURL(in model: BrowserViewModel, _ urlString: String) async -> Bool {
        for _ in 0..<20 {
            if model.activeTab?.urlString == urlString {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private static func makeAFMServiceSession(
        key: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: AFMServiceEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoints = AFMServiceEndpointConfiguration(
            routerBaseURL: URL(string: "http://\(key)-router.test:4810")!,
            registryBaseURL: URL(string: "http://\(key)-registry.test:4820")!,
            pipelinesBaseURL: URL(string: "http://\(key)-pipelines.test:4830")!
        )
        return (endpoints, URLSession(configuration: configuration))
    }

    private static func jsonResponse(
        for request: URLRequest,
        status: Int = 200,
        body: Any
    ) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

}

private final class AFMServiceMockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    nonisolated(unsafe) private static let lock = NSLock()

    nonisolated static func register(
        key: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        requestHandlers[key] = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let key = request.url?.host?.split(separator: "-").first.map(String.init) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Self.lock.lock()
        let handler = Self.requestHandlers[key]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
