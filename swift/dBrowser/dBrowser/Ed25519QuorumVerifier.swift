import Foundation
import CryptoKit

/// Shared real Ed25519 signature verification used by the chain light clients (Substrate GRANDPA,
/// Tron, XRPL, Move, Avalanche) to count only cryptographically-verified quorum signers instead of
/// trusting a `signed` flag. Public keys are hex (32-byte Ed25519), signatures base64.
enum Ed25519QuorumVerifier {
    static func decodeHex(_ hex: String) -> Data? {
        var normalized = hex.lowercased()
        if normalized.hasPrefix("0x") { normalized.removeFirst(2) }
        guard normalized.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    /// True when `signatureBase64` is a valid Ed25519 signature over `message` by `publicKeyHex`.
    static func isValidSignature(signatureBase64: String?, publicKeyHex: String, message: Data) -> Bool {
        guard
            let signatureBase64,
            let signature = Data(base64Encoded: signatureBase64),
            let publicKeyData = decodeHex(publicKeyHex),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        else { return false }
        return publicKey.isValidSignature(signature, for: message)
    }
}
