import Contracts
import LoggingKit
import RuntimeAdapters
import Storage
import Testing
import Foundation
@testable import ControlPlane

@Test
func controlPlaneBootstrapPersistsStateAndDeveloperAPIKeyMetadata() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-tests-\(UUID().uuidString.lowercased())")
    let paths = ApplicationPaths(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let host1 = try await ControlPlaneHost.bootstrap(paths: paths)
    #expect(host1.secrets.plaintextKey != nil)

    let imported = try await host1.service.importModel(
        ImportModelRequest(
            displayName: "Qwen 0.5B",
            sourceKind: .huggingFace,
            sourceRef: "Qwen/Qwen2.5-0.5B-Instruct"
        )
    )
    _ = await host1.service.createConversation(
        CreateConversationRequest(title: "Persist me", modelId: imported.id)
    )

    let host2 = try await ControlPlaneHost.bootstrap(paths: paths)
    #expect(host2.secrets.plaintextKey == nil)
    #expect(host2.secrets.preview == host1.secrets.preview)

    let overview = await host2.service.overview()
    #expect(overview.models.contains(where: { $0.id == imported.id }))
    #expect(overview.conversations.contains(where: { $0.title == "Persist me" }))
}

@Test
func controlPlaneSurfacesBackendAutoProvisionFailuresDuringValidationAndLaunch() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-tests-\(UUID().uuidString.lowercased())")
    let paths = ApplicationPaths(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let persistence = try PersistenceBootstrap(paths: paths)
    let service = try await ControlPlaneService.bootstrap(
        hardware: testHardware(),
        persistence: persistence,
        logger: AppLogger(),
        secrets: .generate(),
        runtimeCatalog: RuntimeCatalog(adapters: [
            MissingRuntimeAdapter(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal),
            MissingRuntimeAdapter(id: BackendKind.mlxNative.rawValue, kind: .mlxNative)
        ]),
        baseURL: "http://127.0.0.1:8400",
        runtimeInstaller: MockRuntimeInstaller { backendID in
            switch backendID {
            case BackendKind.mlxNative.rawValue:
                throw APIErrorEnvelope(
                    code: "BACKEND_INSTALL_PREREQUISITE_MISSING",
                    message: "MLX Native requires a local Python 3.8 interpreter. Install it and retry.",
                    details: ["backendId": backendID]
                )
            case BackendKind.vllmMetal.rawValue:
                throw APIErrorEnvelope(
                    code: "BACKEND_INSTALL_PREREQUISITE_MISSING",
                    message: "vLLM Metal requires a local Python 3.12 interpreter. Install it and retry.",
                    details: ["backendId": backendID]
                )
            default:
                throw APIErrorEnvelope(code: "BACKEND_NOT_SUPPORTED", message: "Unknown backend.", details: ["backendId": backendID])
            }
        }
    )
    let model = try await service.importModel(
        ImportModelRequest(
            displayName: "Qwen 7B Q4",
            sourceKind: .huggingFace,
            sourceRef: "Qwen/Qwen2.5-7B-Instruct-4bit"
        )
    )

    do {
        _ = try await service.validateModel(id: model.id, preferredBackendId: BackendKind.mlxNative.rawValue)
        Issue.record("Expected validation to fail when backend auto-provisioning cannot satisfy prerequisites.")
    } catch let error as APIErrorEnvelope {
        #expect(error.error.code == "BACKEND_AUTO_PROVISION_FAILED")
        #expect(error.error.message.contains("MLX Native"))
        #expect(error.error.message.contains("vLLM Metal"))
        #expect(error.localizedDescription == error.error.message)
    }

    do {
        _ = try await service.launch(LaunchSpec(modelId: model.id, requestMode: .chat, maxContext: 8_192, maxOutputTokens: 512))
        Issue.record("Expected launch to fail when backend auto-provisioning cannot satisfy prerequisites.")
    } catch let error as APIErrorEnvelope {
        #expect(error.error.code == "BACKEND_AUTO_PROVISION_FAILED")
        #expect(error.error.message.contains("MLX Native"))
        #expect(error.error.message.contains("vLLM Metal"))
        #expect(error.localizedDescription == error.error.message)
    }
}

