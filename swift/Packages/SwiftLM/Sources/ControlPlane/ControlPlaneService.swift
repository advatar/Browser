import BenchmarkKit
import Contracts
import CryptoKit
import Foundation
import LoggingKit
import ModelInspection
import RuntimeAdapters
import Storage

public struct DeveloperAPISecrets: Sendable {
    public let plaintextKey: String?
    public let keyHash: String
    private let previewText: String

    public var preview: String {
        previewText
    }

    public static func generate() -> DeveloperAPISecrets {
        let plaintext = "sk-swiftlm-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let hash = SHA256.hash(data: Data(plaintext.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        return DeveloperAPISecrets(plaintextKey: plaintext, keyHash: hash, previewText: "\(plaintext.prefix(10))...")
    }

    public static func restore(keyHash: String, preview: String) -> DeveloperAPISecrets {
        DeveloperAPISecrets(plaintextKey: nil, keyHash: keyHash, previewText: preview)
    }
}

private struct PersistedDeveloperAPIKey: Codable {
    let keyHash: String
    let preview: String
    let createdAt: String
}

private struct PersistedControlPlaneState: Codable {
    let models: [ModelRecord]
    let profiles: [LaunchProfile]
    let benchmarks: [BenchmarkRecord]
    let conversations: [ConversationRecord]

    init(
        models: [ModelRecord] = [],
        profiles: [LaunchProfile] = [],
        benchmarks: [BenchmarkRecord] = [],
        conversations: [ConversationRecord] = []
    ) {
        self.models = models
        self.profiles = profiles
        self.benchmarks = benchmarks
        self.conversations = conversations
    }
}

public struct HardwareProbe: Sendable {
    public init() {}

    public func collect() -> HardwareSnapshot {
        let processInfo = ProcessInfo.processInfo
        let totalMemory = Int64(processInfo.physicalMemory)
        let processorCount = processInfo.processorCount
        let performanceCores = sysctlInt(named: "hw.perflevel0.physicalcpu") ?? max(processorCount / 2, 1)
        let efficiencyCores = sysctlInt(named: "hw.perflevel1.physicalcpu") ?? max(processorCount - performanceCores, 0)
        let gpuCores = sysctlInt(named: "hw.nperflevels") ?? 16
        let freeDisk = freeDiskBytes()
        let chipFamily = sysctlString(named: "machdep.cpu.brand_string") ?? sysctlString(named: "hw.model") ?? "Apple Silicon"
        let osVersion = "\(processInfo.operatingSystemVersionString)"
        return HardwareSnapshot(
            chipFamily: chipFamily,
            performanceCores: performanceCores,
            efficiencyCores: efficiencyCores,
            gpuCores: gpuCores,
            totalMemoryBytes: totalMemory,
            freeDiskBytes: freeDisk,
            osVersion: osVersion,
            metalAvailable: true,
            notes: [
                "unifiedMemory": "true"
            ]
        )
    }

