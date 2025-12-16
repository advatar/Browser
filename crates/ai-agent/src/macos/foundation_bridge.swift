import Foundation
import FoundationModels
import Dispatch

@available(macOS 15.0, *)
private final class FoundationModelBridge {
    static let shared = FoundationModelBridge()

    private init() {}

    func generate(prompt: String, systemPrompt: String?, temperature: Double, maxTokens: Int) throws -> String {
        let model = SystemLanguageModel()
        let session: LanguageModelSession
        if let instructions = systemPrompt, !instructions.isEmpty {
            session = LanguageModelSession(model: model, instructions: instructions)
        } else {
            session = LanguageModelSession(model: model)
        }

        let tokenLimit: Int? = maxTokens > 0 ? maxTokens : nil
        let generationOptions = GenerationOptions(
            sampling: nil,
            temperature: temperature,
            maximumResponseTokens: tokenLimit
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error>?

        Task {
            do {
                let response = try await session.respond(to: prompt, options: generationOptions)
                result = .success(response.content)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw NSError(domain: "com.browser.foundation", code: -102, userInfo: [NSLocalizedDescriptionKey: "Foundation model returned no response"])
        }
    }
}

@_cdecl("foundation_model_generate")
public func foundation_model_generate(
    _ promptPtr: UnsafePointer<CChar>,
    _ systemPromptPtr: UnsafePointer<CChar>?,
    _ temperature: Double,
    _ maxTokens: Int32,
    _ outText: UnsafeMutablePointer<Unmanaged<CFString>?>,
    _ outErrorMessage: UnsafeMutablePointer<Unmanaged<CFString>?>
) -> Int32 {
    guard #available(macOS 15.0, *) else {
        let error = "Foundation models unavailable on this macOS build" as NSString
        outErrorMessage.pointee = Unmanaged.passRetained(error)
        outText.pointee = nil
        return -100
    }

    let prompt = String(cString: promptPtr)
    let systemPrompt = systemPromptPtr.flatMap { String(cString: $0) }

    do {
        let output = try FoundationModelBridge.shared.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: Int(maxTokens)
        )
        outText.pointee = Unmanaged.passRetained(output as NSString)
        outErrorMessage.pointee = nil
        return 0
    } catch {
        let message = (error as NSError).localizedDescription as NSString
        outText.pointee = nil
        outErrorMessage.pointee = Unmanaged.passRetained(message)
        let nsError = error as NSError
        return nsError.code == 0 ? -1 : Int32(nsError.code)
    }
}
