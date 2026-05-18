import Foundation

public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case huggingFace = "hf"
    case local
}

public enum ModelModality: String, Codable, CaseIterable, Sendable {
    case text
    case vision
    case embeddings
    case audio
}

public enum ChatTemplateState: String, Codable, CaseIterable, Sendable {
    case present
    case missing
    case custom
    case unknown
}

public enum ModelStatus: String, Codable, CaseIterable, Sendable {
    case discovered
    case downloading
    case downloaded
    case inspecting
    case validating
    case ready
    case warmable
    case failed
    case unsupported
}

public enum RiskTier: String, Codable, CaseIterable, Sendable {
    case safe
    case caution
    case danger
    case unsupported
    case unknown
}

public enum BackendKind: String, Codable, CaseIterable, Sendable {
    case vllmMetal = "vllm-metal"
    case mlxNative = "mlx-native"
    case mlxSwift = "mlx-swift"
}

public enum BackendStatus: String, Codable, CaseIterable, Sendable {
    case installed
    case missing
    case unhealthy
    case disabled
}

public enum RequestMode: String, Codable, CaseIterable, Sendable {
    case chat
    case responses
    case embeddings
    case benchmark
}

public enum BenchmarkScenario: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatLatency = "chat-latency"
    case chatTools = "chat-tools"
    case mlxFallbackChat = "mlx-fallback-chat"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chatLatency:
            return "Chat Latency"
        case .chatTools:
            return "Chat With Tools"
        case .mlxFallbackChat:
            return "MLX Fallback Chat"
        }
    }

    public var subtitle: String {
        switch self {
        case .chatLatency:
            return "vLLM Metal baseline chat latency profile"
        case .chatTools:
            return "vLLM Metal chat profile with tool routing enabled"
        case .mlxFallbackChat:
            return "MLX Native fallback chat profile for constrained setups"
        }
    }
}

public enum MemoryPressureLevel: String, Codable, CaseIterable, Sendable {
    case normal
    case warning
    case critical
}

public enum EngineStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case launching
    case warming
    case ready
    case busy
    case draining
    case stopping
    case stopped
    case unhealthy
    case crashed
    case quarantined
}

public struct ModelRef: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let sourceKind: SourceKind
    public let sourceRef: String
    public let modality: ModelModality
    public let architecture: String?
    public let quantization: String?

    public init(
        id: String,
        displayName: String,
        sourceKind: SourceKind,
        sourceRef: String,
        modality: ModelModality,
        architecture: String? = nil,
        quantization: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceKind = sourceKind
        self.sourceRef = sourceRef
        self.modality = modality
        self.architecture = architecture
        self.quantization = quantization
    }
}

public struct ModelRecord: Codable, Identifiable, Hashable, Sendable {
    public var ref: ModelRef
    public var family: String?
    public var parameterCount: Int?
    public var tokenizerFamily: String?
    public var chatTemplateState: ChatTemplateState
    public var defaultContextWindow: Int?
    public var sizeOnDiskBytes: Int64
    public var primaryArtifactPath: String?
    public var status: ModelStatus
    public var capabilities: ModelCapabilities
    public var lastValidation: ValidationReport?

    public var id: String { ref.id }

    public init(
        ref: ModelRef,
        family: String? = nil,
        parameterCount: Int? = nil,
        tokenizerFamily: String? = nil,
        chatTemplateState: ChatTemplateState = .unknown,
        defaultContextWindow: Int? = nil,
        sizeOnDiskBytes: Int64 = 0,
        primaryArtifactPath: String? = nil,
        status: ModelStatus = .discovered,
        capabilities: ModelCapabilities = .empty,
        lastValidation: ValidationReport? = nil
    ) {
        self.ref = ref
        self.family = family
        self.parameterCount = parameterCount
        self.tokenizerFamily = tokenizerFamily
        self.chatTemplateState = chatTemplateState
        self.defaultContextWindow = defaultContextWindow
        self.sizeOnDiskBytes = sizeOnDiskBytes
        self.primaryArtifactPath = primaryArtifactPath
        self.status = status
        self.capabilities = capabilities
        self.lastValidation = lastValidation
    }
}

