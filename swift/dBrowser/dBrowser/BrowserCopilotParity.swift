import CryptoKit
import Foundation

struct BrowserTextSelectionRequest: Codable, Equatable {
    var maximumCharacters: Int

    nonisolated init(maximumCharacters: Int = 4_000) {
        self.maximumCharacters = min(max(maximumCharacters, 1), 8_000)
    }
}

struct BrowserTextSelection: Codable, Equatable {
    var text: String
    var urlString: String
    var elementTagName: String?
    var truncated: Bool
    var commitment: String

    private enum CodingKeys: String, CodingKey {
        case text
        case urlString
        case elementTagName
        case truncated
    }

    nonisolated init(
        text: String,
        urlString: String,
        elementTagName: String? = nil,
        truncated: Bool = false
    ) {
        let boundedText = SmartHistoryIndexer.boundedText(text, limit: 8_000)
        self.text = boundedText
        self.urlString = LLMPageContextSanitizer.sanitizedURLString(urlString)
        self.elementTagName = elementTagName.map {
            SmartHistoryIndexer.boundedText($0.lowercased(), limit: 32)
        }
        self.truncated = truncated || boundedText.count < text.count
        self.commitment = Self.commitment(text: boundedText, urlString: self.urlString)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: try container.decode(String.self, forKey: .text),
            urlString: try container.decode(String.self, forKey: .urlString),
            elementTagName: try container.decodeIfPresent(String.self, forKey: .elementTagName),
            truncated: try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(urlString, forKey: .urlString)
        try container.encodeIfPresent(elementTagName, forKey: .elementTagName)
        try container.encode(truncated, forKey: .truncated)
    }

    nonisolated private static func commitment(text: String, urlString: String) -> String {
        let digest = SHA256.hash(data: Data("\(urlString)\n\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum InactiveTabCapturePhase: String, Equatable {
    case idle
    case awaitingConfirmation
    case capturing
    case captured
    case failed
}

struct InactiveTabCaptureState: Equatable {
    var phase: InactiveTabCapturePhase
    var tabID: UUID?
    var tabTitle: String?
    var targetURLString: String?
    var displayURLString: String?
    var navigationGeneration: UInt64?
    var message: String

    nonisolated static let idle = InactiveTabCaptureState(
        phase: .idle,
        tabID: nil,
        tabTitle: nil,
        targetURLString: nil,
        displayURLString: nil,
        navigationGeneration: nil,
        message: "No inactive tab capture is pending."
    )
}

enum CopilotToolProposalStatus: String, Codable, Equatable {
    case pendingApproval
    case approved
    case denied
    case executing
    case completed
    case failed
    case expired
    case consumed

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .denied, .expired, .consumed:
            true
        case .pendingApproval, .approved, .executing:
            false
        }
    }
}

enum CopilotToolCommand: Codable, Equatable {
    case domQuery(DOMQueryRequest)
    case pageSnapshot(PageSnapshotRequest)
    case action(BrowserDOMAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case domQuery
        case pageSnapshot
        case action
    }

    private enum Kind: String, Codable {
        case domQuery
        case pageSnapshot
        case action
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .domQuery:
            self = .domQuery(try container.decode(DOMQueryRequest.self, forKey: .domQuery))
        case .pageSnapshot:
            self = .pageSnapshot(try container.decode(PageSnapshotRequest.self, forKey: .pageSnapshot))
        case .action:
            self = .action(try container.decode(BrowserDOMAction.self, forKey: .action))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .domQuery(let request):
            try container.encode(Kind.domQuery, forKey: .kind)
            try container.encode(request, forKey: .domQuery)
        case .pageSnapshot(let request):
            try container.encode(Kind.pageSnapshot, forKey: .kind)
            try container.encode(request, forKey: .pageSnapshot)
        case .action(let action):
            try container.encode(Kind.action, forKey: .kind)
            try container.encode(action, forKey: .action)
        }
    }