    private func freeDiskBytes() -> Int64 {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    private func sysctlString(named name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let trimmed = buffer.prefix { $0 != 0 }
        return String(decoding: trimmed.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func sysctlInt(named name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

public final class ControlPlaneHost: @unchecked Sendable {
    public let service: ControlPlaneService
    public let server: LocalHTTPServer
    public let secrets: DeveloperAPISecrets

    private init(service: ControlPlaneService, server: LocalHTTPServer, secrets: DeveloperAPISecrets) {
        self.service = service
        self.server = server
        self.secrets = secrets
    }

    public static func bootstrap(
        port: UInt16 = 8_400,
        paths: ApplicationPaths = .defaultPaths()
    ) async throws -> ControlPlaneHost {
        let logger = AppLogger()
        await logger.log(level: "info", category: "control-plane", message: "Starting control plane bootstrap.", metadata: [
            "database": paths.databaseFile.path,
            "port": "\(port)",
            "root": paths.root.path
        ])
        do {
            let persistence = try PersistenceBootstrap(paths: paths)
            await logger.log(level: "info", category: "control-plane", message: "Prepared persistence bootstrap.", metadata: [
                "database": persistence.paths.databaseFile.path,
                "modelsDirectory": persistence.paths.modelsDirectory.path,
                "runtimesDirectory": persistence.paths.runtimesDirectory.path
            ])
            let hardware = HardwareProbe().collect()
            await logger.log(level: "info", category: "control-plane", message: "Collected hardware snapshot.", metadata: [
                "chipFamily": hardware.chipFamily,
                "gpuCores": "\(hardware.gpuCores)",
                "memoryBytes": "\(hardware.totalMemoryBytes)",
                "osVersion": hardware.osVersion
            ])

            let secrets: DeveloperAPISecrets
            if let persisted = try persistence.database.decodableSetting(PersistedDeveloperAPIKey.self, for: "developer_api_key") {
                secrets = .restore(keyHash: persisted.keyHash, preview: persisted.preview)
                await logger.log(level: "info", category: "control-plane", message: "Restored persisted developer API key.", metadata: [
                    "preview": secrets.preview
                ])
            } else {
                let generated = DeveloperAPISecrets.generate()
                let persisted = PersistedDeveloperAPIKey(keyHash: generated.keyHash, preview: generated.preview, createdAt: Time.nowISO8601())
                try persistence.database.upsertSetting(key: "developer_api_key", value: persisted)
                secrets = generated
                await logger.log(level: "info", category: "control-plane", message: "Generated developer API key.", metadata: [
                    "preview": secrets.preview
                ])
            }

            let service = try await ControlPlaneService.bootstrap(
                hardware: hardware,
                persistence: persistence,
                logger: logger,
                secrets: secrets,
                runtimeCatalog: .local,
                baseURL: "http://127.0.0.1:\(port)"
            )
            await logger.log(level: "info", category: "control-plane", message: "Initialized control plane service.", metadata: [
                "baseURL": "http://127.0.0.1:\(port)"
            ])

            let server = try LocalHTTPServer(port: port) { request in
                await service.handle(request: request)
            }
            await logger.log(level: "info", category: "control-plane", message: "Prepared local HTTP server.", metadata: [
                "port": "\(port)"
            ])
            return ControlPlaneHost(service: service, server: server, secrets: secrets)
        } catch {
            await logger.log(level: "error", category: "control-plane", message: "Control plane bootstrap failed.", metadata: [
                "error": String(describing: error),
                "localizedDescription": error.localizedDescription
            ])
            throw error
        }
    }

    public func start() async throws {
        try await server.start()
    }

    public func stop() {
        server.stop()
    }
}

public actor ControlPlaneService {
    private let startedAt = Date()
    private let hardware: HardwareSnapshot
    private let persistence: PersistenceBootstrap
    private let logger: AppLogger
    private let secrets: DeveloperAPISecrets
    private let adaptersByID: [String: any EngineAdapter]
    private let benchmarker: Benchmarker
    private let inspector: ModelInspector
    private let scheduler: Scheduler
    private let baseURL: String
    private let runtimeInstaller: any BackendRuntimeInstalling
    private let modelCatalog: any ModelCatalogSearching

    private var backends: [BackendDetection]
    private var models: [String: ModelRecord]
    private var profiles: [String: LaunchProfile]
    private var instances: [String: EngineInstanceRef]
    private var managedEngines: [String: ManagedEngine]
    private var benchmarks: [String: BenchmarkRecord]
    private var conversations: [String: ConversationRecord]
    private var installingBackends: Set<String>

    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private init(
        hardware: HardwareSnapshot,
        persistence: PersistenceBootstrap,
        logger: AppLogger,
        secrets: DeveloperAPISecrets,
        adaptersByID: [String: any EngineAdapter],
        backends: [BackendDetection],
        benchmarker: Benchmarker,
        inspector: ModelInspector,
        scheduler: Scheduler,
        baseURL: String,
        runtimeInstaller: any BackendRuntimeInstalling,
        modelCatalog: any ModelCatalogSearching,
        initialState: PersistedControlPlaneState
    ) {
        self.hardware = hardware
        self.persistence = persistence
        self.logger = logger
        self.secrets = secrets
        self.adaptersByID = adaptersByID
        self.backends = backends
        self.benchmarker = benchmarker
        self.inspector = inspector
        self.scheduler = scheduler
        self.baseURL = baseURL
        self.runtimeInstaller = runtimeInstaller
        self.modelCatalog = modelCatalog
        self.models = Dictionary(uniqueKeysWithValues: initialState.models.map { ($0.id, $0) })
        self.profiles = Dictionary(uniqueKeysWithValues: initialState.profiles.map { ($0.id, $0) })
        self.instances = [:]
        self.managedEngines = [:]
        self.benchmarks = Dictionary(uniqueKeysWithValues: initialState.benchmarks.map { ($0.id, $0) })
        self.conversations = Dictionary(uniqueKeysWithValues: initialState.conversations.map { ($0.id, $0) })
        self.installingBackends = []
    }

    public static func bootstrap(
        hardware: HardwareSnapshot,
        persistence: PersistenceBootstrap,
        logger: AppLogger,
        secrets: DeveloperAPISecrets,
        runtimeCatalog: RuntimeCatalog,
        baseURL: String,
        modelCatalog: any ModelCatalogSearching = HuggingFaceModelCatalog()
    ) async throws -> ControlPlaneService {
        try await bootstrap(
            hardware: hardware,
            persistence: persistence,
            logger: logger,
            secrets: secrets,
            runtimeCatalog: runtimeCatalog,
            baseURL: baseURL,
            runtimeInstaller: RuntimeInstaller(paths: persistence.paths, logger: logger),
            modelCatalog: modelCatalog
        )
    }

    public static func bootstrap(
        hardware: HardwareSnapshot,
        persistence: PersistenceBootstrap,
        logger: AppLogger,
        secrets: DeveloperAPISecrets,
        runtimeCatalog: RuntimeCatalog,
        baseURL: String,
        runtimeInstaller: any BackendRuntimeInstalling,
        modelCatalog: any ModelCatalogSearching = HuggingFaceModelCatalog()
    ) async throws -> ControlPlaneService {
        let detections = await runtimeCatalog.adapters.asyncMap { adapter in
            await adapter.detect(hardware: hardware)
        }
        let initialState = (try? persistence.database.decodableSetting(PersistedControlPlaneState.self, for: "control_plane_state")) ?? PersistedControlPlaneState()
        let service = ControlPlaneService(
            hardware: hardware,
            persistence: persistence,
            logger: logger,
            secrets: secrets,
            adaptersByID: Dictionary(uniqueKeysWithValues: runtimeCatalog.adapters.map { ($0.id, $0) }),
            backends: detections,
            benchmarker: Benchmarker(),
            inspector: ModelInspector(),
            scheduler: Scheduler(),
            baseURL: baseURL,
            runtimeInstaller: runtimeInstaller,
            modelCatalog: modelCatalog,
            initialState: initialState
        )
        await persistence.persistBootstrapMetadata(hardware: hardware, logger: logger)
        await logger.log(level: "info", category: "control-plane", message: "Control plane bootstrapped.", metadata: [
            "baseURL": baseURL,
            "backendCount": "\(detections.count)"
        ])
        return service
    }

    public func developerAPIStatus() -> DeveloperAPIStatus {
        DeveloperAPIStatus(baseURL: baseURL, requiresAPIKey: false, currentKeyPreview: secrets.preview)
    }

    public func health() -> AppHealth {
        AppHealth(
            status: "ok",
            uptimeSeconds: Int(Date().timeIntervalSince(startedAt)),
            activeEngineCount: instances.values.filter { $0.status == .ready || $0.status == .busy }.count,
            readyModelCount: models.values.filter { $0.status == .ready || $0.status == .warmable }.count
        )
    }

    public func overview() async -> AppOverview {
        AppOverview(
            health: health(),
            hardware: hardware,
            backends: backends,
            models: models.values.sorted { $0.ref.displayName < $1.ref.displayName },
            profiles: profiles.values.sorted { $0.name < $1.name },
            activity: activity(),
            benchmarks: benchmarks.values.sorted { $0.totalLatencyMs < $1.totalLatencyMs },
            logs: await logger.all(),
            conversations: conversations.values.sorted { $0.title < $1.title },
            developerAPI: developerAPIStatus()
        )
    }

    public func handle(request: HTTPRequest) async -> HTTPResponse {
        do {
            switch (request.method, request.path) {
            case ("GET", "/app/v1/health"):
                await refreshBackends()
                return try json(health())
            case ("GET", "/app/v1/hardware"):
                return try json(hardware)
            case ("GET", "/app/v1/backends"):
                await refreshBackends()
                return try json(backends)
            case ("GET", "/app/v1/models"):
                return try json(models.values.sorted { $0.ref.displayName < $1.ref.displayName })
            case ("GET", "/app/v1/models/search"):
                let response = try await searchModelCatalog(
                    query: request.query["q"] ?? "",
                    limit: request.query["limit"].flatMap(Int.init) ?? 12
                )
                return try json(response)
            case ("GET", "/app/v1/models/search/card"):
                let card = try await fetchModelCard(id: request.query["id"] ?? "")
                return try json(card)
            case ("GET", "/app/v1/profiles"):
                return try json(profiles.values.sorted { $0.name < $1.name })
            case ("GET", "/app/v1/activity"):
                return try json(activity())
            case ("GET", "/app/v1/logs"):
                return try json(await logger.all())
            case ("GET", "/app/v1/conversations"):
                return try json(conversations.values.sorted { $0.title < $1.title })
            case ("GET", "/app/v1/overview"):
                await refreshBackends()
                return try json(await overview())
            case ("GET", "/v1/models"):
                try requireAuthorized(request)
                return try json(OpenAIModelList(data: models.values.map { OpenAIModelSummary(id: $0.id) }.sorted { $0.id < $1.id }))
            case ("GET", "/metrics"):
                let body = await metricsText()
                return .text(body: body)
            default:
                break
            }

            if request.method == "POST", request.path == "/app/v1/models/import" {
                let payload = try decode(ImportModelRequest.self, from: request.body)
                let record = try await importModel(payload)
                return try json(record, statusCode: 201)
            }
            if request.method == "POST", request.path == "/app/v1/engines/launch" {
                let payload = try decode(LaunchSpec.self, from: request.body)
                let instance = try await launch(payload)
                return try json(instance, statusCode: 201)
            }
            if request.method == "POST", request.path == "/app/v1/benchmarks/run" {
                let payload = try decode(BenchmarkRequest.self, from: request.body)
                let benchmark = try await runBenchmark(payload)
                return try json(benchmark, statusCode: 201)
            }
            if request.method == "POST", request.path == "/app/v1/profiles" {
                let payload = try decode(CreateProfileRequest.self, from: request.body)
                let profile = try createProfile(payload)
                return try json(profile, statusCode: 201)
            }
            if request.method == "POST", request.path == "/app/v1/conversations" {
                let payload = try decode(CreateConversationRequest.self, from: request.body)
                let conversation = createConversation(payload)
                return try json(conversation, statusCode: 201)
            }
            if request.method == "POST", request.path == "/v1/chat/completions" {
                try requireAuthorized(request)
                return try await proxyChatCompletion(rawBody: request.body)
            }
            if request.method == "POST", request.path == "/v1/embeddings" {
                try requireAuthorized(request)
                return try await proxyEmbeddings(rawBody: request.body)
            }
            if request.method == "POST", request.path == "/v1/responses" {
                try requireAuthorized(request)
                return try await proxyResponses(rawBody: request.body)
            }

            let components = request.path.split(separator: "/").map(String.init)
            if request.method == "POST", components.count == 5, components[0] == "app", components[1] == "v1", components[2] == "models", components[4] == "inspect" {
                let model = try await inspectModel(id: components[3])
                return try json(model)
            }
            if request.method == "POST", components.count == 5, components[0] == "app", components[1] == "v1", components[2] == "backends", components[4] == "install" {
                let backend = try await installBackend(id: components[3])
                return try json(backend, statusCode: 201)
            }
            if request.method == "POST", components.count == 5, components[0] == "app", components[1] == "v1", components[2] == "models", components[4] == "validate" {
                let report = try await validateModel(id: components[3], preferredBackendId: request.query["backendId"])
                return try json(report)
            }
            if request.method == "POST", components.count == 5, components[0] == "app", components[1] == "v1", components[2] == "models", components[4] == "warmup" {
                let instance = try await warmupModel(id: components[3])
                return try json(instance)
            }
            if request.method == "PATCH", components.count == 4, components[0] == "app", components[1] == "v1", components[2] == "profiles" {
                let payload = try decode(UpdateProfileRequest.self, from: request.body)
                let profile = try updateProfile(id: components[3], payload: payload)
                return try json(profile)
            }
            if request.method == "POST", components.count == 5, components[0] == "app", components[1] == "v1", components[2] == "engines", components[4] == "stop" {
                let instance = try await stopEngine(id: components[3])
                return try json(instance)
            }
            if request.method == "POST", components.count == 5, components[0] == "app", components[1] == "v1", components[2] == "engines", components[4] == "restart" {
                let instance = try await restartEngine(id: components[3])
                return try json(instance)
            }
            if request.method == "GET", components.count == 4, components[0] == "app", components[1] == "v1", components[2] == "benchmarks" {
                let benchmark = try benchmark(id: components[3])
                return try json(benchmark)
            }
            if request.method == "POST", components.count == 5, components[0] == "app", components[1] == "v1", components[2] == "conversations", components[4] == "messages" {
                let payload = try decode(AddConversationMessageRequest.self, from: request.body)
                let conversation = try await addMessage(conversationID: components[3], payload: payload)
                return try json(conversation)
            }

            return errorResponse(APIErrorEnvelope(code: "NOT_FOUND", message: "Route not found.", details: ["path": request.path]), statusCode: 404)
        } catch let error as APIErrorEnvelope {
            let status = error.error.code == "API_KEY_REQUIRED" ? 401 : 422
            return errorResponse(error, statusCode: status)
        } catch {
            await logger.log(level: "error", category: "http", message: "Request failed.", metadata: [
                "path": request.path,
                "error": error.localizedDescription
            ])
            return errorResponse(APIErrorEnvelope(code: "INTERNAL", message: error.localizedDescription, retryable: false), statusCode: 500)
        }
    }

    public func importModel(_ request: ImportModelRequest) async throws -> ModelRecord {
        let id = Identifiers.model(from: request.sourceRef)
        if models[id] != nil {
            throw APIErrorEnvelope(code: "MODEL_IMPORT_FAILED", message: "A model with this source already exists.", details: ["modelId": id])
        }

        let baseName = request.displayName ?? request.sourceRef.split(separator: "/").last.map(String.init) ?? "Imported Model"
        let seed = ModelRecord(
            ref: ModelRef(
                id: id,
                displayName: baseName,
                sourceKind: request.sourceKind,
                sourceRef: request.sourceRef,
                modality: .text
            )
        )
        let inspected = inspector.inspect(seed)
        models[id] = inspected
        seedProfilesIfNeeded(for: inspected)
        persistStateSnapshot()
        await logger.log(level: "info", category: "models", message: "Imported model.", metadata: [
            "modelId": id,
            "source": request.sourceRef
        ])
        return inspected
    }

    public func searchModelCatalog(query: String, limit: Int = 12) async throws -> ModelSearchResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return ModelSearchResponse(query: "", results: [])
        }

        let sanitizedLimit = min(max(limit, 1), 40)
        do {
            let results = try await modelCatalog.searchModels(query: trimmedQuery, limit: sanitizedLimit)
            await logger.log(level: "info", category: "models.search", message: "Searched Hugging Face model catalog.", metadata: [
                "query": trimmedQuery,
                "resultCount": "\(results.count)"
            ])
            return ModelSearchResponse(query: trimmedQuery, results: results)
        } catch {
            await logger.log(level: "error", category: "models.search", message: "Hugging Face model search failed.", metadata: [
                "query": trimmedQuery,
                "error": error.localizedDescription
            ])
            throw APIErrorEnvelope(
                code: "MODEL_SEARCH_FAILED",
                message: "Hugging Face search failed: \(error.localizedDescription)",
                details: ["query": trimmedQuery]
            )
        }
    }

    public func fetchModelCard(id: String) async throws -> ModelCatalogCard {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedID.isEmpty == false else {
            throw APIErrorEnvelope(code: "MODEL_CARD_FAILED", message: "Model id is required.", details: [:])
        }

        do {
            let card = try await modelCatalog.fetchModelCard(id: trimmedID)
            await logger.log(level: "info", category: "models.card", message: "Loaded Hugging Face model card.", metadata: [
                "modelId": trimmedID
            ])
            return card
        } catch {
            await logger.log(level: "error", category: "models.card", message: "Hugging Face model card lookup failed.", metadata: [
                "modelId": trimmedID,
                "error": error.localizedDescription
            ])
            throw APIErrorEnvelope(
                code: "MODEL_CARD_FAILED",
                message: "Hugging Face model card fetch failed: \(error.localizedDescription)",
                details: ["modelId": trimmedID]
            )
        }
    }

    public func inspectModel(id: String) async throws -> ModelRecord {
        guard let existing = models[id] else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Model not found.", details: ["modelId": id])
        }
        let inspected = inspector.inspect(existing)
        models[id] = inspected
        persistStateSnapshot()
        return inspected
    }

    public func validateModel(id: String, preferredBackendId: String?) async throws -> ValidationReport {
        await refreshBackends()
        guard let model = models[id] else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Model not found.", details: ["modelId": id])
        }
        let spec = LaunchSpec(
            modelId: id,
            preferredBackendId: preferredBackendId,
            requestMode: model.capabilities.supportsEmbeddings ? .embeddings : .chat,
            maxContext: model.defaultContextWindow ?? 8_192,
            maxOutputTokens: 512,
            enableTools: model.capabilities.supportsTools
        )
        try await ensureSchedulableBackendAvailable(
            model: model,
            spec: spec,
            action: "validate",
            preferredBackendID: preferredBackendId
        )
        guard let decision = schedulerDecision(for: model, spec: spec) else {
            throw APIErrorEnvelope(code: "GPU_ONLY_NO_SUPPORTED_BACKEND", message: "No compatible backend is currently available.", details: ["modelId": id])
        }
        guard let adapter = adaptersByID[decision.backendId] else {
            throw APIErrorEnvelope(code: "BACKEND_NOT_INSTALLED", message: "Selected backend is unavailable.", details: ["backendId": decision.backendId])
        }
        let report = await adapter.validate(model: model, spec: spec, hardware: hardware)
        var updated = model
        updated.lastValidation = report
        updated.status = report.riskTier == .danger ? .warmable : .ready
        models[id] = updated
        persistStateSnapshot()
        return report
    }

    public func warmupModel(id: String) async throws -> EngineInstanceRef {
        let spec = LaunchSpec(modelId: id, requestMode: .chat, maxContext: 8_192, maxOutputTokens: 512)
        return try await launch(spec)
    }

    public func createProfile(_ request: CreateProfileRequest) throws -> LaunchProfile {
        guard models[request.modelId] != nil else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Model not found.", details: ["modelId": request.modelId])
        }
        let profile = LaunchProfile(
            id: Identifiers.prefixed("profile"),
            modelId: request.modelId,
            name: request.name,
            preferredEngine: request.preferredEngine,
            contextWindow: request.contextWindow,
            maxOutputTokens: request.maxOutputTokens,
            enableTools: request.enableTools,
            enableReasoning: request.enableReasoning,
            environment: defaultEnvironment(for: request.preferredEngine, contextWindow: request.contextWindow, enableTools: request.enableTools)
        )
        profiles[profile.id] = profile
        persistStateSnapshot()
        return profile
    }