public struct ModelCapabilities: Codable, Hashable, Sendable {
    public var supportsVLLMMetal: Bool
    public var supportsMLXNative: Bool
    public var supportsChat: Bool
    public var supportsResponses: Bool
    public var supportsEmbeddings: Bool
    public var supportsVision: Bool
    public var supportsAudio: Bool
    public var supportsTools: Bool
    public var supportsStructuredOutputs: Bool
    public var supportsReasoning: Bool
    public var needsCustomChatTemplate: Bool
    public var riskTier: RiskTier
    public var warnings: [String]

    public init(
        supportsVLLMMetal: Bool = false,
        supportsMLXNative: Bool = false,
        supportsChat: Bool = false,
        supportsResponses: Bool = false,
        supportsEmbeddings: Bool = false,
        supportsVision: Bool = false,
        supportsAudio: Bool = false,
        supportsTools: Bool = false,
        supportsStructuredOutputs: Bool = false,
        supportsReasoning: Bool = false,
        needsCustomChatTemplate: Bool = false,
        riskTier: RiskTier = .unknown,
        warnings: [String] = []
    ) {
        self.supportsVLLMMetal = supportsVLLMMetal
        self.supportsMLXNative = supportsMLXNative
        self.supportsChat = supportsChat
        self.supportsResponses = supportsResponses
        self.supportsEmbeddings = supportsEmbeddings
        self.supportsVision = supportsVision
        self.supportsAudio = supportsAudio
        self.supportsTools = supportsTools
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.supportsReasoning = supportsReasoning
        self.needsCustomChatTemplate = needsCustomChatTemplate
        self.riskTier = riskTier
        self.warnings = warnings
    }

    public static let empty = ModelCapabilities()
}

public struct ValidationMetrics: Codable, Hashable, Sendable {
    public let coldStartMs: Double?
    public let promptTokensPerSecond: Double?
    public let decodeTokensPerSecond: Double?
    public let peakMemoryBytes: Int64?

    public init(
        coldStartMs: Double? = nil,
        promptTokensPerSecond: Double? = nil,
        decodeTokensPerSecond: Double? = nil,
        peakMemoryBytes: Int64? = nil
    ) {
        self.coldStartMs = coldStartMs
        self.promptTokensPerSecond = promptTokensPerSecond
        self.decodeTokensPerSecond = decodeTokensPerSecond
        self.peakMemoryBytes = peakMemoryBytes
    }
}

public struct ValidationReport: Codable, Hashable, Sendable {
    public let modelId: String
    public let backendId: String
    public let supportsLoad: Bool
    public let supportsChat: Bool
    public let supportsResponses: Bool
    public let supportsEmbeddings: Bool
    public let supportsVision: Bool
    public let supportsTools: Bool
    public let supportsStructuredOutputs: Bool
    public let needsCustomChatTemplate: Bool
    public let riskTier: RiskTier
    public let warnings: [String]
    public let measured: ValidationMetrics

    public init(
        modelId: String,
        backendId: String,
        supportsLoad: Bool,
        supportsChat: Bool,
        supportsResponses: Bool,
        supportsEmbeddings: Bool,
        supportsVision: Bool,
        supportsTools: Bool,
        supportsStructuredOutputs: Bool,
        needsCustomChatTemplate: Bool,
        riskTier: RiskTier,
        warnings: [String],
        measured: ValidationMetrics
    ) {
        self.modelId = modelId
        self.backendId = backendId
        self.supportsLoad = supportsLoad
        self.supportsChat = supportsChat
        self.supportsResponses = supportsResponses
        self.supportsEmbeddings = supportsEmbeddings
        self.supportsVision = supportsVision
        self.supportsTools = supportsTools
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.needsCustomChatTemplate = needsCustomChatTemplate
        self.riskTier = riskTier
        self.warnings = warnings
        self.measured = measured
    }
}