    nonisolated var browserCommand: BrowserAutomationCommand {
        switch self {
        case .domQuery(let request): .domQuery(request)
        case .pageSnapshot(let request): .pageSnapshot(request)
        case .action(let action): .action(action)
        }
    }

    nonisolated init(browserCommand: BrowserAutomationCommand) {
        switch browserCommand {
        case .domQuery(let request): self = .domQuery(request)
        case .pageSnapshot(let request): self = .pageSnapshot(request)
        case .action(let action): self = .action(action)
        case .textSelection:
            // Provider proposals never receive the inline-selection command.
            self = .domQuery(DOMQueryRequest(selector: "body", limit: 1))
        }
    }

    nonisolated var actionKind: BrowserDOMAction.Kind? {
        guard case .action(let action) = self else { return nil }
        return action.kind
    }

    nonisolated var approvalSummary: String {
        switch self {
        case .domQuery(let request):
            return "Read up to \(request.limit) elements matching selector \(request.selector); include hidden elements: \(request.includeHidden)."
        case .pageSnapshot(let request):
            return "Capture a bounded page snapshot (up to \(request.maxTextCharacters) text characters and \(request.maxElements) elements); include page metadata: \(request.includeMetadata)."
        case .action(let action):
            let target = action.selector.map {
                "match index \(action.elementIndex ?? 0) of selector \($0)"
            } ?? "the current page"
            switch action.kind {
            case .click:
                return "Click \(target)."
            case .typeText:
                let mode = action.clearExistingText ? "Replace existing content" : "Append to existing content"
                return "\(mode) in \(target) with this exact text: \(action.text ?? "")"
            case .submit:
                return "Submit the form associated with \(target)."
            case .scroll:
                return "Scroll by x=\(action.x ?? 0), y=\(action.y ?? 0)."
            case .focus:
                return "Focus \(target)."
            case .navigate:
                return "Navigate to this exact destination: \(action.urlString ?? "<missing>")"
            case .waitForSelector:
                return "Check whether \(target) is present."
            case .stop:
                return "Stop loading the current page."
            }
        }
    }
}

struct CopilotToolProposal: Codable, Equatable, Identifiable {
    let id: UUID
    var sourceToolCallID: String
    var sourceRunID: UUID
    var toolName: String
    var command: CopilotToolCommand
    var targetTabID: UUID
    var targetURLString: String
    var targetPageCommitment: String?
    var navigationGeneration: UInt64
    var argumentCommitment: String
    var commandCommitment: String?
    var approvalBindingCommitment: String?
    var status: CopilotToolProposalStatus
    var createdAt: Date
    var expiresAt: Date
    var statusMessage: String
    var automationRequestID: UUID?

    nonisolated init(
        id: UUID = UUID(),
        sourceToolCallID: String,
        sourceRunID: UUID,
        toolName: String,
        command: CopilotToolCommand,
        targetTabID: UUID,
        targetURLString: String,
        targetPageCommitment: String? = nil,
        navigationGeneration: UInt64,
        argumentCommitment: String,
        commandCommitment: String? = nil,
        approvalBindingCommitment: String? = nil,
        status: CopilotToolProposalStatus = .pendingApproval,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        statusMessage: String = "Waiting for explicit approval.",
        automationRequestID: UUID? = nil
    ) {
        self.id = id
        self.sourceToolCallID = SmartHistoryIndexer.boundedText(sourceToolCallID, limit: 128)
        self.sourceRunID = sourceRunID
        self.toolName = SmartHistoryIndexer.boundedText(toolName, limit: 128)
        self.command = command
        self.targetTabID = targetTabID
        self.targetURLString = LLMPageContextSanitizer.sanitizedURLString(targetURLString)
        let resolvedTargetPageCommitment = targetPageCommitment
            ?? CopilotToolProposalFactory.pageCommitment(urlString: targetURLString)
        self.targetPageCommitment = resolvedTargetPageCommitment
        self.navigationGeneration = navigationGeneration
        self.argumentCommitment = argumentCommitment
        let resolvedCommandCommitment = commandCommitment
            ?? CopilotToolProposalFactory.commandCommitment(command)
        self.commandCommitment = resolvedCommandCommitment
        let resolvedExpiresAt = expiresAt ?? createdAt.addingTimeInterval(5 * 60)
        self.approvalBindingCommitment = approvalBindingCommitment
            ?? resolvedTargetPageCommitment.map {
                CopilotToolProposalFactory.approvalBindingCommitment(
                    proposalID: id,
                    sourceRunID: sourceRunID,
                    targetTabID: targetTabID,
                    targetPageCommitment: $0,
                    navigationGeneration: navigationGeneration,
                    argumentCommitment: argumentCommitment,
                    commandCommitment: resolvedCommandCommitment,
                    expiresAt: resolvedExpiresAt
                )
            }
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = resolvedExpiresAt
        self.statusMessage = SmartHistoryIndexer.boundedText(statusMessage, limit: 500)
        self.automationRequestID = automationRequestID
    }
}