@Test
func controlPlaneAutoInstallsManagedBackendForConversationLaunch() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-tests-\(UUID().uuidString.lowercased())")
    let paths = ApplicationPaths(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let persistence = try PersistenceBootstrap(paths: paths)
    let installationState = SharedInstallationState(
        runtimeRoot: paths.runtimesDirectory.appending(path: "mlx-native-test"),
        executablePath: "/usr/bin/python3"
    )
    let service = try await ControlPlaneService.bootstrap(
        hardware: testHardware(),
        persistence: persistence,
        logger: AppLogger(),
        secrets: .generate(),
        runtimeCatalog: RuntimeCatalog(adapters: [
            AutoInstallChatAdapter(state: installationState),
            MissingRuntimeAdapter(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal)
        ]),
        baseURL: "http://127.0.0.1:8400",
        runtimeInstaller: MockRuntimeInstaller { backendID in
            #expect(backendID == BackendKind.mlxNative.rawValue)
            try FileManager.default.createDirectory(at: installationState.runtimeRoot, withIntermediateDirectories: true)
            installationState.markInstalled()
            return RuntimeManifest(
                backendId: backendID,
                packageName: "mlx-lm",
                version: "test",
                pythonVersion: "3.9.6",
                installedAt: Time.nowISO8601(),
                runtimeRootPath: installationState.runtimeRoot.path,
                executablePath: installationState.executablePath,
                pythonPath: installationState.executablePath
            )
        }
    )
    let model = try await service.importModel(
        ImportModelRequest(
            displayName: "Qwen 7B Q4",
            sourceKind: .huggingFace,
            sourceRef: "Qwen/Qwen2.5-7B-Instruct-4bit"
        )
    )
    let conversation = await service.createConversation(
        CreateConversationRequest(title: "Playground", modelId: model.id)
    )

    let updated = try await service.addMessage(
        conversationID: conversation.id,
        payload: AddConversationMessageRequest(role: "user", content: "Hello")
    )

    #expect(updated.messages.count == 2)
    #expect(updated.messages.last?.role == "assistant")
    #expect(updated.messages.last?.content == "Auto-installed backend reply")
    #expect(installationState.isInstalled())

    let activity = await service.activity()
    if let instanceID = activity.activeInstances.first?.instanceId {
        _ = try? await service.stopEngine(id: instanceID)
    }
}

@Test
func controlPlaneSearchesHuggingFaceModelCatalog() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-tests-\(UUID().uuidString.lowercased())")
    let paths = ApplicationPaths(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let persistence = try PersistenceBootstrap(paths: paths)
    let service = try await ControlPlaneService.bootstrap(
        hardware: testHardware(),
        persistence: persistence,
        logger: AppLogger(),
        secrets: .generate(),
        runtimeCatalog: RuntimeCatalog(adapters: [
            MissingRuntimeAdapter(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal),
            MissingRuntimeAdapter(id: BackendKind.mlxNative.rawValue, kind: .mlxNative)
        ]),
        baseURL: "http://127.0.0.1:8400",
        modelCatalog: MockModelCatalog { query, limit in
            #expect(query == "qwen")
            #expect(limit == 5)
            return [
                ModelSearchResult(
                    id: "Qwen/Qwen2.5-7B-Instruct",
                    displayName: "Qwen2.5-7B-Instruct",
                    downloads: 14881790,
                    likes: 1180,
                    pipelineTag: "text-generation",
                    libraryName: "transformers",
                    createdAt: "2024-09-16T11:55:40.000Z",
                    tags: ["transformers", "chat"]
                )
            ]
        }
    )

    let response = try await service.searchModelCatalog(query: "qwen", limit: 5)

    #expect(response.query == "qwen")
    #expect(response.results.count == 1)
    #expect(response.results.first?.id == "Qwen/Qwen2.5-7B-Instruct")
    #expect(response.results.first?.pipelineTag == "text-generation")
}

