import Contracts
import MemoryEstimator
import Testing

@Test
func memoryEstimatorFlagsDangerForOversizedModel() {
    let estimator = MemoryEstimator()
    let model = ModelRecord(
        ref: ModelRef(
            id: "llama-70b",
            displayName: "Llama 70B",
            sourceKind: .huggingFace,
            sourceRef: "meta/llama-70b",
            modality: .text,
            architecture: "Llama",
            quantization: "fp16"
        ),
        parameterCount: 70_000_000_000,
        defaultContextWindow: 32_768,
        sizeOnDiskBytes: 140 * 1_024 * 1_024 * 1_024,
        capabilities: ModelCapabilities(
            supportsVLLMMetal: true,
            supportsMLXNative: true,
            supportsChat: true,
            supportsResponses: true,
            riskTier: .unknown
        )
    )
    let hardware = HardwareSnapshot(
        chipFamily: "Apple M4 Max",
        performanceCores: 10,
        efficiencyCores: 4,
        gpuCores: 40,
        totalMemoryBytes: 48 * 1_024 * 1_024 * 1_024,
        freeDiskBytes: 512 * 1_024 * 1_024 * 1_024,
        osVersion: "macOS",
        metalAvailable: true
    )
    let spec = LaunchSpec(modelId: model.id, requestMode: .chat, maxContext: 32_768, maxOutputTokens: 2_048)

    let estimate = estimator.estimate(model: model, spec: spec, hardware: hardware)

    #expect(estimate.riskTier == .danger)
    #expect(estimate.headroomBytes < 0)
}

@Test
func memoryEstimatorPreservesHeadroomForCompactQuantizedModel() {
    let estimator = MemoryEstimator()
    let model = ModelRecord(
        ref: ModelRef(
            id: "qwen-7b-q4",
            displayName: "Qwen 7B Q4",
            sourceKind: .huggingFace,
            sourceRef: "Qwen/Qwen2.5-7B-Instruct-4bit",
            modality: .text,
            architecture: "Qwen",
            quantization: "4bit"
        ),
        parameterCount: 7_000_000_000,
        defaultContextWindow: 8_192,
        sizeOnDiskBytes: 8 * 1_024 * 1_024 * 1_024,
        capabilities: ModelCapabilities(
            supportsVLLMMetal: true,
            supportsMLXNative: true,
            supportsChat: true,
            supportsResponses: true,
            riskTier: .unknown
        )
    )
    let hardware = HardwareSnapshot(
        chipFamily: "Apple M3 Pro",
        performanceCores: 6,
        efficiencyCores: 6,
        gpuCores: 18,
        totalMemoryBytes: 36 * 1_024 * 1_024 * 1_024,
        freeDiskBytes: 256 * 1_024 * 1_024 * 1_024,
        osVersion: "macOS",
        metalAvailable: true
    )
    let spec = LaunchSpec(modelId: model.id, requestMode: .chat, maxContext: 8_192, maxOutputTokens: 1_024)

    let estimate = estimator.estimate(model: model, spec: spec, hardware: hardware)

    #expect(estimate.riskTier == .safe || estimate.riskTier == .caution)
    #expect(estimate.headroomBytes > 0)
}