struct BrowserAutomationApprovalGrant: Equatable {
    let proposalID: UUID
    let sourceRunID: UUID
    let targetTabID: UUID
    let targetURLString: String
    let targetPageCommitment: String
    let navigationGeneration: UInt64
    let argumentCommitment: String
    let commandCommitment: String
    let approvalBindingCommitment: String
    let approvedAt: Date
    let expiresAt: Date
}

enum BrowserAutomationGrantPolicy {
    static func matches(
        _ grant: BrowserAutomationApprovalGrant,
        request: BrowserAutomationRequest,
        currentURLString: String?,
        currentNavigationGeneration: UInt64,
        now: Date = Date()
    ) -> Bool {
        let sanitizedCurrentURL = LLMPageContextSanitizer.sanitizedURLString(currentURLString)
        let currentPageCommitment = currentURLString.flatMap {
            CopilotToolProposalFactory.pageCommitment(urlString: $0)
        }
        let currentCommandCommitment = CopilotToolProposalFactory.commandCommitment(request.command)

        return grant.targetTabID == request.tabID
            && grant.targetURLString == sanitizedCurrentURL
            && grant.targetPageCommitment == currentPageCommitment
            && grant.navigationGeneration == request.navigationGeneration
            && grant.navigationGeneration == currentNavigationGeneration
            && grant.commandCommitment == currentCommandCommitment
            && CopilotToolProposalFactory.isCanonicalCommitment(grant.argumentCommitment)
            && CopilotToolProposalFactory.approvalBindingCommitment(
                proposalID: grant.proposalID,
                sourceRunID: grant.sourceRunID,
                targetTabID: grant.targetTabID,
                targetPageCommitment: grant.targetPageCommitment,
                navigationGeneration: grant.navigationGeneration,
                argumentCommitment: grant.argumentCommitment,
                commandCommitment: grant.commandCommitment,
                expiresAt: grant.expiresAt
            ) == grant.approvalBindingCommitment
            && grant.approvedAt <= now
            && grant.expiresAt > now
    }
}

enum CopilotToolProposalError: Error, LocalizedError, Equatable {
    case unsupportedTool(String)
    case invalidArguments(String)
    case disallowedAction(BrowserDOMAction.Kind)
    case staleOrTamperedProposal

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let name):
            "The provider proposed unsupported tool \(name)."
        case .invalidArguments(let message):
            "The provider tool arguments are invalid: \(message)"
        case .disallowedAction(let kind):
            "The workflow does not allow \(kind.rawValue)."
        case .staleOrTamperedProposal:
            "The provider tool proposal no longer matches its exact page and command commitments."
        }
    }
}

enum CopilotToolProposalFactory {
    nonisolated static let maximumPageURLBytes = 2_048

