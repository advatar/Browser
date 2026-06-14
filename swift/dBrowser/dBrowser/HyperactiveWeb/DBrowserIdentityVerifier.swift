import Foundation
import UniversalInteractionKit

/// Verifies a service's declared identity before dBrowser trusts its
/// capabilities. DNS-ID names are checked against a DNS TXT record (the
/// draft-ihsanullah-dnsid anchor); the node-key shim is accepted locally until
/// DNS-ID is universal. Sits alongside dBrowser's existing chain-trust
/// verifiers. Slice 7 of #149.
struct DBrowserIdentityVerifier: NodeIdentityVerifier {
    func verify(_ identity: NodeIdentity) async -> Bool {
        switch identity.scheme {
        case .nodeKey:
            return !identity.id.isEmpty
        case .dnsID:
            return await Self.hasTXTRecord(identity.id)
        }
    }

    /// Best-effort DNS TXT lookup via the system resolver.
    private static func hasTXTRecord(_ name: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
            process.arguments = ["+short", "TXT", name]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
