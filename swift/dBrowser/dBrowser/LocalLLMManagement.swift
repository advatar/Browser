import Foundation

#if os(macOS)
import ControlPlane
import Contracts
#endif

enum LocalLLMControlPlaneMode: String, Equatable, CaseIterable {
    case disconnected
    case connected
    case embedded
    case unavailable

    var title: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connected:
            return "Connected"
        case .embedded:
            return "Embedded"
        case .unavailable:
            return "Unavailable"
        }
    }
}

struct LocalLLMRecommendedImport: Equatable {
    enum SourceKind: String, Equatable {
        case local
        case huggingFace

        var title: String {
            switch self {
            case .local:
                return "Local folder"
            case .huggingFace:
                return "Hugging Face"
            }
        }
    }

    var displayName: String
    var sourceKind: SourceKind
    var sourceRef: String
    var packageSummary: String
    var readinessSummary: String

    static func current(fileManager: FileManager = .default) -> LocalLLMRecommendedImport {
        let selection = BundledLLMSelection.recommended
        let profile = selection.profile

        if let localURL = selection.localWorkspaceModelURL(fileManager: fileManager) {
            return LocalLLMRecommendedImport(
                displayName: profile.displayName,
                sourceKind: .local,
                sourceRef: localURL.path,
                packageSummary: profile.swiftPackageSummary,
                readinessSummary: profile.readinessSummary
            )
        }

        return LocalLLMRecommendedImport(
            displayName: profile.displayName,
            sourceKind: .huggingFace,
            sourceRef: profile.huggingFaceID,
            packageSummary: profile.swiftPackageSummary,
            readinessSummary: profile.readinessSummary
        )
    }
}

struct LocalLLMHardwareSummary: Equatable {
    var chipFamily: String
    var unifiedMemory: String
    var freeDisk: String
    var gpuCores: String
    var osVersion: String

    static let empty = LocalLLMHardwareSummary(
        chipFamily: "Unknown",
        unifiedMemory: "Unknown",
        freeDisk: "Unknown",
        gpuCores: "Unknown",
        osVersion: "Unknown"
    )
}

struct LocalLLMBackendSummary: Identifiable, Equatable {
    var id: String
    var kind: String
    var status: String
    var version: String
    var runtimePath: String
    var capabilities: [String]

    var canInstall: Bool {
        status == "missing" || status == "unhealthy"
    }
}

struct LocalLLMModelSummary: Identifiable, Equatable {
    var id: String
    var displayName: String
    var source: String
    var family: String
    var architecture: String
    var quantization: String
    var status: String
    var sizeOnDisk: String
    var contextWindow: String
    var capabilities: [String]
    var warnings: [String]

    var canInspect: Bool {
        status != "inspecting"
    }

    var canValidate: Bool {
        status != "validating"
    }

    var canWarm: Bool {
        status == "ready" || status == "warmable" || status == "downloaded" || status == "discovered"
    }
}

struct LocalLLMEngineSummary: Identifiable, Equatable {
    var id: String
    var modelID: String
    var backendID: String
    var queueDepth: String
    var outputTokensPerSecond: String
    var peakMemory: String
    var isWarm: Bool
}

struct LocalLLMManagementState: Equatable {
    var mode: LocalLLMControlPlaneMode
    var statusLine: String
    var baseURL: String
    var health: String
    var developerKeyPreview: String?
    var hardware: LocalLLMHardwareSummary
    var backends: [LocalLLMBackendSummary]
    var models: [LocalLLMModelSummary]
    var activeEngines: [LocalLLMEngineSummary]
    var recommendedImport: LocalLLMRecommendedImport
    var lastError: String?
    var isWorking: Bool

    var importedModelCountText: String {
        "\(models.count) model\(models.count == 1 ? "" : "s")"
    }

    var activeEngineCountText: String {
        "\(activeEngines.count) engine\(activeEngines.count == 1 ? "" : "s")"
    }

