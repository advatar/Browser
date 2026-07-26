import Foundation
import UniversalInteractionKit
import dnssd

protocol DNSIDTXTResolving: Sendable {
    func hasTXTRecord(for name: String) async -> Bool
}

/// Resolves DNS-ID anchors with Apple's in-process DNS-SD resolver. This is
/// available on iOS and avoids relying on desktop-only tools such as `dig`.
struct SystemDNSIDTXTResolver: DNSIDTXTResolving {
    func hasTXTRecord(for name: String) async -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.utf8.count <= 253 else {
            return false
        }

        return await withCheckedContinuation { continuation in
            let context = DNSIDQueryContext(continuation: continuation)
            let retainedContext = Unmanaged.passRetained(context)
            var serviceRef: DNSServiceRef?
            let result = DNSServiceQueryRecord(
                &serviceRef,
                0,
                0,
                normalizedName,
                UInt16(kDNSServiceType_TXT),
                UInt16(kDNSServiceClass_IN),
                dnsIDQueryCallback,
                retainedContext.toOpaque()
            )

            guard result == kDNSServiceErr_NoError, let serviceRef else {
                retainedContext.release()
                continuation.resume(returning: false)
                return
            }

            context.attach(serviceRef)
            DNSServiceSetDispatchQueue(serviceRef, DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                if context.complete(false) {
                    retainedContext.release()
                }
            }
        }
    }
}

private final class DNSIDQueryContext: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var continuation: CheckedContinuation<Bool, Never>?
    private nonisolated(unsafe) var serviceRef: DNSServiceRef?

    nonisolated init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    nonisolated func attach(_ serviceRef: DNSServiceRef) {
        lock.lock()
        self.serviceRef = serviceRef
        lock.unlock()
    }

    /// Returns true only for the caller that completed and released the query.
    nonisolated func complete(_ result: Bool) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        let serviceRef = self.serviceRef
        self.serviceRef = nil
        lock.unlock()

        if let serviceRef {
            DNSServiceRefDeallocate(serviceRef)
        }
        continuation.resume(returning: result)
        return true
    }
}

private let dnsIDQueryCallback: DNSServiceQueryRecordReply = {
    _, _, _, errorCode, _, rrtype, _, _, _, _, rawContext in
    guard let rawContext else { return }
    let context = Unmanaged<DNSIDQueryContext>.fromOpaque(rawContext).takeUnretainedValue()
    let foundTXTRecord = errorCode == kDNSServiceErr_NoError && rrtype == UInt16(kDNSServiceType_TXT)
    if context.complete(foundTXTRecord) {
        Unmanaged<DNSIDQueryContext>.fromOpaque(rawContext).release()
    }
}

/// Verifies a service's declared identity before dBrowser trusts its
/// capabilities. DNS-ID names are checked against a DNS TXT record (the
/// draft-ihsanullah-dnsid anchor); the node-key shim is accepted locally until
/// DNS-ID is universal. Sits alongside dBrowser's existing chain-trust
/// verifiers. Slice 7 of #149.
struct DBrowserIdentityVerifier: NodeIdentityVerifier {
    private let dnsResolver: any DNSIDTXTResolving

    init(dnsResolver: any DNSIDTXTResolving = SystemDNSIDTXTResolver()) {
        self.dnsResolver = dnsResolver
    }

    func verify(_ identity: NodeIdentity) async -> Bool {
        switch identity.scheme {
        case .nodeKey:
            return !identity.id.isEmpty
        case .dnsID:
            return await dnsResolver.hasTXTRecord(for: identity.id)
        }
    }
}
