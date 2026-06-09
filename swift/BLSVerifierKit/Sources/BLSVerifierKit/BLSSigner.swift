import Foundation
import CBlst

/// BLS12-381 key generation, signing, and signature aggregation (minimal-pubkey-size). Useful for
/// development, test-vector generation, and any local signing flow. Verification of untrusted
/// signatures should go through `BLSVerifier`.
public enum BLSSigner {
    public struct KeyPair: Equatable {
        /// 48-byte compressed G1 public key.
        public let publicKey: Data
        /// 32-byte IKM seed used to derive the secret key (kept so the holder can re-sign).
        public let seed: Data
    }

    /// Derives a deterministic key pair from input key material (>= 32 bytes recommended).
    public static func keyPair(ikm: Data) -> KeyPair {
        let ikmBytes = Array(ikm)
        var sk = blst_scalar()
        ikmBytes.withUnsafeBufferPointer { blst_keygen(&sk, $0.baseAddress, ikmBytes.count, nil, 0) }
        var pk = blst_p1()
        blst_sk_to_pk_in_g1(&pk, &sk)
        var compressed = [UInt8](repeating: 0, count: 48)
        blst_p1_compress(&compressed, &pk)
        return KeyPair(publicKey: Data(compressed), seed: ikm)
    }

    /// Signs `message` with the key derived from `ikm`, returning a 96-byte compressed G2 signature.
    public static func sign(message: Data, ikm: Data, dst: String = BLSVerifier.ethereumDST) -> Data {
        let ikmBytes = Array(ikm)
        var sk = blst_scalar()
        ikmBytes.withUnsafeBufferPointer { blst_keygen(&sk, $0.baseAddress, ikmBytes.count, nil, 0) }

        let messageBytes = Array(message)
        let dstBytes = Array(dst.utf8)
        var hash = blst_p2()
        messageBytes.withUnsafeBufferPointer { msg in
            dstBytes.withUnsafeBufferPointer { d in
                blst_hash_to_g2(&hash, msg.baseAddress, messageBytes.count, d.baseAddress, dstBytes.count, nil, 0)
            }
        }
        var signature = blst_p2()
        blst_sign_pk_in_g1(&signature, &hash, &sk)
        var compressed = [UInt8](repeating: 0, count: 96)
        blst_p2_compress(&compressed, &signature)
        return Data(compressed)
    }

    /// Aggregates compressed G2 signatures (point addition). Returns nil on any malformed input.
    public static func aggregate(signatures: [Data]) -> Data? {
        guard !signatures.isEmpty else { return nil }
        var aggregate = blst_p2()
        var haveAggregate = false
        for signatureData in signatures {
            guard signatureData.count == 96 else { return nil }
            var affine = blst_p2_affine()
            let decoded = signatureData.withUnsafeBytes { raw in
                raw.baseAddress.map { blst_p2_uncompress(&affine, $0.assumingMemoryBound(to: UInt8.self)) }
            }
            guard decoded == BLST_SUCCESS else { return nil }
            if haveAggregate {
                var sum = blst_p2()
                blst_p2_add_or_double_affine(&sum, &aggregate, &affine)
                aggregate = sum
            } else {
                blst_p2_from_affine(&aggregate, &affine)
                haveAggregate = true
            }
        }
        var compressed = [UInt8](repeating: 0, count: 96)
        blst_p2_compress(&compressed, &aggregate)
        return Data(compressed)
    }
}
