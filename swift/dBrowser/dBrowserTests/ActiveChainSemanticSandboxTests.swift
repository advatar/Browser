import Foundation
import Testing
@testable import dBrowser

@MainActor
struct ActiveChainSemanticSandboxTests {
    @Test
    func currentConfigurationIsPinnedToTheReviewedActiveChainRevision() throws {
        let sandbox = try ActiveChainSemanticSandbox()
        #expect(sandbox.configuration.sourceRevision == "cdb8478")
        #expect(sandbox.configuration.protocolVersion == "development-1")
        #expect(sandbox.configuration.vectors.contains("credential-v1"))
    }

    @Test
    func simulationReportsFixtureProvenanceAndNoFinality() throws {
        let result = try ActiveChainSemanticSandbox().simulate(vectorID: "state-tree-v1")
        #expect(result.provenance == .developmentFixture)
        #expect(result.finalityClaim == "No network finality")
        #expect(result.sourceRevision == "cdb8478")
    }

    @Test
    func unknownVectorsAndRevisionMismatchesFailClosed() {
        #expect(throws: ActiveChainSandboxError.unknownVector("missing")) {
            try ActiveChainSemanticSandbox().simulate(vectorID: "missing")
        }

        let changed = ActiveChainSandboxConfiguration(
            protocolVersion: "development-1",
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
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("development-1"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("cdb8478"))
        #expect(ActiveChainSemanticSandbox.runtimeSummary.contains("no network finality"))
    }
}