    nonisolated static func make(
        toolCall: LLMRouterToolCall,
        sourceRunID: UUID,
        targetTabID: UUID,
        targetURLString: String,
        navigationGeneration: UInt64,
        allowedActions: Set<BrowserDOMAction.Kind>? = nil,
        now: Date = Date()
    ) throws -> CopilotToolProposal {
        guard targetURLString.utf8.count <= maximumPageURLBytes,
              pageCommitment(urlString: targetURLString) != nil else {
            throw CopilotToolProposalError.invalidArguments(
                "provider tools require a bounded HTTP(S) source page"
            )
        }
        let command = try command(for: toolCall)
        if let actionKind = command.actionKind,
           let allowedActions,
           !allowedActions.contains(actionKind) {
            throw CopilotToolProposalError.disallowedAction(actionKind)
        }
        return CopilotToolProposal(
            sourceToolCallID: toolCall.id,
            sourceRunID: sourceRunID,
            toolName: toolCall.name,
            command: command,
            targetTabID: targetTabID,
            targetURLString: targetURLString,
            navigationGeneration: navigationGeneration,
            argumentCommitment: commitment(name: toolCall.name, arguments: toolCall.arguments),
            createdAt: now
        )
    }

    nonisolated static func command(for toolCall: LLMRouterToolCall) throws -> CopilotToolCommand {
        let arguments = toolCall.arguments
        switch toolCall.name.lowercased() {
        case "browser.query", "browser.dom_query":
            return .domQuery(
                DOMQueryRequest(
                    selector: arguments["selector"] ?? "body *",
                    limit: Int(arguments["limit"] ?? "") ?? 40,
                    includeHidden: false
                )
            )
        case "browser.snapshot", "browser.page_snapshot":
            return .pageSnapshot(PageSnapshotRequest())
        case "browser.click":
            return .action(try targetedAction(.click, arguments: arguments))
        case "browser.type", "browser.type_text":
            guard let text = arguments["text"], !text.isEmpty else {
                throw CopilotToolProposalError.invalidArguments("type_text requires bounded text")
            }
            return .action(
                try targetedAction(
                    .typeText,
                    arguments: arguments,
                    text: SmartHistoryIndexer.boundedText(text, limit: 2_000),
                    clearExistingText: arguments["clear_existing"]?.lowercased() != "false"
                )
            )
        case "browser.submit":
            return .action(try targetedAction(.submit, arguments: arguments))
        case "browser.focus":
            return .action(try targetedAction(.focus, arguments: arguments))
        case "browser.scroll":
            return .action(
                BrowserDOMAction(
                    kind: .scroll,
                    x: boundedCoordinate(arguments["x"]),
                    y: boundedCoordinate(arguments["y"])
                )
            )
        case "browser.navigate":
            guard let rawURL = arguments["url"],
                  rawURL.utf8.count <= 2_048,
                  let components = URLComponents(string: rawURL),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  components.host?.isEmpty == false,
                  components.user == nil,
                  components.password == nil else {
                throw CopilotToolProposalError.invalidArguments("navigate requires an HTTP(S) URL")
            }
            return .action(BrowserDOMAction(kind: .navigate, urlString: rawURL))
        case "browser.wait", "browser.wait_for_selector":
            return .action(try targetedAction(.waitForSelector, arguments: arguments))
        case "browser.stop":
            return .action(BrowserDOMAction(kind: .stop))
        default:
            throw CopilotToolProposalError.unsupportedTool(toolCall.name)
        }
    }

    nonisolated private static func targetedAction(
        _ kind: BrowserDOMAction.Kind,
        arguments: [String: String],
        text: String? = nil,
        clearExistingText: Bool = true
    ) throws -> BrowserDOMAction {
        let selector = arguments["selector"].map {
            SmartHistoryIndexer.boundedText($0, limit: 500)
        }
        let elementIndex: Int?
        if let rawElementIndex = arguments["element_index"] {
            guard let parsedElementIndex = Int(rawElementIndex),
                  (0...10_000).contains(parsedElementIndex) else {
                throw CopilotToolProposalError.invalidArguments("\(kind.rawValue) requires a non-negative bounded element_index")
            }
            elementIndex = parsedElementIndex
        } else {
            elementIndex = nil
        }
        guard selector?.isEmpty == false else {
            throw CopilotToolProposalError.invalidArguments("\(kind.rawValue) requires a selector")
        }
        return BrowserDOMAction(
            kind: kind,
            selector: selector,
            elementIndex: elementIndex,
            text: text,
            clearExistingText: clearExistingText
        )
    }

