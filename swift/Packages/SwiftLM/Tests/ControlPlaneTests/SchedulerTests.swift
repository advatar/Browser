import Contracts
import ControlPlane
import Testing

@Test
func schedulerPrefersWarmVLLMMetalInstanceWhenAvailable() {
    let scheduler = Scheduler()
    let model = ModelRecord(
        ref: ModelRef(
            id: "qwen-14b-q4",
            displayName: "Qwen 14B Q4",
            sourceKind: .huggingFace,
            sourceRef: "Qwen/Qwen3-14B-Instruct-4bit",
            modality: .text,
            architecture: "Qwen",
            quantization: "4bit"
        ),
        parameterCount: 14_000_000_000,
        defaultContextWindow: 8_192,
        sizeOnDiskBytes: 16 * 1_024 * 1_024 * 1_024,
        capabilities: ModelCapabilities(
            supportsVLLMMetal: true,
            supportsMLXNative: true,
            supportsChat: true,
            supportsResponses: true,
            supportsTools: true,
            riskTier: .safe
        )
    )
    let hardware = HardwareSnapshot(
        chipFamily: "Apple M4 Max",
        performanceCores: 10,
        efficiencyCores: 4,
        gpuCores: 40,
        totalMemoryBytes: 64 * 1_024 * 1_024 * 1_024,
        freeDiskBytes: 1_024 * 1_024 * 1_024 * 1_024,
        osVersion: "macOS",
        metalAvailable: true
    )
    let spec = LaunchSpec(modelId: model.id, requestMode: .chat, maxContext: 8_192, maxOutputTokens: 1_024, enableTools: true)
    let backends = [
        BackendDetection(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal, status: .installed, capabilities: ["chat"]),
        BackendDetection(id: BackendKind.mlxNative.rawValue, kind: .mlxNative, status: .installed, capabilities: ["chat"])
    ]
    let instances = [
        EngineInstanceRef(
            id: "inst_warm",
            backendId: BackendKind.vllmMetal.rawValue,
            modelId: model.id,
            host: "127.0.0.1",
            port: 8_431,
            status: .ready
        )
    ]

    let decision = scheduler.chooseBackend(model: model, spec: spec, hardware: hardware, backends: backends, instances: instances)

    #expect(decision?.backendId == BackendKind.vllmMetal.rawValue)
}

@Test
func schedulerRejectsCandidatesWithoutHeadroom() {
    let scheduler = Scheduler()
    let model = ModelRecord(
        ref: ModelRef(
            id: "large-fp16",
            displayName: "Large FP16",
            sourceKind: .huggingFace,
            sourceRef: "meta/large-70b-fp16",
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
            riskTier: .safe
        )
    )
    let hardware = HardwareSnapshot(
        chipFamily: "Apple M2 Pro",
        performanceCores: 8,
        efficiencyCores: 4,
        gpuCores: 19,
        totalMemoryBytes: 32 * 1_024 * 1_024 * 1_024,
        freeDiskBytes: 512 * 1_024 * 1_024 * 1_024,
        osVersion: "macOS",
        metalAvailable: true
    )
    let spec = LaunchSpec(modelId: model.id, requestMode: .chat, maxContext: 16_384, maxOutputTokens: 1_024)
    let backends = [
        BackendDetection(id: BackendKind.vllmMetal.rawValue, kind: .vllmMetal, status: .installed, capabilities: ["chat"]),
        BackendDetection(id: BackendKind.mlxNative.rawValue, kind: .mlxNative, status: .installed, capabilities: ["chat"])
    ]

    let decision = scheduler.chooseBackend(model: model, spec: spec, hardware: hardware, backends: backends, instances: [])

    #expect(decision == nil)
}
