import Foundation
import UniversalInteractionKit

/// Maps the Hyperactive Web's risk model onto dBrowser's gate posture: read-safe
/// capabilities run; anything with side effects, payment, or credentials asks
/// first. The resolver then emits a confirmation surface that flows through
/// dBrowser's existing approval UI, and (per the retention invariant) an
/// approval artifact is retained before the action executes. Slice 3 of #149.
struct DBrowserPolicyKernel: PolicyKernel {
    func evaluate(_ capability: Capability, context: AdapterInvocationContext) async -> PolicyDecision {
        switch capability.risk {
        case .readOnly, .lowImpactWrite:
            if capability.authRequired && context.permissions.isEmpty {
                return PolicyDecision(verdict: .requireConfirmation, reason: "Capability needs an authorization scope.")
            }
            return PolicyDecision(verdict: .allow, reason: "Read-safe under dBrowser policy.")
        case .externalCommunication, .financialOrLegal, .credentialOrSecurity, .unknown:
            return PolicyDecision(verdict: .requireConfirmation, reason: "Side-effecting or sensitive — requires an approval gate.")
        }
    }
}
