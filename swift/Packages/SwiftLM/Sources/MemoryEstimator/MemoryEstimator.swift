import Contracts
import Foundation

public struct MemoryEstimator: Sendable {
    public init() {}

    public func estimate(
        model: ModelRecord,
        spec: LaunchSpec,
        hardware: HardwareSnapshot
    ) -> MemoryEstimate {
        let totalMemory = hardware.totalMemoryBytes
        let reserveBytes = max(Int64(6 * 1_024 * 1_024 * 1_024), Int64(Double(totalMemory) * 0.15))
        let weightsResidentBytes = max(model.sizeOnDiskBytes, inferredWeights(for: model))
        let kvCacheBytes = Int64(spec.maxContext) * Int64(max(model.parameterCount ?? 7_000_000_000, 1) / 1_000_000) * 16
        let runtimeOverheadBytes = Int64(Double(weightsResidentBytes) * 0.08)
        let promptBufferBytes = Int64(spec.maxOutputTokens * 4_096)
        let safetyMarginBytes = Int64(Double(totalMemory) * 0.05)
        let estimatedPeakBytes = weightsResidentBytes + kvCacheBytes + runtimeOverheadBytes + promptBufferBytes + safetyMarginBytes
        let headroomBytes = totalMemory - estimatedPeakBytes - reserveBytes
        let riskTier: RiskTier

        let usageRatio = Double(estimatedPeakBytes + reserveBytes) / Double(max(totalMemory, 1))
        switch usageRatio {
        case ..<0.60:
            riskTier = .safe
        case ..<0.75:
            riskTier = .caution
        default:
            riskTier = .danger
        }

        return MemoryEstimate(
            weightsResidentBytes: weightsResidentBytes,
            kvCacheBytes: kvCacheBytes,
            runtimeOverheadBytes: runtimeOverheadBytes,
            promptBufferBytes: promptBufferBytes,
            safetyMarginBytes: safetyMarginBytes,
            estimatedPeakBytes: estimatedPeakBytes,
            reserveBytes: reserveBytes,
            headroomBytes: headroomBytes,
            riskTier: riskTier
        )
    }

    private func inferredWeights(for model: ModelRecord) -> Int64 {
        if let parameterCount = model.parameterCount {
            let bytesPerParameter: Int64
            switch model.ref.quantization?.lowercased() {
            case let quant? where quant.contains("4"):
                bytesPerParameter = 1
            case let quant? where quant.contains("8"):
                bytesPerParameter = 1
            default:
                bytesPerParameter = 2
            }
            return Int64(parameterCount) * bytesPerParameter
        }
        return max(model.sizeOnDiskBytes, 8 * 1_024 * 1_024 * 1_024)
    }
}
