import Contracts
import Foundation

public struct ModelInspector: Sendable {
    public init() {}

    public func inspect(_ model: ModelRecord) -> ModelRecord {
        var updated = model
        updated.status = .inspecting

        let sourceRef = model.ref.sourceRef
        let sourceURL = URL(fileURLWithPath: sourceRef)
        let fileManager = FileManager.default

        if model.ref.sourceKind == .local, fileManager.fileExists(atPath: sourceRef) {
            updated.primaryArtifactPath = sourceRef
            updated.sizeOnDiskBytes = directorySize(at: sourceURL)
            let config = loadJSON(named: "config.json", from: sourceURL)
            let tokenizerConfig = loadJSON(named: "tokenizer_config.json", from: sourceURL)
            let architecture = architecture(from: config) ?? guessArchitecture(from: sourceRef)
            let quantization = guessQuantization(from: sourceRef)
            let contextWindow = contextWindow(from: config, tokenizerConfig: tokenizerConfig)
            let chatTemplateState = chatTemplateState(from: tokenizerConfig, baseURL: sourceURL)
            let modality = guessModality(from: sourceRef)

            updated.ref = ModelRef(
                id: model.ref.id,
                displayName: model.ref.displayName,
                sourceKind: model.ref.sourceKind,
                sourceRef: sourceRef,
                modality: modality,
                architecture: architecture,
                quantization: quantization
            )
            updated.family = architecture?.components(separatedBy: "For").first
            updated.parameterCount = inferParameterCount(from: sourceRef)
            updated.tokenizerFamily = tokenizerFamily(from: tokenizerConfig)
            updated.chatTemplateState = chatTemplateState
            updated.defaultContextWindow = contextWindow
        } else {
            updated.ref = ModelRef(
                id: model.ref.id,
                displayName: model.ref.displayName,
                sourceKind: model.ref.sourceKind,
                sourceRef: sourceRef,
                modality: guessModality(from: sourceRef),
                architecture: guessArchitecture(from: sourceRef),
                quantization: guessQuantization(from: sourceRef)
            )
            updated.parameterCount = inferParameterCount(from: sourceRef)
            updated.defaultContextWindow = 8_192
            updated.chatTemplateState = .present
        }

        updated.capabilities = capabilities(for: updated)
        updated.status = .ready
        return updated
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true,
                let fileSize = values.fileSize
            else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }

    private func loadJSON(named filename: String, from baseURL: URL) -> [String: Any]? {
        let url = baseURL.appending(path: filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func architecture(from config: [String: Any]?) -> String? {
        if let architectures = config?["architectures"] as? [String], let first = architectures.first {
            return first
        }
        if let modelType = config?["model_type"] as? String {
            return modelType
        }
        return nil
    }

    private func tokenizerFamily(from tokenizerConfig: [String: Any]?) -> String? {
        tokenizerConfig?["tokenizer_class"] as? String
    }

    private func contextWindow(from config: [String: Any]?, tokenizerConfig: [String: Any]?) -> Int? {
        let keys = ["max_position_embeddings", "model_max_length", "max_seq_len", "n_ctx"]
        for key in keys {
            if let value = config?[key] as? Int {
                return value
            }
            if let value = tokenizerConfig?[key] as? Int {
                return value
            }
        }
        return nil
    }

    private func chatTemplateState(from tokenizerConfig: [String: Any]?, baseURL: URL) -> ChatTemplateState {
        if let template = tokenizerConfig?["chat_template"] as? String, !template.isEmpty {
            return .present
        }
        if FileManager.default.fileExists(atPath: baseURL.appending(path: "chat_template.jinja").path) {
            return .custom
        }
        return .missing
    }

    private func guessArchitecture(from sourceRef: String) -> String? {
        let lowered = sourceRef.lowercased()
        if lowered.contains("qwen") { return "Qwen" }
        if lowered.contains("llama") { return "Llama" }
        if lowered.contains("mistral") { return "Mistral" }
        if lowered.contains("phi") { return "Phi" }
        if lowered.contains("gemma") { return "Gemma" }
        return nil
    }

    private func guessQuantization(from sourceRef: String) -> String? {
        let lowered = sourceRef.lowercased()
        if lowered.contains("4bit") || lowered.contains("int4") || lowered.contains("q4") { return "4bit" }
        if lowered.contains("8bit") || lowered.contains("int8") || lowered.contains("q8") { return "8bit" }
        if lowered.contains("fp16") { return "fp16" }
        return nil
    }

    private func guessModality(from sourceRef: String) -> ModelModality {
        let lowered = sourceRef.lowercased()
        if lowered.contains("vision") || lowered.contains("vl") {
            return .vision
        }
        if lowered.contains("embed") {
            return .embeddings
        }
        if lowered.contains("audio") || lowered.contains("whisper") {
            return .audio
        }
        return .text
    }

    private func inferParameterCount(from sourceRef: String) -> Int? {
        let pattern = #"(\d+(\.\d+)?)\s*b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(sourceRef.startIndex..<sourceRef.endIndex, in: sourceRef)
        guard let match = regex.firstMatch(in: sourceRef, range: range),
              let valueRange = Range(match.range(at: 1), in: sourceRef),
              let value = Double(sourceRef[valueRange])
        else {
            return nil
        }
        return Int(value * 1_000_000_000)
    }

    private func capabilities(for model: ModelRecord) -> ModelCapabilities {
        let supportsChat = model.ref.modality == .text || model.ref.modality == .vision
        let supportsEmbeddings = model.ref.modality == .embeddings
        let needsTemplate = model.chatTemplateState == .missing && supportsChat
        var warnings: [String] = []
        if needsTemplate {
            warnings.append("Chat template missing; chat serving needs a custom template.")
        }
        if model.ref.modality == .vision {
            warnings.append("Vision models require backend-specific validation before production use.")
        }

        return ModelCapabilities(
            supportsVLLMMetal: model.ref.modality != .audio,
            supportsMLXNative: model.ref.modality != .audio,
            supportsChat: supportsChat,
            supportsResponses: supportsChat,
            supportsEmbeddings: supportsEmbeddings,
            supportsVision: model.ref.modality == .vision,
            supportsAudio: model.ref.modality == .audio,
            supportsTools: supportsChat,
            supportsStructuredOutputs: supportsChat,
            supportsReasoning: supportsChat,
            needsCustomChatTemplate: needsTemplate,
            riskTier: needsTemplate ? .caution : .safe,
            warnings: warnings
        )
    }
}
