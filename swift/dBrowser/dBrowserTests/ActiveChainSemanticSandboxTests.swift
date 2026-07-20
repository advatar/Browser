import Foundation
import Testing
@testable import dBrowser

@MainActor
struct ActiveChainSemanticSandboxTests {
    private let vectorText = """
    vector=principal-v1
    type_tag=0x0001
    schema_version=1
    envelope_hex=0001000104aabbccdd
    """
    @Test
    func currentConfigurationIsPinnedToTheReviewedActiveChainRevision() throws {
        let sandbox = try ActiveChainSemanticSandbox()
        #expect(sandbox.configuration.sourceRevision == "61922bf")
        #expect(sandbox.configuration.protocolVersion == "activechain-v1-dev")
        #expect(sandbox.configuration.vectors.contains("credential-v1"))
    }

    @Test
    func simulationReportsFixtureProvenanceAndNoFinality() throws {
        let result = try ActiveChainSemanticSandbox().simulate(vectorID: "state-tree-v1")
        #expect(result.provenance == .developmentFixture)
        #expect(result.finalityClaim == "No network finality")
        #expect(result.sourceRevision == "61922bf")
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
    func runtimeSummaryExposesPinnedDevelopmentProvenanceWithoutFinality() {
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("activechain-v1-dev"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("61922bf"))
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
        let hashed = ActiveChainSandboxConfiguration(protocolVersion: "activechain-v1-dev", sourceRevision: "61922bf", vectors: ["principal-v1"], vectorSHA256: ["principal-v1": String(repeating: "0", count: 64)])
        #expect(throws: ActiveChainVectorError.hashMismatch) {
            try ActiveChainCanonicalVectorVerifier(configuration: hashed).verify(vectorText, expectedVectorID: "principal-v1")
        }
    }
}
