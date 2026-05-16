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
    @Test func llmConversationRendererCompressesWithoutMutatingLedger() {
        var conversation = LLMConversation(activeModelID: LLMModelRegistry.localGemmaID)
        for index in 0..<12 {
            conversation.appendMessage(
                LLMConversationMessage(
                    role: index.isMultiple(of: 2) ? .user : .assistant,
                    text: "Message \(index) " + String(repeating: "context ", count: 80),
                    modelID: index.isMultiple(of: 2) ? nil : LLMModelRegistry.localGemmaID
                )
            )
        }
        let originalMessageIDs = conversation.messages.map(\.id)
        let smallModel = LLMModelProfile(
            id: "unit.small",
            displayName: "Small Test Model",
            providerKind: .localMLX,
            trustBoundary: .onDevice,
            contextWindowTokens: 700,
            supportsTools: false,
            supportsMemoryCitations: true,
            runtimeMode: .local,
            availability: .available,
            detail: "Small context test model."
        )

        let rendered = LLMConversationContextRenderer.render(
            conversation: conversation,
            model: smallModel,
            latestPageSnapshot: nil
        )

        #expect(rendered.wasCompressed)
        #expect(!rendered.compressedMessageIDs.isEmpty)
        #expect(rendered.includedMessageIDs.contains(originalMessageIDs.last!))
        #expect(rendered.prompt.contains("Compressed prior context"))
        #expect(conversation.messages.map(\.id) == originalMessageIDs)
    }

    @MainActor
    @Test func runtimeBridgeForwardsRenderedConversationContextToAFMServices() async {
        let capturedRequests = JSONRequestCapture()
        let serviceHarness = Self.makeAFMServiceSession(key: "llmcontext") { request in
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
                            "id": "afm://conversation",
                            "name": "Conversation Runner",
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
                        "id": "afm://conversation",
                        "name": "Conversation Runner",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-context",
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
        var conversation = LLMConversation(activeModelID: LLMModelRegistry.afMarketRouterID)
        conversation.appendMessage(LLMConversationMessage(role: .user, text: "Summarize the current report."))
        conversation.appendMessage(
            LLMConversationMessage(
                role: .assistant,
                text: "Earlier context should remain available.",
                modelID: LLMModelRegistry.localGemmaID
            )
        )
        let model = LLMModelRegistry.model(withID: LLMModelRegistry.afMarketRouterID)!
        let rendered = LLMConversationContextRenderer.render(
            conversation: conversation,
            model: model,
            latestPageSnapshot: nil
        )

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Continue",
                pageURLString: "https://example.com",
                preferredModelID: model.id,
                conversationID: conversation.id,
                renderedConversationContext: rendered
            )
        )
        let routeBody = capturedRequests.body(for: "/route")
        let jobBody = capturedRequests.body(for: "/jobs")
        let jobPayload = jobBody?["payload"] as? [String: Any]

        #expect(result.mode == .service)
        #expect((routeBody?["prompt"] as? String)?.contains("Conversation messages") == true)
        #expect((routeBody?["prompt"] as? String)?.contains("Earlier context should remain available.") == true)
        #expect((jobPayload?["prompt"] as? String)?.contains("Active model: AFMarket Router") == true)
    }

    @MainActor
    @Test func llmRouterServiceClientLoadsSnapshotAndCompletes() async throws {
        let capturedRequests = JSONRequestCapture()
        let harness = Self.makeLLMRouterSession(key: "llmrouterclient") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/health" {
                return Self.jsonResponse(for: request, body: [
                    "ok": true,
                    "local_available": true,
                    "message": "router ready"
                ])
            }

            if path == "/models" {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "apple.foundation",
                            "provider": "apple_foundation",
                            "display_name": "Apple Foundation via LLM Router",
                            "context_window_tokens": 16_384,
                            "supports_tools": true,
                            "available": true,
                            "detail": "Local-first Foundation model route"
                        ]
                    ]
                ])
            }

            if path == "/v1/complete" {
                return Self.jsonResponse(for: request, body: [
                    "text": "Router answer with preserved context.",
                    "provider": "apple_foundation",
                    "model_id": "apple.foundation",
                    "usage": [
                        "prompt_tokens": 21,
                        "completion_tokens": 7,
                        "total_tokens": 28
                    ],
                    "tool_calls": [
                        [
                            "id": "tool-1",
                            "name": "browser.query",
                            "arguments": ["selector": "main"],
                            "approval_required": true
                        ]
                    ],
                    "route": "local-first"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = LLMRouterServiceClient(configuration: harness.configuration, session: harness.session)
        let conversationID = UUID()
        let runID = UUID()

        let snapshot = await client.snapshot()
        let response = try await client.complete(
            LLMRouterCompletionRequest(
                prompt: "Conversation messages:\nUSER: Hello",
                modelID: LLMRouterProvider.appleFoundation.modelID,
                policy: LLMRouterRoutingPolicy(preferLocal: true, noEgress: true, forceProvider: .appleFoundation),
                options: LLMRouterCompletionOptions(temperature: 0.6, maxTokens: 256, systemPrompt: "Unit test"),
                context: LLMRouterCompletionContext(
                    conversationID: conversationID,
                    runID: runID,
                    pageURLString: "https://example.com",
                    snapshotCommitment: "fnv1a64:abc",
                    memoryContextIDs: ["mem-1"],
                    estimatedPromptTokens: 21,
                    includedMessageIDs: [UUID()],
                    compressedMessageIDs: []
                )
            )
        )
        let completionBody = capturedRequests.body(for: "/v1/complete")
        let policyBody = completionBody?["policy"] as? [String: Any]
        let contextBody = completionBody?["context"] as? [String: Any]

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.isModelAvailable(provider: .appleFoundation))
        #expect(snapshot.models.first?.contextWindowTokens == 16_384)
        #expect(response.text == "Router answer with preserved context.")
        #expect(response.usage?.totalTokens == 28)
        #expect(response.toolCalls.first?.name == "browser.query")
        #expect(completionBody?["model_id"] as? String == "apple.foundation")
        #expect(policyBody?["no_egress"] as? Bool == true)
        #expect(policyBody?["force_provider"] as? String == "apple_foundation")
        #expect(contextBody?["conversation_id"] as? String == conversationID.uuidString)
        #expect(contextBody?["run_id"] as? String == runID.uuidString)
        #expect((contextBody?["memory_context_ids"] as? [String]) == ["mem-1"])
    }

    @MainActor
    @Test func swiftLLMConversationUsesLLMRouterSelectedModel() async {
        let capturedRequests = JSONRequestCapture()
        let routerHarness = Self.makeLLMRouterSession(key: "llmroutervm") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/health" {
                return Self.jsonResponse(for: request, body: [
                    "ok": true,
                    "local_available": true,
                    "message": "router ready"
                ])
            }

            if path == "/models" {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "apple.foundation",
                            "provider": "apple_foundation",
                            "display_name": "Apple Foundation via LLM Router",
                            "context_window_tokens": 16_384,
                            "supports_tools": true,
                            "available": true
                        ]
                    ]
                ])
            }

            if path == "/v1/complete" {
                return Self.jsonResponse(for: request, body: [
                    "text": "Router answer for the Swift conversation.",
                    "provider": "apple_foundation",
                    "model_id": "apple.foundation",
                    "usage": [
                        "prompt_tokens": 32,
                        "completion_tokens": 9,
                        "total_tokens": 41
                    ],
                    "tool_calls": [
                        [
                            "id": "tool-vm",
                            "name": "browser.query",
                            "arguments": ["selector": "article"],
                            "approval_required": true
                        ]
                    ],
                    "route": "local-first"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineAFM = Self.makeAFMServiceSession(key: "llmrouterafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: offlineAFM.configuration,
                llmRouter: routerHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: offlineAFM.configuration,
                session: offlineAFM.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(
                configuration: routerHarness.configuration,
                session: routerHarness.session
            )
        )
        let model = makeIsolatedBrowserViewModel(runtimeBridge: bridge)
        model.navigate("https://example.com")
        await model.refreshRuntimeBridgeStatus()

        model.selectLLMModel(LLMModelRegistry.llmRouterAppleFoundationID)
        guard let runID = model.sendLLMMessage("Use the router and keep context.") else {
            Issue.record("Expected LLM router conversation run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)
        let completionBody = capturedRequests.body(for: "/v1/complete")
        let contextBody = completionBody?["context"] as? [String: Any]
        let eventKinds = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(completed)
        #expect(model.selectedLLMModelID == LLMModelRegistry.llmRouterAppleFoundationID)
        #expect(model.llmConversation.messages.contains { $0.role == .assistant && $0.modelID == LLMModelRegistry.llmRouterAppleFoundationID })
        #expect(model.llmConversation.latestAssistantMessage?.text.contains("Router answer for the Swift conversation.") == true)
        #expect((completionBody?["prompt"] as? String)?.contains("Conversation messages") == true)
        #expect((completionBody?["prompt"] as? String)?.contains("Use the router and keep context.") == true)
        #expect(contextBody?["conversation_id"] as? String == model.llmConversation.id.uuidString)
        #expect(contextBody?["run_id"] as? String == runID.uuidString)
        #expect(eventKinds.contains(.modelCompleted))
        #expect(eventKinds.contains(.actionRequested))
    }

    @MainActor
    @Test func llmChatModelSwitchPreservesContextAndRecordsFallback() async {
        let offlineServices = Self.makeAFMServiceSession(key: "llmfallback") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: offlineServices.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: offlineServices.configuration,
                session: offlineServices.session
            )
        )
        let model = makeIsolatedBrowserViewModel(runtimeBridge: bridge)
        model.navigate("https://example.com")
        let conversationID = model.llmConversation.id

        model.selectLLMModel(LLMModelRegistry.afMarketRouterID)
        guard let runID = model.sendLLMMessage("Keep the prior context while changing models.") else {
            Issue.record("Expected LLM conversation run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)
        let eventKinds = model.llmConversation.events.map(\.kind)
        let run = model.copilotRuns.first { $0.id == runID }

        #expect(completed)
        #expect(model.llmConversation.id == conversationID)
        #expect(model.llmConversation.activeModelID == LLMModelRegistry.afMarketRouterID)
        #expect(model.llmConversation.messages.contains { $0.role == .user })
        #expect(model.llmConversation.messages.contains { $0.role == .assistant && $0.modelID == LLMModelRegistry.afMarketRouterID })
        #expect(eventKinds.contains(.modelSwitched))
        #expect(eventKinds.contains(.assistantMessageAdded))
        #expect(eventKinds.contains(.providerFallback))
        #expect(run?.conversationID == conversationID)
        #expect(run?.modelID == LLMModelRegistry.afMarketRouterID)
    }

    @MainActor
    @Test func llmConversationStoreRestoresConversationAndModelSelection() async {
        let storeURL = Self.temporaryJSONStoreURL(named: "llm-conversation-restore")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let firstModel = makeIsolatedBrowserViewModel(
            llmConversationStore: LLMConversationStore(fileURL: storeURL)
        )
        firstModel.navigate("https://example.com")
        firstModel.selectLLMModel(LLMModelRegistry.afMarketRouterID)
        guard let runID = firstModel.sendLLMMessage("Persist this conversation state.") else {
            Issue.record("Expected persisted conversation run ID")
            return
        }
        firstModel.cancelCopilotRun(runID)

        let restoredModel = makeIsolatedBrowserViewModel(
            llmConversationStore: LLMConversationStore(fileURL: storeURL)
        )

        #expect(restoredModel.llmConversation.id == firstModel.llmConversation.id)
        #expect(restoredModel.selectedLLMModelID == LLMModelRegistry.afMarketRouterID)
        #expect(restoredModel.llmConversation.activeModelID == LLMModelRegistry.afMarketRouterID)
        #expect(restoredModel.llmConversation.messages.contains { $0.text == "Persist this conversation state." })
        #expect(restoredModel.copilotRuns.isEmpty)
    }

    @MainActor
    @Test func llmConversationResetClearsPersistedThread() {
        let storeURL = Self.temporaryJSONStoreURL(named: "llm-conversation-reset")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let model = makeIsolatedBrowserViewModel(
            llmConversationStore: LLMConversationStore(fileURL: storeURL)
        )
        model.navigate("https://example.com")
        guard let runID = model.sendLLMMessage("This should be cleared.") else {
            Issue.record("Expected reset test conversation run ID")
            return
        }
        model.cancelCopilotRun(runID)
        let previousConversationID = model.llmConversation.id

        model.startNewLLMConversation()
        let restoredModel = makeIsolatedBrowserViewModel(
            llmConversationStore: LLMConversationStore(fileURL: storeURL)
        )

        #expect(model.llmConversation.id != previousConversationID)
        #expect(model.llmConversation.messages.isEmpty)
        #expect(restoredModel.llmConversation.id == model.llmConversation.id)
        #expect(restoredModel.llmConversation.messages.isEmpty)
    }

    @MainActor
    @Test func llmConversationRestoreFallsBackFromUnavailableModel() {
        let unavailableConversation = LLMConversation(activeModelID: LLMModelRegistry.llmGatewayID)
        let store = LLMConversationStore.ephemeral(
            seed: LLMConversationStorePayload(
                conversation: unavailableConversation,
                selectedModelID: LLMModelRegistry.llmGatewayID
            )
        )

        let model = makeIsolatedBrowserViewModel(llmConversationStore: store)

        #expect(model.selectedLLMModelID == LLMModelRegistry.defaultModelID)
        #expect(model.llmConversation.activeModelID == LLMModelRegistry.defaultModelID)
        #expect(model.llmConversation.events.contains { $0.kind == .modelSwitched })
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
    @Test func afmServicesClientLoadsV1RegistryExpertsAndBundles() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "v1registry") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: [
                    "experts": [
                        [
                            "id": "exp-001",
                            "name": "demo-afm",
                            "payoutAddr": "0x000000000000000000000000000000000000dead",
                            "nodePub": "node-public-key-000000000000000000000000000000",
                            "capability": [0.12, 0.01, 0.75],
                            "pricePer1k": 2.5,
                            "latencyP50": 320,
                            "tags": ["afm", "legal"],
                            "baseModel": "apple.afm.demo",
                            "coverage": 0.85,
                            "reputation": 0.72,
                            "stake": 250.0,
                            "attestation": "cbor+base64",
                            "ingestUrl": "http://localhost:8686",
                            "profileSig": "hex-hmac"
                        ]
                    ]
                ])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: [
                    "bundles": [
                        [
                            "id": "bundle-001",
                            "runnerId": "afm://demo-writer",
                            "version": "1.0.0",
                            "capability": [0.12, 0.01, 0.75],
                            "hashes": [
                                "manifest": "sha256:manifest",
                                "bundle": "sha256:bundle"
                            ],
                            "attestation": ["secure-enclave"],
                            "bundleUrl": "https://example.com/demo-writer.tar",
                            "runner_root": "0xrunnerroot",
                            "bundleSig": "0xsig"
                        ]
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = AFMServicesClient(
            configuration: serviceHarness.configuration,
            session: serviceHarness.session
        )

        let snapshot = await client.snapshot()
        let bundlePack = snapshot.availablePacks.first { $0.id == "afm://demo-writer" }

        #expect(snapshot.registryExperts.first?.id == "exp-001")
        #expect(snapshot.registryExperts.first?.pricePer1K == 2.5)
        #expect(snapshot.registryBundles.first?.runnerID == "afm://demo-writer")
        #expect(snapshot.registryBundles.first?.hashes.bundle == "sha256:bundle")
        #expect(bundlePack?.checksum == "sha256:bundle")
        #expect(bundlePack?.bundleURL == "https://example.com/demo-writer.tar")
    }

    @MainActor
    @Test func afmServicesClientLoadsMarketplaceRunnerPacks() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "marketpacks", includesMarketplace: true) { request in
            let path = request.url?.path ?? ""

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: ["experts": []])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: ["bundles": []])
            }

            if path == "/api/packs" {
                return Self.jsonResponse(for: request, body: [
                    [
                        "runner_id": "eu-law@v1",
                        "afm": [
                            "model_id": "apple.afm.medium:2025.10"
                        ],
                        "prompting": [
                            "system": "You are a concise EU law specialist.",
                            "template": "{{input}}",
                            "params": [
                                "temperature": 0.2,
                                "top_p": 0.9,
                                "max_tokens": 750
                            ]
                        ],
                        "policy": [
                            "allowed_domains": ["law:eu"],
                            "max_context": 160000
                        ],
                        "royalties": [
                            "creator_bps": 700,
                            "data_bps": 200
                        ],
                        "attestation": ["secure-enclave"],
                        "capability_vector": [0.12, 0.01, 0.75],
                        "hashes": [
                            "manifest": "sha256:manifest",
                            "bundle": "sha256:bundle"
                        ],
                        "bundle_url": "https://market.example/eu-law.tar",
                        "signature": "0xsig",
                        "runner_root": "0xdf6a4e",
                        "owner_id": "creator-1",
                        "created_at": 1762127512523
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = AFMServicesClient(
            configuration: serviceHarness.configuration,
            session: serviceHarness.session
        )

        let snapshot = await client.snapshot()
        let pack = snapshot.availablePacks.first { $0.id == "eu-law@v1" }

        #expect(snapshot.marketplaceAvailable == true)
        #expect(snapshot.marketplacePacks.first?.runnerID == "eu-law@v1")
        #expect(snapshot.marketplacePacks.first?.prompting.params.temperature == 0.2)
        #expect(snapshot.marketplacePacks.first?.hashes?.preferredChecksum == "sha256:bundle")
        #expect(pack?.modelID == "apple.afm.medium:2025.10")
        #expect(pack?.bundleURL == "https://market.example/eu-law.tar")
        #expect(pack?.runnerRoot == "0xdf6a4e")
        #expect(pack?.allowedDomains == ["law:eu"])
        #expect(pack?.maxContext == 160000)
        #expect(pack?.creatorRoyaltyBPS == 700)
        #expect(pack?.dataRoyaltyBPS == 200)
        #expect(pack?.signature == "0xsig")
        #expect(pack?.ownerID == "creator-1")
        #expect(pack?.createdAtMillis == 1762127512523)
    }

    @MainActor
    @Test func afmServicesClientRoutesThroughV1ContractAndFallsBackToLocal() async {
        let capturedV1Requests = JSONRequestCapture()
        let v1Harness = Self.makeAFMServiceSession(key: "v1route") { request in
            let path = request.url?.path ?? ""
            capturedV1Requests.capture(request)

            if path == "/v1/route" {
                return Self.jsonResponse(for: request, body: [
                    "primary": [
                        "node_id": "exp-001",
                        "lease_id": "lease-001",
                        "verifier": "attestation-ref",
                        "payout_address": "0x000000000000000000000000000000000000dead",
                        "dispatch": [
                            "status": "ok",
                            "http_status": 202
                        ]
                    ],
                    "backups": [
                        [
                            "node_id": "exp-002",
                            "lease_id": "lease-002"
                        ]
                    ],
                    "lease_ttl_ms": 15000,
                    "explain": [
                        [
                            "expert_id": "exp-001",
                            "score": 0.81,
                            "vrf_ratio": 0.12,
                            "rendezvous": 0.34
                        ]
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let v1Client = AFMServicesClient(
            configuration: v1Harness.configuration,
            session: v1Harness.session
        )

        var v1Route: AFMRouteResult?
        do {
            v1Route = try await v1Client.route(
                skill: "summarize",
                prompt: "Summarize v1 route",
                pageURLString: "https://example.com",
                pageSnapshotCommitment: "snapshot-commitment",
                memoryContextIDs: ["mem-1"]
            )
        } catch {
            Issue.record("Expected v1 route, got \(error)")
            v1Route = nil
        }
        let v1Body = capturedV1Requests.body(for: "/v1/route")
        let hpkeInfo = v1Body?["hpke_info"] as? [String: Any]
        let sla = v1Body?["sla"] as? [String: Any]

        #expect(v1Route?.contract == "afmarket-v1")
        #expect(v1Route?.primary?.leaseID == "lease-001")
        #expect(v1Route?.backups.first?.nodeID == "exp-002")
        #expect(v1Route?.request?.chainRef == "base-sepolia")
        #expect(v1Body?["task_id"] as? String != nil)
        #expect(v1Body?["input_commitment"] as? String == "snapshot-commitment")
        #expect(v1Body?["chain_ref"] as? String == "base-sepolia")
        #expect((v1Body?["task_tags"] as? [String])?.contains("summarize") == true)
        #expect(sla?["max_latency_ms"] as? Int == 12_000)
        #expect(hpkeInfo?["version"] as? String == "X25519-HKDF-SHA256/CHACHA20POLY1305-v1")

        let capturedFallbackRequests = JSONRequestCapture()
        let fallbackHarness = Self.makeAFMServiceSession(key: "v1fallback") { request in
            let path = request.url?.path ?? ""
            capturedFallbackRequests.capture(request)

            if path == "/v1/route" {
                return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
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

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let fallbackClient = AFMServicesClient(
            configuration: fallbackHarness.configuration,
            session: fallbackHarness.session
        )

        var fallbackRoute: AFMRouteResult?
        do {
            fallbackRoute = try await fallbackClient.route(
                skill: "summarize",
                prompt: "Summarize local route",
                pageURLString: "https://example.com",
                preferredPackID: "afm://demo-writer",
                pageSnapshotCommitment: "snapshot-commitment"
            )
        } catch {
            Issue.record("Expected fallback route, got \(error)")
            fallbackRoute = nil
        }
        let fallbackBody = capturedFallbackRequests.body(for: "/route")

        #expect(capturedFallbackRequests.body(for: "/v1/route") != nil)
        #expect(fallbackRoute?.contract == "local")
        #expect(fallbackRoute?.selection?.id == "afm://demo-writer")
        #expect(fallbackRoute?.request?.inputCommitment == "snapshot-commitment")
        #expect(fallbackBody?["preferredPackID"] as? String == "afm://demo-writer")
    }

    @Test func afmNodeVerificationReportRecognizesChainAnchoredEvidence() {
        let taskID = "task-prod"
        let outputCommitment = "0x\(String(repeating: "11", count: 32))"
        let nonce = AFMNodeVerificationReport.bindingNonceHex(
            taskID: taskID,
            outputCommitment: outputCommitment
        )
        let nodeTask = AFMNodeTaskResult(
            ok: true,
            id: taskID,
            taskID: taskID,
            packID: "eu-law@v1",
            installID: "install-prod",
            status: "completed",
            mode: "production",
            result: AFMNodeTaskOutput(
                summary: "production completed",
                outputCommitment: outputCommitment,
                completedAt: "2026-05-16T00:00:01Z"
            ),
            attestation: AFMAttestedRun(
                mode: "secure-enclave",
                taskID: taskID,
                outputCommitment: outputCommitment,
                nonce: nonce ?? "",
                tokenCount: 42,
                contextPassages: 2,
                attestationToken: "cbor-base64"
            ),
            proof: AFMProofState(
                proofID: "proof-prod",
                status: "verified",
                verifier: "0xverifier",
                publicInputs: [
                    "taskID": taskID,
                    "outputCommitment": outputCommitment,
                    "deadline": "1730203600"
                ],
                proofBytes: "0xproof",
                publicInputsABI: "0xinputs",
                deadline: 1730203600,
                payoutAddress: "0x000000000000000000000000000000000000dead",
                modelIDHash: "0xmodel"
            ),
            settlement: AFMSettlementState(
                id: "settlement-prod",
                status: "settled",
                chainRef: "base-sepolia",
                escrowID: "escrow-prod",
                escrowContract: "0xescrow",
                transactionHash: "0xtx",
                blockNumber: 123,
                deadline: 1730203600,
                verifier: "0xverifier",
                mode: "production",
                settledAt: "2026-05-16T00:00:02Z"
            )
        )

        let report = nodeTask.verificationReport

        #expect(nonce != nil)
        #expect(report.state == .chainAnchored)
        #expect(report.checks.allSatisfy { $0.status == .passed })
        #expect(report.summary.contains("chain-anchored"))
        #expect(report.transactionHash == "0xtx")
    }

    @MainActor
    @Test func chainTrustRegistrySeedsSupportedFamiliesAndLabelsFallback() {
        let registry = ChainTrustRegistry.defaultRegistry
        let families = Set(registry.statuses.map(\.family))
        let base = registry.status(forChainRef: "base-sepolia")

        #expect(families.isSuperset(of: Set(ChainTrustFamily.allCases.filter { $0 != .unknown })))
        #expect(registry.statuses.count >= 12)
        #expect(base?.family == .evmLayer2)
        #expect(base?.state == .rpcFallback)
        #expect(base?.displaySummary.contains("Gateway/RPC fallback") == true)
        #expect(registry.runtimeStatusText.contains("gateway/RPC fallback only"))
        #expect(registry.fallbackWarning.contains("not local light-client verification"))
    }

    @MainActor
    @Test func chainTrustRegistryRecordsAFMarketSettlementEvidence() {
        var registry = ChainTrustRegistry.defaultRegistry
        let taskID = "task-chain-registry"
        let outputCommitment = "0x\(String(repeating: "22", count: 32))"
        let nodeTask = Self.chainAnchoredNodeTask(taskID: taskID, outputCommitment: outputCommitment)

        let update = registry.recordAFMarketVerification(nodeTask.verificationReport)
        let base = registry.status(forChainRef: "base-sepolia")

        #expect(update?.state == .proofChecked)
        #expect(update?.trustSource == .afMarketSettlement)
        #expect(update?.latestCheckpoint?.height == 456)
        #expect(base?.state == .proofChecked)
        #expect(base?.evidence.first?.taskID == taskID)
        #expect(base?.evidence.first?.transactionHash == "0xtx-chain")
        #expect(base?.displaySummary.contains("proof-checked evidence") == true)
    }

    @MainActor
    @Test func runtimeBridgeSurfacesChainTrustFeatureState() {
        var registry = ChainTrustRegistry.defaultRegistry
        let nodeTask = Self.chainAnchoredNodeTask(
            taskID: "task-chain-feature",
            outputCommitment: "0x\(String(repeating: "33", count: 32))"
        )
        _ = registry.recordAFMarketVerification(nodeTask.verificationReport)
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(chainTrustRegistry: registry)
        )
        let chainTrust = bridge.featureStates.first { $0.feature == .chainTrust }

        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.isAvailable == true)
        #expect(chainTrust?.status.contains("Base Sepolia proof checked") == true)
    }

    @MainActor
    @Test func runtimeBridgeRecordsAFMarketSettlementInChainTrustRegistry() async {
        let taskID = "task-chain-runtime"
        let outputCommitment = "0x\(String(repeating: "44", count: 32))"
        let nonce = AFMNodeVerificationReport.bindingNonceHex(
            taskID: taskID,
            outputCommitment: outputCommitment
        ) ?? ""
        let serviceHarness = Self.makeAFMServiceSession(key: "chaintrust") { request in
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
                            "status": "healthy",
                            "checksum": "0xabc"
                        ]
                    ]
                ])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: ["experts": []])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: ["bundles": []])
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
                    "id": "job-chain",
                    "status": "queued"
                ])
            }

            if path == "/packs/install" {
                return Self.jsonResponse(for: request, status: 201, body: [
                    "id": "install-chain",
                    "packID": "afm://demo-writer",
                    "checksum": "0xabc",
                    "status": "installed",
                    "mode": "production"
                ])
            }

            if path == "/tasks" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "id": taskID,
                    "taskID": taskID,
                    "packID": "afm://demo-writer",
                    "installID": "install-chain",
                    "status": "completed",
                    "mode": "production",
                    "result": [
                        "summary": "production completed",
                        "outputCommitment": outputCommitment
                    ],
                    "attestation": [
                        "mode": "secure-enclave",
                        "taskID": taskID,
                        "outputCommitment": outputCommitment,
                        "nonce": nonce,
                        "tokenCount": 20,
                        "contextPassages": 1
                    ],
                    "proof": [
                        "proofID": "proof-chain",
                        "status": "verified",
                        "verifier": "0xverifier",
                        "publicInputs": [
                            "taskID": taskID,
                            "outputCommitment": outputCommitment
                        ],
                        "proofBytes": "0xproof",
                        "publicInputsABI": "0xinputs"
                    ],
                    "settlement": [
                        "id": "settlement-chain",
                        "status": "settled",
                        "chainRef": "base-sepolia",
                        "escrowID": "escrow-chain",
                        "escrowContract": "0xescrow",
                        "transactionHash": "0xtx-chain",
                        "blockNumber": 456,
                        "verifier": "0xverifier",
                        "mode": "production"
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

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Summarize with chain evidence",
                pageURLString: "https://example.com",
                preferredAFMPackID: "afm://demo-writer"
            )
        )
        let base = bridge.chainTrustSnapshot.status(forChainRef: "base-sepolia")
        let feature = bridge.featureStates.first { $0.feature == .chainTrust }

        #expect(result.mode == .service)
        #expect(result.afmNodeTask?.verificationReport.state == .chainAnchored)
        #expect(result.chainTrustUpdate?.state == .proofChecked)
        #expect(base?.state == .proofChecked)
        #expect(base?.latestCheckpoint?.height == 456)
        #expect(feature?.mode == .service)
        #expect(feature?.status.contains("Base Sepolia proof checked") == true)
        #expect(result.suggestions.contains { $0.contains("Chain trust Proof checked") })
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
    @Test func runtimeBridgeSurfacesAFMarketV1RouteLeaseMetadata() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "runtimev1route") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": port != 4840])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: [
                    "experts": [
                        [
                            "id": "exp-001",
                            "name": "demo-afm",
                            "nodePub": "node-public-key-000000000000000000000000000000",
                            "capability": [0.12, 0.01, 0.75],
                            "pricePer1k": 2.5,
                            "latencyP50": 320,
                            "tags": ["afm"],
                            "baseModel": "apple.afm.demo"
                        ]
                    ]
                ])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: [
                    "bundles": [
                        [
                            "runnerId": "afm://demo-writer",
                            "version": "1.0.0",
                            "capability": [0.12, 0.01, 0.75],
                            "hashes": ["manifest": "sha256:manifest"]
                        ]
                    ]
                ])
            }

            if path == "/v1/route" {
                return Self.jsonResponse(for: request, body: [
                    "primary": [
                        "node_id": "exp-001",
                        "lease_id": "lease-v1",
                        "verifier": "attestation-ref",
                        "payout_address": "0x000000000000000000000000000000000000dead"
                    ],
                    "backups": [],
                    "lease_ttl_ms": 15000,
                    "explain": [
                        [
                            "expert_id": "exp-001",
                            "score": 0.81
                        ]
                    ]
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-v1",
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

        let result = await bridge.runCopilot(
            CopilotRunRequest(prompt: "Summarize through AFMarket v1", pageURLString: "https://example.com")
        )

        #expect(result.mode == .service)
        #expect(result.summary.contains("lease-v1"))
        #expect(result.summary.contains("base-sepolia"))
        #expect(result.suggestions.contains { $0.contains("AFMarket v1 primary lease lease-v1") })
        #expect(result.suggestions.contains { $0.contains("Route afmarket-v1 used chain base-sepolia") })
        #expect(result.suggestions.contains { $0.contains("1 bundle") && $0.contains("1 expert") })
        #expect(result.suggestions.contains { $0.contains("Node agent unavailable") })
    }

    @MainActor
    @Test func runtimeBridgeSurfacesAFMarketMarketplacePacks() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "runtimemarket", includesMarketplace: true) { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": port != 4840])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: ["experts": []])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: ["bundles": []])
            }

            if path == "/api/packs" {
                return Self.jsonResponse(for: request, body: [
                    [
                        "runner_id": "eu-law@v1",
                        "afm": ["model_id": "apple.afm.medium:2025.10"],
                        "prompting": [
                            "system": "You are a concise EU law specialist.",
                            "template": "{{input}}",
                            "params": [
                                "temperature": 0.2,
                                "top_p": 0.9,
                                "max_tokens": 750
                            ]
                        ],
                        "policy": [
                            "allowed_domains": ["law:eu"],
                            "max_context": 160000
                        ],
                        "royalties": [
                            "creator_bps": 700,
                            "data_bps": 200
                        ],
                        "hashes": ["bundle": "sha256:bundle"],
                        "bundle_url": "https://market.example/eu-law.tar",
                        "runner_root": "0xdf6a4e",
                        "owner_id": "creator-1",
                        "created_at": 1762127512523
                    ]
                ])
            }

            if path == "/v1/route" {
                return Self.jsonResponse(for: request, body: [
                    "primary": [
                        "node_id": "exp-001",
                        "lease_id": "lease-market",
                        "verifier": "attestation-ref",
                        "payout_address": "0x000000000000000000000000000000000000dead"
                    ],
                    "backups": [],
                    "lease_ttl_ms": 15000,
                    "explain": []
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-market",
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

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Summarize with marketplace pack",
                pageURLString: "https://example.com",
                preferredAFMPackID: "eu-law@v1"
            )
        )
        let marketplacePack = bridge.afmServiceSnapshot.availablePacks.first { $0.id == "eu-law@v1" }

        #expect(result.mode == .service)
        #expect(result.suggestions.contains { $0.contains("Marketplace has 1 runner pack") })
        #expect(result.suggestions.contains { $0.contains("Copilot requested runner pack eu-law@v1") })
        #expect(marketplacePack?.modelID == "apple.afm.medium:2025.10")
        #expect(marketplacePack?.creatorRoyaltyBPS == 700)
        #expect(marketplacePack?.bundleURL == "https://market.example/eu-law.tar")
    }

    @MainActor
    @Test func runtimeBridgeInstallsAndDispatchesThroughAFMNode() async {
        let capturedRequests = JSONRequestCapture()
        let serviceHarness = Self.makeAFMServiceSession(key: "node") { request in
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
                    "id": "job-node",
                    "status": "queued"
                ])
            }

            if path == "/packs/install" {
                return Self.jsonResponse(for: request, status: 201, body: [
                    "ok": true,
                    "id": "install-1",
                    "packID": "afm://demo-writer",
                    "checksum": "0xabc",
                    "status": "installed",
                    "mode": "local-mock",
                    "installedAt": "2026-05-16T00:00:00Z",
                    "receipt": [
                        "mode": "local-mock",
                        "installCommitment": "0xinstall",
                        "verifier": "local-dev"
                    ]
                ])
            }

            if path == "/tasks" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "task-1",
                    "taskID": "task-1",
                    "packID": "afm://demo-writer",
                    "installID": "install-1",
                    "status": "completed",
                    "mode": "local-mock",
                    "result": [
                        "summary": "node completed",
                        "outputCommitment": "0xoutput",
                        "completedAt": "2026-05-16T00:00:01Z"
                    ],
                    "attestation": [
                        "mode": "local-mock",
                        "taskID": "task-1",
                        "outputCommitment": "0xoutput",
                        "nonce": "nonce-1",
                        "tokenCount": 12,
                        "contextPassages": 1
                    ],
                    "proof": [
                        "id": "proof-1",
                        "proofID": "proof-1",
                        "status": "mock",
                        "verifier": "local-dev",
                        "publicInputs": [
                            "packID": "afm://demo-writer",
                            "pageSnapshotCommitment": "0xsnapshot",
                            "outputCommitment": "0xoutput"
                        ]
                    ],
                    "settlement": [
                        "id": "settlement-1",
                        "status": "mock",
                        "chainRef": "local-devnet",
                        "verifier": "local-dev",
                        "mode": "local-mock",
                        "settledAt": "2026-05-16T00:00:02Z"
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
                    id: "mem-node",
                    summary: "Use AFMarket node evidence.",
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
                preferredAFMPackID: "afm://demo-writer",
                memoryRecall: memoryRecall
            )
        )

        let installBody = capturedRequests.body(for: "/packs/install")
        let taskBody = capturedRequests.body(for: "/tasks")

        #expect(result.mode == .service)
        #expect(result.afmInstall?.status == "installed")
        #expect(result.afmInstall?.mode == "local-mock")
        #expect(result.afmNodeTask?.attestation.mode == "local-mock")
        #expect(result.afmNodeTask?.proof.status == "mock")
        #expect(result.afmNodeTask?.settlement.status == "mock")
        #expect(result.afmNodeTask?.verificationReport.state == .mock)
        #expect(result.summary.contains("local-mock attestation"))
        #expect(result.summary.contains("local/mock only"))
        #expect(result.suggestions.contains { $0.contains("Node installed afm://demo-writer") })
        #expect(result.suggestions.contains { $0.contains("Verification Mock") })
        #expect(result.suggestions.contains { $0.contains("Local mock attestation") })
        #expect(installBody?["checksum"] as? String == "0xabc")
        #expect(taskBody?["selectedPackID"] as? String == "afm://demo-writer")
        #expect(taskBody?["memoryContextIDs"] as? [String] == ["mem-node"])
    }

    @MainActor
    @Test func copilotRunRecordsAFMarketNodeActivity() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "nodeevents") { request in
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
                    "id": "job-node-events",
                    "status": "queued"
                ])
            }

            if path == "/packs/install" {
                return Self.jsonResponse(for: request, status: 201, body: [
                    "id": "install-events",
                    "packID": "afm://demo-writer",
                    "checksum": "0xabc",
                    "status": "installed",
                    "mode": "local-mock"
                ])
            }

            if path == "/tasks" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "id": "task-events",
                    "taskID": "task-events",
                    "packID": "afm://demo-writer",
                    "installID": "install-events",
                    "status": "completed",
                    "mode": "local-mock",
                    "result": [
                        "summary": "node completed",
                        "outputCommitment": "0xevents"
                    ],
                    "attestation": [
                        "mode": "local-mock",
                        "taskID": "task-events",
                        "outputCommitment": "0xevents",
                        "nonce": "nonce-events",
                        "tokenCount": 10,
                        "contextPassages": 0
                    ],
                    "proof": [
                        "proofID": "proof-events",
                        "status": "mock",
                        "verifier": "local-dev"
                    ],
                    "settlement": [
                        "status": "mock",
                        "chainRef": "local-devnet",
                        "mode": "local-mock"
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
        model.navigate("https://example.com")

        guard let runID = model.runCopilot(prompt: "Summarize with node") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)
        let events = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(completed)
        #expect(events.contains(.afMarketInstallCompleted))
        #expect(events.contains(.afMarketDispatchCompleted))
        #expect(events.contains(.afMarketAttestationRecorded))
        #expect(events.contains(.afMarketSettlementRecorded))
        #expect(events.contains(.afMarketVerificationRecorded))
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

    @MainActor @Test func openMindMemoryClientRecallsAllowedContextAndWriteback() async {
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

            if path == "/mcp/tools/mind.retrieve_evidence_bundle" {
                return Self.jsonResponse(for: request, body: [
                    "bundleId": "evb-1",
                    "profile": "OMSEM-0.1",
                    "createdAt": "2026-05-16T00:00:00Z",
                    "query": [
                        "text": "Summarize this page",
                        "purpose": "copilot_recall"
                    ],
                    "scope": [
                        "domains": ["example.com"],
                        "maxSensitivity": "normal",
                        "outputMode": "evidence_summary"
                    ],
                    "items": [
                        [
                            "kind": "memory",
                            "id": "mem-evidence",
                            "summary": "Evidence says user prefers audited memory.",
                            "confidence": 0.88,
                            "evidenceRefs": ["event-1"],
                            "why": "matched",
                            "sensitivity": "normal"
                        ]
                    ],
                    "governanceNotes": ["policy filtered"]
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
        #expect(capabilities.transport?.kind == .directHTTP)

        let recall = await client.recall(
            prompt: "Summarize this page",
            pageURLString: "https://example.com",
            pageSnapshot: nil
        )
        #expect(recall.decision.status == .allowed)
        #expect(recall.memories.first?.id == "mem-1")
        #expect(recall.memories.contains { $0.id == "mem-evidence" })
        #expect(recall.evidenceBundle?.bundleID == "evb-1")
        #expect(recall.evidenceBundle?.items.first?.evidenceRefs == ["event-1"])
        #expect(recall.intent?.purpose == "copilot_recall")
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

    @MainActor @Test func openMindMemoryClientHandlesDeniedStepUpAndUnavailableStates() async {
        let capturedStepRequests = JSONRequestCapture()
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
            let path = request.url?.path ?? ""
            capturedStepRequests.capture(request)

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "stepUpRequired",
                    "allowedScopes": [],
                    "reason": "grant required",
                    "redactionCount": 0,
                    "stepUpPrompt": "Confirm memory access"
                ])
            }

            if path == "/mcp/tools/gateway.request_step_up_grant" {
                return Self.jsonResponse(for: request, body: [
                    "requestId": "step-1",
                    "status": "pending",
                    "operation": "memory.search",
                    "requestedScopes": ["mind.read.basic"],
                    "purpose": "copilot_recall",
                    "requestedTtl": "PT1H",
                    "justification": "Confirm memory access"
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
        let stepClient = OpenMindMemoryClient(
            configuration: stepHarness.configuration,
            session: stepHarness.session
        )
        let stepUp = await stepClient.recall(prompt: "Find memory", pageURLString: nil, pageSnapshot: nil)
        let stepRequest: OpenMindStepUpRequest?
        if let intent = stepUp.intent {
            stepRequest = await stepClient.requestStepUpGrant(
                intent: intent,
                decision: stepUp.decision,
                justification: stepUp.decision.stepUpPrompt
            )
        } else {
            stepRequest = nil
        }
        let stepBody = capturedStepRequests.body(for: "/mcp/tools/gateway.request_step_up_grant")
        let stepIntentBody = stepBody?["intent"] as? [String: Any]
        let unavailable = await OpenMindMemoryClient(
            configuration: unavailableHarness.configuration,
            session: unavailableHarness.session
        ).recall(prompt: "Find memory", pageURLString: nil, pageSnapshot: nil)

        #expect(denied.decision.status == .denied)
        #expect(denied.memories.isEmpty)
        #expect(stepUp.decision.status == .stepUpRequired)
        #expect(stepUp.decision.stepUpPrompt == "Confirm memory access")
        #expect(stepUp.intent?.purpose == "copilot_recall")
        #expect(stepRequest?.requestID == "step-1")
        #expect(stepRequest?.requestedScopes == ["mind.read.basic"])
        #expect(stepBody?["justification"] as? String == "Confirm memory access")
        #expect(stepIntentBody?["operation"] as? String == "memory.search")
        #expect(unavailable.decision.status == .unavailable)
    }

    @MainActor @Test func openMindMemoryClientLoadsContinuityAndPosture() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "runtime") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/capabilities" {
                return Self.jsonResponse(for: request, body: [
                    "available": true,
                    "capabilities": ["mind.search_memories", "posture.get"],
                    "posture": "normal",
                    "message": "ready"
                ])
            }

            if path == "/mcp/resources/mind/continuity" {
                return Self.jsonResponse(for: request, body: [
                    "version": "omcont/0.1",
                    "mode": "normal",
                    "summary": "Continuity ready",
                    "pendingStepUps": 2,
                    "updatedAt": "2026-05-16T00:00:00Z",
                    "notices": ["review one peer grant"]
                ])
            }

            if path == "/mcp/tools/posture.get" {
                return Self.jsonResponse(for: request, body: [
                    "mode": "protective",
                    "userMessage": "Protective mode is active.",
                    "allowsMemoryWriteback": false,
                    "requiresExplicitConfirmation": true,
                    "summary": "Protective posture",
                    "notices": ["writeback paused"]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let state = await client.refreshRuntimeState()
        let postureBody = capturedRequests.body(for: "/mcp/tools/posture.get")

        #expect(state.capability.status == .available)
        #expect(state.capability.transport?.kind == .directHTTP)
        #expect(state.continuity.version == "omcont/0.1")
        #expect(state.continuity.pendingStepUps == 2)
        #expect(state.continuity.notices == ["review one peer grant"])
        #expect(state.posture.mode == "protective")
        #expect(state.posture.allowsMemoryWriteback == false)
        #expect(state.posture.requiresExplicitConfirmation)
        #expect(postureBody?["clientID"] as? String == "dBrowser.swift")
    }

    @MainActor @Test func openMindMemoryClientNegotiatesJSONRPCBridgeAndRecallsMemory() async {
        let capturedRPC = JSONRPCRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "memoryrpc") { request in
            guard request.url?.path == "/mcp" else {
                return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
            }

            let payload = capturedRPC.capture(request) ?? [:]
            let method = payload["method"] as? String
            let id = payload["id"] ?? 1

            if method == "initialize" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "protocolVersion": "2025-11-25",
                        "serverInfo": [
                            "name": "openmind-test",
                            "version": "1.0"
                        ],
                        "capabilities": [
                            "tools": [:] as [String: Any],
                            "resources": [:] as [String: Any]
                        ]
                    ]
                ])
            }

            if method == "notifications/initialized" {
                return Self.emptyResponse(for: request)
            }

            if method == "tools/list" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "tools": [
                            ["name": "gateway.evaluate_access_intent"],
                            ["name": "mind.retrieve_evidence_bundle"],
                            ["name": "mind.search_memories"],
                            ["name": "mind.add_memory"],
                            ["name": "posture.get"]
                        ]
                    ]
                ])
            }

            if method == "resources/list" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "resources": [
                            ["uri": "mind://continuity"]
                        ]
                    ]
                ])
            }

            if method == "resources/read" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "contents": [
                            [
                                "uri": "mind://continuity",
                                "mimeType": "application/json",
                                "text": Self.jsonString([
                                    "version": "omcont/0.1",
                                    "mode": "normal",
                                    "summary": "Bridge continuity ready",
                                    "pendingStepUps": 1,
                                    "notices": ["bridge resource"]
                                ])
                            ]
                        ]
                    ]
                ])
            }

            guard method == "tools/call",
                  let params = payload["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                return Self.jsonResponse(for: request, status: 400, body: ["error": "unexpected JSON-RPC request"])
            }

            switch toolName {
            case "posture.get":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "mode": "normal",
                            "allowsMemoryWriteback": true,
                            "requiresExplicitConfirmation": false,
                            "summary": "Bridge posture"
                        ],
                        "isError": false
                    ]
                ])
            case "gateway.evaluate_access_intent":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "status": "allow",
                            "allowedScopes": ["mind.read.private"],
                            "reason": "bridge allowed",
                            "redactionCount": 0
                        ],
                        "isError": false
                    ]
                ])
            case "mind.retrieve_evidence_bundle":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "bundleId": "evb-rpc",
                            "profile": "OMSEM-0.1",
                            "items": [
                                [
                                    "kind": "memory",
                                    "id": "mem-rpc-evidence",
                                    "summary": "RPC evidence memory",
                                    "evidenceRefs": ["event-rpc"],
                                    "sensitivity": "normal"
                                ]
                            ],
                            "governanceNotes": ["rpc governed"]
                        ],
                        "isError": false
                    ]
                ])
            case "mind.search_memories":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "results": [
                                [
                                    "id": "mem-rpc",
                                    "summary": "RPC bridge memory.",
                                    "source": "BrIAn",
                                    "sensitivity": "normal"
                                ]
                            ],
                            "notices": ["rpc notice"]
                        ],
                        "isError": false
                    ]
                ])
            case "mind.add_memory":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "id": "rev-rpc"
                        ],
                        "isError": false
                    ]
                ])
            default:
                return Self.jsonResponse(for: request, status: 404, body: ["error": "unknown tool"])
            }
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let state = await client.refreshRuntimeState()
        #expect(state.capability.status == .available)
        #expect(state.capability.transport?.kind == .jsonRPCHTTPBridge)
        #expect(state.capability.transport?.serverName == "openmind-test")
        #expect(state.capability.capabilities.contains("mind.search_memories"))
        #expect(state.capability.capabilities.contains("mind://continuity"))
        #expect(state.continuity.version == "omcont/0.1")
        #expect(state.continuity.pendingStepUps == 1)
        #expect(state.posture.mode == "normal")

        let recall = await client.recall(
            prompt: "Summarize via bridge",
            pageURLString: "https://example.com/path",
            pageSnapshot: nil
        )
        #expect(recall.decision.status == .allowed)
        #expect(recall.memories.first?.id == "mem-rpc")
        #expect(recall.memories.contains { $0.id == "mem-rpc-evidence" })
        #expect(recall.evidenceBundle?.bundleID == "evb-rpc")
        #expect(recall.notices == ["rpc notice"])

        let outcome = await client.writeback(
            OpenMindWritebackRequest(
                runID: UUID(),
                prompt: "Summarize via bridge",
                pageURLString: "https://example.com/path",
                summary: "Completed RPC bridge test.",
                source: "unit-test",
                snapshotCommitment: "fnv1a64:abc",
                idempotencyKey: "rpc-key"
            )
        )
        let accessArguments = capturedRPC.toolArguments(named: "gateway.evaluate_access_intent")
        let addArguments = capturedRPC.toolArguments(named: "mind.add_memory")
        let addSource = addArguments?["source"] as? [String: Any]

        #expect(outcome.status == .recorded)
        #expect(outcome.revisionID == "rev-rpc")
        #expect(accessArguments?["operation"] as? String == "memory.search")
        #expect((accessArguments?["requestedDomains"] as? [String]) == ["example.com"])
        #expect(addArguments?["summary"] as? String == "Completed RPC bridge test.")
        #expect(addArguments?["idempotencyKey"] as? String == "rpc-key")
        #expect(addSource?["product"] as? String == "dBrowser.swift")
        #expect(addSource?["clientSource"] as? String == "unit-test")
    }

    @MainActor @Test func openMindMemoryClientLoadsReviewTasksAndCreatesCorrection() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "memoryreview") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/resources/mind/governed-memory/review-tasks" {
                return Self.jsonResponse(for: request, body: [
                    "items": [
                        [
                            "reviewTaskId": "review-1",
                            "taskType": "claim_review",
                            "state": "open",
                            "entityId": "claim-1",
                            "entityType": "Claim",
                            "title": "Review proposed memory claim",
                            "summary": "User prefers terse summaries.",
                            "priority": 5,
                            "recommendedDecision": "review",
                            "createdAt": "2026-05-16T00:00:00Z"
                        ]
                    ]
                ])
            }

            if path == "/mcp/tools/gmem.create_correction" {
                return Self.jsonResponse(for: request, body: [
                    "correctionId": "corr-1",
                    "targetId": "mem-1",
                    "correctionText": "Actually prefers detailed implementation notes.",
                    "mode": "supersede_not_overwrite",
                    "createdAt": "2026-05-16T00:00:00Z"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let reviewTasks = await client.refreshReviewTasks()
        let outcome = await client.createCorrection(
            OpenMindCorrectionRequest(
                targetID: "mem-1",
                correctionText: "Actually prefers detailed implementation notes.",
                actor: "dBrowser.user",
                source: OpenMindActionSource(
                    product: "dBrowser.swift",
                    runID: nil,
                    pageURLString: "https://example.com",
                    snapshotCommitment: "fnv1a64:abc",
                    prompt: "Summarize"
                ),
                idempotencyKey: "correction-key"
            )
        )
        let correctionBody = capturedRequests.body(for: "/mcp/tools/gmem.create_correction")
        let sourceBody = correctionBody?["source"] as? [String: Any]

        #expect(reviewTasks.first?.id == "review-1")
        #expect(reviewTasks.first?.entityID == "claim-1")
        #expect(outcome.status == .recorded)
        #expect(outcome.correctionID == "corr-1")
        #expect(outcome.targetID == "mem-1")
        #expect(outcome.mode == "supersede_not_overwrite")
        #expect(correctionBody?["targetId"] as? String == "mem-1")
        #expect(correctionBody?["correctionText"] as? String == "Actually prefers detailed implementation notes.")
        #expect(correctionBody?["actor"] as? String == "dBrowser.user")
        #expect(correctionBody?["idempotencyKey"] as? String == "correction-key")
        #expect(sourceBody?["product"] as? String == "dBrowser.swift")
    }

    @MainActor @Test func openMindMemoryClientUsesJSONRPCForReviewTasksAndCorrection() async {
        let capturedRPC = JSONRPCRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "memoryreviewrpc") { request in
            guard request.url?.path == "/mcp" else {
                return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
            }

            let payload = capturedRPC.capture(request) ?? [:]
            let method = payload["method"] as? String
            let id = payload["id"] ?? 1

            if method == "resources/read" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "contents": [
                            [
                                "uri": "mind://governed-memory/review-tasks",
                                "mimeType": "application/json",
                                "text": Self.jsonString([
                                    "items": [
                                        [
                                            "id": "review-rpc",
                                            "taskType": "claim_review",
                                            "state": "open",
                                            "entityId": "claim-rpc",
                                            "title": "Review RPC memory claim",
                                            "summary": "RPC review task"
                                        ]
                                    ]
                                ])
                            ]
                        ]
                    ]
                ])
            }

            if method == "tools/call",
               let params = payload["params"] as? [String: Any],
               params["name"] as? String == "gmem.create_correction" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "correctionId": "corr-rpc",
                            "targetId": "mem-rpc",
                            "correctionText": "Corrected via bridge",
                            "mode": "supersede_not_overwrite"
                        ],
                        "isError": false
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 400, body: ["error": "unexpected JSON-RPC request"])
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let reviewTasks = await client.refreshReviewTasks()
        let outcome = await client.createCorrection(
            OpenMindCorrectionRequest(
                targetID: "mem-rpc",
                correctionText: "Corrected via bridge",
                actor: "dBrowser.user",
                source: OpenMindActionSource(
                    product: "dBrowser.swift",
                    runID: nil,
                    pageURLString: nil,
                    snapshotCommitment: nil,
                    prompt: nil
                ),
                idempotencyKey: "correction-rpc"
            )
        )
        let correctionArguments = capturedRPC.toolArguments(named: "gmem.create_correction")

        #expect(reviewTasks.first?.id == "review-rpc")
        #expect(reviewTasks.first?.entityID == "claim-rpc")
        #expect(outcome.status == .recorded)
        #expect(outcome.correctionID == "corr-rpc")
        #expect(correctionArguments?["targetId"] as? String == "mem-rpc")
        #expect(correctionArguments?["correctionText"] as? String == "Corrected via bridge")
        #expect(correctionArguments?["idempotencyKey"] as? String == "correction-rpc")
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
    @Test func copilotRequestsOpenMindStepUpGrantFromRecallIntent() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "copilotstep") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "stepUpRequired",
                    "allowedScopes": [],
                    "reason": "grant required",
                    "redactionCount": 0,
                    "stepUpPrompt": "Confirm memory access"
                ])
            }

            if path == "/mcp/tools/gateway.request_step_up_grant" {
                return Self.jsonResponse(for: request, body: [
                    "requestId": "step-copilot",
                    "status": "pending",
                    "operation": "memory.search",
                    "requestedScopes": ["mind.read.basic"],
                    "purpose": "copilot_recall",
                    "requestedTtl": "PT1H",
                    "justification": "Confirm memory access"
                ])
            }

            if path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, status: 500, body: ["error": "search should wait for step-up"])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineServices = Self.makeAFMServiceSession(key: "copilotstepafm") { request in
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
        model.navigate("https://example.com/private")

        guard let runID = model.runCopilot(prompt: "Find private memory") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)

        #expect(completed)
        #expect(model.latestOpenMindRecall?.decision.status == .stepUpRequired)
        #expect(model.latestOpenMindStepUpRequest == nil)

        let stepTask = model.requestOpenMindStepUp()
        let requested = await waitForOpenMindStepUpRequest(in: model)
        let stepBody = capturedRequests.body(for: "/mcp/tools/gateway.request_step_up_grant")
        let stepIntentBody = stepBody?["intent"] as? [String: Any]

        #expect(stepTask != nil)
        #expect(requested)
        #expect(model.latestOpenMindStepUpRequest?.requestID == "step-copilot")
        #expect(model.latestOpenMindRecall?.stepUpRequest?.requestID == "step-copilot")
        #expect(capturedRequests.body(for: "/mcp/tools/mind.search_memories") == nil)
        #expect(stepBody?["justification"] as? String == "Confirm memory access")
        #expect(stepIntentBody?["prompt"] as? String == "Find private memory")
        #expect((stepIntentBody?["requestedDomains"] as? [String]) == ["example.com"])
    }

    @MainActor
    @Test func copilotMemoryWritebackRequiresExplicitActionAndRecordsOutcome() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "writeback") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "allowed",
                    "allowedScopes": ["profile"],
                    "reason": "allowed",
                    "redactionCount": 0
                ])
            }

            if path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, body: [
                    "memories": [],
                    "notices": []
                ])
            }

            if path == "/mcp/tools/mind.add_memory" {
                return Self.jsonResponse(for: request, body: [
                    "status": "recorded",
                    "revisionID": "rev-writeback",
                    "message": "recorded"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineServices = Self.makeAFMServiceSession(key: "writebackafm") { request in
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
        let snapshot = PageSnapshot(
            urlString: "https://example.com",
            title: "Example",
            visibleText: "Remember governed page context.",
            headings: ["Memory"],
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

        guard let runID = model.runCopilot(prompt: "Summarize and remember") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)

        #expect(completed)
        #expect(capturedRequests.body(for: "/mcp/tools/mind.add_memory") == nil)

        let outcome = await model.writeBackOpenMindMemory(for: runID)
        let writebackBody = capturedRequests.body(for: "/mcp/tools/mind.add_memory")
        let requestBody = writebackBody?["request"] as? [String: Any]
        let events = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(outcome.status == .recorded)
        #expect(outcome.revisionID == "rev-writeback")
        #expect(model.latestOpenMindWriteback == outcome)
        #expect(requestBody?["runID"] as? String == runID.uuidString)
        #expect(requestBody?["prompt"] as? String == "Summarize and remember")
        #expect(requestBody?["pageURLString"] as? String == "https://example.com")
        #expect(requestBody?["source"] as? String == "dBrowser.copilot")
        #expect((requestBody?["summary"] as? String)?.contains("Summarize and remember") == true)
        #expect((requestBody?["snapshotCommitment"] as? String)?.hasPrefix("fnv1a64:") == true)
        #expect(requestBody?["idempotencyKey"] as? String == "copilot-\(runID.uuidString)-writeback")
        #expect(events.contains(.memoryWritebackRequested))
        #expect(events.contains(.memoryWritebackRecorded))
    }

    @MainActor
    @Test func copilotMemoryWritebackRespectsProtectivePosture() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "protective") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/capabilities" {
                return Self.jsonResponse(for: request, body: [
                    "available": true,
                    "capabilities": ["mind.search_memories", "mind.add_memory", "posture.get"],
                    "posture": "protective",
                    "message": "ready"
                ])
            }

            if path == "/mcp/resources/mind/continuity" {
                return Self.jsonResponse(for: request, body: [
                    "summary": "Continuity ready",
                    "pendingStepUps": 0
                ])
            }

            if path == "/mcp/tools/posture.get" {
                return Self.jsonResponse(for: request, body: [
                    "mode": "protective",
                    "userMessage": "Protective posture blocks memory writeback.",
                    "allowsMemoryWriteback": false,
                    "requiresExplicitConfirmation": true
                ])
            }

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "allowed",
                    "allowedScopes": ["profile"],
                    "reason": "allowed",
                    "redactionCount": 0
                ])
            }

            if path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, body: [
                    "memories": [],
                    "notices": []
                ])
            }

            if path == "/mcp/tools/mind.add_memory" {
                return Self.jsonResponse(for: request, status: 500, body: ["error": "writeback should be blocked by posture"])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineServices = Self.makeAFMServiceSession(key: "protectiveafm") { request in
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

        await model.refreshRuntimeBridgeStatus()
        model.navigate("https://example.com")
        guard let runID = model.runCopilot(prompt: "Summarize without writeback") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)
        let outcome = await model.writeBackOpenMindMemory(for: runID)
        let events = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(completed)
        #expect(model.openMindPostureState.status == .available)
        #expect(model.openMindPostureState.allowsMemoryWriteback == false)
        #expect(outcome.status == .denied)
        #expect(outcome.message == "Protective posture blocks memory writeback.")
        #expect(capturedRequests.body(for: "/mcp/tools/mind.add_memory") == nil)
        #expect(events.contains(.memoryWritebackDenied))
    }

    @MainActor
    @Test func copilotOpenMindCorrectionRecordsOutcomeAndEvents() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "correctionvm") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/resources/mind/governed-memory/review-tasks" {
                return Self.jsonResponse(for: request, body: [
                    "items": [
                        [
                            "id": "review-after-correction",
                            "taskType": "claim_review",
                            "state": "open",
                            "entityId": "claim-after",
                            "title": "Review updated memory"
                        ]
                    ]
                ])
            }

            if path == "/mcp/tools/gmem.create_correction" {
                return Self.jsonResponse(for: request, body: [
                    "correctionId": "corr-vm",
                    "targetId": "mem-1",
                    "correctionText": "Correction from Copilot panel",
                    "mode": "supersede_not_overwrite"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let model = makeIsolatedBrowserViewModel(
            openMindMemoryClient: OpenMindMemoryClient(
                configuration: memoryHarness.configuration,
                session: memoryHarness.session
            )
        )
        model.navigate("https://example.com")
        let runID = UUID()
        model.copilotRuns = [
            CopilotRun(
                id: runID,
                prompt: "Summarize",
                activeTabID: model.activeTabID,
                targetURLString: "https://example.com",
                status: .completed
            )
        ]

        let task = model.requestOpenMindCorrection(
            targetID: "mem-1",
            correctionText: "Correction from Copilot panel"
        )
        let completed = await waitForOpenMindCorrection(in: model)
        let correctionBody = capturedRequests.body(for: "/mcp/tools/gmem.create_correction")
        let sourceBody = correctionBody?["source"] as? [String: Any]
        let events = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(task != nil)
        #expect(completed)
        #expect(model.latestOpenMindCorrection?.correctionID == "corr-vm")
        #expect(model.latestOpenMindCorrection?.status == .recorded)
        #expect(model.openMindReviewTasks.first?.id == "review-after-correction")
        #expect(correctionBody?["targetId"] as? String == "mem-1")
        #expect(correctionBody?["correctionText"] as? String == "Correction from Copilot panel")
        #expect(correctionBody?["actor"] as? String == "dBrowser.user")
        #expect((correctionBody?["idempotencyKey"] as? String)?.hasPrefix("correction-") == true)
        #expect(sourceBody?["product"] as? String == "dBrowser.swift")
        #expect(sourceBody?["runID"] as? String == runID.uuidString)
        #expect(events.contains(.memoryCorrectionRequested))
        #expect(events.contains(.memoryCorrectionRecorded))
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
    private func waitForOpenMindStepUpRequest(in model: BrowserViewModel) async -> Bool {
        for _ in 0..<40 {
            if model.latestOpenMindStepUpRequest != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @MainActor
    private func waitForOpenMindCorrection(in model: BrowserViewModel) async -> Bool {
        for _ in 0..<40 {
            if model.latestOpenMindCorrection != nil {
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
        llmConversationStore: LLMConversationStore = .ephemeral(),
        openMindMemoryClient: OpenMindMemoryClient? = nil
    ) -> BrowserViewModel {
        BrowserViewModel(
            initialURL: initialURL,
            runtimeBridge: runtimeBridge ?? MobileRuntimeBridge(),
            copilotWorkflowStore: workflowStore,
            smartHistoryStore: smartHistoryStore,
            llmConversationStore: llmConversationStore,
            openMindMemoryClient: openMindMemoryClient
        )
    }

    private static func chainAnchoredNodeTask(taskID: String, outputCommitment: String) -> AFMNodeTaskResult {
        let nonce = AFMNodeVerificationReport.bindingNonceHex(
            taskID: taskID,
            outputCommitment: outputCommitment
        ) ?? ""
        return AFMNodeTaskResult(
            ok: true,
            id: taskID,
            taskID: taskID,
            packID: "afm://demo-writer",
            installID: "install-chain",
            status: "completed",
            mode: "production",
            result: AFMNodeTaskOutput(
                summary: "production completed",
                outputCommitment: outputCommitment,
                completedAt: "2026-05-16T00:00:01Z"
            ),
            attestation: AFMAttestedRun(
                mode: "secure-enclave",
                taskID: taskID,
                outputCommitment: outputCommitment,
                nonce: nonce,
                tokenCount: 42,
                contextPassages: 2,
                attestationToken: "cbor-base64"
            ),
            proof: AFMProofState(
                proofID: "proof-chain",
                status: "verified",
                verifier: "0xverifier",
                publicInputs: [
                    "taskID": taskID,
                    "outputCommitment": outputCommitment
                ],
                proofBytes: "0xproof",
                publicInputsABI: "0xinputs",
                deadline: 1730203600,
                payoutAddress: "0x000000000000000000000000000000000000dead",
                modelIDHash: "0xmodel"
            ),
            settlement: AFMSettlementState(
                id: "settlement-chain",
                status: "settled",
                chainRef: "base-sepolia",
                escrowID: "escrow-chain",
                escrowContract: "0xescrow",
                transactionHash: "0xtx-chain",
                blockNumber: 456,
                deadline: 1730203600,
                verifier: "0xverifier",
                mode: "production",
                settledAt: "2026-05-16T00:00:02Z"
            )
        )
    }

    private static func temporaryJSONStoreURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dbrowser-\(name)-\(UUID().uuidString).json")
    }

    private static func makeAFMServiceSession(
        key: String,
        includesMarketplace: Bool = false,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: AFMServiceEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoints = AFMServiceEndpointConfiguration(
            routerBaseURL: URL(string: "http://\(key)-router.test:4810")!,
            registryBaseURL: URL(string: "http://\(key)-registry.test:4820")!,
            pipelinesBaseURL: URL(string: "http://\(key)-pipelines.test:4830")!,
            nodeBaseURL: URL(string: "http://\(key)-node.test:4840")!,
            marketplaceBaseURL: includesMarketplace ? URL(string: "http://\(key)-marketplace.test:4850")! : nil
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

    private static func makeLLMRouterSession(
        key: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: LLMRouterEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = LLMRouterEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-llm-router.test:4850")!,
            provider: .appleFoundation,
            preferLocal: true,
            noEgress: true
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

    private static func emptyResponse(
        for request: URLRequest,
        status: Int = 204
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: [:]
        )!
        return (response, Data())
    }

    private static func jsonString(_ body: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: body)
        return String(data: data, encoding: .utf8)!
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

    fileprivate static func readBodyStream(_ stream: InputStream?) -> Data? {
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

private final class JSONRPCRequestCapture {
    private let lock = NSLock()
    private var bodies: [[String: Any]] = []

    func capture(_ request: URLRequest) -> [String: Any]? {
        guard let data = request.httpBody ?? JSONRequestCapture.readBodyStream(request.httpBodyStream),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        lock.lock()
        bodies.append(object)
        lock.unlock()
        return object
    }

    func toolArguments(named name: String) -> [String: Any]? {
        lock.lock()
        let match = bodies.last { body in
            guard body["method"] as? String == "tools/call",
                  let params = body["params"] as? [String: Any] else {
                return false
            }
            return params["name"] as? String == name
        }
        lock.unlock()

        let params = match?["params"] as? [String: Any]
        return params?["arguments"] as? [String: Any]
    }
}

private final class AFMServiceMockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    private static let lock = NSLock()

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