    static func disconnected(
        message: String = "SwiftLM control plane is not connected.",
        baseURL: String = LocalLLMManager.defaultBaseURLString,
        error: String? = nil
    ) -> LocalLLMManagementState {
        LocalLLMManagementState(
            mode: .disconnected,
            statusLine: message,
            baseURL: baseURL,
            health: "offline",
            developerKeyPreview: nil,
            hardware: .empty,
            backends: [],
            models: [],
            activeEngines: [],
            recommendedImport: .current(),
            lastError: error,
            isWorking: false
        )
    }

    static func unavailable(_ message: String) -> LocalLLMManagementState {
        LocalLLMManagementState(
            mode: .unavailable,
            statusLine: message,
            baseURL: LocalLLMManager.defaultBaseURLString,
            health: "unavailable",
            developerKeyPreview: nil,
            hardware: .empty,
            backends: [],
            models: [],
            activeEngines: [],
            recommendedImport: .current(),
            lastError: message,
            isWorking: false
        )
    }
}

@MainActor
protocol LocalLLMManaging: AnyObject {
    var currentState: LocalLLMManagementState { get }
    func refresh() async -> LocalLLMManagementState
    func connect() async -> LocalLLMManagementState
    func bootstrapEmbeddedControlPlane() async -> LocalLLMManagementState
    func importRecommendedModel() async -> LocalLLMManagementState
    func inspectModel(id: String) async -> LocalLLMManagementState
    func validateModel(id: String) async -> LocalLLMManagementState
    func warmModel(id: String) async -> LocalLLMManagementState
    func stopEngine(id: String) async -> LocalLLMManagementState
    func installBackend(id: String) async -> LocalLLMManagementState
}

@MainActor
final class LocalLLMManager: LocalLLMManaging {
    nonisolated static let defaultBaseURLString = "http://127.0.0.1:8400"

    private(set) var currentState: LocalLLMManagementState

#if os(macOS)
    private var host: ControlPlaneHost?
    private var client: ControlPlaneClient
#endif

    init() {
        self.currentState = .disconnected()
#if os(macOS)
        self.client = ControlPlaneClient()
#endif
    }

    func refresh() async -> LocalLLMManagementState {
#if os(macOS)
        return await loadOverview(
            mode: host == nil ? .connected : .embedded,
            successStatus: host == nil
                ? "Connected to SwiftLM control plane at \(Self.defaultBaseURLString)."
                : "Embedded SwiftLM control plane is running at \(Self.defaultBaseURLString)."
        )
#else
        return setState(.unavailable("SwiftLM control-plane management is currently available on macOS."))
#endif
    }

    func connect() async -> LocalLLMManagementState {
#if os(macOS)
        host = nil
        client = ControlPlaneClient()
        return await loadOverview(
            mode: .connected,
            successStatus: "Connected to existing SwiftLM control plane at \(Self.defaultBaseURLString)."
        )
#else
        return setState(.unavailable("SwiftLM control-plane management is currently available on macOS."))
#endif
    }

    func bootstrapEmbeddedControlPlane() async -> LocalLLMManagementState {
#if os(macOS)
        if host != nil {
            return await refresh()
        }

        if let overview = try? await client.fetchOverview() {
            return setState(snapshot(
                from: overview,
                mode: .connected,
                statusLine: "Reused existing SwiftLM control plane at \(Self.defaultBaseURLString)."
            ))
        }

        do {
            let host = try await ControlPlaneHost.bootstrap()
            do {
                try await host.start()
                self.host = host
                self.client = ControlPlaneClient(apiKey: host.secrets.plaintextKey)
                return await loadOverview(
                    mode: .embedded,
                    successStatus: "Embedded SwiftLM control plane is running at \(Self.defaultBaseURLString)."
                )
            } catch {
                if let overview = try? await ControlPlaneClient().fetchOverview() {
                    self.host = nil
                    self.client = ControlPlaneClient()
                    return setState(snapshot(
                        from: overview,
                        mode: .connected,
                        statusLine: "Connected to existing SwiftLM control plane after the embedded port was already in use."
                    ))
                }
                throw error
            }
        } catch {
            return setState(.disconnected(
                message: "Failed to start SwiftLM control plane.",
                error: describe(error)
            ))
        }
#else
        return setState(.unavailable("SwiftLM embedded control-plane bootstrap is currently available on macOS."))
#endif
    }

