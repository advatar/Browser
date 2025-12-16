import Foundation

public struct AFMRunRequest: Codable {
    public let modelIdentifier: String
    public let prompt: String
    public let temperature: Double

    public init(modelIdentifier: String, prompt: String, temperature: Double = 0.2) {
        self.modelIdentifier = modelIdentifier
        self.prompt = prompt
        self.temperature = temperature
    }
}

public struct AFMRunResponse: Codable {
    public let output: String
    public let emittedAt: Date
}

public enum AFMRunnerError: Error {
    case runtimeUnavailable(String)
}

public final class AFMRunner {
    public static let shared = AFMRunner()

    private init() {}

    public func runModel(_ request: AFMRunRequest) throws -> AFMRunResponse {
        // The real implementation will invoke the Apple Foundation Model runtime
        // and return the attested output. For now we keep a deterministic stub so
        // the Rust FFI layer has something to talk to during integration.
        let echoed = "[afm-runner] \(request.modelIdentifier): \(request.prompt)"
        return AFMRunResponse(output: echoed, emittedAt: Date())
    }
}

@_cdecl("afm_runner_run_model")
public func afm_runner_run_model(_ prompt: UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    guard let prompt else { return nil }
    let request = AFMRunRequest(modelIdentifier: "foundation-stub", prompt: String(cString: prompt))
    guard let output = try? AFMRunner.shared.runModel(request).output else { return nil }
    return strdup(output)
}
