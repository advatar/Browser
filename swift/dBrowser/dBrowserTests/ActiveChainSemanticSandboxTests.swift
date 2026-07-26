import Foundation
import Testing
@testable import dBrowser

@MainActor
struct ActiveChainSemanticSandboxTests {
    private let reviewedRevision = "2befc06bcd1693dffe9a60cd103d6d9139a710b8"
    private let digest = String(repeating: "a", count: 96)

    private let vectorText = """
    vector=principal-v1
    type_tag=0x0001
    schema_version=1
    envelope_hex=0001000104aabbccdd
    """
    @Test
    func currentConfigurationIsPinnedToTheReviewedActiveChainRevision() throws {
        let sandbox = try ActiveChainSemanticSandbox()
        #expect(sandbox.configuration.sourceRevision == reviewedRevision)
        #expect(sandbox.configuration.walletABIRevision == 2)
        #expect(sandbox.configuration.verifierABIRevision == 1)
        #expect(sandbox.configuration.rpcSchemaRevision == 1)
        #expect(sandbox.configuration.lightClientSchemaRevision == 1)
        #expect(sandbox.configuration.productionCertified == false)
        #expect(sandbox.configuration.independentlyAudited == false)
        #expect(sandbox.configuration.artifactLinked == false)
        #expect(sandbox.configuration.protocolVersion == "activechain-v1-dev")
        #expect(sandbox.configuration.vectors.contains("credential-v1"))
        #expect(sandbox.configuration.vectors.contains("light-client-v1"))
        #expect(sandbox.configuration.vectorSourceSHA256["dbrowser-verifier-sdk-v1"] == "434b39f4579af807e69fffb1e439d13c83bb93580576bff72b7f48142fc17340")
    }

    @Test
    func simulationReportsFixtureProvenanceAndNoFinality() throws {
        let result = try ActiveChainSemanticSandbox().simulate(vectorID: "state-tree-v1")
        #expect(result.provenance == .developmentFixture)
        #expect(result.finalityClaim == "No network finality")
        #expect(result.sourceRevision == reviewedRevision)
    }

    @Test
    func unknownVectorsAndRevisionMismatchesFailClosed() {
        #expect(throws: ActiveChainSandboxError.unknownVector("missing")) {
            try ActiveChainSemanticSandbox().simulate(vectorID: "missing")
        }