    func importRecommendedModel() async -> LocalLLMManagementState {
#if os(macOS)
        let recommended = LocalLLMRecommendedImport.current()
        do {
            let sourceKind: Contracts.SourceKind = recommended.sourceKind == .local ? .local : .huggingFace
            let record = try await client.importModel(
                ImportModelRequest(
                    displayName: recommended.displayName,
                    sourceKind: sourceKind,
                    sourceRef: recommended.sourceRef
                )
            )
            return await loadOverview(
                mode: host == nil ? .connected : .embedded,
                successStatus: "Imported \(record.ref.displayName) into SwiftLM."
            )
        } catch {
            return setState(failedState(prefix: "Import failed", error: error))
        }
#else
        return setState(.unavailable("SwiftLM model import is currently available on macOS."))
#endif
    }

    func inspectModel(id: String) async -> LocalLLMManagementState {
#if os(macOS)
        do {
            let record = try await client.inspectModel(id: id)
            return await loadOverview(
                mode: host == nil ? .connected : .embedded,
                successStatus: "Inspected \(record.ref.displayName)."
            )
        } catch {
            return setState(failedState(prefix: "Inspect failed", error: error))
        }
#else
        return setState(.unavailable("SwiftLM model inspection is currently available on macOS."))
#endif
    }

    func validateModel(id: String) async -> LocalLLMManagementState {
#if os(macOS)
        do {
            let report = try await client.validateModel(id: id)
            return await loadOverview(
                mode: host == nil ? .connected : .embedded,
                successStatus: "Validated \(id) on \(report.backendId) with \(report.riskTier.rawValue) risk."
            )
        } catch {
            return setState(failedState(prefix: "Validation failed", error: error))
        }
#else
        return setState(.unavailable("SwiftLM model validation is currently available on macOS."))
#endif
    }

    func warmModel(id: String) async -> LocalLLMManagementState {
#if os(macOS)
        do {
            let instance = try await client.launch(
                LaunchSpec(modelId: id, requestMode: .chat, maxContext: 8_192, maxOutputTokens: 512)
            )
            return await loadOverview(
                mode: host == nil ? .connected : .embedded,
                successStatus: "Launched \(id) on \(instance.backendId)."
            )
        } catch {
            return setState(failedState(prefix: "Launch failed", error: error))
        }
#else
        return setState(.unavailable("SwiftLM model launch is currently available on macOS."))
#endif
    }

    func stopEngine(id: String) async -> LocalLLMManagementState {
#if os(macOS)
        do {
            let instance = try await client.stopEngine(id: id)
            return await loadOverview(
                mode: host == nil ? .connected : .embedded,
                successStatus: "Stopped \(instance.modelId) on \(instance.backendId)."
            )
        } catch {
            return setState(failedState(prefix: "Stop failed", error: error))
        }
#else
        return setState(.unavailable("SwiftLM engine control is currently available on macOS."))
#endif
    }

    func installBackend(id: String) async -> LocalLLMManagementState {
#if os(macOS)
        do {
            let backend = try await client.installBackend(id: id)
            return await loadOverview(
                mode: host == nil ? .connected : .embedded,
                successStatus: "Installed \(backend.kind.rawValue)."
            )
        } catch {
            return setState(failedState(prefix: "Runtime install failed", error: error))
        }
#else
        return setState(.unavailable("SwiftLM runtime installation is currently available on macOS."))
#endif
    }

#if os(macOS)
    private func loadOverview(mode: LocalLLMControlPlaneMode, successStatus: String) async -> LocalLLMManagementState {
        do {
            let overview = try await client.fetchOverview()
            return setState(snapshot(from: overview, mode: mode, statusLine: successStatus))
        } catch {
            return setState(.disconnected(
                message: "SwiftLM control plane is not reachable at \(Self.defaultBaseURLString).",
                error: describe(error)
            ))
        }
    }

