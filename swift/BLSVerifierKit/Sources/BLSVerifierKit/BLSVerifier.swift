import Foundation
import CBlst

/// Real BLS12-381 signature verification (minimal-pubkey-size: public keys in G1, signatures in
/// G2), backed by the vendored, audited blst library. This is the primitive Ethereum sync-committee
/// verification needs, performed locally rather than trusting a remote service's claim.
public enum BLSVerifier {
    /// Ethereum proof-of-possession DST for minimal-pubkey-size signatures.
    public static let ethereumDST = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"

    /// FastAggregateVerify: every signer signed the *same* message. Aggregates the 48-byte
    /// compressed G1 public keys and verifies the 96-byte compressed G2 aggregate signature.
    /// Returns false on any malformed input or signature mismatch.
    public static func fastAggregateVerify(
        publicKeys: [Data],
        message: Data,
        signature: Data,
        dst: String = ethereumDST
    ) -> Bool {
        guard !publicKeys.isEmpty, signature.count == 96 else { return false }

        var aggregate = blst_p1()
        var haveAggregate = false
        for keyData in publicKeys {
            guard keyData.count == 48 else { return false }
            var affine = blst_p1_affine()
            let decoded = keyData.withUnsafeBytes { raw in
                raw.baseAddress.map { blst_p1_uncompress(&affine, $0.assumingMemoryBound(to: UInt8.self)) }
            }
            guard decoded == BLST_SUCCESS else { return false }
            if haveAggregate {
                var sum = blst_p1()
                blst_p1_add_or_double_affine(&sum, &aggregate, &affine)
                aggregate = sum
            } else {
                blst_p1_from_affine(&aggregate, &affine)
                haveAggregate = true
            }
        }
        var aggregateAffine = blst_p1_affine()
        blst_p1_to_affine(&aggregateAffine, &aggregate)

        var signatureAffine = blst_p2_affine()
        let sigDecoded = signature.withUnsafeBytes { raw in
            raw.baseAddress.map { blst_p2_uncompress(&signatureAffine, $0.assumingMemoryBound(to: UInt8.self)) }
        }
        guard sigDecoded == BLST_SUCCESS else { return false }

        let dstBytes = Array(dst.utf8)
        let messageBytes = Array(message)
        let result = messageBytes.withUnsafeBufferPointer { msg in
            dstBytes.withUnsafeBufferPointer { d in
                blst_core_verify_pk_in_g1(
                    &aggregateAffine,
                    &signatureAffine,
                    true, // hash-to-curve (random oracle), per the Ethereum suite
                    msg.baseAddress, messageBytes.count,
                    d.baseAddress, dstBytes.count,
                    nil, 0
                )
            }
        }
        return result == BLST_SUCCESS
    }

    /// Verifies a single public key's signature over a message.
    public static func verify(publicKey: Data, message: Data, signature: Data, dst: String = ethereumDST) -> Bool {
        fastAggregateVerify(publicKeys: [publicKey], message: message, signature: signature, dst: dst)
    }
}