public struct LaunchSpec: Codable, Hashable, Sendable {
    public let modelId: String
    public let profileId: String?
    public let preferredBackendId: String?
    public let gpuOnly: Bool
    public let requestMode: RequestMode
    public let maxContext: Int
    public let maxOutputTokens: Int
    public let enableTools: Bool
    public let enableReasoning: Bool
    public let structuredOutputSchemaJson: String?
    public let extraSamplingJson: String?

    public init(
        modelId: String,
        profileId: String? = nil,
        preferredBackendId: String? = nil,
        gpuOnly: Bool = true,
        requestMode: RequestMode = .chat,
        maxContext: Int = 8_192,
        maxOutputTokens: Int = 1_024,
        enableTools: Bool = false,
        enableReasoning: Bool = false,
        structuredOutputSchemaJson: String? = nil,
        extraSamplingJson: String? = nil
    ) {
        self.modelId = modelId
        self.profileId = profileId
        self.preferredBackendId = preferredBackendId
        self.gpuOnly = gpuOnly
        self.requestMode = requestMode
        self.maxContext = maxContext
        self.maxOutputTokens = maxOutputTokens
        self.enableTools = enableTools
        self.enableReasoning = enableReasoning
        self.structuredOutputSchemaJson = structuredOutputSchemaJson
        self.extraSamplingJson = extraSamplingJson
    }
}

public struct LaunchProfile: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let modelId: String
    public var name: String
    public var preferredEngine: BackendKind
    public var gpuOnly: Bool
    public var contextWindow: Int
    public var maxOutputTokens: Int
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var repetitionPenalty: Double?
    public var enableTools: Bool
    public var enableReasoning: Bool
    public var structuredOutputBackend: String?
    public var chatTemplatePath: String?
    public var extraArgs: [String: String]
    public var environment: [String: String]

    public init(
        id: String,
        modelId: String,
        name: String,
        preferredEngine: BackendKind,
        gpuOnly: Bool = true,
        contextWindow: Int,
        maxOutputTokens: Int,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        repetitionPenalty: Double? = nil,
        enableTools: Bool = false,
        enableReasoning: Bool = false,
        structuredOutputBackend: String? = nil,
        chatTemplatePath: String? = nil,
        extraArgs: [String: String] = [:],
        environment: [String: String] = [:]
    ) {
        self.id = id
        self.modelId = modelId
        self.name = name
        self.preferredEngine = preferredEngine
        self.gpuOnly = gpuOnly
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repetitionPenalty = repetitionPenalty
        self.enableTools = enableTools
        self.enableReasoning = enableReasoning
        self.structuredOutputBackend = structuredOutputBackend
        self.chatTemplatePath = chatTemplatePath
        self.extraArgs = extraArgs
        self.environment = environment
    }
}

public struct EngineInstanceRef: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let backendId: String
    public let modelId: String
    public let host: String
    public let port: Int
    public let status: EngineStatus
    public let warnings: [String]
    public let pid: Int?
    public let launchedAt: String?
    public let profileId: String?
    public let engineModelName: String?

    public init(
        id: String,
        backendId: String,
        modelId: String,
        host: String,
        port: Int,
        status: EngineStatus,
        warnings: [String] = [],
        pid: Int? = nil,
        launchedAt: String? = nil,
        profileId: String? = nil,
        engineModelName: String? = nil
    ) {
        self.id = id
        self.backendId = backendId
        self.modelId = modelId
        self.host = host
        self.port = port
        self.status = status
        self.warnings = warnings
        self.pid = pid
        self.launchedAt = launchedAt
        self.profileId = profileId
        self.engineModelName = engineModelName
    }
}

public struct InstanceActivity: Codable, Hashable, Sendable {
    public let instanceId: String
    public let modelId: String
    public let backendId: String
    public let queueDepth: Int
    public let ttftMsP50: Double?
    public let outputTokPerSecP50: Double?
    public let peakMemoryBytes: Int64?
    public let isWarm: Bool

    public init(
        instanceId: String,
        modelId: String,
        backendId: String,
        queueDepth: Int,
        ttftMsP50: Double?,
        outputTokPerSecP50: Double?,
        peakMemoryBytes: Int64?,
        isWarm: Bool
    ) {
        self.instanceId = instanceId
        self.modelId = modelId
        self.backendId = backendId
        self.queueDepth = queueDepth
        self.ttftMsP50 = ttftMsP50
        self.outputTokPerSecP50 = outputTokPerSecP50
        self.peakMemoryBytes = peakMemoryBytes
        self.isWarm = isWarm
    }
}

