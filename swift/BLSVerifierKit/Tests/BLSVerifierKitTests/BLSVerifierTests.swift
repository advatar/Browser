import Testing
import Foundation
import CBlst
@testable import BLSVerifierKit

struct BLSVerifierTests {
    /// Generates a key with blst, signs a message, and verifies it through BLSVerifier — proving
    /// the vendored BLS12-381 primitive performs real cryptographic verification end to end.
    private func makeKeyAndSignature(message: [UInt8], ikmByte: UInt8) -> (publicKey: Data, signature: Data) {
        let ikm = [UInt8](repeating: ikmByte, count: 32)
        var sk = blst_scalar()
        ikm.withUnsafeBufferPointer { blst_keygen(&sk, $0.baseAddress, ikm.count, nil, 0) }

        var pk = blst_p1()
        blst_sk_to_pk_in_g1(&pk, &sk)
        var pkCompressed = [UInt8](repeating: 0, count: 48)
        blst_p1_compress(&pkCompressed, &pk)

        let dst = Array(BLSVerifier.ethereumDST.utf8)
        var hash = blst_p2()
        message.withUnsafeBufferPointer { msg in
            dst.withUnsafeBufferPointer { d in
                blst_hash_to_g2(&hash, msg.baseAddress, message.count, d.baseAddress, dst.count, nil, 0)
            }
        }
        var sig = blst_p2()
        blst_sign_pk_in_g1(&sig, &hash, &sk)
        var sigCompressed = [UInt8](repeating: 0, count: 96)
        blst_p2_compress(&sigCompressed, &sig)

        return (Data(pkCompressed), Data(sigCompressed))
    }

    @Test func verifiesGenuineSignatureAndRejectsTampering() {
        let message = Array("dbrowser-bls-signing-root".utf8)
        let signer = makeKeyAndSignature(message: message, ikmByte: 0x11)

        // A genuine signature verifies.
        #expect(BLSVerifier.verify(publicKey: signer.publicKey, message: Data(message), signature: signer.signature))

        // A different message does not.
        #expect(BLSVerifier.verify(publicKey: signer.publicKey, message: Data("tampered".utf8), signature: signer.signature) == false)

        // A different signer's key does not verify this signature.
        let other = makeKeyAndSignature(message: message, ikmByte: 0x22)
        #expect(BLSVerifier.verify(publicKey: other.publicKey, message: Data(message), signature: signer.signature) == false)

        // Malformed inputs are rejected, not crashed on.
        #expect(BLSVerifier.fastAggregateVerify(publicKeys: [], message: Data(message), signature: signer.signature) == false)
        #expect(BLSVerifier.verify(publicKey: Data([0x00]), message: Data(message), signature: signer.signature) == false)
    }

    @Test func aggregatesMultipleSignersOverSameMessage() {
        // FastAggregateVerify over two signers of the same message: aggregate the two signatures
        // (point addition in G2) and verify against both public keys.
        let message = Array("dbrowser-aggregate-root".utf8)
        let a = makeKeyAndSignature(message: message, ikmByte: 0x31)
        let b = makeKeyAndSignature(message: message, ikmByte: 0x41)

        var sigA = blst_p2_affine()
        var sigB = blst_p2_affine()
        _ = a.signature.withUnsafeBytes { blst_p2_uncompress(&sigA, $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
        _ = b.signature.withUnsafeBytes { blst_p2_uncompress(&sigB, $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
        var aggregate = blst_p2()
        blst_p2_from_affine(&aggregate, &sigA)
        var aggregateSum = blst_p2()
        blst_p2_add_or_double_affine(&aggregateSum, &aggregate, &sigB)
        aggregate = aggregateSum
        var aggregateCompressed = [UInt8](repeating: 0, count: 96)
        blst_p2_compress(&aggregateCompressed, &aggregate)

        #expect(BLSVerifier.fastAggregateVerify(
            publicKeys: [a.publicKey, b.publicKey],
            message: Data(message),
            signature: Data(aggregateCompressed)
        ))
        // Missing one of the signers' keys breaks the aggregate verification.
        #expect(BLSVerifier.fastAggregateVerify(
            publicKeys: [a.publicKey],
            message: Data(message),
            signature: Data(aggregateCompressed)
        ) == false)
    }
}