@Test
func controlPlaneRewritesPublicModelIDForMLXProxyRequests() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-tests-\(UUID().uuidString.lowercased())")
    let paths = ApplicationPaths(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let secrets = DeveloperAPISecrets.generate()
    let persistence = try PersistenceBootstrap(paths: paths)
    let service = try await ControlPlaneService.bootstrap(
        hardware: testHardware(),
        persistence: persistence,
        logger: AppLogger(),
        secrets: secrets,
        runtimeCatalog: RuntimeCatalog(adapters: [
            ModelNameRewritingAdapter(),
            MissingRuntimeAdapter(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal)
        ]),
        baseURL: "http://127.0.0.1:8400"
    )
    let model = try await service.importModel(
        ImportModelRequest(
            displayName: "Qwen 1.5B",
            sourceKind: .huggingFace,
            sourceRef: "Qwen/Qwen2.5-1.5B-Instruct"
        )
    )

    let completion = try await service.chatCompletion(
        OpenAIChatCompletionRequest(
            model: model.id,
            messages: [ChatMessagePayload(role: "user", content: "ready")],
            maxTokens: 8
        )
    )
    #expect(completion.choices.first?.message.content == "rewritten")

    let requestBody = try JSONEncoder().encode(
        OpenAIChatCompletionRequest(
            model: model.id,
            messages: [ChatMessagePayload(role: "user", content: "ready")],
            maxTokens: 8
        )
    )
    let response = await service.handle(
        request: HTTPRequest(
            method: "POST",
            path: "/v1/chat/completions",
            query: [:],
            headers: ["authorization": "Bearer \(secrets.plaintextKey ?? "")"],
            body: requestBody
        )
    )

    #expect(response.statusCode == 200)
    let routedCompletion = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: response.body)
    #expect(routedCompletion.choices.first?.message.content == "rewritten")

    let activity = await service.activity()
    if let instanceID = activity.activeInstances.first?.instanceId {
        _ = try? await service.stopEngine(id: instanceID)
    }
}

@Test
func controlPlaneAllowsUnauthenticatedAndStaleKeyProxyRequests() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-tests-\(UUID().uuidString.lowercased())")
    let paths = ApplicationPaths(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let secrets = DeveloperAPISecrets.generate()
    let persistence = try PersistenceBootstrap(paths: paths)
    let service = try await ControlPlaneService.bootstrap(
        hardware: testHardware(),
        persistence: persistence,
        logger: AppLogger(),
        secrets: secrets,
        runtimeCatalog: RuntimeCatalog(adapters: [
            ModelNameRewritingAdapter(),
            MissingRuntimeAdapter(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal)
        ]),
        baseURL: "http://127.0.0.1:8400"
    )
    let model = try await service.importModel(
        ImportModelRequest(
            displayName: "Qwen 1.5B",
            sourceKind: .huggingFace,
            sourceRef: "Qwen/Qwen2.5-1.5B-Instruct"
        )
    )

    let requestBody = try JSONEncoder().encode(
        OpenAIChatCompletionRequest(
            model: model.id,
            messages: [ChatMessagePayload(role: "user", content: "ready")],
            maxTokens: 8
        )
    )

    let unauthenticatedResponse = await service.handle(
        request: HTTPRequest(
            method: "POST",
            path: "/v1/chat/completions",
            query: [:],
            headers: [:],
            body: requestBody
        )
    )
    #expect(unauthenticatedResponse.statusCode == 200)

    let staleKeyResponse = await service.handle(
        request: HTTPRequest(
            method: "POST",
            path: "/v1/chat/completions",
            query: [:],
            headers: ["authorization": "Bearer stale-key"],
            body: requestBody
        )
    )
    #expect(staleKeyResponse.statusCode == 200)

    let modelsResponse = await service.handle(
        request: HTTPRequest(
            method: "GET",
            path: "/v1/models",
            query: [:],
            headers: [:],
            body: Data()
        )
    )
    #expect(modelsResponse.statusCode == 200)

    let developerAPI = await service.overview().developerAPI
    #expect(developerAPI.requiresAPIKey == false)

    let activity = await service.activity()
    if let instanceID = activity.activeInstances.first?.instanceId {
        _ = try? await service.stopEngine(id: instanceID)
    }
}

@Test
func controlPlaneSurfacesModelSearchFailures() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-tests-\(UUID().uuidString.lowercased())")
    let paths = ApplicationPaths(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let persistence = try PersistenceBootstrap(paths: paths)
    let service = try await ControlPlaneService.bootstrap(
        hardware: testHardware(),
        persistence: persistence,
        logger: AppLogger(),
        secrets: .generate(),
        runtimeCatalog: RuntimeCatalog(adapters: [
            MissingRuntimeAdapter(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal),
            MissingRuntimeAdapter(id: BackendKind.mlxNative.rawValue, kind: .mlxNative)
        ]),
        baseURL: "http://127.0.0.1:8400",
        modelCatalog: MockModelCatalog { _, _ in
            throw URLError(.notConnectedToInternet)
        }
    )

    do {
        _ = try await service.searchModelCatalog(query: "qwen", limit: 10)
        Issue.record("Expected model search to fail when the catalog fetch fails.")
    } catch let error as APIErrorEnvelope {
        #expect(error.error.code == "MODEL_SEARCH_FAILED")
        #expect(error.error.details["query"] == "qwen")
        #expect(error.error.message.contains("Hugging Face search failed"))
    }
}