public struct ActivitySnapshot: Codable, Hashable, Sendable {
    public let timestamp: String
    public let totalUnifiedMemoryBytes: Int64
    public let estimatedFreeBytes: Int64
    public let memoryPressure: MemoryPressureLevel
    public let activeInstances: [InstanceActivity]

    public init(
        timestamp: String,
        totalUnifiedMemoryBytes: Int64,
        estimatedFreeBytes: Int64,
        memoryPressure: MemoryPressureLevel,
        activeInstances: [InstanceActivity]
    ) {
        self.timestamp = timestamp
        self.totalUnifiedMemoryBytes = totalUnifiedMemoryBytes
        self.estimatedFreeBytes = estimatedFreeBytes
        self.memoryPressure = memoryPressure
        self.activeInstances = activeInstances
    }
}

public struct HardwareSnapshot: Codable, Hashable, Sendable {
    public let chipFamily: String
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let gpuCores: Int
    public let totalMemoryBytes: Int64
    public let freeDiskBytes: Int64
    public let osVersion: String
    public let metalAvailable: Bool
    public let notes: [String: String]

    public init(
        chipFamily: String,
        performanceCores: Int,
        efficiencyCores: Int,
        gpuCores: Int,
        totalMemoryBytes: Int64,
        freeDiskBytes: Int64,
        osVersion: String,
        metalAvailable: Bool,
        notes: [String: String] = [:]
    ) {
        self.chipFamily = chipFamily
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.gpuCores = gpuCores
        self.totalMemoryBytes = totalMemoryBytes
        self.freeDiskBytes = freeDiskBytes
        self.osVersion = osVersion
        self.metalAvailable = metalAvailable
        self.notes = notes
    }
}

public struct BackendDetection: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: BackendKind
    public let version: String?
    public let runtimePath: String?
    public let pythonVersion: String?
    public let status: BackendStatus
    public let capabilities: [String]

    public init(
        id: String,
        kind: BackendKind,
        version: String? = nil,
        runtimePath: String? = nil,
        pythonVersion: String? = nil,
        status: BackendStatus,
        capabilities: [String]
    ) {
        self.id = id
        self.kind = kind
        self.version = version
        self.runtimePath = runtimePath
        self.pythonVersion = pythonVersion
        self.status = status
        self.capabilities = capabilities
    }
}

public struct RuntimeManifest: Codable, Hashable, Sendable {
    public let backendId: String
    public let packageName: String
    public let version: String
    public let pythonVersion: String
    public let installedAt: String
    public let runtimeRootPath: String
    public let executablePath: String
    public let pythonPath: String?
    public let metadata: [String: String]

    public init(
        backendId: String,
        packageName: String,
        version: String,
        pythonVersion: String,
        installedAt: String,
        runtimeRootPath: String,
        executablePath: String,
        pythonPath: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.backendId = backendId
        self.packageName = packageName
        self.version = version
        self.pythonVersion = pythonVersion
        self.installedAt = installedAt
        self.runtimeRootPath = runtimeRootPath
        self.executablePath = executablePath
        self.pythonPath = pythonPath
        self.metadata = metadata
    }
}

public struct MemoryEstimate: Codable, Hashable, Sendable {
    public let weightsResidentBytes: Int64
    public let kvCacheBytes: Int64
    public let runtimeOverheadBytes: Int64
    public let promptBufferBytes: Int64
    public let safetyMarginBytes: Int64
    public let estimatedPeakBytes: Int64
    public let reserveBytes: Int64
    public let headroomBytes: Int64
    public let riskTier: RiskTier

