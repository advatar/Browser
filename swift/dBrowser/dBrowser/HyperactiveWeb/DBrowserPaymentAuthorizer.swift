import Foundation
import UniversalInteractionKit

/// Authorizes 402-gated capabilities for dBrowser. It defers to a manual payment
/// surface (returns nil) so the user authorizes explicitly; wiring auto-payment
/// to `AgenticPayments` / Stripe MPP / Shared Payment Tokens within the wallet's
/// spend limits is the next step of slice 6 (#149).
struct DBrowserPaymentAuthorizer: PaymentAuthorizer {
    func authorize(_ requirements: PaymentRequirements, context: AdapterInvocationContext) async throws -> PaymentAuthorization? {
        return nil
    }
}
