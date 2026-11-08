#if os(iOS)
import XCTest
import Foundation
import SwiftUI
import UIKit
import WebKit
@testable import dBrowser

/// Hosted tests: no replacement WKWebView, copied JavaScript, or fabricated browser results.
/// Run each method with a fresh #211 fixture via run-native.mjs. Ordinary test runs skip
/// without explicit configuration; the qualification runner rejects skipped/zero tests.
@MainActor
final class NativeMobileBrowserTests: XCTestCase {
    private let brief = "Tuesday at 10:00 in Room Delta; please arrange an aisle seat and decaf coffee."

    func testNavigationAndAutosaveBeforeSubmit() async throws {
        let oracle = try FixtureOracle(expectedFault: nil)
        let host = try await mount(oracle, path: "/sources/one")
        defer { host.close() }
        let first = try await host.snapshot()
        XCTAssertTrue(first.visibleText.contains("10:00 on Tuesday"))
        XCTAssertTrue(first.visibleText.contains("Room Delta"))
        let heading = try await host.query("h1")
        XCTAssertEqual(heading.elements.first?.text, "Source A: workshop schedule")
        try await host.navigate(oracle.baseURL.appendingPathComponent("sources/two"))
        let second = try await host.snapshot()
        XCTAssertTrue(second.visibleText.contains("aisle seat"))
        XCTAssertTrue(second.visibleText.contains("decaf coffee"))
        try await host.navigate(oracle.baseURL.appendingPathComponent("drafts/alpha/draft-a"))
        try await host.waitForState("ready")

        let focus = try XCTUnwrap(host.model.requestDOMAction(.init(kind: .focus, selector: "#notes")))
        let focused = try await host.result(focus)
        XCTAssertEqual(focused.status, .success)
        let proposal = try host.propose("browser.type_text", ["selector": "#notes", "text": brief])
        let beforeApproval = try await oracle.read()
        XCTAssertTrue(beforeApproval.operations.isEmpty)
        let typed = try await host.approve(proposal)
        XCTAssertEqual(typed.status, .success) // Only the DOM call, not the provider outcome.
        try await host.waitForState("saved")
        let saved = try await oracle.read()
        XCTAssertEqual(saved.operations.count, 1)
        XCTAssertEqual(try saved.alpha.autosaveCount, 1)
        XCTAssertEqual(try saved.alpha.submissionCount, 0)
        XCTAssertFalse(try saved.alpha.submitted)
        XCTAssertEqual(try saved.alpha.notes, brief)
        let operationID = try await host.text("#operation")
        XCTAssertEqual(saved.operations.first?.operation.operationId, operationID)
        XCTAssertEqual(saved.operations.first?.operation.kind, "autosave")
        XCTAssertNil(host.model.approveToolProposal(proposal.id), "A consumed grant cannot dispatch twice")

        // The ordinary typed-action entry point still requires approval for submit.
        XCTAssertNil(host.model.requestDOMAction(.init(kind: .submit, selector: "#draft-form")))
        let stillSaved = try await oracle.read()
        XCTAssertEqual(stillSaved, saved)
        let submit = try host.propose("browser.submit", ["selector": "#draft-form"])
        _ = try await host.approve(submit)
        try await host.waitForState("submitted")
        let final = try await oracle.read()
        XCTAssertEqual(final.operations.map { $0.operation.kind }, ["autosave", "submit"])
        XCTAssertEqual(try final.alpha.revision, 2)
        XCTAssertEqual(try final.alpha.submissionCount, 1)
        XCTAssertTrue(try final.alpha.submitted)
        XCTAssertEqual(try final.alpha.notes, brief)
        XCTAssertEqual(final.operations.last?.operation.baseRevision, 1)
        try record(final, host: host)
    }

    func testStaleDocumentRefusal() async throws {
        let oracle = try FixtureOracle(expectedFault: nil)
        let stale = try await mount(oracle, path: "/drafts/alpha/draft-a")
        defer { stale.close() }
        let writer = try await mount(oracle, path: "/drafts/alpha/draft-a")
        defer { writer.close() }
        try await stale.waitForState("ready")
        try await writer.waitForState("ready")
        _ = try await writer.approve(writer.propose("browser.type_text", ["selector": "#notes", "text": brief]))
        try await writer.waitForState("saved")
        let committed = try await oracle.read()
        XCTAssertEqual(try committed.alpha.revision, 1)
        _ = try await stale.approve(stale.propose("browser.type_text", ["selector": "#notes", "text": "Stale writer"] ))
        try await stale.waitForState("refused")
        let refusedID = try await stale.text("#operation")
        let after = try await oracle.read()
        XCTAssertEqual(after, committed)
        XCTAssertFalse(after.operations.contains { $0.operation.operationId == refusedID })
        let locked = try await stale.query("#title:disabled, #notes:disabled, #submit-button:disabled")
        XCTAssertEqual(locked.elements.count, 3)
        try record(after, host: stale)
    }