    public init(
        weightsResidentBytes: Int64,
        kvCacheBytes: Int64,
        runtimeOverheadBytes: Int64,
        promptBufferBytes: Int64,
        safetyMarginBytes: Int64,
        estimatedPeakBytes: Int64,
        reserveBytes: Int64,
        headroomBytes: Int64,
        riskTier: RiskTier
    ) {
        self.weightsResidentBytes = weightsResidentBytes
        self.kvCacheBytes = kvCacheBytes
        self.runtimeOverheadBytes = runtimeOverheadBytes
        self.promptBufferBytes = promptBufferBytes
        self.safetyMarginBytes = safetyMarginBytes
        self.estimatedPeakBytes = estimatedPeakBytes
        self.reserveBytes = reserveBytes
        self.headroomBytes = headroomBytes
        self.riskTier = riskTier
    }
}

public struct HealthReport: Codable, Hashable, Sendable {
    public let instanceId: String
    public let healthy: Bool
    public let status: EngineStatus
    public let message: String

    public init(instanceId: String, healthy: Bool, status: EngineStatus, message: String) {
        self.instanceId = instanceId
        self.healthy = healthy
        self.status = status
        self.message = message
    }
}

public struct BenchmarkRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let modelId: String
    public let engineBackendId: String
    public let launchProfileId: String?
    public let scenario: String
    public let promptTokens: Int
    public let outputTokens: Int
    public let ttftMs: Double
    public let tokS: Double
    public let totalLatencyMs: Double
    public let peakMemoryBytes: Int64
    public let success: Bool
    public let rawMetrics: [String: Double]

    public init(
        id: String,
        modelId: String,
        engineBackendId: String,
        launchProfileId: String?,
        scenario: String,
        promptTokens: Int,
        outputTokens: Int,
        ttftMs: Double,
        tokS: Double,
        totalLatencyMs: Double,
        peakMemoryBytes: Int64,
        success: Bool,
        rawMetrics: [String: Double]
    ) {
        self.id = id
        self.modelId = modelId
        self.engineBackendId = engineBackendId
        self.launchProfileId = launchProfileId
        self.scenario = scenario
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
        self.ttftMs = ttftMs
        self.tokS = tokS
        self.totalLatencyMs = totalLatencyMs
        self.peakMemoryBytes = peakMemoryBytes
        self.success = success
        self.rawMetrics = rawMetrics
    }
}

public struct ConversationRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var modelId: String?
    public var launchProfileId: String?
    public var messages: [ConversationMessage]

    public init(id: String, title: String, modelId: String? = nil, launchProfileId: String? = nil, messages: [ConversationMessage] = []) {
        self.id = id
        self.title = title
        self.modelId = modelId
        self.launchProfileId = launchProfileId
        self.messages = messages
    }
}

public struct ConversationMessage: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let role: String
    public let content: String
    public let createdAt: String

    public init(id: String, role: String, content: String, createdAt: String) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct RequestLogRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let level: String
    public let category: String
    public let message: String
    public let metadata: [String: String]
    public let createdAt: String

    public init(id: String, level: String, category: String, message: String, metadata: [String: String], createdAt: String) {
        self.id = id
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct AppOverview: Codable, Hashable, Sendable {
    public let health: AppHealth
    public let hardware: HardwareSnapshot
    public let backends: [BackendDetection]
    public let models: [ModelRecord]
    public let profiles: [LaunchProfile]
    public let activity: ActivitySnapshot
    public let benchmarks: [BenchmarkRecord]
    public let logs: [RequestLogRecord]
    public let conversations: [ConversationRecord]
    public let developerAPI: DeveloperAPIStatus

    public init(
        health: AppHealth,
        hardware: HardwareSnapshot,
        backends: [BackendDetection],
        models: [ModelRecord],
        profiles: [LaunchProfile],
        activity: ActivitySnapshot,
        benchmarks: [BenchmarkRecord],
        logs: [RequestLogRecord],
        conversations: [ConversationRecord],
        developerAPI: DeveloperAPIStatus
    ) {
        self.health = health
        self.hardware = hardware
        self.backends = backends
        self.models = models
        self.profiles = profiles
        self.activity = activity
        self.benchmarks = benchmarks
        self.logs = logs
        self.conversations = conversations
        self.developerAPI = developerAPI
    }
}

public struct DeveloperAPIStatus: Codable, Hashable, Sendable {
    public let baseURL: String
    public let requiresAPIKey: Bool
    public let currentKeyPreview: String?

    public init(baseURL: String, requiresAPIKey: Bool, currentKeyPreview: String?) {
        self.baseURL = baseURL
        self.requiresAPIKey = requiresAPIKey
        self.currentKeyPreview = currentKeyPreview
    }
}

public enum HubModelFormat: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case gguf
    case mlx

    public var id: String { rawValue }

    public var title: String {
        rawValue.uppercased()
    }

    public static func infer(
        repoID: String,
        libraryName: String?,
        tags: [String],
        siblingFiles: [String] = []
    ) -> [HubModelFormat] {
        let searchCorpus = ([repoID, libraryName ?? ""] + tags + siblingFiles)
            .joined(separator: " ")
            .lowercased()

        return HubModelFormat.allCases.filter { format in
            searchCorpus.contains(format.rawValue)
        }
    }
}

