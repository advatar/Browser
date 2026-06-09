import Foundation
import BLSVerifierKit

/// Ethereum (Altair) sync-committee verification, performed locally with real BLS12-381
/// (`BLSVerifier`, backed by vendored blst) rather than trusting a remote service's claim. The
/// committee's aggregate signature over the signing root is verified against the participating
/// public keys, and a supermajority of participation is required.
///
/// Scope: this verifies the committee signature itself — the cryptographic core. Deriving the
/// signing root via exact SSZ `hash_tree_root` + `compute_domain` (genesis validators root, fork
/// version) is the remaining precision step; the root is taken as an input here.
struct EVMSyncCommitteeUpdate: Equatable {
    /// Compressed 48-byte G1 public keys of the full sync committee.
    var committeePublicKeys: [Data]
    /// Participation flags, one per committee member (true = this member signed).
    var participationBits: [Bool]
    /// The 32-byte signing root the committee signed (SSZ signing root of the attested header).
    var signingRoot: Data
    /// Compressed 96-byte G2 aggregate signature.
    var aggregateSignature: Data
}

enum EVMSyncCommitteeVerificationStatus: String, Codable, Equatable {
    case verified
    case insufficientParticipation
    case signatureInvalid
    case malformed
}

struct EVMSyncCommitteeVerificationResult: Equatable {
    var status: EVMSyncCommitteeVerificationStatus
    var participantCount: Int
    var committeeSize: Int
    var summary: String

    var verified: Bool { status == .verified }

    /// Local-proof trust when the committee signature verifies; otherwise gateway/RPC fallback.
    var chainTrustState: ChainTrustState {
        verified ? .proofChecked : .rpcFallback
    }
}

enum EVMSyncCommitteeVerifier {
    /// Verifies the sync-committee aggregate signature and that participation meets a supermajority
    /// (default two-thirds, as Ethereum requires for a trusted light-client update).
    static func verify(
        _ update: EVMSyncCommitteeUpdate,
        participationNumerator: Int = 2,
        participationDenominator: Int = 3
    ) -> EVMSyncCommitteeVerificationResult {
        let committeeSize = update.committeePublicKeys.count
        guard
            committeeSize > 0,
            update.participationBits.count == committeeSize,
            update.signingRoot.count == 32,
            update.aggregateSignature.count == 96
        else {
            return EVMSyncCommitteeVerificationResult(
                status: .malformed,
                participantCount: 0,
                committeeSize: committeeSize,
                summary: "Sync-committee update is malformed (size, bitfield, root, or signature length mismatch)."
            )
        }

        let participants = zip(update.committeePublicKeys, update.participationBits)
            .filter { $0.1 }
            .map { $0.0 }
        let participantCount = participants.count

        guard participantCount * participationDenominator >= committeeSize * participationNumerator else {
            return EVMSyncCommitteeVerificationResult(
                status: .insufficientParticipation,
                participantCount: participantCount,
                committeeSize: committeeSize,
                summary: "Sync-committee participation \(participantCount)/\(committeeSize) is below the required supermajority."
            )
        }

        let signatureValid = BLSVerifier.fastAggregateVerify(
            publicKeys: participants,
            message: update.signingRoot,
            signature: update.aggregateSignature
        )
        guard signatureValid else {
            return EVMSyncCommitteeVerificationResult(
                status: .signatureInvalid,
                participantCount: participantCount,
                committeeSize: committeeSize,
                summary: "Sync-committee aggregate BLS signature did not verify against the participating keys."
            )
        }

        return EVMSyncCommitteeVerificationResult(
            status: .verified,
            participantCount: participantCount,
            committeeSize: committeeSize,
            summary: "Sync-committee update verified: \(participantCount)/\(committeeSize) signed and the aggregate BLS signature is valid."
        )
    }
}

/// Builds real, BLS-signed sync-committee updates from deterministic seeds, for tests and local
/// development. Lives in the app module because only it links BLSVerifierKit (CBlst is internal to
/// the package), so the test target reaches this via `@testable import dBrowser`.
enum EVMSyncCommitteeTestSupport {
    static func signedUpdate(
        committeeSize: Int,
        signingRoot: Data,
        participation: Int
    ) -> EVMSyncCommitteeUpdate {
        var publicKeys: [Data] = []
        var bits: [Bool] = []
        var signatures: [Data] = []
        for index in 0..<committeeSize {
            let ikm = Data((0..<32).map { UInt8((index + $0) & 0xff) })
            publicKeys.append(BLSSigner.keyPair(ikm: ikm).publicKey)
            let signs = index < participation
            bits.append(signs)
            if signs {
                signatures.append(BLSSigner.sign(message: signingRoot, ikm: ikm))
            }
        }
        let aggregate = BLSSigner.aggregate(signatures: signatures) ?? Data(repeating: 0, count: 96)
        return EVMSyncCommitteeUpdate(
            committeePublicKeys: publicKeys,
            participationBits: bits,
            signingRoot: signingRoot,
            aggregateSignature: aggregate
        )
    }
}
