import Foundation
import UniversalInteractionKit

/// Authorizes 402-gated capabilities for dBrowser. The background authorizer declines by default;
/// `BrowserViewModel` injects the wallet approval path so x402 spends produce policy receipts
/// through the same user-approved flow as direct wallet actions.
struct DBrowserPaymentAuthorizer: PaymentAuthorizer {
    func authorize(_ requirements: PaymentRequirements, context: AdapterInvocationContext) async throws -> PaymentAuthorization? {
        return nil
    }
}