public struct ModelSearchResult: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let downloads: Int?
    public let likes: Int?
    public let pipelineTag: String?
    public let libraryName: String?
    public let createdAt: String?
    public let artifactFormats: [HubModelFormat]
    public let tags: [String]

    public init(
        id: String,
        displayName: String,
        downloads: Int? = nil,
        likes: Int? = nil,
        pipelineTag: String? = nil,
        libraryName: String? = nil,
        createdAt: String? = nil,
        artifactFormats: [HubModelFormat] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.downloads = downloads
        self.likes = likes
        self.pipelineTag = pipelineTag
        self.libraryName = libraryName
        self.createdAt = createdAt
        self.artifactFormats = artifactFormats
        self.tags = tags
    }
}

public struct ModelSearchResponse: Codable, Hashable, Sendable {
    public let query: String
    public let results: [ModelSearchResult]

    public init(query: String, results: [ModelSearchResult]) {
        self.query = query
        self.results = results
    }
}

public struct ModelCatalogCard: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let downloads: Int?
    public let likes: Int?
    public let pipelineTag: String?
    public let libraryName: String?
    public let license: String?
    public let baseModel: String?
    public let languages: [String]
    public let createdAt: String?
    public let lastModified: String?
    public let artifactFormats: [HubModelFormat]
    public let tags: [String]
    public let siblingFiles: [String]
    public let readme: String?
    public let repositoryURL: String

    public init(
        id: String,
        displayName: String,
        downloads: Int? = nil,
        likes: Int? = nil,
        pipelineTag: String? = nil,
        libraryName: String? = nil,
        license: String? = nil,
        baseModel: String? = nil,
        languages: [String] = [],
        createdAt: String? = nil,
        lastModified: String? = nil,
        artifactFormats: [HubModelFormat] = [],
        tags: [String] = [],
        siblingFiles: [String] = [],
        readme: String? = nil,
        repositoryURL: String
    ) {
        self.id = id
        self.displayName = displayName
        self.downloads = downloads
        self.likes = likes
        self.pipelineTag = pipelineTag
        self.libraryName = libraryName
        self.license = license
        self.baseModel = baseModel
        self.languages = languages
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.artifactFormats = artifactFormats
        self.tags = tags
        self.siblingFiles = siblingFiles
        self.readme = readme
        self.repositoryURL = repositoryURL
    }
}

public struct AppHealth: Codable, Hashable, Sendable {
    public let status: String
    public let uptimeSeconds: Int
    public let activeEngineCount: Int
    public let readyModelCount: Int

    public init(status: String, uptimeSeconds: Int, activeEngineCount: Int, readyModelCount: Int) {
        self.status = status
        self.uptimeSeconds = uptimeSeconds
        self.activeEngineCount = activeEngineCount
        self.readyModelCount = readyModelCount
    }
}

public struct ImportModelRequest: Codable, Sendable {
    public let displayName: String?
    public let sourceKind: SourceKind
    public let sourceRef: String

    public init(displayName: String? = nil, sourceKind: SourceKind, sourceRef: String) {
        self.displayName = displayName
        self.sourceKind = sourceKind
        self.sourceRef = sourceRef
    }
}