    public func updateProfile(id: String, payload: UpdateProfileRequest) throws -> LaunchProfile {
        guard var profile = profiles[id] else {
            throw APIErrorEnvelope(code: "NOT_FOUND", message: "Profile not found.", details: ["profileId": id])
        }
        if let name = payload.name { profile.name = name }
        if let contextWindow = payload.contextWindow { profile.contextWindow = contextWindow }
        if let maxOutputTokens = payload.maxOutputTokens { profile.maxOutputTokens = maxOutputTokens }
        if let enableTools = payload.enableTools { profile.enableTools = enableTools }
        if let enableReasoning = payload.enableReasoning { profile.enableReasoning = enableReasoning }
        profiles[id] = profile
        persistStateSnapshot()
        return profile
    }

    public func launch(_ spec: LaunchSpec) async throws -> EngineInstanceRef {
        await refreshBackends()
        guard let model = models[spec.modelId] else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Model not found.", details: ["modelId": spec.modelId])
        }
        let profile = spec.profileId.flatMap { profiles[$0] }
        if let existing = reusableInstance(for: spec) {
            return existing
        }
        try await ensureSchedulableBackendAvailable(
            model: model,
            spec: spec,
            action: "launch",
            preferredBackendID: spec.preferredBackendId
        )
        guard let decision = schedulerDecision(for: model, spec: spec) else {
            throw APIErrorEnvelope(code: "INSUFFICIENT_UNIFIED_MEMORY", message: "No backend satisfies the current memory policy.", details: ["modelId": spec.modelId])
        }
        guard let adapter = adaptersByID[decision.backendId] else {
            throw APIErrorEnvelope(code: "BACKEND_NOT_INSTALLED", message: "Selected backend is unavailable.", details: ["backendId": decision.backendId])
        }
        guard let installation = adapter.detectInstallation() else {
            throw APIErrorEnvelope(
                code: "BACKEND_NOT_INSTALLED",
                message: "The selected backend is not installed on this Mac.",
                details: ["backendId": decision.backendId]
            )
        }