    nonisolated private static func boundedCoordinate(_ raw: String?) -> Double? {
        raw.flatMap(Double.init).map { min(max($0, -100_000), 100_000) }
    }

    nonisolated static func commitment(name: String, arguments: [String: String]) -> String {
        let argumentFields = arguments
            .sorted { left, right in
                left.key == right.key ? left.value < right.value : left.key < right.key
            }
            .flatMap { [$0.key, $0.value] }
        return canonicalCommitment(["copilot-arguments-v2", name] + argumentFields)
    }

    nonisolated static func pageCommitment(urlString: String) -> String? {
        guard urlString.utf8.count <= maximumPageURLBytes,
              var components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        components.scheme = scheme
        components.host = host
        guard let canonical = components.string else { return nil }
        return canonicalCommitment(["copilot-page-v1", canonical])
    }

    nonisolated static func commandCommitment(_ command: CopilotToolCommand) -> String {
        let fields: [String]
        switch command {
        case .domQuery(let request):
            fields = [
                "dom-query",
                request.selector,
                String(request.limit),
                String(request.includeHidden)
            ]
        case .pageSnapshot(let request):
            fields = [
                "page-snapshot",
                String(request.maxTextCharacters),
                String(request.maxElements),
                String(request.includeMetadata)
            ]
        case .action(let action):
            fields = [
                "action",
                action.kind.rawValue,
                action.selector ?? "<nil>",
                action.elementIndex.map { String($0) } ?? "<nil>",
                action.text ?? "<nil>",
                String(action.clearExistingText),
                action.x.map { String($0) } ?? "<nil>",
                action.y.map { String($0) } ?? "<nil>",
                action.urlString ?? "<nil>"
            ]
        }
        return canonicalCommitment(["copilot-command-v1"] + fields)
    }

    nonisolated static func commandCommitment(_ command: BrowserAutomationCommand) -> String? {
        guard case .textSelection = command else {
            return commandCommitment(CopilotToolCommand(browserCommand: command))
        }
        return nil
    }