        let changed = ActiveChainSandboxConfiguration(
            protocolVersion: "activechain-v1-dev",
            sourceRevision: "different-revision",
            vectors: ["principal-v1"]
        )
        #expect(throws: ActiveChainSandboxError.unsupportedRevision) {
            try ActiveChainSemanticSandbox(configuration: changed)
        }
    }

    @Test
    func unsupportedWalletABIAndProductionCertificationFailClosed() {
        let unsupportedABI = ActiveChainSandboxConfiguration(
            protocolVersion: "activechain-v1-dev",
            sourceRevision: reviewedRevision,
            vectors: ["principal-v1"],
            walletABIRevision: 1
        )
        #expect(throws: ActiveChainSandboxError.unsupportedWalletABIRevision(1)) {
            try ActiveChainSemanticSandbox(configuration: unsupportedABI)
        }

        let productionCertified = ActiveChainSandboxConfiguration(
            protocolVersion: "activechain-v1-dev",
            sourceRevision: reviewedRevision,
            vectors: ["principal-v1"],
            productionCertified: true
        )
        #expect(throws: ActiveChainSandboxError.productionCertificationUnsupported) {
            try ActiveChainSemanticSandbox(configuration: productionCertified)
        }
    }

    @Test
    func onlyVerificationAndSimulationCapabilitiesAreAllowed() throws {
        let sandbox = try ActiveChainSemanticSandbox()
        try sandbox.request(.canonicalVerification)
        try sandbox.request(.semanticSimulation)

        for capability in ActiveChainSandboxCapability.allCases where !capability.isAllowed {
            #expect(throws: ActiveChainSandboxError.capabilityDenied(capability)) {
                try sandbox.request(capability)
            }
        }
    }

    @Test
    func walletSigningNodeOperationAndNetworkIngressRemainDenied() throws {
        let sandbox = try ActiveChainSemanticSandbox()
        let deniedCapabilities: [ActiveChainSandboxCapability] = [
            .sign,
            .spend,
            .broadcast,
            .nodeStartup,
            .peerService,
            .networkIngress
        ]

        for capability in deniedCapabilities {
            #expect(throws: ActiveChainSandboxError.capabilityDenied(capability)) {
                try sandbox.request(capability)
            }
        }
    }

    @Test
    func runtimeSummaryExposesPinnedDevelopmentProvenanceWithoutFinality() {
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("activechain-v1-dev"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains(reviewedRevision))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("wallet ABI v2"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("verifier ABI/schema v1/v1"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("RPC/light-client schema v1/v1"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("artifact linked: false"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("independently audited: false"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("development-only"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("production certified: false"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("no network finality"))
        #expect(ActiveChainSemanticSandbox.verifierStatus.contains("fail-closed"))
    }

    @Test
    func canonicalVectorVerifierAcceptsExactEnvelope() throws {
        let verifier = ActiveChainCanonicalVectorVerifier(configuration: .current)
        let vector = try verifier.verify(vectorText, expectedVectorID: "principal-v1")
        #expect(vector.envelope.count == 9)
    }

    @Test
    func canonicalVectorVerifierRejectsMalformedTamperedVersionAndTrailingBytes() {
        let verifier = ActiveChainCanonicalVectorVerifier(configuration: .current)
        #expect(throws: ActiveChainVectorError.invalidHex) {
            try verifier.verify(vectorText.replacing("aabbccdd", with: "aabbc"), expectedVectorID: "principal-v1")
        }
        let wrongVersion = vectorText.replacing("00010001", with: "00010002")
        #expect(throws: ActiveChainVectorError.unsupportedVersion) {
            try verifier.verify(wrongVersion, expectedVectorID: "principal-v1")
        }
        let trailing = vectorText.replacing("aabbccdd", with: "aabbccddee")
        #expect(throws: ActiveChainVectorError.trailingBytes) {
            try verifier.verify(trailing, expectedVectorID: "principal-v1")
        }
        let hashed = ActiveChainSandboxConfiguration(protocolVersion: "activechain-v1-dev", sourceRevision: reviewedRevision, vectors: ["principal-v1"], vectorSHA256: ["principal-v1": String(repeating: "0", count: 64)])
        #expect(throws: ActiveChainVectorError.hashMismatch) {
            try ActiveChainCanonicalVectorVerifier(configuration: hashed).verify(vectorText, expectedVectorID: "principal-v1")
        }
    }

    @Test
    func downstreamCompatibilityManifestAcceptsOnlyTheReviewedContract() throws {
        let manifest = compatibleManifest()
        try ActiveChainCompatibilityPolicy().validateMetadata(manifest)

        let oldWalletABI = replacing(manifest, walletABIRevision: 1)
        #expect(throws: ActiveChainCompatibilityError.unsupportedWalletABI(1)) {
            try ActiveChainCompatibilityPolicy().validateMetadata(oldWalletABI)
        }

        let claimedAudit = replacing(manifest, independentlyAudited: true)
        #expect(throws: ActiveChainCompatibilityError.auditClaimUnsupported) {
            try ActiveChainCompatibilityPolicy().validateMetadata(claimedAudit)
        }

        let unsortedArtifacts = replacing(
            manifest,
            artifacts: [
                .init(path: "z", sha256: String(repeating: "b", count: 64)),
                .init(path: "a", sha256: String(repeating: "a", count: 64))
            ]
        )
        #expect(throws: ActiveChainCompatibilityError.invalidArtifacts) {
            try ActiveChainCompatibilityPolicy().validateMetadata(unsortedArtifacts)
        }
    }

    @Test
    func developmentRPCStatusRequiresFreshExactProofBearingIdentity() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let status = ActiveChainDevelopmentRPCStatus(
            chainID: digest,
            genesisCommitment: digest,
            protocolRevision: 1,
            finalizedHeight: 42,
            finalizedBlockHash: digest,
            finalizedAt: now.addingTimeInterval(-10),
            healthy: true,
            supportedProofProfiles: ["finality", "state-membership"],
            verifierRevision: 1
        )
        let policy = ActiveChainDevelopmentRPCPolicy(
            expectedChainID: digest,
            expectedGenesis: digest,
            maximumStaleness: 30
        )
        try policy.validate(status, now: now)

        let stale = replacing(status, finalizedAt: now.addingTimeInterval(-31))
        #expect(throws: ActiveChainDevelopmentRPCError.stale) {
            try policy.validate(stale, now: now)
        }
        let noProofs = replacing(status, supportedProofProfiles: [])
        #expect(throws: ActiveChainDevelopmentRPCError.invalidProofProfiles) {
            try policy.validate(noProofs, now: now)
        }
    }

    @Test
    func verifierOutcomeNeverPromotesInvalidUnavailableOrWrongNetworkEvidence() {
        let verified = ActiveChainVerifierOutcome(
            disposition: .verified,
            chainID: digest,
            genesisCommitment: digest,
            protocolRevision: 1,
            verifierRevision: 1,
            finalizedHeight: 42,
            verifiedCommitment: digest
        )
        #expect(verified.isAccepted(expectedChainID: digest, expectedGenesis: digest))

        for disposition in [ActiveChainVerifierDisposition.invalid, .unsupported, .unavailable] {
            let rejected = ActiveChainVerifierOutcome(
                disposition: disposition,
                chainID: digest,
                genesisCommitment: digest,
                protocolRevision: 1,
                verifierRevision: 1,
                finalizedHeight: 42,
                verifiedCommitment: digest
            )
            #expect(!rejected.isAccepted(expectedChainID: digest, expectedGenesis: digest))
        }
        #expect(!verified.isAccepted(expectedChainID: String(repeating: "b", count: 96), expectedGenesis: digest))
    }

    private func compatibleManifest() -> ActiveChainCompatibilityManifest {
        ActiveChainCompatibilityManifest(
            format: "activechain-apple-compatibility-v1",
            sourceRevision: reviewedRevision,
            releaseStatus: "developmental-unaudited",
            independentlyAudited: false,
            verifierABIRevision: 1,
            verifierSchemaRevision: 1,
            walletABIRevision: 2,
            rpcSchemaRevision: 1,
            lightClientSchemaRevision: 1,
            minimumProtocolRevision: 1,
            supportedProtocolRevisions: [1],
            schemas: ActiveChainCompatibilityPolicy.expectedSchemas,
            appleSlices: ActiveChainCompatibilityPolicy.expectedAppleSlices,
            upgradePolicy: "reject-unknown-abi-schema-or-protocol-revision",
            artifacts: [.init(path: "ActiveChainVerifier.xcframework/Info.plist", sha256: String(repeating: "a", count: 64))]
        )
    }

    private func replacing(
        _ manifest: ActiveChainCompatibilityManifest,
        walletABIRevision: UInt32? = nil,
        independentlyAudited: Bool? = nil,
        artifacts: [ActiveChainCompatibilityArtifact]? = nil
    ) -> ActiveChainCompatibilityManifest {
        ActiveChainCompatibilityManifest(
            format: manifest.format,
            sourceRevision: manifest.sourceRevision,
            releaseStatus: manifest.releaseStatus,
            independentlyAudited: independentlyAudited ?? manifest.independentlyAudited,
            verifierABIRevision: manifest.verifierABIRevision,
            verifierSchemaRevision: manifest.verifierSchemaRevision,
            walletABIRevision: walletABIRevision ?? manifest.walletABIRevision,
            rpcSchemaRevision: manifest.rpcSchemaRevision,
            lightClientSchemaRevision: manifest.lightClientSchemaRevision,
            minimumProtocolRevision: manifest.minimumProtocolRevision,
            supportedProtocolRevisions: manifest.supportedProtocolRevisions,
            schemas: manifest.schemas,
            appleSlices: manifest.appleSlices,
            upgradePolicy: manifest.upgradePolicy,
            artifacts: artifacts ?? manifest.artifacts
        )
    }

    private func replacing(
        _ status: ActiveChainDevelopmentRPCStatus,
        finalizedAt: Date? = nil,
        supportedProofProfiles: [String]? = nil
    ) -> ActiveChainDevelopmentRPCStatus {
        ActiveChainDevelopmentRPCStatus(
            chainID: status.chainID,
            genesisCommitment: status.genesisCommitment,
            protocolRevision: status.protocolRevision,
            finalizedHeight: status.finalizedHeight,
            finalizedBlockHash: status.finalizedBlockHash,
            finalizedAt: finalizedAt ?? status.finalizedAt,
            healthy: status.healthy,
            supportedProofProfiles: supportedProofProfiles ?? status.supportedProofProfiles,
            verifierRevision: status.verifierRevision
        )
    }
}