    func testNavigationInvalidatesApprovalAndDispatch() async throws {
        let oracle = try FixtureOracle(expectedFault: nil)
        let host = try await mount(oracle, path: "/drafts/alpha/draft-a")
        defer { host.close() }
        try await host.waitForState("ready")
        _ = try await host.snapshot()
        let old = try host.propose("browser.type_text", ["selector": "#notes", "text": "Expired proposal"])
        let generation = host.model.navigationGeneration(for: try XCTUnwrap(host.model.activeTab).id)
        let finished = host.finishedNavigations
        host.model.reload() // Same URL must still invalidate the document generation.
        XCTAssertNil(host.model.latestPageSnapshot)
        try await host.waitForNavigation(after: finished)
        try await host.waitForState("ready")
        XCTAssertGreaterThan(host.model.navigationGeneration(for: try XCTUnwrap(host.model.activeTab).id), generation)
        XCTAssertNil(host.model.approveToolProposal(old.id))

        // Hold delivery, obtain a real one-time grant, then navigate before dispatch.
        host.delivery.hold = true
        let pending = try host.propose("browser.type_text", ["selector": "#notes", "text": "Must never be sent"])
        let request = try XCTUnwrap(host.model.approveToolProposal(pending.id))
        try await host.navigate(oracle.baseURL.appendingPathComponent("drafts/beta/draft-b"))
        try await host.waitForStateWhileHeld("ready")
        XCTAssertNil(host.model.approveToolProposal(pending.id))
        // Feed the captured request through the actual mounted representable. Its
        // coordinator must refuse the obsolete dispatch claim before evaluating JS.
        host.delivery.replay = request
        host.delivery.hold = false
        try await host.waitUntil("real coordinator observes stale request") {
            host.coordinator?.lastHandledAutomationID == request.id
        }
        XCTAssertFalse(host.coordinator?.ownedApprovedAutomationRequestIDs.contains(request.id) ?? true)
        host.delivery.replay = nil
        let unchanged = try await oracle.read()
        XCTAssertTrue(unchanged.operations.isEmpty)
        // A live dispatch claim alone is insufficient: the mounted coordinator
        // must also reject a request whose generation no longer matches its grant.
        host.delivery.hold = true
        let mismatched = try host.propose("browser.type_text", ["selector": "#notes", "text": "Wrong generation"])
        var changedRequest = try XCTUnwrap(host.model.approveToolProposal(mismatched.id))
        changedRequest.navigationGeneration &+= 1
        host.delivery.replay = changedRequest
        host.delivery.hold = false
        let refusal = try await host.result(changedRequest, expectedStatus: .failed)
        XCTAssertNotNil(refusal.approvedAutomationDispatchOwnerID)
        XCTAssertTrue(refusal.message.contains("no longer matches"))
        XCTAssertNil(host.model.approveToolProposal(mismatched.id))
        host.delivery.replay = nil
        let afterRefusal = try await oracle.read()
        XCTAssertTrue(afterRefusal.operations.isEmpty)
        // Positive control on the new document prevents an inert host passing the negative test.
        _ = try await host.approve(host.propose("browser.type_text", ["selector": "#notes", "text": "Current beta writer"]))
        try await host.waitForState("saved")
        let after = try await oracle.read()
        XCTAssertEqual(after.operations.count, 1)
        XCTAssertEqual(after.operations.first?.operation.accountId, "beta")
        XCTAssertEqual(after.operations.first?.operation.documentId, "draft-b")
        XCTAssertEqual(try after.alpha.revision, 0)
        try record(after, host: host)
    }

    func testLostAutosaveAcknowledgement() async throws {
        try await lostAcknowledgement(kind: "autosave")
    }

    func testLostSubmitAcknowledgement() async throws {
        try await lostAcknowledgement(kind: "submit")
    }