    nonisolated static func isCanonicalCommitment(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    nonisolated static func approvalBindingCommitment(
        proposalID: UUID,
        sourceRunID: UUID,
        targetTabID: UUID,
        targetPageCommitment: String,
        navigationGeneration: UInt64,
        argumentCommitment: String,
        commandCommitment: String,
        expiresAt: Date
    ) -> String {
        canonicalCommitment([
            "copilot-approval-binding-v2",
            proposalID.uuidString.lowercased(),
            sourceRunID.uuidString.lowercased(),
            targetTabID.uuidString.lowercased(),
            targetPageCommitment,
            String(navigationGeneration),
            argumentCommitment,
            commandCommitment,
            String(expiresAt.timeIntervalSinceReferenceDate.bitPattern)
        ])
    }

    nonisolated private static func canonicalCommitment(_ fields: [String]) -> String {
        var canonical = Data()
        for field in fields {
            let bytes = Data(field.utf8)
            var length = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { canonical.append(contentsOf: $0) }
            canonical.append(bytes)
        }
        let digest = SHA256.hash(data: canonical)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum CopilotScheduledWorkflowPhase: String, Equatable {
    case due
    case waitingForUser
    case queued
    case running
    case completed
    case failed
}

enum CopilotRunPresentationPhase: String, Equatable {
    case waitingForContext
    case recallingMemory
    case invokingModel
    case streaming
    case bufferedResponse
    case completed
    case cancelled
    case failed
}

struct CopilotRunPresentation: Equatable, Identifiable {
    var runID: UUID
    var phase: CopilotRunPresentationPhase
    var partialText: String
    var statusMessage: String
    var providerBoundary: String

    var id: UUID { runID }

    mutating func append(delta: String, maximumCharacters: Int = 100_000) {
        guard !delta.isEmpty else { return }
        partialText = String((partialText + delta).prefix(max(1, maximumCharacters)))
        phase = .streaming
    }
}

struct CopilotScheduledWorkflowState: Equatable, Identifiable {
    var workflowID: UUID
    var title: String
    var phase: CopilotScheduledWorkflowPhase
    var message: String
    var evaluatedAt: Date
    var runID: UUID?

    var id: UUID { workflowID }
}

extension SavedCopilotWorkflow {
    nonisolated func isDue(
        now: Date = Date(),
        hasRunThisLaunch: Bool = false
    ) -> Bool {
        guard isEnabled else { return false }
        switch schedule.kind {
        case .manual:
            return false
        case .everyLaunch:
            return !hasRunThisLaunch
        case .intervalHours:
            guard let intervalHours = schedule.intervalHours else { return false }
            guard let lastRunAt else { return true }
            return now.timeIntervalSince(lastRunAt) >= TimeInterval(max(1, intervalHours) * 3_600)
        }
    }

    nonisolated func targetMatches(_ urlString: String?) -> Bool {
        guard let targetURLPattern = targetURLPattern?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetURLPattern.isEmpty else {
            return true
        }
        guard let urlString,
              let current = URLComponents(string: urlString),
              let currentScheme = current.scheme?.lowercased(),
              ["http", "https"].contains(currentScheme),
              let currentHost = current.host?.lowercased(),
              current.user == nil,
              current.password == nil else {
            return false
        }

        let patternHasScheme = targetURLPattern.contains("://")
        let patternValue = patternHasScheme ? targetURLPattern : "https://\(targetURLPattern)"
        guard let pattern = URLComponents(string: patternValue),
              let patternHostValue = pattern.host?.lowercased(),
              !patternHostValue.isEmpty,
              pattern.user == nil,
              pattern.password == nil,
              pattern.fragment == nil else {
            return false
        }
        if patternHasScheme, pattern.scheme?.lowercased() != currentScheme {
            return false
        }

        let hostMatches: Bool
        if patternHostValue.hasPrefix("*.") {
            let suffix = String(patternHostValue.dropFirst(2))
            hostMatches = !suffix.isEmpty
                && currentHost.hasSuffix(".\(suffix)")
                && currentHost != suffix
        } else {
            hostMatches = currentHost == patternHostValue
        }
        guard hostMatches else { return false }

        if let patternPort = pattern.port {
            guard effectivePort(scheme: currentScheme, explicitPort: current.port) == patternPort else {
                return false
            }
        } else if let currentPort = current.port,
                  effectivePort(scheme: currentScheme, explicitPort: nil) != currentPort {
            // A pattern without an explicit port means the scheme's default
            // port; it must not silently authorize an alternate service.
            return false
        }

        let patternPath = pattern.percentEncodedPath
        if !patternPath.isEmpty, patternPath != "/" {
            let currentPath = current.percentEncodedPath
            let pathMatches = currentPath == patternPath
                || (patternPath.hasSuffix("/")
                    ? currentPath.hasPrefix(patternPath)
                    : currentPath.hasPrefix(patternPath + "/"))
            guard pathMatches else { return false }
        }

        if let requiredQueryItems = pattern.queryItems, !requiredQueryItems.isEmpty {
            var availableQueryItems = current.queryItems ?? []
            for required in requiredQueryItems {
                guard let index = availableQueryItems.firstIndex(of: required) else {
                    return false
                }
                availableQueryItems.remove(at: index)
            }
        }
        return true
    }

    nonisolated private func effectivePort(scheme: String, explicitPort: Int?) -> Int? {
        if let explicitPort { return explicitPort }
        switch scheme {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}