public struct CreateProfileRequest: Codable, Sendable {
    public let modelId: String
    public let name: String
    public let preferredEngine: BackendKind
    public let contextWindow: Int
    public let maxOutputTokens: Int
    public let enableTools: Bool
    public let enableReasoning: Bool

    public init(
        modelId: String,
        name: String,
        preferredEngine: BackendKind,
        contextWindow: Int,
        maxOutputTokens: Int,
        enableTools: Bool = false,
        enableReasoning: Bool = false
    ) {
        self.modelId = modelId
        self.name = name
        self.preferredEngine = preferredEngine
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.enableTools = enableTools
        self.enableReasoning = enableReasoning
    }
}

public struct UpdateProfileRequest: Codable, Sendable {
    public let name: String?
    public let contextWindow: Int?
    public let maxOutputTokens: Int?
    public let enableTools: Bool?
    public let enableReasoning: Bool?

    public init(
        name: String? = nil,
        contextWindow: Int? = nil,
        maxOutputTokens: Int? = nil,
        enableTools: Bool? = nil,
        enableReasoning: Bool? = nil
    ) {
        self.name = name
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.enableTools = enableTools
        self.enableReasoning = enableReasoning
    }
}

public struct CreateConversationRequest: Codable, Sendable {
    public let title: String
    public let modelId: String?
    public let launchProfileId: String?

    public init(title: String, modelId: String? = nil, launchProfileId: String? = nil) {
        self.title = title
        self.modelId = modelId
        self.launchProfileId = launchProfileId
    }
}

public struct AddConversationMessageRequest: Codable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct BenchmarkRequest: Codable, Sendable {
    public let modelId: String
    public let profileId: String?
    public let scenario: BenchmarkScenario

    public init(modelId: String, profileId: String? = nil, scenario: BenchmarkScenario) {
        self.modelId = modelId
        self.profileId = profileId
        self.scenario = scenario
    }
}

public struct OpenAIModelSummary: Codable, Hashable, Sendable {
    public let id: String
    public let object: String
    public let ownedBy: String
    public let created: Int

    public init(id: String, object: String = "model", ownedBy: String = "swiftlm", created: Int = Int(Date().timeIntervalSince1970)) {
        self.id = id
        self.object = object
        self.ownedBy = ownedBy
        self.created = created
    }

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case ownedBy = "owned_by"
        case created
    }
}

public struct OpenAIModelList: Codable, Hashable, Sendable {
    public let object: String
    public let data: [OpenAIModelSummary]

    public init(data: [OpenAIModelSummary]) {
        self.object = "list"
        self.data = data
    }
}

public struct ChatMessagePayload: Codable, Hashable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct OpenAIChatCompletionRequest: Codable, Sendable {
    public let model: String
    public let messages: [ChatMessagePayload]
    public let stream: Bool?
    public let maxTokens: Int?
    public let temperature: Double?

    public init(model: String, messages: [ChatMessagePayload], stream: Bool? = nil, maxTokens: Int? = nil, temperature: Double? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case maxTokens = "max_tokens"
        case temperature
    }
}

public struct ChatCompletionChoice: Codable, Hashable, Sendable {
    public let index: Int
    public let message: ChatMessagePayload
    public let finishReason: String

    public init(index: Int, message: ChatMessagePayload, finishReason: String) {
        self.index = index
        self.message = message
        self.finishReason = finishReason
    }

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

public struct OpenAIUsage: Codable, Hashable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct OpenAIChatCompletionResponse: Codable, Hashable, Sendable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let choices: [ChatCompletionChoice]
    public let usage: OpenAIUsage

    public init(id: String, model: String, choices: [ChatCompletionChoice], usage: OpenAIUsage) {
        self.id = id
        self.object = "chat.completion"
        self.created = Int(Date().timeIntervalSince1970)
        self.model = model
        self.choices = choices
        self.usage = usage
    }
}

public struct EmbeddingsRequest: Codable, Sendable {
    public let model: String
    public let input: String

    public init(model: String, input: String) {
        self.model = model
        self.input = input
    }
}