    private func snapshot(
        from overview: AppOverview,
        mode: LocalLLMControlPlaneMode,
        statusLine: String
    ) -> LocalLLMManagementState {
        LocalLLMManagementState(
            mode: mode,
            statusLine: statusLine,
            baseURL: overview.developerAPI.baseURL,
            health: overview.health.status,
            developerKeyPreview: overview.developerAPI.currentKeyPreview,
            hardware: LocalLLMHardwareSummary(
                chipFamily: overview.hardware.chipFamily,
                unifiedMemory: byteCount(overview.hardware.totalMemoryBytes, style: .memory),
                freeDisk: byteCount(overview.hardware.freeDiskBytes, style: .file),
                gpuCores: "\(overview.hardware.gpuCores)",
                osVersion: overview.hardware.osVersion
            ),
            backends: overview.backends.map(backendSummary),
            models: overview.models.map(modelSummary),
            activeEngines: overview.activity.activeInstances.map(engineSummary),
            recommendedImport: .current(),
            lastError: nil,
            isWorking: false
        )
    }

    private func backendSummary(_ backend: BackendDetection) -> LocalLLMBackendSummary {
        LocalLLMBackendSummary(
            id: backend.id,
            kind: backend.kind.rawValue,
            status: backend.status.rawValue,
            version: backend.version ?? "unknown",
            runtimePath: backend.runtimePath ?? "not installed",
            capabilities: backend.capabilities
        )
    }

    private func modelSummary(_ model: ModelRecord) -> LocalLLMModelSummary {
        var capabilities: [String] = []
        if model.capabilities.supportsChat {
            capabilities.append("Chat")
        }
        if model.capabilities.supportsResponses {
            capabilities.append("Responses")
        }
        if model.capabilities.supportsEmbeddings {
            capabilities.append("Embeddings")
        }
        if model.capabilities.supportsVision {
            capabilities.append("Vision")
        }
        if model.capabilities.supportsTools {
            capabilities.append("Tools")
        }
        if model.capabilities.supportsStructuredOutputs {
            capabilities.append("Structured output")
        }

        return LocalLLMModelSummary(
            id: model.id,
            displayName: model.ref.displayName,
            source: "\(model.ref.sourceKind.rawValue): \(model.ref.sourceRef)",
            family: model.family ?? "unknown",
            architecture: model.ref.architecture ?? model.tokenizerFamily ?? "unknown",
            quantization: model.ref.quantization ?? "unknown",
            status: model.status.rawValue,
            sizeOnDisk: byteCount(model.sizeOnDiskBytes, style: .file),
            contextWindow: model.defaultContextWindow.map(String.init) ?? "unknown",
            capabilities: capabilities.isEmpty ? ["Uninspected"] : capabilities,
            warnings: model.capabilities.warnings + (model.lastValidation?.warnings ?? [])
        )
    }

    private func engineSummary(_ activity: InstanceActivity) -> LocalLLMEngineSummary {
        LocalLLMEngineSummary(
            id: activity.instanceId,
            modelID: activity.modelId,
            backendID: activity.backendId,
            queueDepth: "\(activity.queueDepth)",
            outputTokensPerSecond: activity.outputTokPerSecP50.map { String(format: "%.1f tok/s", $0) } ?? "unknown",
            peakMemory: activity.peakMemoryBytes.map { byteCount($0, style: .memory) } ?? "unknown",
            isWarm: activity.isWarm
        )
    }
#endif

    private func failedState(prefix: String, error: Error) -> LocalLLMManagementState {
        var state = currentState
        state.statusLine = "\(prefix): \(error.localizedDescription)"
        state.lastError = describe(error)
        state.isWorking = false
        return state
    }

    private func setState(_ state: LocalLLMManagementState) -> LocalLLMManagementState {
        currentState = state
        return state
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)"
        ]
        if let reason = nsError.localizedFailureReason, reason.isEmpty == false {
            parts.append("reason=\(reason)")
        }
        return parts.joined(separator: " ")
    }
}

private func byteCount(_ bytes: Int64, style: ByteCountFormatter.CountStyle) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: style)
}
