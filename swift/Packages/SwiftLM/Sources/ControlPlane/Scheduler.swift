import Contracts
import Foundation
import MemoryEstimator

public struct SchedulerDecision: Sendable {
    public let backendId: String
    public let score: Int
    public let estimate: MemoryEstimate
    public let warnings: [String]

    public init(backendId: String, score: Int, estimate: MemoryEstimate, warnings: [String]) {
        self.backendId = backendId
        self.score = score
        self.estimate = estimate
        self.warnings = warnings
    }
}

public struct Scheduler: Sendable {
    private let estimator: MemoryEstimator

    public init(estimator: MemoryEstimator = MemoryEstimator()) {
        self.estimator = estimator
    }

    public func chooseBackend(
        model: ModelRecord,
        spec: LaunchSpec,
        hardware: HardwareSnapshot,
        backends: [BackendDetection],
        instances: [EngineInstanceRef]
    ) -> SchedulerDecision? {
        let activeBackendIds = Set(backends.map(\.id))
        let candidates = backends.compactMap { backend -> SchedulerDecision? in
            guard backend.status == .installed, activeBackendIds.contains(backend.id) else {
                return nil
            }

            let supportsFeature: Bool
            switch spec.requestMode {
            case .chat, .responses:
                supportsFeature = model.capabilities.supportsChat
            case .embeddings:
                supportsFeature = model.capabilities.supportsEmbeddings
            case .benchmark:
                supportsFeature = true
            }
            guard supportsFeature else { return nil }
            if spec.gpuOnly, backend.kind == .mlxSwift {
                return nil
            }

            let estimate = estimator.estimate(model: model, spec: spec, hardware: hardware)
            guard estimate.headroomBytes > 0 else {
                return nil
            }

            var score = 0
            var warnings: [String] = []
            switch backend.kind {
            case .vllmMetal:
                score += 100
            case .mlxNative:
                score += 70
            case .mlxSwift:
                score += 45
            }

            if let preferred = spec.preferredBackendId, preferred == backend.id {
                score += 15
            }
            if instances.contains(where: { $0.modelId == model.id && $0.backendId == backend.id && $0.status == .ready }) {
                score += 20
            }
            switch estimate.riskTier {
            case .safe:
                score += 12
            case .caution:
                score += 2
                warnings.append("Memory headroom is in the caution zone.")
            case .danger:
                score -= 25
                warnings.append("Danger-zone memory estimate.")
            case .unsupported, .unknown:
                score -= 10
            }

            if model.capabilities.needsCustomChatTemplate {
                score -= 8
                warnings.append("Chat template needs explicit resolution.")
            }
            if spec.enableTools {
                score -= 4
                warnings.append("Tool argument validation should stay enabled.")
            }

            return SchedulerDecision(backendId: backend.id, score: score, estimate: estimate, warnings: warnings)
        }

        return candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.estimate.headroomBytes > rhs.estimate.headroomBytes
            }
            return lhs.score > rhs.score
        }.first
    }
}
