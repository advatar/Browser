import Foundation

public struct AttestationToken: Codable {
    public let issuedAt: Date
    public let subject: String
    public let payload: Data

    public init(subject: String, payload: Data) {
        self.issuedAt = Date()
        self.subject = subject
        self.payload = payload
    }
}

public enum AttestationError: Error {
    case signerUnavailable
}

public final class AttestationSigner {
    public static let shared = AttestationSigner()
    private init() {}

    public func issue(subject: String, payload: Data) throws -> AttestationToken {
        // Placeholder until the native Apple APIs are wired in. The AFM node will
        // validate the resulting token via Rust FFI before relaying it to the
        // router/registry stack.
        guard !subject.isEmpty else {
            throw AttestationError.signerUnavailable
        }
        return AttestationToken(subject: subject, payload: payload)
    }
}