@Test
func controlPlaneBenchmarkUsesScenarioProfileSelection() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "swiftlm-tests-\(UUID().uuidString.lowercased())")
    let paths = ApplicationPaths(root: root)
    defer { try? FileManager.default.removeItem(at: root) }

    let persistence = try PersistenceBootstrap(paths: paths)
    let service = try await ControlPlaneService.bootstrap(
        hardware: testHardware(),
        persistence: persistence,
        logger: AppLogger(),
        secrets: .generate(),
        runtimeCatalog: RuntimeCatalog(adapters: [
            MissingRuntimeAdapter(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal),
            MissingRuntimeAdapter(id: BackendKind.mlxNative.rawValue, kind: .mlxNative)
        ]),
        baseURL: "http://127.0.0.1:8400"
    )
    let model = try await service.importModel(
        ImportModelRequest(
            displayName: "Qwen 7B Q4",
            sourceKind: .huggingFace,
            sourceRef: "Qwen/Qwen2.5-7B-Instruct-4bit"
        )
    )

    let record = try await service.runBenchmark(
        BenchmarkRequest(modelId: model.id, scenario: .mlxFallbackChat)
    )

    #expect(record.engineBackendId == BackendKind.mlxNative.rawValue)
    #expect(record.scenario == BenchmarkScenario.mlxFallbackChat.rawValue)
}

private func testHardware() -> HardwareSnapshot {
    HardwareSnapshot(
        chipFamily: "Apple M5 Max",
        performanceCores: 12,
        efficiencyCores: 4,
        gpuCores: 40,
        totalMemoryBytes: 128 * 1_024 * 1_024 * 1_024,
        freeDiskBytes: 512 * 1_024 * 1_024 * 1_024,
        osVersion: "macOS 26.4",
        metalAvailable: true
    )
}

private struct MissingRuntimeAdapter: EngineAdapter {
    let id: String
    let kind: BackendKind

    func detect(hardware: HardwareSnapshot) async -> BackendDetection {
        BackendDetection(
            id: id,
            kind: kind,
            version: nil,
            runtimePath: nil,
            pythonVersion: nil,
            status: .missing,
            capabilities: ["chat"]
        )
    }

    func detectInstallation() -> RuntimeInstallation? {
        nil
    }

