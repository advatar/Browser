import Contracts
import Foundation
import MemoryEstimator

public struct Benchmarker: Sendable {
    private let estimator: MemoryEstimator

    public init(estimator: MemoryEstimator = MemoryEstimator()) {
        self.estimator = estimator
    }

    public func run(
        request: BenchmarkRequest,
        model: ModelRecord,
        profile: LaunchProfile?,
        backendId: String,
        hardware: HardwareSnapshot
    ) -> BenchmarkRecord {
        let spec = LaunchSpec(
            modelId: request.modelId,
            profileId: request.profileId,
            preferredBackendId: backendId,
            requestMode: .benchmark,
            maxContext: profile?.contextWindow ?? model.defaultContextWindow ?? 8_192,
            maxOutputTokens: profile?.maxOutputTokens ?? 512,
            enableTools: profile?.enableTools ?? false,
            enableReasoning: profile?.enableReasoning ?? false
        )
        let estimate = estimator.estimate(model: model, spec: spec, hardware: hardware)
        let promptTokens = min(spec.maxContext / 8, 1_024)
        let outputTokens = min(spec.maxOutputTokens, 256)
        let ttft = max(180, Double(estimate.estimatedPeakBytes / 1_000_000_000) * 110)
        let tokS = max(12, 52 - Double(model.parameterCount ?? 7_000_000_000) / 1_000_000_000 * 2.1)
        let totalLatency = ttft + (Double(outputTokens) / tokS * 1_000)

        return BenchmarkRecord(
            id: Identifiers.prefixed("bench"),
            modelId: request.modelId,
            engineBackendId: backendId,
            launchProfileId: request.profileId,
            scenario: request.scenario.rawValue,
            promptTokens: promptTokens,
            outputTokens: outputTokens,
            ttftMs: ttft,
            tokS: tokS,
            totalLatencyMs: totalLatency,
            peakMemoryBytes: estimate.estimatedPeakBytes,
            success: estimate.riskTier != .danger,
            rawMetrics: [
                "headroomBytes": Double(estimate.headroomBytes),
                "reserveBytes": Double(estimate.reserveBytes)
            ]
        )
    }
}
