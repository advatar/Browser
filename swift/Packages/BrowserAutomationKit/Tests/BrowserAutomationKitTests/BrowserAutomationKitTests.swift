import BrowserAutomationKit
import Foundation
import XCTest

final class BrowserAutomationKitTests: XCTestCase {
    func testTemplatesCoverDeveloperWorkflowCategoriesAndLocalEntryPoints() {
        let templates = BrowserDeveloperWorkflowTemplate.localFirstDefaults
        XCTAssertEqual(Set(templates.map(\.kind)), Set(BrowserDeveloperWorkflowKind.allCases))
        XCTAssertEqual(templates.count, 10)
        XCTAssertTrue(templates.allSatisfy { $0.entryPoints.contains(.mcp) })
        XCTAssertTrue(templates.allSatisfy { $0.entryPoints.contains(.localREPL) })

        let surfaces = BrowserDeveloperAutomationSurface.localFirstSurfaces(browserAutomationKitPackaged: true)
        XCTAssertEqual(surfaces.first { $0.id == .mcp }?.status, .ready)
        XCTAssertEqual(surfaces.first { $0.id == .localREPL }?.status, .ready)
        XCTAssertEqual(surfaces.first { $0.id == .mcp }?.privacyBoundary, .privateBrowserContext)
    }

    func testLedgerPersistsRunsAtExplicitLocalPath() throws {
        let fileURL = temporaryLedgerURL()
        let store = DeveloperWorkflowLedgerStore(fileURL: fileURL)
        let service = BrowserAutomationService(store: store)

        let run = try service.startRun(
            templateID: "failed-ci-triage",
            sourceURLString: "https://github.com/advatar/Browser/actions/runs/1"
        )

        let reloaded = try DeveloperWorkflowLedgerStore(fileURL: fileURL).load()
        XCTAssertEqual(reloaded.first?.id, run.id)
        XCTAssertEqual(reloaded.first?.entryPoint, .mcp)
        XCTAssertEqual(reloaded.first?.evidenceItems.first?.privacyBoundary, .privateBrowserContext)
    }

    func testCommandServiceAppendsEvidenceAndBlocksProtectedMutations() throws {
        let service = BrowserAutomationService(store: .ephemeral())
        let run = try service.startRun(templateID: "feature-flag-audit")
        let evidence = BrowserDeveloperEvidenceItem(
            kind: .dashboardSignal,
            title: "Rollout dashboard",
            summary: "Flag is at 25 percent for beta cohort.",
            externalURLString: "https://flags.example.local/demo",
            redactionState: .redacted,
            privacyBoundary: .externalReferenceOnly
        )

        let withEvidence = try service.appendEvidence(evidence, to: run.id)
        XCTAssertEqual(withEvidence.evidenceItems.last?.title, "Rollout dashboard")
        XCTAssertEqual(withEvidence.evidenceItems.last?.privacyBoundary, .externalReferenceOnly)

        let blocked = try service.proposeProtectedMutation(
            runID: run.id,
            action: .changeFeatureFlag,
            summary: "Increase beta rollout to 50 percent."
        )
        XCTAssertEqual(blocked.status, .waitingForApproval)
        XCTAssertTrue(blocked.approvalDecisions.contains { $0.action == .changeFeatureFlag })
        XCTAssertTrue(blocked.evidenceItems.contains { item in
            item.title.contains("Blocked protected action")
                && item.metadata["approvalRequired"] == "true"
                && item.privacyBoundary == .localOnly
        })
    }

    func testMCPConfigurationRejectsRemoteHostBindings() throws {
        XCTAssertNoThrow(try BrowserAutomationMCPServerConfiguration(host: "localhost"))
        XCTAssertNoThrow(try BrowserAutomationMCPServerConfiguration(host: "127.0.0.1"))
        XCTAssertNoThrow(try BrowserAutomationMCPServerConfiguration(host: "::1"))
        XCTAssertThrowsError(try BrowserAutomationMCPServerConfiguration(host: "0.0.0.0"))
        XCTAssertThrowsError(try BrowserAutomationMCPServerConfiguration(host: "192.168.1.9"))

        let descriptor = try BrowserAutomationMCPServerConfiguration().descriptor
        XCTAssertEqual(descriptor.binding, "localProcess")
        XCTAssertTrue(descriptor.methods.contains("browserAutomation/startRun"))
        XCTAssertTrue(descriptor.allowedHosts.contains("127.0.0.1"))
    }

    func testJSONRPCServerStartsRunsAndProposesMutations() throws {
        let service = BrowserAutomationService(store: .ephemeral())
        let server = BrowserAutomationMCPServer(service: service)

        let startResponse = server.handleJSONRPCLine(
            #"{"jsonrpc":"2.0","id":1,"method":"browserAutomation/startRun","params":{"templateID":"pr-evidence-packet","sourceURLString":"https://github.com/advatar/Browser/pull/1"}}"#
        )
        let startResult = try jsonResult(startResponse)
        let run = try XCTUnwrap((startResult["run"] as? [String: Any]))
        let runID = try XCTUnwrap(run["id"] as? String)
        XCTAssertEqual(run["status"] as? String, "running")
        XCTAssertEqual(run["entryPoint"] as? String, "mcp")

        let mutationResponse = server.handleJSONRPCLine(
            #"{"jsonrpc":"2.0","id":2,"method":"browserAutomation/proposeMutation","params":{"runID":""# + runID + #"","action":"postPRComment","summary":"Post reviewer summary."}}"#
        )
        let mutationResult = try jsonResult(mutationResponse)
        let updatedRun = try XCTUnwrap(mutationResult["run"] as? [String: Any])
        let evidence = try XCTUnwrap(updatedRun["evidenceItems"] as? [[String: Any]])
        XCTAssertEqual(updatedRun["status"] as? String, "waitingForApproval")
        XCTAssertTrue(evidence.contains { ($0["title"] as? String)?.contains("Blocked protected action") == true })
    }

    private func temporaryLedgerURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserAutomationKitTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("developer-workflow-runs.json")
    }

    private func jsonResult(_ line: String) throws -> [String: Any] {
        let data = try XCTUnwrap(line.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        if let error = object["error"] {
            XCTFail("Unexpected JSON-RPC error: \(error)")
        }
        return try XCTUnwrap(object["result"] as? [String: Any])
    }
}