    func validate(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> ValidationReport {
        ValidationReport(
            modelId: model.id,
            backendId: id,
            supportsLoad: false,
            supportsChat: true,
            supportsResponses: true,
            supportsEmbeddings: false,
            supportsVision: false,
            supportsTools: false,
            supportsStructuredOutputs: false,
            needsCustomChatTemplate: false,
            riskTier: .unknown,
            warnings: [],
            measured: ValidationMetrics()
        )
    }

    func estimateMemory(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> MemoryEstimate {
        MemoryEstimate(
            weightsResidentBytes: 0,
            kvCacheBytes: 0,
            runtimeOverheadBytes: 0,
            promptBufferBytes: 0,
            safetyMarginBytes: 0,
            estimatedPeakBytes: 0,
            reserveBytes: 0,
            headroomBytes: hardware.totalMemoryBytes,
            riskTier: .safe
        )
    }

    func launch(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async throws -> EngineInstanceRef {
        throw APIErrorEnvelope(code: "UNREACHABLE", message: "Missing runtime adapter should never launch.")
    }

    func stop(instanceId: String) async {}

    func health(instanceId: String) async -> HealthReport {
        HealthReport(instanceId: instanceId, healthy: false, status: .unhealthy, message: "Runtime not installed")
    }

    func launchPlan(
        model: ModelRecord,
        spec: LaunchSpec,
        profile: LaunchProfile?,
        installation: RuntimeInstallation,
        port: Int,
        publicModelName: String,
        apiKey: String?
    ) throws -> EngineLaunchPlan {
        throw APIErrorEnvelope(code: "UNREACHABLE", message: "Missing runtime adapter should never create a launch plan.")
    }
}

private final class SharedInstallationState: @unchecked Sendable {
    let runtimeRoot: URL
    let executablePath: String

    private let lock = NSLock()
    private var installed = false

    init(runtimeRoot: URL, executablePath: String) {
        self.runtimeRoot = runtimeRoot
        self.executablePath = executablePath
    }

    func markInstalled() {
        lock.lock()
        installed = true
        lock.unlock()
    }

    func isInstalled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return installed
    }
}

private struct AutoInstallChatAdapter: EngineAdapter {
    let id = BackendKind.mlxNative.rawValue
    let state: SharedInstallationState

    func detect(hardware: HardwareSnapshot) async -> BackendDetection {
        BackendDetection(
            id: id,
            kind: .mlxNative,
            version: state.isInstalled() ? "test" : nil,
            runtimePath: state.runtimeRoot.path,
            pythonVersion: state.isInstalled() ? "3.9.6" : nil,
            status: state.isInstalled() ? .installed : .missing,
            capabilities: ["chat", "responses"]
        )
    }

    func detectInstallation() -> RuntimeInstallation? {
        guard state.isInstalled() else {
            return nil
        }
        return RuntimeInstallation(
            backendId: id,
            rootPath: state.runtimeRoot.path,
            executablePath: state.executablePath,
            pythonPath: state.executablePath,
            version: "test",
            pythonVersion: "3.9.6"
        )
    }

    func validate(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> ValidationReport {
        ValidationReport(
            modelId: model.id,
            backendId: id,
            supportsLoad: state.isInstalled(),
            supportsChat: true,
            supportsResponses: true,
            supportsEmbeddings: false,
            supportsVision: false,
            supportsTools: false,
            supportsStructuredOutputs: false,
            needsCustomChatTemplate: false,
            riskTier: .safe,
            warnings: [],
            measured: ValidationMetrics(peakMemoryBytes: 1_024 * 1_024 * 1_024)
        )
    }

    func estimateMemory(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> MemoryEstimate {
        MemoryEstimate(
            weightsResidentBytes: 1_024 * 1_024 * 1_024,
            kvCacheBytes: 256 * 1_024 * 1_024,
            runtimeOverheadBytes: 128 * 1_024 * 1_024,
            promptBufferBytes: 64 * 1_024 * 1_024,
            safetyMarginBytes: 64 * 1_024 * 1_024,
            estimatedPeakBytes: 1_536 * 1_024 * 1_024,
            reserveBytes: 512 * 1_024 * 1_024,
            headroomBytes: hardware.totalMemoryBytes - (2_048 * 1_024 * 1_024),
            riskTier: .safe
        )
    }

    func launch(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async throws -> EngineInstanceRef {
        throw APIErrorEnvelope(code: "UNREACHABLE", message: "Test adapter launch should route through launchPlan.")
    }

    func stop(instanceId: String) async {}

    func health(instanceId: String) async -> HealthReport {
        HealthReport(instanceId: instanceId, healthy: state.isInstalled(), status: .ready, message: "Test backend ready")
    }

    func launchPlan(
        model: ModelRecord,
        spec: LaunchSpec,
        profile: LaunchProfile?,
        installation: RuntimeInstallation,
        port: Int,
        publicModelName: String,
        apiKey: String?
    ) throws -> EngineLaunchPlan {
        let serverScript = """
        import json, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer

        model_name = sys.argv[2]

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                return

            def _send_json(self, payload):
                encoded = json.dumps(payload).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

            def do_GET(self):
                if self.path == "/v1/models":
                    self._send_json({"object": "list", "data": [{"id": model_name, "object": "model", "owned_by": "swiftlm", "created": 0}]})
                    return
                self.send_error(404)

            def do_POST(self):
                if self.path == "/v1/chat/completions":
                    self._send_json({
                        "id": "chatcmpl-test",
                        "object": "chat.completion",
                        "created": 0,
                        "model": model_name,
                        "choices": [{"index": 0, "message": {"role": "assistant", "content": "Auto-installed backend reply"}, "finish_reason": "stop"}],
                        "usage": {"prompt_tokens": 4, "completion_tokens": 4, "total_tokens": 8}
                    })
                    return
                self.send_error(404)

        HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
        """

        return EngineLaunchPlan(
            backendId: id,
            executablePath: installation.executablePath,
            arguments: ["-c", serverScript, "\(port)", publicModelName],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            readinessPath: "/v1/models",
            metricsPath: nil,
            engineModelName: publicModelName,
            supportsDirectResponses: true,
            supportsDirectEmbeddings: false
        )
    }
}

private struct MockRuntimeInstaller: BackendRuntimeInstalling {
    let handler: @Sendable (String) async throws -> RuntimeManifest

    func install(backendID: String) async throws -> RuntimeManifest {
        try await handler(backendID)
    }
}

private struct ModelNameRewritingAdapter: EngineAdapter {
    let id = BackendKind.mlxNative.rawValue

    func detect(hardware: HardwareSnapshot) async -> BackendDetection {
        BackendDetection(
            id: id,
            kind: .mlxNative,
            version: "test",
            runtimePath: "/tmp/model-name-rewrite",
            pythonVersion: "3.11",
            status: .installed,
            capabilities: ["chat", "responses"]
        )
    }

    func detectInstallation() -> RuntimeInstallation? {
        RuntimeInstallation(
            backendId: id,
            rootPath: "/tmp/model-name-rewrite",
            executablePath: "/usr/bin/python3",
            pythonPath: "/usr/bin/python3",
            version: "test",
            pythonVersion: "3.11"
        )
    }

    func validate(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> ValidationReport {
        ValidationReport(
            modelId: model.id,
            backendId: id,
            supportsLoad: true,
            supportsChat: true,
            supportsResponses: true,
            supportsEmbeddings: false,
            supportsVision: false,
            supportsTools: false,
            supportsStructuredOutputs: false,
            needsCustomChatTemplate: false,
            riskTier: .safe,
            warnings: [],
            measured: ValidationMetrics(peakMemoryBytes: 1_024 * 1_024)
        )
    }

    func estimateMemory(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> MemoryEstimate {
        MemoryEstimate(
            weightsResidentBytes: 1_024 * 1_024,
            kvCacheBytes: 1_024 * 1_024,
            runtimeOverheadBytes: 1_024 * 1_024,
            promptBufferBytes: 1_024 * 1_024,
            safetyMarginBytes: 1_024 * 1_024,
            estimatedPeakBytes: 5 * 1_024 * 1_024,
            reserveBytes: 1_024 * 1_024,
            headroomBytes: hardware.totalMemoryBytes - (8 * 1_024 * 1_024),
            riskTier: .safe
        )
    }

    func launch(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async throws -> EngineInstanceRef {
        throw APIErrorEnvelope(code: "UNREACHABLE", message: "Rewrite adapter launch should route through launchPlan.")
    }

    func stop(instanceId: String) async {}

    func health(instanceId: String) async -> HealthReport {
        HealthReport(instanceId: instanceId, healthy: true, status: .ready, message: "Rewrite adapter ready")
    }

    func launchPlan(
        model: ModelRecord,
        spec: LaunchSpec,
        profile: LaunchProfile?,
        installation: RuntimeInstallation,
        port: Int,
        publicModelName: String,
        apiKey: String?
    ) throws -> EngineLaunchPlan {
        let serverScript = """
        import json, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer

        expected_model = sys.argv[2]

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                return

            def _send(self, status_code, payload):
                encoded = json.dumps(payload).encode('utf-8')
                self.send_response(status_code)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)

            def do_GET(self):
                if self.path == '/v1/models':
                    self._send(200, {'object': 'list', 'data': [{'id': expected_model, 'object': 'model', 'owned_by': 'swiftlm', 'created': 0}]})
                    return
                self.send_error(404)

            def do_POST(self):
                length = int(self.headers.get('Content-Length', '0'))
                payload = json.loads(self.rfile.read(length).decode('utf-8') or '{}')
                if payload.get('model') != expected_model:
                    self._send(404, {'error': f"expected model {expected_model}, got {payload.get('model')}"})
                    return
                self._send(200, {
                    'id': 'chatcmpl-rewrite',
                    'object': 'chat.completion',
                    'created': 0,
                    'model': expected_model,
                    'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': 'rewritten'}, 'finish_reason': 'stop'}],
                    'usage': {'prompt_tokens': 4, 'completion_tokens': 1, 'total_tokens': 5}
                })

        HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
        """

        return EngineLaunchPlan(
            backendId: id,
            executablePath: installation.executablePath,
            arguments: ["-c", serverScript, "\(port)", "internal-engine-model"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            readinessPath: "/v1/models",
            metricsPath: nil,
            engineModelName: "internal-engine-model",
            supportsDirectResponses: false,
            supportsDirectEmbeddings: false
        )
    }
}

private struct MockModelCatalog: ModelCatalogSearching {
    let handler: @Sendable (String, Int) async throws -> [ModelSearchResult]
    var modelCardHandler: @Sendable (String) async throws -> ModelCatalogCard = { id in
        ModelCatalogCard(
            id: id,
            displayName: id,
            repositoryURL: "https://huggingface.co/\(id)"
        )
    }

    func searchModels(query: String, limit: Int) async throws -> [ModelSearchResult] {
        try await handler(query, limit)
    }

    func fetchModelCard(id: String) async throws -> ModelCatalogCard {
        try await modelCardHandler(id)
    }
}
