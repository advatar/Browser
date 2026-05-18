import Contracts
import Foundation
import MemoryEstimator

public struct RuntimeInstallation: Codable, Hashable, Sendable {
    public let backendId: String
    public let rootPath: String
    public let executablePath: String
    public let pythonPath: String?
    public let version: String?
    public let pythonVersion: String?

    public init(
        backendId: String,
        rootPath: String,
        executablePath: String,
        pythonPath: String? = nil,
        version: String? = nil,
        pythonVersion: String? = nil
    ) {
        self.backendId = backendId
        self.rootPath = rootPath
        self.executablePath = executablePath
        self.pythonPath = pythonPath
        self.version = version
        self.pythonVersion = pythonVersion
    }
}

public struct EngineLaunchPlan: Codable, Hashable, Sendable {
    public let backendId: String
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: String?
    public let readinessPath: String
    public let metricsPath: String?
    public let engineModelName: String
    public let supportsDirectResponses: Bool
    public let supportsDirectEmbeddings: Bool

    public init(
        backendId: String,
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        readinessPath: String,
        metricsPath: String? = nil,
        engineModelName: String,
        supportsDirectResponses: Bool,
        supportsDirectEmbeddings: Bool
    ) {
        self.backendId = backendId
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.readinessPath = readinessPath
        self.metricsPath = metricsPath
        self.engineModelName = engineModelName
        self.supportsDirectResponses = supportsDirectResponses
        self.supportsDirectEmbeddings = supportsDirectEmbeddings
    }
}