public struct EmbeddingDatum: Codable, Hashable, Sendable {
    public let index: Int
    public let embedding: [Double]
    public let object: String

    public init(index: Int, embedding: [Double], object: String = "embedding") {
        self.index = index
        self.embedding = embedding
        self.object = object
    }
}

public struct EmbeddingsResponse: Codable, Hashable, Sendable {
    public let object: String
    public let data: [EmbeddingDatum]
    public let model: String
    public let usage: OpenAIUsage

    public init(data: [EmbeddingDatum], model: String, usage: OpenAIUsage) {
        self.object = "list"
        self.data = data
        self.model = model
        self.usage = usage
    }
}

public struct APIErrorEnvelope: Codable, Hashable, Sendable, Error, LocalizedError {
    public let error: APIErrorPayload

    public init(code: String, message: String, retryable: Bool = false, details: [String: String] = [:]) {
        self.error = APIErrorPayload(code: code, message: message, retryable: retryable, details: details)
    }

    public var errorDescription: String? {
        error.message
    }

    public var failureReason: String? {
        error.code
    }

    public var recoverySuggestion: String? {
        error.retryable ? "Try again in a moment." : nil
    }
}

public struct GenericResponsesRequest: Codable, Sendable {
    public let model: String
    public let input: [ResponsesInputItem]?
    public let text: ResponsesTextFormat?
    public let maxOutputTokens: Int?
    public let temperature: Double?

    public init(
        model: String,
        input: [ResponsesInputItem]? = nil,
        text: ResponsesTextFormat? = nil,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil
    ) {
        self.model = model
        self.input = input
        self.text = text
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case text
        case maxOutputTokens = "max_output_tokens"
        case temperature
    }
}

public struct ResponsesInputItem: Codable, Sendable {
    public let role: String
    public let content: [ResponsesContentItem]

    public init(role: String, content: [ResponsesContentItem]) {
        self.role = role
        self.content = content
    }
}

public struct ResponsesContentItem: Codable, Sendable {
    public let type: String
    public let text: String?

    public init(type: String = "input_text", text: String?) {
        self.type = type
        self.text = text
    }
}

public struct ResponsesTextFormat: Codable, Sendable {
    public let format: ResponsesFormatValue?

    public init(format: ResponsesFormatValue? = nil) {
        self.format = format
    }
}

public struct ResponsesFormatValue: Codable, Sendable {
    public let type: String

    public init(type: String) {
        self.type = type
    }
}

public struct APIErrorPayload: Codable, Hashable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let details: [String: String]

    public init(code: String, message: String, retryable: Bool, details: [String: String]) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.details = details
    }
}

public enum MetricsSample {
    public static func prometheus(
        health: AppHealth,
        activity: ActivitySnapshot,
        backends: [BackendDetection]
    ) -> String {
        let healthyValue = health.status == "ok" ? 1 : 0
        let backendHealthyCount = backends.filter { $0.status == .installed }.count
        return """
        # HELP swiftlm_health Whether the control plane is healthy.
        # TYPE swiftlm_health gauge
        swiftlm_health \(healthyValue)
        # HELP swiftlm_active_engines Number of active engine instances.
        # TYPE swiftlm_active_engines gauge
        swiftlm_active_engines \(health.activeEngineCount)
        # HELP swiftlm_ready_models Number of ready models.
        # TYPE swiftlm_ready_models gauge
        swiftlm_ready_models \(health.readyModelCount)
        # HELP swiftlm_backend_ready_count Number of healthy backends.
        # TYPE swiftlm_backend_ready_count gauge
        swiftlm_backend_ready_count \(backendHealthyCount)
        # HELP swiftlm_estimated_free_memory_bytes Estimated free unified memory.
        # TYPE swiftlm_estimated_free_memory_bytes gauge
        swiftlm_estimated_free_memory_bytes \(activity.estimatedFreeBytes)
        """
    }
}

public enum Time {
    public static func nowISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

public enum Identifiers {
    public static func model(from sourceRef: String) -> String {
        sourceRef
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    public static func prefixed(_ prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }
}
