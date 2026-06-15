import Foundation
import UniversalInteractionKit

/// Maps the Hyperactive Web's 402 / MPP payment model onto dBrowser's existing
/// **X402** payment types (`X402PaymentRequirement` / `X402PaymentPayload`), so
/// 402-gated capabilities flow through dBrowser's wallet / AgenticPayments
/// approval path rather than a parallel implementation. Slice 6 of #149.
enum X402Bridge {
    /// UIK `PaymentRequirements` → dBrowser `X402PaymentRequirement`.
    static func requirement(from req: PaymentRequirements, resourceURLString: String) -> X402PaymentRequirement {
        X402PaymentRequirement(
            id: req.nonce ?? UUID().uuidString,
            resourceURLString: req.resource ?? resourceURLString,
            amountMinorUnits: minorUnits(req.price),
            asset: req.price.currency.uppercased(),
            network: req.metadata["network"]?.stringValue ?? "",
            payTo: req.payTo ?? "",
            facilitatorURLString: req.metadata["facilitator"]?.stringValue,
            expiresAt: req.expiresAt ?? Date(timeIntervalSinceNow: 300)
        )
    }

    /// A signed dBrowser `X402PaymentPayload` → UIK `PaymentAuthorization`
    /// (the proof the resolver retries the capability with).
    static func authorization(from payload: X402PaymentPayload, price: CapabilityPrice) -> PaymentAuthorization {
        PaymentAuthorization(
            scheme: "x402",
            rail: "x402",
            proof: payload.signatureReference.isEmpty ? (payload.transactionReference ?? "") : payload.signatureReference,
            amount: price,
            metadata: [
                "walletAccount": .string(payload.walletAccount),
                "requirementHash": .string(payload.requirementHash)
            ]
        )
    }

    /// Decimal-string amount (e.g. "0.02") → minor units (cents) for the asset.
    static func minorUnits(_ price: CapabilityPrice, decimals: Int = 2) -> Int {
        let scale = pow(10.0, Double(decimals))
        let value = Double(price.amount) ?? 0
        return Int((value * scale).rounded())
    }
}