public protocol EngineAdapter: Sendable {
    var id: String { get }
    func detect(hardware: HardwareSnapshot) async -> BackendDetection
    func detectInstallation() -> RuntimeInstallation?
    func validate(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> ValidationReport
    func estimateMemory(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> MemoryEstimate
    func launch(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async throws -> EngineInstanceRef
    func stop(instanceId: String) async
    func health(instanceId: String) async -> HealthReport
    func launchPlan(
        model: ModelRecord,
        spec: LaunchSpec,
        profile: LaunchProfile?,
        installation: RuntimeInstallation,
        port: Int,
        publicModelName: String,
        apiKey: String?
    ) throws -> EngineLaunchPlan
}

public struct VLLMMetalAdapter: EngineAdapter {
    public let id = BackendKind.vllmMetal.rawValue
    private let estimator: MemoryEstimator

    public init(estimator: MemoryEstimator = MemoryEstimator()) {
        self.estimator = estimator
    }

    public func detect(hardware: HardwareSnapshot) async -> BackendDetection {
        let installation = detectInstallation()
        return BackendDetection(
            id: id,
            kind: .vllmMetal,
            version: installation?.version ?? "latest",
            runtimePath: installation?.rootPath ?? RuntimePaths.currentRoot().appending(path: "vllm-metal").path,
            pythonVersion: installation?.pythonVersion ?? "3.12",
            status: hardware.metalAvailable ? (installation == nil ? .missing : .installed) : .missing,
            capabilities: ["chat", "responses", "embeddings", "metrics", "tool-calling", "structured-outputs"]
        )
    }

    public func detectInstallation() -> RuntimeInstallation? {
        for candidate in RuntimePaths.vllmMetalCandidates() {
            let executable = RuntimePaths.executablePath(in: candidate, named: "vllm")
            let python = RuntimePaths.executablePath(in: candidate, named: "python")
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                continue
            }
            let manifest = RuntimePaths.loadManifest(fromRuntimeRoot: RuntimePaths.runtimeRoot(for: candidate))
            let runtimeRoot = RuntimePaths.runtimeRoot(for: candidate)
            return RuntimeInstallation(
                backendId: id,
                rootPath: runtimeRoot.path,
                executablePath: executable,
                pythonPath: FileManager.default.isExecutableFile(atPath: python) ? python : nil,
                version: manifest?.version,
                pythonVersion: manifest?.pythonVersion
            )
        }
        return nil
    }

    public func validate(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> ValidationReport {
        let estimate = estimator.estimate(model: model, spec: spec, hardware: hardware)
        var warnings = model.capabilities.warnings
        warnings.append("Generation config will be pinned to vllm.")
        if spec.enableTools {
            warnings.append("Tool arguments should be post-validated after parser output.")
        }
        return ValidationReport(
            modelId: model.id,
            backendId: id,
            supportsLoad: detectInstallation() != nil,
            supportsChat: model.capabilities.supportsChat,
            supportsResponses: model.capabilities.supportsResponses,
            supportsEmbeddings: true,
            supportsVision: model.capabilities.supportsVision,
            supportsTools: model.capabilities.supportsTools,
            supportsStructuredOutputs: model.capabilities.supportsStructuredOutputs,
            needsCustomChatTemplate: model.capabilities.needsCustomChatTemplate,
            riskTier: estimate.riskTier,
            warnings: warnings,
            measured: ValidationMetrics(peakMemoryBytes: estimate.estimatedPeakBytes)
        )
    }

    public func estimateMemory(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> MemoryEstimate {
        estimator.estimate(model: model, spec: spec, hardware: hardware)
    }

    public func launch(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async throws -> EngineInstanceRef {
        let validation = await validate(model: model, spec: spec, hardware: hardware)
        return EngineInstanceRef(
            id: Identifiers.prefixed("inst"),
            backendId: id,
            modelId: model.id,
            host: "127.0.0.1",
            port: 8_400 + Int.random(in: 20...220),
            status: validation.riskTier == .danger ? .warming : .ready,
            warnings: validation.warnings,
            launchedAt: Time.nowISO8601(),
            engineModelName: model.id
        )
    }

    public func stop(instanceId: String) async {}

    public func health(instanceId: String) async -> HealthReport {
        HealthReport(instanceId: instanceId, healthy: detectInstallation() != nil, status: .ready, message: "vLLM Metal installation detected")
    }

    public func launchPlan(
        model: ModelRecord,
        spec: LaunchSpec,
        profile: LaunchProfile?,
        installation: RuntimeInstallation,
        port: Int,
        publicModelName: String,
        apiKey: String?
    ) throws -> EngineLaunchPlan {
        let source = model.primaryArtifactPath ?? model.ref.sourceRef
        var arguments = [
            "serve",
            source,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--served-model-name", publicModelName,
            "--generation-config", "vllm",
            "--max-model-len", "\(spec.maxContext)"
        ]

        if let apiKey, apiKey.isEmpty == false {
            arguments += ["--api-key", apiKey]
        }

        if let chatTemplatePath = profile?.chatTemplatePath {
            arguments += ["--chat-template", chatTemplatePath]
        } else if model.capabilities.needsCustomChatTemplate {
            throw APIErrorEnvelope(
                code: "CHAT_TEMPLATE_MISSING",
                message: "This model requires an explicit chat template before vLLM Metal can serve chat requests.",
                details: ["modelId": model.id, "backendId": id]
            )
        }

        if spec.enableTools {
            arguments += ["--enable-auto-tool-choice", "--tool-call-parser", "hermes"]
        }

        var environment = ProcessInfo.processInfo.environment
        environment["VLLM_PLUGINS"] = "metal"
        environment["VLLM_METAL_MEMORY_FRACTION"] = spec.maxContext > 8_192 ? "0.75" : "auto"
        environment["VLLM_MLX_DEVICE"] = spec.gpuOnly ? "gpu" : "cpu"
        environment["VLLM_METAL_PREFIX_CACHE"] = "1"
        environment["VLLM_METAL_USE_PAGED_ATTENTION"] = spec.maxContext > 8_192 ? "1" : "0"
        profile?.environment.forEach { environment[$0.key] = $0.value }

        return EngineLaunchPlan(
            backendId: id,
            executablePath: installation.executablePath,
            arguments: arguments,
            environment: environment,
            workingDirectory: nil,
            readinessPath: "/v1/models",
            metricsPath: "/metrics",
            engineModelName: publicModelName,
            supportsDirectResponses: true,
            supportsDirectEmbeddings: true
        )
    }
}

public struct MLXNativeAdapter: EngineAdapter {
    public let id = BackendKind.mlxNative.rawValue
    private let estimator: MemoryEstimator

    public init(estimator: MemoryEstimator = MemoryEstimator()) {
        self.estimator = estimator
    }

    public func detect(hardware: HardwareSnapshot) async -> BackendDetection {
        let installation = detectInstallation()
        return BackendDetection(
            id: id,
            kind: .mlxNative,
            version: installation?.version ?? "latest",
            runtimePath: installation?.rootPath ?? RuntimePaths.currentRoot().appending(path: "mlx-native").path,
            pythonVersion: installation?.pythonVersion ?? "3.12",
            status: hardware.metalAvailable ? (installation == nil ? .missing : .installed) : .disabled,
            capabilities: ["chat", "models", "local-proxy"]
        )
    }

    public func detectInstallation() -> RuntimeInstallation? {
        for candidate in RuntimePaths.mlxNativeCandidates() {
            if let installation = Self.runtimeInstallation(candidate: candidate, backendId: id) {
                return installation
            }
        }
        return nil
    }

    public func validate(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> ValidationReport {
        let estimate = estimator.estimate(model: model, spec: spec, hardware: hardware)
        var warnings = model.capabilities.warnings
        warnings.append("MLX native is expected to run behind the control plane and not as a public server.")
        return ValidationReport(
            modelId: model.id,
            backendId: id,
            supportsLoad: detectInstallation() != nil,
            supportsChat: model.capabilities.supportsChat,
            supportsResponses: model.capabilities.supportsResponses,
            supportsEmbeddings: false,
            supportsVision: false,
            supportsTools: false,
            supportsStructuredOutputs: false,
            needsCustomChatTemplate: false,
            riskTier: estimate.riskTier == .danger ? .caution : estimate.riskTier,
            warnings: warnings,
            measured: ValidationMetrics(peakMemoryBytes: estimate.estimatedPeakBytes)
        )
    }

    public func estimateMemory(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async -> MemoryEstimate {
        estimator.estimate(model: model, spec: spec, hardware: hardware)
    }

    public func launch(model: ModelRecord, spec: LaunchSpec, hardware: HardwareSnapshot) async throws -> EngineInstanceRef {
        let validation = await validate(model: model, spec: spec, hardware: hardware)
        return EngineInstanceRef(
            id: Identifiers.prefixed("inst"),
            backendId: id,
            modelId: model.id,
            host: "127.0.0.1",
            port: 8_400 + Int.random(in: 250...450),
            status: .ready,
            warnings: validation.warnings,
            launchedAt: Time.nowISO8601(),
            engineModelName: model.id
        )
    }

    public func stop(instanceId: String) async {}

    public func health(instanceId: String) async -> HealthReport {
        HealthReport(instanceId: instanceId, healthy: detectInstallation() != nil, status: .ready, message: "MLX native installation detected")
    }

    public func launchPlan(
        model: ModelRecord,
        spec: LaunchSpec,
        profile: LaunchProfile?,
        installation: RuntimeInstallation,
        port: Int,
        publicModelName: String,
        apiKey: String?
    ) throws -> EngineLaunchPlan {
        guard let python = installation.pythonPath ?? detectInstallation()?.pythonPath else {
            throw APIErrorEnvelope(
                code: "BACKEND_NOT_INSTALLED",
                message: "MLX native runtime is not installed.",
                details: ["backendId": id]
            )
        }

        let source = model.primaryArtifactPath ?? model.ref.sourceRef
        let arguments = [
            "-m", "mlx_lm.server",
            "--model", source,
            "--host", "127.0.0.1",
            "--port", "\(port)"
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["MLX_DEVICE"] = spec.gpuOnly ? "gpu" : "cpu"
        environment["SWIFTLM_PUBLIC_HTTP_DISABLED"] = "1"
        if let sitePackagesPath = RuntimePaths.loadManifest(fromRuntimeRoot: URL(fileURLWithPath: installation.rootPath))?.metadata["sitePackagesPath"] {
            guard ManagedMLXSitePackagesValidator.isValid(at: sitePackagesPath, pythonPath: python) else {
                throw APIErrorEnvelope(
                    code: "BACKEND_NOT_INSTALLED",
                    message: "MLX native runtime is incomplete and must be reinstalled.",
                    details: ["backendId": id]
                )
            }
            let existing = environment["PYTHONPATH"].flatMap { $0.isEmpty ? nil : $0 }
            environment["PYTHONPATH"] = existing.map { "\(sitePackagesPath):\($0)" } ?? sitePackagesPath
        }
        profile?.environment.forEach { environment[$0.key] = $0.value }
        if let apiKey, apiKey.isEmpty == false {
            environment["SWIFTLM_PROXY_API_KEY"] = apiKey
        }

        return EngineLaunchPlan(
            backendId: id,
            executablePath: python,
            arguments: arguments,
            environment: environment,
            workingDirectory: model.ref.sourceKind == .local ? URL(fileURLWithPath: source).deletingLastPathComponent().path : nil,
            readinessPath: "/v1/models",
            metricsPath: nil,
            engineModelName: source,
            supportsDirectResponses: false,
            supportsDirectEmbeddings: false
        )
    }

    static func runtimeInstallation(
        candidate: URL,
        backendId: String,
        sitePackagesValidator: (String, String) -> Bool = { sitePackagesPath, pythonPath in
            ManagedMLXSitePackagesValidator.isValid(at: sitePackagesPath, pythonPath: pythonPath)
        }
    ) -> RuntimeInstallation? {
        let runtimeRoot = RuntimePaths.runtimeRoot(for: candidate)
        let manifest = RuntimePaths.loadManifest(fromRuntimeRoot: runtimeRoot)
        if let manifest,
           let pythonPath = manifest.pythonPath,
           FileManager.default.isExecutableFile(atPath: pythonPath) {
            if let sitePackagesPath = manifest.metadata["sitePackagesPath"],
               sitePackagesValidator(sitePackagesPath, pythonPath) == false {
                return nil
            }
            return RuntimeInstallation(
                backendId: backendId,
                rootPath: runtimeRoot.path,
                executablePath: manifest.executablePath,
                pythonPath: pythonPath,
                version: manifest.version,
                pythonVersion: manifest.pythonVersion
            )
        }

        let python = RuntimePaths.executablePath(in: candidate, named: "python")
        guard FileManager.default.isExecutableFile(atPath: python) else {
            return nil
        }
        return RuntimeInstallation(
            backendId: backendId,
            rootPath: runtimeRoot.path,
            executablePath: python,
            pythonPath: python,
            version: manifest?.version,
            pythonVersion: manifest?.pythonVersion
        )
    }
}

public enum ManagedMLXSitePackagesValidator {
    public static func isValid(
        at sitePackagesPath: String,
        pythonPath: String? = nil,
        importProbe: ((String, String) -> Bool)? = nil
    ) -> Bool {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: sitePackagesPath)
        let serverPath = root.appending(path: "mlx_lm/server.py").path
        guard fileManager.fileExists(atPath: serverPath) else {
            return false
        }
        guard fileManager.fileExists(atPath: root.appending(path: "mlx").path) else {
            return false
        }

        guard let pythonPath else {
            return containsNativeMLXRuntime(at: root)
        }
        guard fileManager.isExecutableFile(atPath: pythonPath) else {
            return false
        }
        return (importProbe ?? defaultImportProbe)(pythonPath, sitePackagesPath)
    }

    private static func containsNativeMLXRuntime(at root: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: root.appending(path: "mlx/lib/libmlx.dylib").path) {
            return true
        }

        let mlxDirectory = root.appending(path: "mlx")
        guard let children = try? fileManager.contentsOfDirectory(
            at: mlxDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return children.contains { child in
            let name = child.lastPathComponent
            return name.hasPrefix("core.") && name.hasSuffix(".so")
        }
    }

    private static func defaultImportProbe(pythonPath: String, sitePackagesPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-c",
            "import mlx.core as mx; import mlx_lm.server; assert hasattr(mx, 'float32')"
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONPATH"] = sitePackagesPath
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

public struct RuntimeCatalog: Sendable {
    public let adapters: [any EngineAdapter]

    public init(adapters: [any EngineAdapter]) {
        self.adapters = adapters
    }

    public static let local = RuntimeCatalog(adapters: [
        VLLMMetalAdapter(),
        MLXNativeAdapter()
    ])
}

enum RuntimePaths {
    static func managedRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "SwiftLM")
    }

    static func currentRoot() -> URL {
        managedRoot().appending(path: "current")
    }

    static func vllmMetalCandidates() -> [URL] {
        let managed = currentRoot().appending(path: "vllm-metal/venv")
        let legacy = URL(fileURLWithPath: "\(NSHomeDirectory())/.venv-vllm-metal")
        return [managed, legacy]
    }

    static func mlxNativeCandidates() -> [URL] {
        let managed = currentRoot().appending(path: "mlx-native/venv")
        let legacyPy311 = managedRoot().appending(path: "runtimes/mlx-native-py311")
        let legacyPy312 = managedRoot().appending(path: "runtimes/mlx-native-py312")
        return [managed, legacyPy312, legacyPy311]
    }

    static func runtimeRoot(for candidate: URL) -> URL {
        candidate.lastPathComponent == "venv" ? candidate.deletingLastPathComponent() : candidate
    }

    static func executablePath(in candidate: URL, named executableName: String) -> String {
        candidate.appending(path: "bin/\(executableName)").path
    }

    static func loadManifest(fromRuntimeRoot runtimeRoot: URL) -> RuntimeManifest? {
        let manifestURL = runtimeRoot.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        return try? JSONDecoder().decode(RuntimeManifest.self, from: data)
    }
}
