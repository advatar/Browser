import Foundation
import Combine

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var tabs: [BrowserTab]
    @Published var activeTabID: UUID
    @Published var addressText: String
    @Published var selectedPanel: BrowserPanel?
    @Published var history: [BrowserHistoryEntry] = []
    @Published var bookmarks: [BrowserBookmark] = BrowserBookmark.defaults
    @Published var webCommand: BrowserWebCommandRequest?
    @Published var automationRequest: BrowserAutomationRequest?
    @Published var automationResults: [BrowserAutomationResult] = []
    @Published var latestDOMQueryResult: DOMQueryResult?
    @Published var latestPageSnapshot: PageSnapshot?
    @Published var copilotRuns: [CopilotRun] = []
    @Published var copilotWorkflows: [SavedCopilotWorkflow] = []
    @Published var runtimeFeatureStates: [RuntimeFeatureState]

    let runtimeBridge: MobileRuntimeBridge
    private let workflowStore: CopilotWorkflowStore
    private let smartHistoryStore: SmartHistoryStore
    private var smartHistoryExcludedDomains: Set<String>
    private var copilotTasks: [UUID: Task<Void, Never>] = [:]

    convenience init(initialURL: String = "about:home") {
        self.init(initialURL: initialURL, runtimeBridge: MobileRuntimeBridge())
    }

    init(
        initialURL: String,
        runtimeBridge: MobileRuntimeBridge,
        copilotWorkflowStore: CopilotWorkflowStore = CopilotWorkflowStore(),
        smartHistoryStore: SmartHistoryStore = SmartHistoryStore()
    ) {
        let tab = BrowserTab(urlString: initialURL)
        let smartHistoryPayload = smartHistoryStore.load()
        self.runtimeBridge = runtimeBridge
        self.workflowStore = copilotWorkflowStore
        self.smartHistoryStore = smartHistoryStore
        self.smartHistoryExcludedDomains = Set(smartHistoryPayload.excludedDomains)
        self.runtimeFeatureStates = runtimeBridge.featureStates
        self.tabs = [tab]
        self.activeTabID = tab.id
        self.addressText = initialURL
        self.history = smartHistoryPayload.history
        self.copilotWorkflows = copilotWorkflowStore.load()
    }

    var activeTabIndex: Int? {
        tabs.firstIndex { $0.id == activeTabID }
    }

    var activeTab: BrowserTab? {
        guard let index = activeTabIndex else { return nil }
        return tabs[index]
    }

    var canGoBack: Bool {
        activeTab?.canGoBack ?? false
    }

    var canGoForward: Bool {
        activeTab?.canGoForward ?? false
    }

    var unavailableFeatureCount: Int {
        runtimeFeatureStates.filter { !$0.isAvailable }.count
    }

    var activeCopilotRunCount: Int {
        copilotRuns.filter { $0.status == .queued || $0.status == .running }.count
    }

    func activateTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedPanel = nil
        activeTabID = id
        addressText = activeTab?.urlString ?? BrowserURLResolver.homeURLString
    }

    func newTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        activateTab(tab.id)
    }

    func selectPanel(_ panel: BrowserPanel?) {
        selectedPanel = panel
    }

    func closeTab(_ id: UUID) {
        cancelCopilotRuns(boundTo: id, reason: "Target tab closed.")
        guard tabs.count > 1 else {
            tabs[0] = BrowserTab(id: tabs[0].id)
            activeTabID = tabs[0].id
            addressText = tabs[0].urlString
            return
        }

        let wasActive = activeTabID == id
        tabs.removeAll { $0.id == id }
        if wasActive {
            activeTabID = tabs.first?.id ?? UUID()
            addressText = activeTab?.urlString ?? BrowserURLResolver.homeURLString
        }
    }

    func navigateFromAddress() {
        navigate(addressText)
    }

    func addressAutocompleteSuggestions(limit: Int = 6) -> [BrowserAddressSuggestion] {
        let query = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = normalizedAutocompleteText(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var seenURLs = Set<String>()
        let rankedSuggestions = history.enumerated().compactMap { index, entry -> (rank: Int, index: Int, suggestion: BrowserAddressSuggestion)? in
            let normalizedURL = normalizedAutocompleteText(entry.urlString)
            guard seenURLs.insert(normalizedURL).inserted else { return nil }
            guard let rank = autocompleteRank(for: entry, query: normalizedQuery) else { return nil }

            return (
                rank,
                index,
                BrowserAddressSuggestion(title: entry.title, urlString: entry.urlString)
            )
        }

        return rankedSuggestions
            .sorted {
                if $0.rank != $1.rank {
                    return $0.rank < $1.rank
                }
                return $0.index < $1.index
            }
            .prefix(limit)
            .map { $0.suggestion }
    }

    func openAddressSuggestion(_ suggestion: BrowserAddressSuggestion) {
        navigate(suggestion.urlString)
    }

    func navigate(_ rawInput: String) {
        guard let index = activeTabIndex else { return }
        selectedPanel = nil
        cancelCopilotRuns(boundTo: tabs[index].id, reason: "Manual navigation took over the tab.")

        switch BrowserURLResolver.resolve(rawInput) {
        case .home:
            tabs[index].title = "Home"
            tabs[index].urlString = BrowserURLResolver.homeURLString
            tabs[index].mobileNotice = nil
            tabs[index].isLoading = false
            addressText = BrowserURLResolver.homeURLString
        case .web(let url):
            let title = titleForURL(url)
            tabs[index].title = title
            tabs[index].urlString = url.absoluteString
            tabs[index].mobileNotice = nil
            tabs[index].isLoading = true
            addressText = url.absoluteString
            recordHistory(title: title, urlString: url.absoluteString)
        case .unsupported(let raw, let message):
            resolveThroughRuntimeBridge(raw: raw, fallbackMessage: message, tabID: tabs[index].id)
        }
    }

    func refreshRuntimeBridgeStatus() async {
        runtimeFeatureStates = await runtimeBridge.refreshStatus()
    }

    func openBookmark(_ bookmark: BrowserBookmark) {
        navigate(bookmark.urlString)
    }

    func openHistoryEntry(_ entry: BrowserHistoryEntry) {
        navigate(entry.urlString)
    }

    func addActivePageBookmark() {
        guard let tab = activeTab else { return }
        guard tab.urlString != BrowserURLResolver.homeURLString else { return }
        guard bookmarks.contains(where: { $0.urlString == tab.urlString }) == false else { return }
        bookmarks.insert(BrowserBookmark(title: tab.title, urlString: tab.urlString), at: 0)
    }

    func goBack() {
        issueCommand(.back)
    }

    func goForward() {
        issueCommand(.forward)
    }

    func reload() {
        issueCommand(.reload)
    }

    func stop() {
        issueCommand(.stop)
        if let activeTab {
            cancelCopilotRuns(boundTo: activeTab.id, reason: "Stop requested by the user.")
        }
    }

    @discardableResult
    func requestDOMQuery(_ request: DOMQueryRequest = DOMQueryRequest()) -> BrowserAutomationRequest? {
        issueAutomationRequest(.domQuery(request))
    }

    @discardableResult
    func requestPageSnapshot(_ request: PageSnapshotRequest = PageSnapshotRequest()) -> BrowserAutomationRequest? {
        issueAutomationRequest(.pageSnapshot(request))
    }

    @discardableResult
    func requestDOMAction(_ action: BrowserDOMAction) -> BrowserAutomationRequest? {
        guard let tab = activeTab else { return nil }
        let target = targetElement(for: action)
        if let approval = BrowserAutomationApprovalPolicy.evaluate(
            action: action,
            currentURLString: tab.urlString,
            target: target
        ) {
            let requestID = UUID()
            let result = BrowserAutomationResult(
                requestID: requestID,
                tabID: tab.id,
                status: .needsApproval,
                message: approval.summary,
                approval: approval
            )
            applyAutomationResult(result)
            return nil
        }

        return issueAutomationRequest(.action(action))
    }

    func applyAutomationResult(_ result: BrowserAutomationResult) {
        automationResults.insert(result, at: 0)
        if automationResults.count > 100 {
            automationResults.removeLast(automationResults.count - 100)
        }

        if let domQuery = result.domQuery {
            latestDOMQueryResult = domQuery
        }

        if let snapshot = result.pageSnapshot {
            latestPageSnapshot = snapshot
            updateSmartHistorySummary(from: snapshot)
        }

        if let approval = result.approval {
            appendApproval(approval, tabID: result.tabID)
        }
    }

    @discardableResult
    func runCopilot(prompt: String) -> UUID? {
        guard let tab = activeTab else { return nil }
        let runID = UUID()
        let snapshot = latestPageSnapshot?.urlString == tab.urlString ? latestPageSnapshot : nil
        let usage = CopilotCreditUsage.estimate(prompt: prompt, snapshot: snapshot)
        let run = CopilotRun(
            id: runID,
            prompt: prompt,
            activeTabID: tab.id,
            targetURLString: tab.urlString,
            status: .running,
            events: [
                CopilotRunEvent(kind: .queued, message: "Queued Copilot run for \(tab.displayURL)."),
                CopilotRunEvent(kind: .pageSnapshotRequested, message: "Requested a bounded page snapshot for context.")
            ],
            usage: usage
        )
        copilotRuns.insert(run, at: 0)
        requestPageSnapshot()

        let task = Task { @MainActor in
            appendCopilotEvent(runID: runID, kind: .modelStarted, message: "Started model bridge.")
            let result = await runtimeBridge.runCopilot(
                CopilotRunRequest(prompt: prompt, pageURLString: tab.urlString, pageSnapshot: snapshot)
            )

            guard !Task.isCancelled else {
                finishCopilotRun(runID, status: .cancelled, result: nil, message: "Run cancelled before completion.")
                return
            }

            let provider = result.mode == .service ? "afm" : "local"
            let finalUsage = CopilotCreditUsage.estimate(prompt: prompt, snapshot: snapshot, provider: provider)
            finishCopilotRun(
                runID,
                status: .completed,
                result: result,
                usage: finalUsage,
                message: "Completed Copilot run with \(provider) execution."
            )
        }
        copilotTasks[runID] = task
        return runID
    }

    func cancelCopilotRun(_ id: UUID) {
        copilotTasks[id]?.cancel()
        copilotTasks[id] = nil
        finishCopilotRun(id, status: .cancelled, result: nil, message: "Run cancelled.")
    }

    @discardableResult
    func saveCopilotWorkflow(
        title: String,
        promptTemplate: String,
        targetURLPattern: String? = nil,
        allowedActions: [BrowserDOMAction.Kind] = [],
        schedule: CopilotWorkflowSchedule = .manual
    ) -> SavedCopilotWorkflow {
        let workflow = SavedCopilotWorkflow(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled workflow" : title,
            promptTemplate: promptTemplate,
            targetURLPattern: targetURLPattern,
            allowedActions: allowedActions,
            schedule: schedule
        )
        copilotWorkflows.insert(workflow, at: 0)
        persistWorkflows()
        return workflow
    }

    @discardableResult
    func runWorkflow(_ id: UUID) -> UUID? {
        guard let index = copilotWorkflows.firstIndex(where: { $0.id == id }) else { return nil }
        guard copilotWorkflows[index].isEnabled else { return nil }
        copilotWorkflows[index].lastRunAt = Date()
        persistWorkflows()
        return runCopilot(prompt: copilotWorkflows[index].promptTemplate)
    }

    func setWorkflow(_ id: UUID, isEnabled: Bool) {
        guard let index = copilotWorkflows.firstIndex(where: { $0.id == id }) else { return }
        copilotWorkflows[index].isEnabled = isEnabled
        persistWorkflows()
    }

    func deleteWorkflow(_ id: UUID) {
        copilotWorkflows.removeAll { $0.id == id }
        persistWorkflows()
    }

    func smartHistoryRecall(_ query: String, limit: Int = 6) -> [SmartHistoryRecallResult] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        return history.compactMap { entry -> SmartHistoryRecallResult? in
            guard entry.isSmartHistoryIndexed else { return nil }
            let searchable = [
                entry.title,
                entry.urlString,
                entry.summary ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            guard terms.allSatisfy({ searchable.contains($0) }) else { return nil }

            var score = 0
            for term in terms {
                if entry.title.lowercased().contains(term) { score += 4 }
                if entry.urlString.lowercased().contains(term) { score += 3 }
                if entry.summary?.lowercased().contains(term) == true { score += 5 }
            }
            return SmartHistoryRecallResult(entry: entry, score: score, matchedText: entry.summary ?? entry.title)
        }
        .sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.entry.visitedAt > $1.entry.visitedAt
        }
        .prefix(limit)
        .map { $0 }
    }

    func setSmartHistoryIndexing(enabled: Bool, forDomain domain: String) {
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDomain.isEmpty else { return }
        if enabled {
            smartHistoryExcludedDomains.remove(normalizedDomain)
        } else {
            smartHistoryExcludedDomains.insert(normalizedDomain)
            for index in history.indices where URL(string: history[index].urlString)?.host?.lowercased() == normalizedDomain {
                history[index].summary = nil
                history[index].isSmartHistoryIndexed = false
            }
        }
        persistSmartHistory()
    }

    func clearSmartHistorySummaries() {
        for index in history.indices {
            history[index].summary = nil
            history[index].isSmartHistoryIndexed = false
        }
        persistSmartHistory()
    }

    func deleteHistoryEntry(_ id: UUID) {
        history.removeAll { $0.id == id }
        persistSmartHistory()
    }

    func applyNavigationUpdate(_ update: BrowserNavigationUpdate) {
        guard let index = tabs.firstIndex(where: { $0.id == update.tabID }) else { return }
        if let title = update.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            tabs[index].title = title
        }
        if let urlString = update.urlString, !urlString.isEmpty {
            tabs[index].urlString = urlString
            if update.tabID == activeTabID {
                addressText = urlString
            }
        }
        tabs[index].isLoading = update.isLoading
        tabs[index].canGoBack = update.canGoBack
        tabs[index].canGoForward = update.canGoForward

        if !update.isLoading, let urlString = update.urlString, !urlString.isEmpty {
            recordHistory(title: tabs[index].title, urlString: urlString)
        }
    }

    private func issueCommand(_ command: BrowserWebCommand) {
        guard let tab = activeTab else { return }
        webCommand = BrowserWebCommandRequest(tabID: tab.id, command: command)
    }

    @discardableResult
    private func issueAutomationRequest(_ command: BrowserAutomationCommand) -> BrowserAutomationRequest? {
        guard let tab = activeTab else { return nil }
        let request = BrowserAutomationRequest(tabID: tab.id, command: command)
        automationRequest = request
        return request
    }

    private func resolveThroughRuntimeBridge(raw: String, fallbackMessage: String, tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].title = "Runtime bridge"
        tabs[index].urlString = raw
        tabs[index].mobileNotice = "Resolving through the iOS runtime bridge."
        tabs[index].isLoading = true
        tabs[index].canGoBack = false
        tabs[index].canGoForward = false
        addressText = raw

        Task { @MainActor in
            let resolution = await runtimeBridge.resolve(raw)
            applyRuntimeResolution(resolution, tabID: tabID, fallbackMessage: fallbackMessage)
        }
    }

    private func applyRuntimeResolution(
        _ resolution: RuntimeBridgeResolution,
        tabID: UUID,
        fallbackMessage: String
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard let resolvedURLString = resolution.resolvedURLString, let url = URL(string: resolvedURLString) else {
            tabs[index].title = "Mobile runtime"
            tabs[index].urlString = resolution.originalInput
            tabs[index].mobileNotice = resolution.message ?? fallbackMessage
            tabs[index].isLoading = false
            tabs[index].canGoBack = false
            tabs[index].canGoForward = false
            if tabID == activeTabID {
                addressText = resolution.originalInput
            }
            return
        }

        let title = titleForURL(url)
        tabs[index].title = title
        tabs[index].urlString = resolvedURLString
        tabs[index].mobileNotice = nil
        tabs[index].isLoading = true
        if tabID == activeTabID {
            addressText = resolvedURLString
        }
        recordHistory(title: title, urlString: resolvedURLString)
    }

    private func recordHistory(title: String, urlString: String) {
        guard urlString != BrowserURLResolver.homeURLString else { return }
        if history.first?.urlString == urlString {
            return
        }
        let isIndexed = isSmartHistoryIndexable(urlString)
        let summary = isIndexed ? SmartHistoryIndexer.summary(title: title, urlString: urlString) : nil
        history.insert(
            BrowserHistoryEntry(
                title: title,
                urlString: urlString,
                visitedAt: Date(),
                summary: summary,
                isSmartHistoryIndexed: isIndexed
            ),
            at: 0
        )
        if history.count > 100 {
            history.removeLast(history.count - 100)
        }
        persistSmartHistory()
    }

    private func updateSmartHistorySummary(from snapshot: PageSnapshot) {
        guard isSmartHistoryIndexable(snapshot.urlString) else { return }
        guard let index = history.firstIndex(where: { $0.urlString == snapshot.urlString }) else { return }
        history[index].summary = SmartHistoryIndexer.summary(
            title: history[index].title,
            urlString: history[index].urlString,
            snapshot: snapshot
        )
        history[index].isSmartHistoryIndexed = true
        persistSmartHistory()
    }

    private func isSmartHistoryIndexable(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return true }
        return !smartHistoryExcludedDomains.contains(host)
    }

    private func persistSmartHistory() {
        smartHistoryStore.save(
            SmartHistoryStorePayload(
                history: history,
                excludedDomains: Array(smartHistoryExcludedDomains).sorted()
            )
        )
    }

    private func persistWorkflows() {
        workflowStore.save(copilotWorkflows)
    }

    private func targetElement(for action: BrowserDOMAction) -> DOMElementRecord? {
        guard let latestDOMQueryResult else { return nil }
        if let elementIndex = action.elementIndex {
            return latestDOMQueryResult.elements.first { $0.index == elementIndex }
        }
        guard let selector = action.selector?.lowercased() else { return nil }
        return latestDOMQueryResult.elements.first { element in
            element.searchableText.contains(selector)
        }
    }

    private func appendApproval(_ approval: BrowserAutomationApproval, tabID: UUID) {
        guard let index = copilotRuns.firstIndex(where: { $0.activeTabID == tabID && $0.status == .running }) else { return }
        copilotRuns[index].approvals.append(approval)
        copilotRuns[index].events.append(
            CopilotRunEvent(kind: .approvalRequired, message: approval.summary)
        )
    }

    private func appendCopilotEvent(runID: UUID, kind: CopilotRunEventKind, message: String) {
        guard let index = copilotRuns.firstIndex(where: { $0.id == runID }) else { return }
        copilotRuns[index].events.append(CopilotRunEvent(kind: kind, message: message))
    }

    private func finishCopilotRun(
        _ id: UUID,
        status: CopilotRunStatus,
        result: CopilotRunResult?,
        usage: CopilotCreditUsage? = nil,
        message: String
    ) {
        guard let index = copilotRuns.firstIndex(where: { $0.id == id }) else { return }
        copilotRuns[index].status = status
        copilotRuns[index].finishedAt = Date()
        copilotRuns[index].result = result
        if let usage {
            copilotRuns[index].usage = usage
        }
        let kind: CopilotRunEventKind = {
            switch status {
            case .completed: return .modelCompleted
            case .cancelled: return .cancelled
            case .failed: return .failed
            case .queued, .running: return .modelStarted
            }
        }()
        copilotRuns[index].events.append(CopilotRunEvent(kind: kind, message: message))
        copilotTasks[id] = nil
    }

    private func cancelCopilotRuns(boundTo tabID: UUID, reason: String) {
        let runIDs = copilotRuns
            .filter { $0.activeTabID == tabID && ($0.status == .queued || $0.status == .running) }
            .map(\.id)
        for runID in runIDs {
            copilotTasks[runID]?.cancel()
            copilotTasks[runID] = nil
            finishCopilotRun(runID, status: .cancelled, result: nil, message: reason)
        }
    }

    private func titleForURL(_ url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.absoluteString
    }

    private func autocompleteRank(for entry: BrowserHistoryEntry, query: String) -> Int? {
        let normalizedURL = normalizedAutocompleteText(entry.urlString)
        let displayURL = displayAutocompleteText(for: entry.urlString)
        let host = URL(string: entry.urlString)?.host.map(normalizedAutocompleteText) ?? ""
        let title = normalizedAutocompleteText(entry.title)

        guard normalizedURL != query, displayURL != query else {
            return nil
        }

        if normalizedURL.hasPrefix(query) {
            return 0
        }
        if displayURL.hasPrefix(query) {
            return 1
        }
        if host.hasPrefix(query) {
            return 2
        }
        if normalizedURL.contains(query) || displayURL.contains(query) {
            return 3
        }
        if title.contains(query) {
            return 4
        }
        if entry.summary?.lowercased().contains(query) == true {
            return 5
        }
        return nil
    }

    private func normalizedAutocompleteText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func displayAutocompleteText(for urlString: String) -> String {
        var text = normalizedAutocompleteText(urlString)
        for prefix in ["https://www.", "http://www.", "https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        return text
    }
}
