import Foundation
import Combine

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var tabs: [BrowserTab]
    @Published var activeTabID: UUID
    @Published var addressText: String
    @Published var selectedPanel: BrowserPanel = .runtime
    @Published var history: [BrowserHistoryEntry] = []
    @Published var bookmarks: [BrowserBookmark] = [
        BrowserBookmark(title: "Advatar Browser", urlString: "https://github.com/advatar/browser"),
        BrowserBookmark(title: "DuckDuckGo", urlString: "https://duckduckgo.com")
    ]
    @Published var webCommand: BrowserWebCommandRequest?
    @Published var runtimeFeatureStates: [RuntimeFeatureState]

    let runtimeBridge: MobileRuntimeBridge

    convenience init(initialURL: String = "about:home") {
        self.init(initialURL: initialURL, runtimeBridge: MobileRuntimeBridge())
    }

    init(initialURL: String, runtimeBridge: MobileRuntimeBridge) {
        let tab = BrowserTab(urlString: initialURL)
        self.runtimeBridge = runtimeBridge
        self.runtimeFeatureStates = runtimeBridge.featureStates
        self.tabs = [tab]
        self.activeTabID = tab.id
        self.addressText = initialURL
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

    func activateTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        addressText = activeTab?.urlString ?? BrowserURLResolver.homeURLString
    }

    func newTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        activateTab(tab.id)
    }

    func closeTab(_ id: UUID) {
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

    func navigate(_ rawInput: String) {
        guard let index = activeTabIndex else { return }

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
        history.insert(BrowserHistoryEntry(title: title, urlString: urlString, visitedAt: Date()), at: 0)
        if history.count > 100 {
            history.removeLast(history.count - 100)
        }
    }

    private func titleForURL(_ url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.absoluteString
    }
}