        let port = try PortAllocator.nextAvailablePort()
        let internalAPIKey: String? = adapter.id == BackendKind.vllmMetal.rawValue ? secrets.plaintextKey : nil
        let plan = try adapter.launchPlan(
            model: model,
            spec: spec,
            profile: profile,
            installation: installation,
            port: port,
            publicModelName: model.id,
            apiKey: internalAPIKey
        )
        let managed = try ProcessSupervisor.launch(
            plan: plan,
            spec: spec,
            host: "127.0.0.1",
            port: port,
            modelId: model.id,
            profileId: spec.profileId,
            internalAPIKey: internalAPIKey,
            logger: logger
        )
        do {
            try await ProcessSupervisor.waitUntilReady(managed)
        } catch {
            await ProcessSupervisor.stop(managed)
            throw error
        }

        let instance = managed.instance
        managedEngines[instance.id] = managed
        instances[instance.id] = instance
        await logger.log(level: "info", category: "engines", message: "Launched engine.", metadata: [
            "instanceId": instance.id,
            "backendId": instance.backendId,
            "modelId": instance.modelId
        ])
        return instance
    }

    public func stopEngine(id: String) async throws -> EngineInstanceRef {
        guard let managed = managedEngines[id] else {
            throw APIErrorEnvelope(code: "NOT_FOUND", message: "Engine instance not found.", details: ["instanceId": id])
        }
        await ProcessSupervisor.stop(managed)
        instances[id] = managed.instance
        managedEngines[id] = nil
        return managed.instance
    }

    public func restartEngine(id: String) async throws -> EngineInstanceRef {
        guard let managed = managedEngines[id] else {
            throw APIErrorEnvelope(code: "NOT_FOUND", message: "Engine instance not found.", details: ["instanceId": id])
        }
        let spec = managed.launchSpec
        _ = try await stopEngine(id: id)
        return try await launch(spec)
    }

    public func activity() -> ActivitySnapshot {
        let currentInstances = Array(managedEngines.values).map { managed in
            let status: EngineStatus = managed.isRunning ? managed.instance.status : .stopped
            return EngineInstanceRef(
                id: managed.instance.id,
                backendId: managed.instance.backendId,
                modelId: managed.instance.modelId,
                host: managed.instance.host,
                port: managed.instance.port,
                status: status,
                warnings: managed.instance.warnings,
                pid: managed.instance.pid,
                launchedAt: managed.instance.launchedAt,
                profileId: managed.instance.profileId,
                engineModelName: managed.instance.engineModelName
            )
        }
        let instancesActivity = currentInstances.map { instance in
            InstanceActivity(
                instanceId: instance.id,
                modelId: instance.modelId,
                backendId: instance.backendId,
                queueDepth: instance.status == .busy ? 1 : 0,
                ttftMsP50: 420,
                outputTokPerSecP50: instance.backendId == BackendKind.vllmMetal.rawValue ? 41.0 : 29.0,
                peakMemoryBytes: models[instance.modelId]?.lastValidation?.measured.peakMemoryBytes,
                isWarm: instance.status == .ready
            )
        }.sorted { $0.modelId < $1.modelId }

        let estimatedUsed = instancesActivity.compactMap(\.peakMemoryBytes).reduce(Int64(0), +)
        let estimatedFree = max(hardware.totalMemoryBytes - estimatedUsed, 0)
        let pressure: MemoryPressureLevel
        let ratio = Double(estimatedFree) / Double(max(hardware.totalMemoryBytes, 1))
        switch ratio {
        case ..<0.18:
            pressure = .critical
        case ..<0.35:
            pressure = .warning
        default:
            pressure = .normal
        }

        return ActivitySnapshot(
            timestamp: Time.nowISO8601(),
            totalUnifiedMemoryBytes: hardware.totalMemoryBytes,
            estimatedFreeBytes: estimatedFree,
            memoryPressure: pressure,
            activeInstances: instancesActivity
        )
    }

    public func runBenchmark(_ request: BenchmarkRequest) async throws -> BenchmarkRecord {
        guard let model = models[request.modelId] else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Model not found.", details: ["modelId": request.modelId])
        }
        let profile = benchmarkProfile(for: request)
        let backendId = profile?.preferredEngine.rawValue ?? BackendKind.vllmMetal.rawValue
        let record = benchmarker.run(
            request: request,
            model: model,
            profile: profile,
            backendId: backendId,
            hardware: hardware
        )
        benchmarks[record.id] = record
        persistStateSnapshot()
        return record
    }

    private func benchmarkProfile(for request: BenchmarkRequest) -> LaunchProfile? {
        if let profileID = request.profileId {
            return profiles[profileID]
        }
        return profiles.values.first {
            $0.modelId == request.modelId && $0.name == request.scenario.rawValue
        }
    }

    public func benchmark(id: String) throws -> BenchmarkRecord {
        guard let benchmark = benchmarks[id] else {
            throw APIErrorEnvelope(code: "NOT_FOUND", message: "Benchmark not found.", details: ["benchmarkId": id])
        }
        return benchmark
    }

    public func installBackend(id: String) async throws -> BackendDetection {
        guard adaptersByID[id] != nil else {
            throw APIErrorEnvelope(code: "BACKEND_NOT_SUPPORTED", message: "Unknown backend.", details: ["backendId": id])
        }
        guard installingBackends.contains(id) == false else {
            throw APIErrorEnvelope(code: "BACKEND_INSTALL_IN_PROGRESS", message: "This backend is already being installed.", details: ["backendId": id])
        }

        installingBackends.insert(id)
        defer { installingBackends.remove(id) }

        let manifest = try await runtimeInstaller.install(backendID: id)
        await logger.log(level: "info", category: "runtime.install", message: "Installed backend runtime.", metadata: [
            "backendId": id,
            "version": manifest.version,
            "pythonVersion": manifest.pythonVersion
        ])
        await refreshBackends()
        guard let detection = backends.first(where: { $0.id == id }) else {
            throw APIErrorEnvelope(code: "BACKEND_INSTALL_FAILED", message: "Backend installed but could not be rediscovered.", details: ["backendId": id])
        }
        return detection
    }

    public func createConversation(_ request: CreateConversationRequest) -> ConversationRecord {
        let conversation = ConversationRecord(
            id: Identifiers.prefixed("conv"),
            title: request.title,
            modelId: request.modelId,
            launchProfileId: request.launchProfileId
        )
        conversations[conversation.id] = conversation
        persistStateSnapshot()
        return conversation
    }

    public func addMessage(conversationID: String, payload: AddConversationMessageRequest) async throws -> ConversationRecord {
        guard var conversation = conversations[conversationID] else {
            throw APIErrorEnvelope(code: "NOT_FOUND", message: "Conversation not found.", details: ["conversationId": conversationID])
        }
        guard let modelId = conversation.modelId else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Conversation is not bound to a model.", details: ["conversationId": conversationID])
        }
        let userMessage = ConversationMessage(id: Identifiers.prefixed("msg"), role: payload.role, content: payload.content, createdAt: Time.nowISO8601())
        conversation.messages.append(userMessage)
        let promptMessages = conversation.messages.map { ChatMessagePayload(role: $0.role, content: $0.content) }
        let completion = try await chatCompletion(
            OpenAIChatCompletionRequest(
                model: modelId,
                messages: promptMessages,
                maxTokens: 512
            )
        )
        let assistantText = completion.choices.first?.message.content ?? ""
        let assistant = ConversationMessage(id: Identifiers.prefixed("msg"), role: "assistant", content: assistantText, createdAt: Time.nowISO8601())
        conversation.messages.append(assistant)
        conversations[conversationID] = conversation
        persistStateSnapshot()
        return conversation
    }

    public func chatCompletion(_ request: OpenAIChatCompletionRequest) async throws -> OpenAIChatCompletionResponse {
        guard models[request.model] != nil else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Model not found.", details: ["modelId": request.model])
        }
        let engine = try await ensureEngine(for: request.model, mode: .chat)
        let body = try Self.encoder.encode(
            OpenAIChatCompletionRequest(
                model: engine.plan.engineModelName,
                messages: request.messages,
                stream: request.stream,
                maxTokens: request.maxTokens,
                temperature: request.temperature
            )
        )
        let (data, _) = try await EngineHTTPClient.request(engine: engine, path: "/v1/chat/completions", method: "POST", body: body)
        return try Self.decoder.decode(OpenAIChatCompletionResponse.self, from: data)
    }

    public func embeddings(_ request: EmbeddingsRequest) async throws -> EmbeddingsResponse {
        guard models[request.model] != nil else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Model not found.", details: ["modelId": request.model])
        }
        let engine = try await ensureEngine(for: request.model, mode: .embeddings, preferredBackendId: BackendKind.vllmMetal.rawValue)
        guard engine.plan.supportsDirectEmbeddings else {
            throw APIErrorEnvelope(
                code: "MODEL_UNSUPPORTED",
                message: "No active backend for this model supports embeddings.",
                details: ["modelId": request.model]
            )
        }
        let body = try Self.encoder.encode(
            EmbeddingsRequest(model: engine.plan.engineModelName, input: request.input)
        )
        let (data, _) = try await EngineHTTPClient.request(engine: engine, path: "/v1/embeddings", method: "POST", body: body)
        return try Self.decoder.decode(EmbeddingsResponse.self, from: data)
    }

    private func requireAuthorized(_ request: HTTPRequest) throws {
        _ = request
    }

    private func seedProfilesIfNeeded(for model: ModelRecord) {
        let existing = profiles.values.filter { $0.modelId == model.id }
        guard existing.isEmpty else { return }

        let templates: [LaunchProfile] = [
            LaunchProfile(
                id: Identifiers.prefixed("profile"),
                modelId: model.id,
                name: "chat-latency",
                preferredEngine: .vllmMetal,
                contextWindow: min(model.defaultContextWindow ?? 8_192, 8_192),
                maxOutputTokens: 1_024,
                environment: defaultEnvironment(for: .vllmMetal, contextWindow: 8_192, enableTools: false)
            ),
            LaunchProfile(
                id: Identifiers.prefixed("profile"),
                modelId: model.id,
                name: "chat-tools",
                preferredEngine: .vllmMetal,
                contextWindow: min(model.defaultContextWindow ?? 8_192, 8_192),
                maxOutputTokens: 1_024,
                enableTools: true,
                environment: defaultEnvironment(for: .vllmMetal, contextWindow: 8_192, enableTools: true)
            ),
            LaunchProfile(
                id: Identifiers.prefixed("profile"),
                modelId: model.id,
                name: "mlx-fallback-chat",
                preferredEngine: .mlxNative,
                contextWindow: min(model.defaultContextWindow ?? 4_096, 4_096),
                maxOutputTokens: 768,
                environment: defaultEnvironment(for: .mlxNative, contextWindow: 4_096, enableTools: false)
            )
        ]
        for profile in templates {
            profiles[profile.id] = profile
        }
    }

    private func defaultEnvironment(for backend: BackendKind, contextWindow: Int, enableTools: Bool) -> [String: String] {
        switch backend {
        case .vllmMetal:
            return [
                "VLLM_PLUGINS": "metal",
                "VLLM_METAL_MEMORY_FRACTION": contextWindow > 8_192 ? "0.75" : "auto",
                "VLLM_MLX_DEVICE": "gpu",
                "VLLM_METAL_PREFIX_CACHE": "1",
                "VLLM_METAL_USE_PAGED_ATTENTION": contextWindow > 8_192 ? "1" : "0",
                "SWIFTLM_TOOLS_ENABLED": enableTools ? "1" : "0"
            ]
        case .mlxNative:
            return [
                "SWIFTLM_PUBLIC_HTTP_DISABLED": "1",
                "MLX_DEVICE": "gpu"
            ]
        case .mlxSwift:
            return [:]
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.isEmpty == false else {
            throw APIErrorEnvelope(code: "BAD_REQUEST", message: "Missing request body.")
        }
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw APIErrorEnvelope(code: "BAD_REQUEST", message: "Failed to decode request body.", details: ["type": String(describing: type)])
        }
    }

    private func json<T: Encodable>(_ value: T, statusCode: Int = 200) throws -> HTTPResponse {
        let data = try Self.encoder.encode(value)
        return HTTPResponse.json(statusCode: statusCode, body: data)
    }

    private func errorResponse(_ error: APIErrorEnvelope, statusCode: Int) -> HTTPResponse {
        let data = (try? Self.encoder.encode(error)) ?? Data("{\"error\":{\"code\":\"INTERNAL\",\"message\":\"Encoding error\",\"retryable\":false,\"details\":{}}}".utf8)
        return HTTPResponse.json(statusCode: statusCode, body: data)
    }

    private func refreshBackends() async {
        var refreshed: [BackendDetection] = []
        for adapter in Array(adaptersByID.values).sorted(by: { $0.id < $1.id }) {
            refreshed.append(await adapter.detect(hardware: hardware))
        }
        backends = refreshed
    }

    private func schedulerDecision(for model: ModelRecord, spec: LaunchSpec) -> SchedulerDecision? {
        scheduler.chooseBackend(
            model: model,
            spec: spec,
            hardware: hardware,
            backends: backends,
            instances: Array(instances.values)
        )
    }

    private func ensureSchedulableBackendAvailable(
        model: ModelRecord,
        spec: LaunchSpec,
        action: String,
        preferredBackendID: String?
    ) async throws {
        if schedulerDecision(for: model, spec: spec) != nil {
            return
        }

        let candidateBackendIDs = autoProvisionCandidateBackendIDs(
            preferredBackendID: preferredBackendID,
            mode: spec.requestMode
        )
        var failures: [(backendID: String, message: String)] = []

        for backendID in candidateBackendIDs {
            guard let detection = backends.first(where: { $0.id == backendID }) else {
                continue
            }
            guard detection.status != .disabled else {
                continue
            }
            guard detection.status != .installed else {
                if schedulerDecision(for: model, spec: spec) != nil {
                    return
                }
                continue
            }

            do {
                try await installManagedBackendIfNeeded(id: backendID, modelId: model.id, action: action)
            } catch let error as APIErrorEnvelope {
                failures.append((backendID, error.error.message))
                continue
            } catch {
                failures.append((backendID, error.localizedDescription))
                continue
            }

            if schedulerDecision(for: model, spec: spec) != nil {
                return
            }
        }

        if let failure = autoProvisionFailure(
            failures: failures,
            modelId: model.id,
            action: action
        ) {
            throw failure
        }

        guard backends.contains(where: { $0.status == .installed }) else {
            await logger.log(level: "warning", category: "control-plane", message: "Model request requires an installed backend runtime.", metadata: [
                "action": action,
                "modelId": model.id
            ])
            throw APIErrorEnvelope(
                code: "BACKEND_RUNTIME_REQUIRED",
                message: "No backend runtime is installed. SwiftLM could not auto-provision MLX Native or vLLM Metal for this request.",
                details: ["modelId": model.id, "action": action]
            )
        }
    }

    private func autoProvisionCandidateBackendIDs(
        preferredBackendID: String?,
        mode: RequestMode
    ) -> [String] {
        var backendIDs: [String] = []
        if let preferredBackendID, preferredBackendID.isEmpty == false {
            backendIDs.append(preferredBackendID)
        }
        switch mode {
        case .embeddings:
            backendIDs.append(BackendKind.vllmMetal.rawValue)
        case .chat, .responses, .benchmark:
            backendIDs.append(contentsOf: [
                BackendKind.mlxNative.rawValue,
                BackendKind.vllmMetal.rawValue
            ])
        }

        var seen: Set<String> = []
        return backendIDs.filter { seen.insert($0).inserted }
    }

    private func installManagedBackendIfNeeded(
        id: String,
        modelId: String,
        action: String
    ) async throws {
        if backends.contains(where: { $0.id == id && $0.status == .installed }) {
            return
        }
        if installingBackends.contains(id) {
            await logger.log(level: "info", category: "runtime.auto-install", message: "Waiting for in-flight backend installation.", metadata: [
                "backendId": id,
                "modelId": modelId,
                "action": action
            ])
            guard await waitForInstalledBackend(id: id) else {
                throw APIErrorEnvelope(
                    code: "BACKEND_INSTALL_FAILED",
                    message: "Backend installation did not finish successfully.",
                    details: ["backendId": id, "modelId": modelId, "action": action]
                )
            }
            return
        }

        await logger.log(level: "info", category: "runtime.auto-install", message: "Attempting managed backend installation for request.", metadata: [
            "backendId": id,
            "modelId": modelId,
            "action": action
        ])
        _ = try await installBackend(id: id)
        await logger.log(level: "info", category: "runtime.auto-install", message: "Managed backend installation completed for request.", metadata: [
            "backendId": id,
            "modelId": modelId,
            "action": action
        ])
    }

    private func waitForInstalledBackend(id: String, timeoutSeconds: TimeInterval = 120) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            await refreshBackends()
            if backends.contains(where: { $0.id == id && $0.status == .installed }) {
                return true
            }
            if installingBackends.contains(id) == false {
                return false
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return false
    }

    private func autoProvisionFailure(
        failures: [(backendID: String, message: String)],
        modelId: String,
        action: String
    ) -> APIErrorEnvelope? {
        guard failures.isEmpty == false else {
            return nil
        }
        let summary = failures.map { failure in
            "\(backendDisplayName(failure.backendID)): \(failure.message)"
        }.joined(separator: " ")
        return APIErrorEnvelope(
            code: "BACKEND_AUTO_PROVISION_FAILED",
            message: "SwiftLM could not automatically provision a backend runtime for this request. \(summary)",
            details: [
                "action": action,
                "attemptedBackends": failures.map(\.backendID).joined(separator: ","),
                "modelId": modelId
            ]
        )
    }

    private func backendDisplayName(_ backendID: String) -> String {
        switch backendID {
        case BackendKind.mlxNative.rawValue:
            return "MLX Native"
        case BackendKind.vllmMetal.rawValue:
            return "vLLM Metal"
        case BackendKind.mlxSwift.rawValue:
            return "MLX Swift"
        default:
            return backendID
        }
    }

    private func reusableInstance(for spec: LaunchSpec) -> EngineInstanceRef? {
        managedEngines.values.first(where: { managed in
            managed.instance.modelId == spec.modelId &&
            managed.isRunning &&
            (spec.preferredBackendId == nil || spec.preferredBackendId == managed.instance.backendId)
        })?.instance
    }

    private func ensureEngine(
        for modelId: String,
        mode: RequestMode,
        preferredBackendId: String? = nil
    ) async throws -> ManagedEngine {
        if let existing = managedEngines.values.first(where: { managed in
            managed.instance.modelId == modelId &&
            managed.isRunning &&
            (preferredBackendId == nil || managed.instance.backendId == preferredBackendId)
        }) {
            return existing
        }

        guard let model = models[modelId] else {
            throw APIErrorEnvelope(code: "MODEL_UNSUPPORTED", message: "Model not found.", details: ["modelId": modelId])
        }
        let profile = profiles.values.first { $0.modelId == modelId && (preferredBackendId == nil || $0.preferredEngine.rawValue == preferredBackendId) }
        let spec = LaunchSpec(
            modelId: modelId,
            profileId: profile?.id,
            preferredBackendId: preferredBackendId,
            requestMode: mode,
            maxContext: profile?.contextWindow ?? model.defaultContextWindow ?? 8_192,
            maxOutputTokens: profile?.maxOutputTokens ?? 1_024,
            enableTools: profile?.enableTools ?? false,
            enableReasoning: profile?.enableReasoning ?? false
        )
        let instance = try await launch(spec)
        guard let managed = managedEngines[instance.id] else {
            throw APIErrorEnvelope(code: "ENGINE_CRASHED", message: "Engine launched but was not retained.", details: ["instanceId": instance.id])
        }
        return managed
    }

    private func proxyChatCompletion(rawBody: Data) async throws -> HTTPResponse {
        let payload = try decode(OpenAIChatCompletionRequest.self, from: rawBody)
        let engine = try await ensureEngine(for: payload.model, mode: .chat)
        let rewrittenBody = try rewriteModelID(in: rawBody, to: engine.plan.engineModelName)
        let (data, _) = try await EngineHTTPClient.request(engine: engine, path: "/v1/chat/completions", method: "POST", body: rewrittenBody)
        return .json(body: data)
    }

    private func proxyEmbeddings(rawBody: Data) async throws -> HTTPResponse {
        let payload = try decode(EmbeddingsRequest.self, from: rawBody)
        let engine = try await ensureEngine(for: payload.model, mode: .embeddings, preferredBackendId: BackendKind.vllmMetal.rawValue)
        guard engine.plan.supportsDirectEmbeddings else {
            throw APIErrorEnvelope(
                code: "MODEL_UNSUPPORTED",
                message: "No backend currently available for this model supports embeddings.",
                details: ["modelId": payload.model]
            )
        }
        let rewrittenBody = try rewriteModelID(in: rawBody, to: engine.plan.engineModelName)
        let (data, _) = try await EngineHTTPClient.request(engine: engine, path: "/v1/embeddings", method: "POST", body: rewrittenBody)
        return .json(body: data)
    }

    private func proxyResponses(rawBody: Data) async throws -> HTTPResponse {
        let payload = try parseResponsesRequest(from: rawBody)
        let engine = try await ensureEngine(for: payload.model, mode: .responses, preferredBackendId: BackendKind.vllmMetal.rawValue)
        if engine.plan.supportsDirectResponses {
            let rewrittenBody = try rewriteModelID(in: rawBody, to: engine.plan.engineModelName)
            let (data, _) = try await EngineHTTPClient.request(engine: engine, path: "/v1/responses", method: "POST", body: rewrittenBody)
            return .json(body: data)
        }

        let chatRequest = OpenAIChatCompletionRequest(
            model: payload.model,
            messages: [ChatMessagePayload(role: "user", content: payload.promptText)],
            maxTokens: payload.maxOutputTokens,
            temperature: payload.temperature
        )
        let completion = try await chatCompletion(chatRequest)
        let content = completion.choices.first?.message.content ?? ""
        let response = ResponseEnvelope(
            id: Identifiers.prefixed("resp"),
            model: payload.model,
            outputText: content,
            usage: completion.usage
        )
        let data = try Self.encoder.encode(response)
        return .json(body: data)
    }

    private func rewriteModelID(in body: Data, to engineModelName: String) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return body
        }
        root["model"] = engineModelName
        return try JSONSerialization.data(withJSONObject: root, options: [])
    }

    private func parseResponsesRequest(from data: Data) throws -> ParsedResponsesRequest {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = root["model"] as? String
        else {
            throw APIErrorEnvelope(code: "BAD_REQUEST", message: "Responses request must include a model.")
        }

        if let input = root["input"] as? String {
            return ParsedResponsesRequest(
                model: model,
                promptText: input,
                maxOutputTokens: root["max_output_tokens"] as? Int,
                temperature: root["temperature"] as? Double
            )
        }

        if let inputItems = root["input"] as? [[String: Any]] {
            let prompt = inputItems.flatMap { item -> [String] in
                if let content = item["content"] as? [[String: Any]] {
                    return content.compactMap { $0["text"] as? String }
                }
                if let content = item["content"] as? String {
                    return [content]
                }
                return []
            }.joined(separator: "\n")
            return ParsedResponsesRequest(
                model: model,
                promptText: prompt,
                maxOutputTokens: root["max_output_tokens"] as? Int,
                temperature: root["temperature"] as? Double
            )
        }

        throw APIErrorEnvelope(code: "BAD_REQUEST", message: "Unsupported responses input shape.", details: ["model": model])
    }

    private func metricsText() async -> String {
        var sections = [MetricsSample.prometheus(health: health(), activity: activity(), backends: backends)]
        for engine in managedEngines.values where engine.isRunning {
            guard let metricsPath = engine.plan.metricsPath else { continue }
            if let text = try? await EngineHTTPClient.text(engine: engine, path: metricsPath) {
                sections.append("# Engine \(engine.instance.id)\n\(text)")
            }
        }
        return sections.joined(separator: "\n")
    }

    private func persistStateSnapshot() {
        let snapshot = PersistedControlPlaneState(
            models: models.values.sorted { $0.id < $1.id },
            profiles: profiles.values.sorted { $0.id < $1.id },
            benchmarks: benchmarks.values.sorted { $0.id < $1.id },
            conversations: conversations.values.sorted { $0.id < $1.id }
        )
        do {
            try persistence.database.upsertSetting(key: "control_plane_state", value: snapshot)
        } catch {
            Task {
                await logger.log(level: "error", category: "storage", message: "Failed to persist control-plane state.", metadata: [
                    "error": error.localizedDescription
                ])
            }
        }
    }
}

private struct ResponseEnvelope: Encodable {
    let id: String
    let object: String = "response"
    let model: String
    let output: [ResponseItem]
    let usage: OpenAIUsage

    init(id: String, model: String, outputText: String, usage: OpenAIUsage) {
        self.id = id
        self.model = model
        self.output = [
            ResponseItem(
                id: Identifiers.prefixed("msg"),
                content: [ResponseContent(text: outputText)]
            )
        ]
        self.usage = usage
    }
}

private struct ResponseItem: Encodable {
    let id: String
    let type: String = "message"
    let role: String = "assistant"
    let content: [ResponseContent]
}

private struct ResponseContent: Encodable {
    let type: String = "output_text"
    let text: String
}

private struct ParsedResponsesRequest {
    let model: String
    let promptText: String
    let maxOutputTokens: Int?
    let temperature: Double?
}

private extension Array {
    func asyncMap<T>(_ transform: @escaping (Element) async -> T) async -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(await transform(element))
        }
        return values
    }
}
