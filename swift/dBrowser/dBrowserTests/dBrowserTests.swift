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

    @Test func architectureOverviewExplainsAFMarketZeroKAndLLMGateway() {
        let feature = MobileRuntimeFeature.architectureOverview
        let explanation = feature.explanation
        let searchableText = (
            [
                feature.title,
                feature.status,
                explanation.overview,
                explanation.bridgeBehavior
            ] + explanation.detailPoints
        ).joined(separator: " ")

        #expect(searchableText.contains("AF Market"))
        #expect(searchableText.contains("AFM router"))
        #expect(searchableText.contains("embedded blockchain light clients"))
        #expect(searchableText.contains("Ethereum-compatible"))
        #expect(searchableText.contains("Substrate/Polkadot"))
        #expect(searchableText.contains("centralized RPC"))
        #expect(searchableText.contains("escrow status"))
        #expect(searchableText.contains("proof settlement"))
        #expect(searchableText.contains("ZeroK"))
        #expect(searchableText.contains("LLM Gateway"))
        #expect(searchableText.contains("https://zerok.cloud"))
        #expect(searchableText.contains("https://llmos.showntell.dev"))
        #expect(searchableText.contains("encrypted envelopes"))
        #expect(searchableText.contains("token-class padding"))
        #expect(searchableText.contains("privacy relay"))
        #expect(searchableText.contains("Provider boundary"))
    }

    @MainActor
    @Test func runtimeBridgeExposesArchitectureOverviewButton() {
        let bridge = MobileRuntimeBridge()
        let architecture = bridge.featureStates.first { $0.feature == .architectureOverview }

        #expect(architecture?.mode == .gateway)
        #expect(architecture?.isAvailable == true)
        #expect(architecture?.status.contains("AF Market") == true)
        #expect(architecture?.status.contains("Light clients") == true)
        #expect(architecture?.status.contains("ZeroK") == true)
        #expect(architecture?.status.contains("LLM Gateway") == true)
    }

    @Test func decentralizedProtocolExplanationKeepsLightClientsAsTrustRoot() {
        let explanation = MobileRuntimeFeature.decentralizedProtocols.explanation
        let searchableText = ([explanation.overview, explanation.bridgeBehavior] + explanation.detailPoints)
            .joined(separator: " ")

        #expect(searchableText.contains("embedded light-client contract"))
        #expect(searchableText.contains("Ethereum"))
        #expect(searchableText.contains("Substrate/Polkadot"))
        #expect(searchableText.contains("centralized RPC"))
        #expect(searchableText.contains("verify block headers"))
        #expect(searchableText.contains("wallet state"))
        #expect(searchableText.contains("AFM settlement"))
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

    @Test func gatewayStartingPointsIncludeRequiredHTTPSGateways() {
        let points = RuntimeGatewayStartingPoint.featured
        let urls = Set(points.map(\.urlString))

        #expect(urls.contains("https://llmos.showntell.dev"))
        #expect(urls.contains("https://zerok.cloud"))
        #expect(points.first { $0.urlString == "https://zerok.cloud" }?.isZeroKnowledgeGateway == true)

        for point in points {
            let resolved = BrowserURLResolver.resolve(point.urlString)
            guard case .web(let url) = resolved else {
                Issue.record("Expected HTTPS gateway URL for \(point.title)")
                continue
            }
            #expect(url.scheme == "https")
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
    @Test func browserViewModelSurfacesAFMServicePacks() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "surface") { request in
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

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )
        let model = makeIsolatedBrowserViewModel(runtimeBridge: bridge)

        await model.refreshRuntimeBridgeStatus()

        #expect(model.afmServiceSnapshot.allServicesAvailable)
        #expect(model.availableAFMPacks.first?.id == "afm://demo-writer")
        #expect(model.availableAFMPacks.first?.maintainer == "core")

        model.selectAFMPack("afm://demo-writer")
        #expect(model.selectedAFMPackID == "afm://demo-writer")
    }

    @MainActor
    @Test func runtimeBridgeForwardsSelectedAFMPackAndContextToServices() async {
        let capturedRequests = JSONRequestCapture()
        let serviceHarness = Self.makeAFMServiceSession(key: "forward") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port
            capturedRequests.capture(request)

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
                return Self.jsonResponse(for: request, body: ["data": []])
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
                    "id": "job-42",
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
        let snapshot = PageSnapshot(
            urlString: "https://example.com",
            title: "Example",
            visibleText: "Service-backed context",
            headings: [],
            links: [],
            buttons: [],
            formControls: [],
            metadata: [:],
            truncated: false,
            redactionCount: 0
        )
        let memoryRecall = OpenMindMemoryRecallResult(
            decision: OpenMindAccessDecision(
                status: .allowed,
                allowedScopes: ["profile"],
                reason: "allowed",
                redactionCount: 0,
                stepUpPrompt: nil
            ),
            memories: [
                OpenMindMemoryRecord(
                    id: "mem-1",
                    summary: "Prefers concise summaries",
                    source: "test",
                    sensitivity: "normal",
                    evidenceURLString: nil
                )
            ],
            notices: []
        )

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Summarize",
                pageURLString: "https://example.com",
                pageSnapshot: snapshot,
                preferredAFMPackID: "afm://demo-writer",
                memoryRecall: memoryRecall
            )
        )

        let routeBody = capturedRequests.body(for: "/route")
        let jobBody = capturedRequests.body(for: "/jobs")
        let jobPayload = jobBody?["payload"] as? [String: Any]

        #expect(result.mode == .service)
        #expect(result.summary.contains("OpenMind approved 1 governed memory item"))
        #expect(routeBody?["preferredPackID"] as? String == "afm://demo-writer")
        #expect(routeBody?["pageSnapshotCommitment"] as? String != nil)
        #expect(routeBody?["memoryContextIDs"] as? [String] == ["mem-1"])
        #expect(jobPayload?["preferredPackID"] as? String == "afm://demo-writer")
        #expect(jobPayload?["memoryContextIDs"] as? [String] == ["mem-1"])
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
    @Test func defaultBookmarksExposeRequiredGateways() {
        let model = BrowserViewModel()
        let urls = Set(model.bookmarks.map(\.urlString))

        #expect(urls.contains("https://llmos.showntell.dev"))
        #expect(urls.contains("https://zerok.cloud"))
    }

    @MainActor
    @Test func addressAutocompleteUsesPreviouslyVisitedURLs() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/docs/start")
        model.navigate("https://docs.ipfs.tech/concepts/ipns")
        model.addressText = "exa"

        let suggestions = model.addressAutocompleteSuggestions()

        #expect(suggestions.first?.urlString == "https://example.com/docs/start")
        #expect(suggestions.allSatisfy { suggestion in
            model.history.contains { $0.urlString == suggestion.urlString }
        })
    }

    @MainActor
    @Test func addressAutocompleteRanksURLPrefixMatchesBeforeContainsMatches() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/docs")
        model.navigate("https://docs.example.com/guide")
        model.addressText = "example"

        let suggestions = model.addressAutocompleteSuggestions()

        #expect(suggestions.map(\.urlString) == [
            "https://example.com/docs",
            "https://docs.example.com/guide"
        ])
    }

    @MainActor
    @Test func addressAutocompleteDeduplicatesHistoryAndHidesExactMatch() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://repeat.example/path")
        model.navigate("https://other.example")
        model.navigate("https://repeat.example/path")
        model.addressText = "repeat"

        let suggestions = model.addressAutocompleteSuggestions()

        #expect(suggestions.filter { $0.urlString == "https://repeat.example/path" }.count == 1)

        model.addressText = "https://repeat.example/path"
        #expect(model.addressAutocompleteSuggestions().isEmpty)
    }

    @MainActor
    @Test func automationRequestsAreScopedToTheActiveTab() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com")

        let request = model.requestDOMQuery(DOMQueryRequest(selector: "a", limit: 500))

        #expect(request?.tabID == model.activeTabID)
        guard case .domQuery(let query) = request?.command else {
            Issue.record("Expected DOM query automation request")
            return
        }
        #expect(query.selector == "a")
        #expect(query.limit == 100)
    }

    @MainActor
    @Test func pageSnapshotsUpdateSmartHistoryRecall() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/research")
        let snapshot = PageSnapshot(
            urlString: "https://example.com/research",
            title: "Research Notes",
            visibleText: "A local summary about verifiable Strawberry automation and page actions.",
            headings: ["Research"],
            links: [],
            buttons: [],
            formControls: [],
            metadata: [:],
            truncated: false,
            redactionCount: 0
        )

        model.applyAutomationResult(
            BrowserAutomationResult(
                requestID: UUID(),
                tabID: model.activeTabID,
                status: .success,
                message: "snapshot",
                pageSnapshot: snapshot
            )
        )

        let recall = model.smartHistoryRecall("verifiable automation")
        #expect(recall.first?.entry.urlString == "https://example.com/research")
        #expect(model.latestPageSnapshot == snapshot)
    }

    @MainActor
    @Test func sensitiveDOMActionsRequireApproval() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/login")
        model.applyAutomationResult(
            BrowserAutomationResult(
                requestID: UUID(),
                tabID: model.activeTabID,
                status: .success,
                message: "query",
                domQuery: DOMQueryResult(
                    selector: "input",
                    elements: [
                        DOMElementRecord(
                            index: 0,
                            tagName: "input",
                            role: nil,
                            ariaLabel: "Password",
                            text: nil,
                            value: "[redacted]",
                            href: nil,
                            inputType: "password",
                            name: "password",
                            placeholder: "Password",
                            disabled: false,
                            hidden: false
                        )
                    ],
                    totalMatched: 1,
                    truncated: false
                )
            )
        )

        let request = model.requestDOMAction(
            BrowserDOMAction(kind: .typeText, selector: "password", elementIndex: 0, text: "secret")
        )

        #expect(request == nil)
        #expect(model.automationResults.first?.status == .needsApproval)
        #expect(model.automationResults.first?.approval?.reasons.contains(.credentialField) == true)

        let submitRequest = model.requestDOMAction(BrowserDOMAction(kind: .submit, selector: "form"))
        #expect(submitRequest == nil)
        #expect(model.automationResults.first?.approval?.reasons.contains(.formSubmit) == true)
    }

    @MainActor
    @Test func copilotRunsTrackUsageAndCancellation() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com")

        guard let runID = model.runCopilot(prompt: "Summarize the current page") else {
            Issue.record("Expected Copilot run ID")
            return
        }

        #expect(model.activeCopilotRunCount == 1)
        #expect(model.copilotRuns.first?.usage?.isEstimated == true)
        model.cancelCopilotRun(runID)
        #expect(model.copilotRuns.first?.status == .cancelled)
        #expect(model.copilotRuns.first?.events.contains { $0.kind == .cancelled } == true)
    }

    @MainActor
    @Test func copilotWorkflowsPersistAndRunWhenEnabled() {
        let workflowStore = CopilotWorkflowStore.ephemeral()
        let firstModel = makeIsolatedBrowserViewModel(workflowStore: workflowStore)
        let workflow = firstModel.saveCopilotWorkflow(
            title: "Daily summary",
            promptTemplate: "Summarize this page",
            allowedActions: [.scroll, .waitForSelector],
            schedule: .interval(hours: 24)
        )

        let secondModel = makeIsolatedBrowserViewModel(workflowStore: workflowStore)
        #expect(secondModel.copilotWorkflows.first?.id == workflow.id)

        secondModel.setWorkflow(workflow.id, isEnabled: false)
        #expect(secondModel.runWorkflow(workflow.id) == nil)

        secondModel.setWorkflow(workflow.id, isEnabled: true)
        secondModel.navigate("https://example.com")
        let runID = secondModel.runWorkflow(workflow.id)
        #expect(runID != nil)
        #expect(secondModel.copilotWorkflows.first?.lastRunAt != nil)
        if let runID {
            secondModel.cancelCopilotRun(runID)
        }
    }

    @MainActor
    @Test func smartHistoryRecallRespectsOptOutAndDeletion() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/private-notes")
        #expect(model.smartHistoryRecall("private notes").first?.entry.urlString == "https://example.com/private-notes")

        model.setSmartHistoryIndexing(enabled: false, forDomain: "example.com")
        #expect(model.smartHistoryRecall("private notes").isEmpty)

        guard let entryID = model.history.first?.id else {
            Issue.record("Expected history entry")
            return
        }
        model.deleteHistoryEntry(entryID)
        #expect(model.history.isEmpty)
    }

    @Test func creditEstimatorSeparatesBrowserFreeAndAIWork() {
        let zero = CopilotCreditUsage.zeroBrowserOperation
        let estimated = CopilotCreditUsage.estimate(prompt: "Summarize this page", snapshot: nil)

        #expect(zero.creditsSpent == Decimal.zero)
        #expect(!zero.isEstimated)
        #expect(estimated.creditsSpent > Decimal.zero)
        #expect(estimated.isEstimated)
    }

    @Test func openMindMemoryClientRecallsAllowedContextAndWriteback() async {
        let memoryHarness = Self.makeOpenMindMemorySession(key: "memory") { request in
            let path = request.url?.path ?? ""

            if path == "/mcp/capabilities" {
                return Self.jsonResponse(for: request, body: [
                    "available": true,
                    "capabilities": ["mind.search_memories", "mind.add_memory"],
                    "posture": "normal",
                    "message": "ready"
                ])
            }

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "allowed",
                    "allowedScopes": ["profile"],
                    "reason": "allowed for test",
                    "redactionCount": 1
                ])
            }

            if path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, body: [
                    "memories": [
                        [
                            "id": "mem-1",
                            "summary": "User prefers short implementation summaries.",
                            "source": "BrIAn",
                            "sensitivity": "normal"
                        ]
                    ],
                    "notices": ["one item redacted"]
                ])
            }

            if path == "/mcp/tools/mind.add_memory" {
                return Self.jsonResponse(for: request, body: [
                    "status": "recorded",
                    "revisionID": "rev-1",
                    "message": "recorded"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let capabilities = await client.refreshCapabilities()
        #expect(capabilities.status == .available)
        #expect(capabilities.capabilities.contains("mind.search_memories"))

        let recall = await client.recall(
            prompt: "Summarize this page",
            pageURLString: "https://example.com",
            pageSnapshot: nil
        )
        #expect(recall.decision.status == .allowed)
        #expect(recall.memories.first?.id == "mem-1")
        #expect(recall.notices == ["one item redacted"])

        let outcome = await client.writeback(
            OpenMindWritebackRequest(
                runID: UUID(),
                prompt: "Summarize this page",
                pageURLString: "https://example.com",
                summary: "Completed test run.",
                source: "unit-test",
                snapshotCommitment: nil,
                idempotencyKey: "test-key"
            )
        )
        #expect(outcome.status == .recorded)
        #expect(outcome.revisionID == "rev-1")
    }

    @Test func openMindMemoryClientHandlesDeniedStepUpAndUnavailableStates() async {
        let deniedHarness = Self.makeOpenMindMemorySession(key: "denied") { request in
            if request.url?.path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "denied",
                    "allowedScopes": [],
                    "reason": "private memory blocked",
                    "redactionCount": 0
                ])
            }
            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let stepHarness = Self.makeOpenMindMemorySession(key: "step") { request in
            if request.url?.path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "stepUpRequired",
                    "allowedScopes": [],
                    "reason": "grant required",
                    "redactionCount": 0,
                    "stepUpPrompt": "Confirm memory access"
                ])
            }
            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let unavailableHarness = Self.makeOpenMindMemorySession(key: "down") { request in
            Self.jsonResponse(for: request, status: 503, body: ["error": "offline"])
        }

        let denied = await OpenMindMemoryClient(
            configuration: deniedHarness.configuration,
            session: deniedHarness.session
        ).recall(prompt: "Find memory", pageURLString: nil, pageSnapshot: nil)
        let stepUp = await OpenMindMemoryClient(
            configuration: stepHarness.configuration,
            session: stepHarness.session
        ).recall(prompt: "Find memory", pageURLString: nil, pageSnapshot: nil)
        let unavailable = await OpenMindMemoryClient(
            configuration: unavailableHarness.configuration,
            session: unavailableHarness.session
        ).recall(prompt: "Find memory", pageURLString: nil, pageSnapshot: nil)

        #expect(denied.decision.status == .denied)
        #expect(denied.memories.isEmpty)
        #expect(stepUp.decision.status == .stepUpRequired)
        #expect(stepUp.decision.stepUpPrompt == "Confirm memory access")
        #expect(unavailable.decision.status == .unavailable)
    }

    @MainActor
    @Test func copilotRequestsOpenMindMemoryBeforeModelRun() async {
        let memoryHarness = Self.makeOpenMindMemorySession(key: "copilotmemory") { request in
            if request.url?.path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "allowed",
                    "allowedScopes": ["profile"],
                    "reason": "allowed",
                    "redactionCount": 0
                ])
            }

            if request.url?.path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, body: [
                    "memories": [
                        [
                            "id": "mem-1",
                            "summary": "Use service-backed context when available.",
                            "source": "BrIAn",
                            "sensitivity": "normal"
                        ]
                    ],
                    "notices": []
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineServices = Self.makeAFMServiceSession(key: "memoryoffline") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: offlineServices.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: offlineServices.configuration,
                session: offlineServices.session
            )
        )
        let model = makeIsolatedBrowserViewModel(
            runtimeBridge: bridge,
            openMindMemoryClient: OpenMindMemoryClient(
                configuration: memoryHarness.configuration,
                session: memoryHarness.session
            )
        )
        model.navigate("https://example.com")

        guard let runID = model.runCopilot(prompt: "Summarize with memory") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)

        #expect(completed)
        #expect(model.latestOpenMindRecall?.memories.first?.id == "mem-1")
        #expect(model.copilotRuns.first?.events.contains { $0.kind == .memoryAccessStarted } == true)
        #expect(model.copilotRuns.first?.events.contains { $0.kind == .memoryAccessCompleted } == true)
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

    @MainActor
    private func waitForCopilotRun(
        in model: BrowserViewModel,
        _ id: UUID,
        status: CopilotRunStatus
    ) async -> Bool {
        for _ in 0..<40 {
            if model.copilotRuns.first(where: { $0.id == id })?.status == status {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @MainActor
    private func makeIsolatedBrowserViewModel(
        initialURL: String = "about:home",
        runtimeBridge: MobileRuntimeBridge? = nil,
        workflowStore: CopilotWorkflowStore = .ephemeral(),
        smartHistoryStore: SmartHistoryStore = .ephemeral(),
        openMindMemoryClient: OpenMindMemoryClient? = nil
    ) -> BrowserViewModel {
        BrowserViewModel(
            initialURL: initialURL,
            runtimeBridge: runtimeBridge ?? MobileRuntimeBridge(),
            copilotWorkflowStore: workflowStore,
            smartHistoryStore: smartHistoryStore,
            openMindMemoryClient: openMindMemoryClient
        )
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

    private static func makeOpenMindMemorySession(
        key: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: OpenMindMemoryEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = OpenMindMemoryEndpointConfiguration(
            httpBaseURL: URL(string: "http://\(key)-memory.test:4840")!
        )
        return (endpoint, URLSession(configuration: configuration))
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

private final class JSONRequestCapture {
    private let lock = NSLock()
    private var bodiesByPath: [String: [String: Any]] = [:]

    func capture(_ request: URLRequest) {
        guard let path = request.url?.path, let data = request.httpBody ?? Self.readBodyStream(request.httpBodyStream) else { return }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        lock.lock()
        bodiesByPath[path] = object
        lock.unlock()
    }

    func body(for path: String) -> [String: Any]? {
        lock.lock()
        let body = bodiesByPath[path]
        lock.unlock()
        return body
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
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