    private func lostAcknowledgement(kind: String) async throws {
        let oracle = try FixtureOracle(expectedFault: kind)
        let host = try await mount(oracle, path: "/drafts/alpha/draft-a")
        defer { host.close() }
        try await host.waitForState("ready")
        var proposal = try host.propose("browser.type_text", ["selector": "#notes", "text": brief])
        _ = try await host.approve(proposal)
        if kind == "submit" {
            try await host.waitForState("saved")
            proposal = try host.propose("browser.submit", ["selector": "#draft-form"])
            _ = try await host.approve(proposal)
        }
        try await host.waitForState("unknown")
        let originalID = try await host.text("#operation")
        XCTAssertNotEqual(originalID, "None")
        let authoritative = try await oracle.read()
        let committedEntry = try XCTUnwrap(authoritative.operations.first { $0.operation.operationId == originalID })
        XCTAssertEqual(committedEntry.operation.fixtureId, authoritative.fixtureId)
        XCTAssertEqual(committedEntry.operation.kind, kind)
        XCTAssertEqual(committedEntry.operation.accountId, "alpha")
        XCTAssertEqual(committedEntry.operation.documentId, "draft-a")
        XCTAssertEqual(committedEntry.operation.payload.notes, brief)
        XCTAssertEqual(committedEntry.receipt.status, "committed")
        XCTAssertEqual(committedEntry.receipt.operation, committedEntry.operation)
        XCTAssertEqual(committedEntry.operation.baseRevision, kind == "submit" ? 1 : 0)
        XCTAssertEqual(authoritative.operations.count, kind == "submit" ? 2 : 1)
        XCTAssertEqual(committedEntry.receipt.operationId, originalID)
        XCTAssertEqual(committedEntry.receipt.revision, committedEntry.operation.baseRevision + 1)
        XCTAssertEqual(try authoritative.alpha.autosaveCount, 1)
        XCTAssertEqual(try authoritative.alpha.submissionCount, kind == "submit" ? 1 : 0)
        XCTAssertEqual(authoritative.fault.droppedResponses, 1)
        XCTAssertNil(host.model.approveToolProposal(proposal.id))

        let finished = host.finishedNavigations
        host.model.reload()
        try await host.waitForNavigation(after: finished)
        try await host.waitForState("unknown")
        let retainedID = try await host.text("#operation")
        XCTAssertEqual(retainedID, originalID)
        let disabled = try await host.query("#title:disabled, #notes:disabled, #submit-button:disabled")
        XCTAssertEqual(disabled.elements.count, 3)
        // Deliberately attempt fresh native input/submit on the locked page. Even
        // programmatic events must not cause a fresh provider mutation or new ID.
        _ = try await host.approve(host.propose("browser.type_text", ["selector": "#notes", "text": "Unsafe retry probe"]))
        _ = try await host.approve(host.propose("browser.submit", ["selector": "#draft-form"]))
        // Observe longer than the fixture's 5s fetch timeout; repeated read-only
        // checks also give WebKit event/network work time to reveal redispatch.
        for _ in 0..<22 {
            try await Task.sleep(for: .milliseconds(250))
            let readback = try await oracle.read()
            XCTAssertEqual(readback, authoritative)
        }
        try await host.waitForState("unknown")
        let finalID = try await host.text("#operation")
        XCTAssertEqual(finalID, originalID)
        try record(authoritative, host: host)
    }

    private func mount(_ oracle: FixtureOracle, path: String) async throws -> NativeFixtureHost {
        let initial = try await oracle.read()
        XCTAssertTrue(initial.operations.isEmpty, "Each method requires a fresh fixture instance")
        let host = try NativeFixtureHost(url: oracle.baseURL.appendingPathComponent(String(path.dropFirst())))
        do {
            try await host.waitForNavigation(after: 0)
            return host
        } catch {
            host.close()
            throw error
        }
    }

    private func record(_ ledger: FixtureLedger, host: NativeFixtureHost) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(ledger), uniformTypeIdentifier: "public.json")
        attachment.name = "independent-fixture-ledger"
        attachment.lifetime = .keepAlways
        add(attachment)
        let platform = "\(UIDevice.current.model); \(UIDevice.current.systemName) \(UIDevice.current.systemVersion); \(ProcessInfo.processInfo.operatingSystemVersionString)"
        let events = XCTAttachment(string: platform + "\n" + host.events.joined(separator: "\n"))
        events.name = "native-platform-and-callbacks"
        events.lifetime = .keepAlways
        add(events)
    }
}

@MainActor
private final class NativeDelivery: ObservableObject {
    @Published var hold = false
    @Published var replay: BrowserAutomationRequest?
}

@MainActor
private struct NativeFixtureView: View {
    @ObservedObject var model: BrowserViewModel
    @ObservedObject var delivery: NativeDelivery
    let navigation: (BrowserNavigationUpdate) -> Void
    let result: (BrowserAutomationResult) -> Void

    var body: some View {
        ForEach($model.tabs) { $tab in
            BrowserWebView(
                tab: $tab,
                command: model.webCommand,
                adBlockingMode: model.adBlockingMode,
                automationRequest: delivery.hold ? nil : (delivery.replay ?? model.automationRequest),
                navigationGeneration: model.navigationGeneration(for: tab.id),
                onApprovedAutomationDispatch: model.claimApprovedAutomationDispatch,
                onNavigationUpdate: navigation,
                onAutomationResult: result
            )
        }
    }
}

@MainActor
private final class NativeFixtureHost {
    let model: BrowserViewModel
    let delivery = NativeDelivery()
    private let window: UIWindow
    private weak var previousKeyWindow: UIWindow?
    private let defaultsName = "NativeMobileBrowserTests.\(UUID().uuidString)"
    var finishedNavigations = 0
    var events: [String] = []
    private var results: [UUID: BrowserAutomationResult] = [:]

    var webView: WKWebView? { findWebView(window) }
    var coordinator: BrowserWebView.Coordinator? { webView?.navigationDelegate as? BrowserWebView.Coordinator }

    init(url: URL) throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            throw NativeFixtureFailure("No foreground UIWindowScene; keep the test app foregrounded")
        }
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        model = BrowserViewModel(
            initialURL: url.absoluteString,
            runtimeBridge: MobileRuntimeBridge(),
            copilotWorkflowStore: .ephemeral(), researchLedgerStore: .ephemeral(),
            developerWorkflowStore: .ephemeral(), smartHistoryStore: .ephemeral(),
            llmConversationStore: .ephemeral(),
            adBlockingDefaults: try XCTUnwrap(UserDefaults(suiteName: defaultsName)),
            adBlockingMode: .paused, automationRequestTimeoutSeconds: 10
        )
        window.rootViewController = UIHostingController(rootView: NativeFixtureView(
            model: model, delivery: delivery,
            navigation: { [weak self] update in
                guard let self else { return }
                self.model.applyNavigationUpdate(update)
                self.events.append("navigation loading=\(update.isLoading) url=\(update.urlString ?? "nil")")
                if !update.isLoading { self.finishedNavigations += 1 }
            },
            result: { [weak self] value in
                guard let self else { return }
                self.model.applyAutomationResult(value)
                self.results[value.requestID] = value
                self.events.append("automation id=\(value.requestID) status=\(value.status.rawValue)")
            }
        ))
        window.makeKeyAndVisible()
    }

    func close() {
        webView?.stopLoading()
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
    }

    private func findWebView(_ view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { findWebView($0) }.first
    }

    func waitUntil(_ description: String, predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw NativeFixtureFailure("Timed out: \(description)") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    func waitForNavigation(after count: Int) async throws {
        try await waitUntil("WebKit navigation completion") {
            self.finishedNavigations > count && self.webView?.isLoading == false && self.model.activeTab?.isLoading == false
        }
        XCTAssertNotNil(coordinator, "Must mount the production BrowserWebView coordinator")
    }

    func navigate(_ url: URL) async throws {
        let finished = finishedNavigations
        model.navigate(url.absoluteString)
        try await waitForNavigation(after: finished)
        XCTAssertEqual(webView?.url, url)
    }

    func result(_ request: BrowserAutomationRequest, expectedStatus: BrowserAutomationStatus = .success) async throws -> BrowserAutomationResult {
        try await waitUntil("real automation callback") { self.results[request.id] != nil }
        let result = try XCTUnwrap(results.removeValue(forKey: request.id))
        XCTAssertEqual(result.tabID, request.tabID)
        XCTAssertEqual(result.status, expectedStatus)
        return result
    }

    func query(_ selector: String) async throws -> DOMQueryResult {
        let request = try XCTUnwrap(model.requestDOMQuery(DOMQueryRequest(selector: selector)))
        let value = try await result(request)
        return try XCTUnwrap(value.domQuery)
    }

    func text(_ selector: String) async throws -> String {
        let value = try await query(selector)
        return try XCTUnwrap(value.elements.first?.text)
    }

    func snapshot() async throws -> PageSnapshot {
        let request = try XCTUnwrap(model.requestPageSnapshot())
        let value = try await result(request)
        let snapshot = try XCTUnwrap(value.pageSnapshot)
        XCTAssertEqual(model.latestPageSnapshot, snapshot)
        return snapshot
    }

    func waitForState(_ state: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        repeat {
            if try await query("#status[data-state='\(state)']").totalMatched == 1 { return }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        throw NativeFixtureFailure("Fixture did not reach expected state: \(state)")
    }

    func waitForStateWhileHeld(_ state: String) async throws {
        // No approved request remains live after navigation. Resume ordinary reads.
        delivery.hold = false
        try await waitForState(state)
        delivery.hold = true
    }

    func propose(_ name: String, _ arguments: [String: String]) throws -> CopilotToolProposal {
        let tab = try XCTUnwrap(model.activeTab)
        let proposal = try CopilotToolProposalFactory.make(
            toolCall: LLMRouterToolCall(id: UUID().uuidString, name: name, arguments: arguments, approvalRequired: true),
            sourceRunID: UUID(), targetTabID: tab.id, targetURLString: tab.urlString,
            navigationGeneration: model.navigationGeneration(for: tab.id)
        )
        // Use the application's existing conversation restoration path, as its
        // proposal unit tests do. Only tool INPUT is seeded; every browser result
        // and navigation update comes from the mounted production coordinator.
        let conversationID = model.llmConversation.id
        model.llmConversation.upsertToolProposal(proposal)
        model.startNewLLMConversation()
        XCTAssertTrue(model.selectLLMConversation(conversationID))
        return proposal
    }

    func approve(_ proposal: CopilotToolProposal) async throws -> BrowserAutomationResult {
        let request = try XCTUnwrap(model.approveToolProposal(proposal.id))
        let value = try await result(request)
        XCTAssertNotNil(value.approvedAutomationDispatchOwnerID)
        return value
    }
}

private struct NativeFixtureFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// Credential is owned ONLY by private XCTest instrumentation. No WKWebView
// configuration, cookies, URL, JavaScript, BrowserViewModel or LLM context gets it.
private final class NoOracleRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
private final class FixtureOracle {
    let baseURL: URL
    private let credential: String
    private let expectedFault: String?
    private let session = URLSession(configuration: .ephemeral, delegate: NoOracleRedirects(), delegateQueue: nil)

    init(expectedFault: String?) throws {
        let env = ProcessInfo.processInfo.environment
        guard env["BROWSER_NATIVE_QUALIFICATION"] == "1" else {
            throw XCTSkip("Explicit native fixture configuration is required")
        }
        guard let raw = env["BROWSER_FIXTURE_URL"], let url = URL(string: raw),
              url.scheme == "http", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              let token = env["BROWSER_FIXTURE_ORACLE_TOKEN"],
              token.range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil else {
            throw NativeFixtureFailure("Missing or invalid private fixture configuration")
        }
        baseURL = url
        credential = token
        self.expectedFault = expectedFault
    }

    deinit { session.invalidateAndCancel() }

    func read() async throws -> FixtureLedger {
        var request = URLRequest(url: baseURL.appendingPathComponent("oracle"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NativeFixtureFailure("Independent read-only oracle failed (credential omitted)")
        }
        let ledger = try JSONDecoder().decode(FixtureLedger.self, from: data)
        guard ledger.fault.kind == expectedFault else { throw NativeFixtureFailure("Wrong fixture fault configuration") }
        return ledger
    }
}

private struct FixtureLedger: Codable, Equatable {
    struct Payload: Codable, Equatable { let title: String; let notes: String }
    struct Operation: Codable, Equatable {
        let fixtureId: String; let operationId: String; let kind: String
        let accountId: String; let documentId: String; let baseRevision: Int; let payload: Payload
    }
    struct Receipt: Codable, Equatable {
        let status: String; let operationId: String; let revision: Int
        let fixtureId: String; let kind: String; let accountId: String; let documentId: String
        let baseRevision: Int; let payload: Payload
        var operation: Operation {
            Operation(fixtureId: fixtureId, operationId: operationId, kind: kind,
                      accountId: accountId, documentId: documentId, baseRevision: baseRevision, payload: payload)
        }
    }
    struct Entry: Codable, Equatable { let operation: Operation; let receipt: Receipt }
    struct Document: Codable, Equatable {
        let accountId: String; let documentId: String; let revision: Int; let notes: String
        let autosaveCount: Int; let submissionCount: Int; let submitted: Bool
    }
    struct Fault: Codable, Equatable { let kind: String?; let droppedResponses: Int }
    let fixtureId: String; let documents: [Document]; let operations: [Entry]; let fault: Fault
    var alpha: Document { get throws { try XCTUnwrap(documents.first { $0.accountId == "alpha" && $0.documentId == "draft-a" }) } }
}
#endif
