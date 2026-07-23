//
//  ContentView.swift
//  dBrowser
//
//  Created by Johan Sellström on 2026-05-15.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

var platformBackgroundColor: Color {
#if os(macOS)
    Color(nsColor: .windowBackgroundColor)
#else
    Color(uiColor: .systemBackground)
#endif
}

struct ContentView: View {
    @StateObject private var browser = BrowserViewModel()
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        BrowserRootLayout(browser: browser) {
            browserWorkspace
        }
        .task {
            BrowserAdBlocker.prewarm()
            browser.startWorkflowScheduler()
            await browser.refreshRuntimeBridgeStatus()
        }
        .onOpenURL { url in
            guard browser.connectorCoordinator.oauthConfiguration.matchesCallbackURL(url) else { return }
            Task { await browser.connectorCoordinator.handleOAuthCallback(url) }
        }
    }

    private var browserWorkspace: some View {
        VStack(spacing: 0) {
            browserToolbar
#if !os(macOS)
            BrowserPanelSelector(browser: browser)
#endif
            tabStrip
            Divider()
            browserSurface
            Divider()
            statusBar
        }
        .background(platformBackgroundColor)
    }

    private var browserToolbar: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                browser.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!browser.canGoBack)
            .help("Back")

            Button {
                browser.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!browser.canGoForward)
            .help("Forward")

            Button {
                browser.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")

            Button {
                browser.toggleAdBlocking()
            } label: {
                Image(systemName: browser.adBlockingMode.systemImage)
            }
            .help(browser.adBlockingMode.toolbarHelp)
            .accessibilityIdentifier("ad-blocker-toggle")

            BrowserAddressAutocompleteField(
                browser: browser,
                isFocused: $addressFieldFocused
            ) {
                browser.navigateFromAddress()
                addressFieldFocused = false
            }

            Button {
                browser.navigateFromAddress()
                addressFieldFocused = false
            } label: {
                Image(systemName: "arrow.right.circle.fill")
            }
            .help("Go")

            Button {
                browser.addActivePageBookmark()
            } label: {
                Image(systemName: "bookmark")
            }
            .help("Bookmark")

            Button {
                browser.newTab()
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .help("New Tab")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(browser.tabs) { tab in
                    HStack(spacing: 6) {
                        Button {
                            browser.activateTab(tab.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                                Text(tab.title)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(tab.title) tab")

                        if browser.tabs.count > 1 {
                            Button {
                                browser.closeTab(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .padding(4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close \(tab.title) tab")
                            .accessibilityIdentifier("close-tab-\(tab.id.uuidString)")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: 220, alignment: .leading)
                    .background(tab.id == browser.activeTabID ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var browserSurface: some View {
        ZStack {
            CopilotBrowserWorkspace(
                browser: browser,
                showsCopilot: browser.selectedPanel == .copilot
            ) {
                activeBrowserSurface
            }
            .opacity(browser.selectedPanel != nil && browser.selectedPanel != .copilot ? 0 : 1)
            .allowsHitTesting(browser.selectedPanel == nil || browser.selectedPanel == .copilot)

            if let panel = browser.selectedPanel, panel != .copilot {
                BrowserPanelContentView(browser: browser, panel: panel)
                    .background(platformBackgroundColor)
            }
        }
    }

    @ViewBuilder
    private var activeBrowserSurface: some View {
        ZStack {
            ForEach($browser.tabs) { $tab in
                if tab.urlString != BrowserURLResolver.homeURLString,
                   tab.mobileNotice == nil,
                   !tab.isTraceMinimized,
                   browser.searchSessionsByTabID[tab.id] == nil {
                    BrowserWebView(
                        tab: $tab,
                        command: browser.webCommand,
                        adBlockingMode: browser.adBlockingMode,
                        automationRequest: browser.automationRequest,
                        navigationGeneration: browser.navigationGeneration(for: tab.id),
                        onApprovedAutomationDispatch: browser.claimApprovedAutomationDispatch,
                        onNavigationUpdate: browser.applyNavigationUpdate,
                        onAutomationResult: browser.applyAutomationResult
                    )
                    .opacity(tab.id == browser.activeTabID ? 1 : 0)
                    .allowsHitTesting(tab.id == browser.activeTabID)
                    .accessibilityHidden(tab.id != browser.activeTabID)
                    .zIndex(tab.id == browser.activeTabID ? 1 : 0)
                }
            }

            if let tab = browser.activeTab, let session = browser.searchSessionsByTabID[tab.id] {
                BrowserNativeSearchResultsView(browser: browser, tabID: tab.id, session: session)
                    .zIndex(2)
            } else if let tab = browser.activeTab, tab.urlString == BrowserURLResolver.homeURLString {
                BrowserHomeView(browser: browser)
                    .zIndex(2)
            } else if let tab = browser.activeTab, let notice = tab.mobileNotice {
                RuntimeNoticeView(urlString: tab.urlString, message: notice)
                    .zIndex(2)
            } else if browser.activeTab == nil {
                BrowserHomeView(browser: browser)
                    .zIndex(2)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: browser.activeTab?.isLoading == true ? "network" : "lock.shield")
            Text(browser.activeTab?.displayURL ?? "Home")
                .lineLimit(1)
                .accessibilityIdentifier("active-url")
            Spacer()
            if browser.activeCopilotRunCount > 0 {
                Text("\(browser.activeCopilotRunCount) Copilot active")
            }
            Label(browser.adBlockingMode.statusText, systemImage: browser.adBlockingMode.systemImage)
            Text("\(browser.tabs.count) tab\(browser.tabs.count == 1 ? "" : "s")")
            Text(runtimeBridgeStatusText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var runtimeBridgeStatusText: String {
        if browser.unavailableFeatureCount == 0 {
            return "runtime bridges ready"
        }
        return "\(browser.unavailableFeatureCount) bridge\(browser.unavailableFeatureCount == 1 ? "" : "s") offline"
    }
}

private struct BrowserAddressAutocompleteField: View {
    @ObservedObject var browser: BrowserViewModel
    let isFocused: FocusState<Bool>.Binding
    let onCommit: () -> Void

    private var suggestions: [BrowserAddressSuggestion] {
        guard isFocused.wrappedValue else { return [] }
        return browser.addressAutocompleteSuggestions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search or enter address", text: $browser.addressText)
                .focused(isFocused)
                .browserAddressFieldStyle()
                .onSubmit(onCommit)

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            browser.openAddressSuggestion(suggestion)
                            isFocused.wrappedValue = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .frame(width: 22)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(suggestion.urlString)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Image(systemName: "arrow.turn.down.left")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open previously visited URL")

                        if suggestion.id != suggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(platformBackgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
                .accessibilityIdentifier("address-autocomplete-suggestions")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func browserAddressFieldStyle() -> some View {
#if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textFieldStyle(RoundedBorderTextFieldStyle())
#else
        self
            .textFieldStyle(RoundedBorderTextFieldStyle())
#endif
    }
}

private struct BrowserRootLayout<Content: View>: View {
    @ObservedObject var browser: BrowserViewModel
    @ViewBuilder var content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            BrowserSidebar(browser: browser)
        } detail: {
            content()
        }
#else
        content()
#endif
    }
}

private struct CopilotBrowserWorkspace<BrowserContent: View>: View {
    @ObservedObject var browser: BrowserViewModel
    let showsCopilot: Bool
    private let browserContent: BrowserContent

    init(
        browser: BrowserViewModel,
        showsCopilot: Bool,
        @ViewBuilder browserContent: () -> BrowserContent
    ) {
        self.browser = browser
        self.showsCopilot = showsCopilot
        self.browserContent = browserContent()
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 760
            let sidecarWidth = min(max(proxy.size.width * 0.38, 320), 420)
            let compactPanelHeight = min(
                max(proxy.size.height * 0.44, 200),
                min(380, proxy.size.height * 0.55)
            )
            let workspaceLayout = showsCopilot && isCompact
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(spacing: 0))

            workspaceLayout {
                browserContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    .accessibilityIdentifier("browser-web-content")

                if showsCopilot {
                    Divider()

                    copilotPanel(
                        isCompact: isCompact,
                        sidecarWidth: sidecarWidth,
                        compactPanelHeight: compactPanelHeight
                    )
                }
            }
        }
        .accessibilityIdentifier(showsCopilot ? "copilot-browser-workspace" : "browser-workspace")
    }

    @ViewBuilder
    private func copilotPanel(
        isCompact: Bool,
        sidecarWidth: CGFloat,
        compactPanelHeight: CGFloat
    ) -> some View {
        if isCompact {
            BrowserPanelContentView(browser: browser, panel: .copilot)
                .frame(maxWidth: .infinity)
                .frame(height: compactPanelHeight)
                .accessibilityIdentifier("copilot-sidecar")
        } else {
            BrowserPanelContentView(browser: browser, panel: .copilot)
                .frame(width: sidecarWidth)
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("copilot-sidecar")
        }
    }
}

private struct BrowserPanelSelector: View {
    @ObservedObject var browser: BrowserViewModel
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                BrowserPanelSelectorButton(
                    title: "Browser",
                    systemImage: "globe",
                    isSelected: browser.selectedPanel == nil
                ) {
                    browser.selectPanel(nil)
                }
                .accessibilityIdentifier("panel-browser")

                ForEach(BrowserPanel.primaryPanels) { panel in
                    BrowserPanelSelectorButton(
                        title: panel.title,
                        systemImage: panel.systemImage,
                        isSelected: browser.selectedPanel == panel
                    ) {
                        browser.selectPanel(panel)
                    }
                    .accessibilityIdentifier("panel-\(panel.id)")
                }
            }

            Text("Advanced")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .accessibilityIdentifier("panel-advanced-header")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(BrowserPanel.advancedPanels) { panel in
                    BrowserPanelSelectorButton(
                        title: panel.title,
                        systemImage: panel.systemImage,
                        isSelected: browser.selectedPanel == panel
                    ) {
                        browser.selectPanel(panel)
                    }
                    .accessibilityIdentifier("panel-\(panel.id)")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct BrowserPanelSelectorButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BrowserPanelContentView: View {
    @ObservedObject var browser: BrowserViewModel
    let panel: BrowserPanel
    @State private var selectedFeature: RuntimeFeatureState?

    var body: some View {
        Group {
            switch panel {
            case .history:
                HistoryPanelView(browser: browser)
            case .bookmarks:
                BookmarksPanelView(browser: browser)
            case .wallet:
                WalletPanelView(browser: browser)
            case .mcp:
                MCPServersPanelView(browser: browser)
            case .a2ui:
                A2UITokenPanelView()
            case .hyperactiveWeb:
                if let coordinator = browser.hyperactiveWeb {
                    HyperactiveWebPanel(coordinator: coordinator)
                } else {
                    ContentUnavailableView("Hyperactive Web unavailable", systemImage: "point.3.connected.trianglepath.dotted")
                }
            case .copilot:
                CopilotPanelView(browser: browser)
            case .advantage:
                AdvantagePanelView(browser: browser)
            case .localLLM:
                LocalLLMPanelView(browser: browser)
            case .runtime:
                RuntimePanelView(browser: browser) { feature in
                    selectedFeature = feature
                }
            }
        }
        .sheet(item: $selectedFeature) { feature in
            RuntimeFeatureDetailView(state: feature)
        }
    }
}

struct PanelHeaderView: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

struct EmptyPanelView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AdvantagePanelView: View {
    @ObservedObject var browser: BrowserViewModel
    private let scorecard = BrowserAdvantageScorecard.current

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 10)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelHeaderView(
                    title: "Advantage",
                    systemImage: BrowserPanel.advantage.systemImage,
                    subtitle: "Track where dBrowser beats Strawberry and jump directly to the tracked UX gap work."
                )

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                    AdvantageMetricTile(
                        title: "Lead",
                        value: "\(scorecard.exceededCount)",
                        systemImage: BrowserAdvantageStatus.exceeds.systemImage,
                        tint: .green
                    )
                    AdvantageMetricTile(
                        title: "Parity",
                        value: "\(scorecard.matchedCount)",
                        systemImage: BrowserAdvantageStatus.matches.systemImage,
                        tint: .blue
                    )
                    AdvantageMetricTile(
                        title: "Next",
                        value: "\(scorecard.gapCount)",
                        systemImage: BrowserAdvantageStatus.gap.systemImage,
                        tint: .orange
                    )
                    AdvantageMetricTile(
                        title: "Coverage",
                        value: scorecard.baselineCoverageText,
                        systemImage: "scope",
                        tint: .purple
                    )
                }

                Text(scorecard.leadText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(BrowserAdvantageStatus.allCases) { status in
                    AdvantageStatusSection(
                        status: status,
                        capabilities: scorecard.capabilities(with: status),
                        browser: browser
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-advantage")
    }
}

private struct AdvantageMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 72)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AdvantageStatusSection: View {
    let status: BrowserAdvantageStatus
    let capabilities: [BrowserAdvantageCapability]
    @ObservedObject var browser: BrowserViewModel

    private var tint: Color {
        switch status {
        case .exceeds: .green
        case .matches: .blue
        case .gap: .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(status.title, systemImage: status.systemImage)
                .font(.headline)
                .foregroundStyle(tint)

            if capabilities.isEmpty {
                Text("No capabilities in this state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(capabilities) { capability in
                    AdvantageCapabilityCard(
                        capability: capability,
                        tint: tint,
                        browser: browser
                    )
                }
            }
        }
    }
}

private struct AdvantageCapabilityCard: View {
    let capability: BrowserAdvantageCapability
    let tint: Color
    @ObservedObject var browser: BrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(capability.title)
                    .font(.subheadline.weight(.semibold))
                Text(capability.category.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(capability.strawberryBaseline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(capability.dBrowserPosition)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            if !capability.evidence.isEmpty {
                FlowPillRow(items: capability.evidence, tint: tint)
            }

            if let action = capability.action {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.caption.weight(.semibold))
                        Text(action.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let target = action.targetPanel {
                        Button {
                            browser.selectPanel(target)
                        } label: {
                            Label(target.title, systemImage: target.systemImage)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct FlowPillRow: View {
    let items: [String]
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items.prefix(4), id: \.self) { item in
                Text(item)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if items.count > 4 {
                Text("+\(items.count - 4)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HistoryPanelView: View {
    @ObservedObject var browser: BrowserViewModel
    @State private var smartHistoryQuery = ""

    private var recallResults: [SmartHistoryRecallResult] {
        browser.smartHistoryRecall(smartHistoryQuery)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "History",
                    systemImage: BrowserPanel.history.systemImage,
                    subtitle: "Recently visited pages and local Smart History recall."
                )

                HStack(spacing: 10) {
                    TextField("Recall pages by description", text: $smartHistoryQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .accessibilityIdentifier("smart-history-query")
                    Button {
                        browser.clearSmartHistorySummaries()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Clear Smart History summaries")
                }

                if !smartHistoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recall")
                            .font(.headline)
                        if recallResults.isEmpty {
                            Text("No local recall matches.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(recallResults) { result in
                                Button {
                                    browser.openHistoryEntry(result.entry)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "magnifyingglass.circle")
                                            .frame(width: 22)
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.entry.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Text(result.matchedText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .accessibilityIdentifier("smart-history-results")
                }

                if browser.history.isEmpty {
                    EmptyPanelView(title: "No history yet", message: "Visited pages will appear here after navigation completes.")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(browser.history) { entry in
                            Button {
                                browser.openHistoryEntry(entry)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .frame(width: 24)
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(entry.urlString)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text(entry.visitedAt, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Open history entry")
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-history")
    }
}

private struct BookmarksPanelView: View {
    @ObservedObject var browser: BrowserViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    PanelHeaderView(
                        title: "Bookmarks",
                        systemImage: BrowserPanel.bookmarks.systemImage,
                        subtitle: "Saved pages and project defaults."
                    )
                    Spacer()
                    Button {
                        browser.addActivePageBookmark()
                    } label: {
                        Label("Add Current", systemImage: "bookmark.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(browser.activeTab?.urlString == BrowserURLResolver.homeURLString)
                }

                if browser.bookmarks.isEmpty {
                    EmptyPanelView(title: "No bookmarks", message: "Bookmark useful pages from the toolbar or this panel.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(browser.bookmarks) { bookmark in
                            Button {
                                browser.openBookmark(bookmark)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "bookmark")
                                            .frame(width: 22)
                                            .foregroundStyle(Color.accentColor)
                                        Text(bookmark.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(bookmark.urlString)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Open bookmark")
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-bookmarks")
    }
}

private struct BrowserNativeSearchResultsView: View {
    @ObservedObject var browser: BrowserViewModel
    let tabID: UUID
    let session: BrowserSearchSession

    private var synthesis: BrowserResearchSynthesisResult? {
        browser.researchSynthesisResultsBySessionID[session.id]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Native research search", systemImage: "sparkle.magnifyingglass")
                            .font(.title2.weight(.semibold))
                        Text(session.query)
                            .font(.title3)
                        Text(session.provider.map { "Structured results from \($0)" }
                            ?? "Structured search stays inside the configured JSON boundary.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if session.status == .completed {
                        Button {
                            browser.synthesizeSearchSession(tabID: tabID)
                        } label: {
                            Label("Synthesize with citations", systemImage: "text.book.closed")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(browser.activeCopilotRunCount > 0 || session.results.isEmpty)
                        .accessibilityIdentifier("native-search-synthesize")
                    }
                }

                switch session.status {
                case .idle, .loading:
                    ProgressView("Searching the configured structured endpoint…")
                case .configurationRequired:
                    Label(
                        session.errorMessage ?? "Configure DBROWSER_SEARCH_ENDPOINT with a dbrowser.search.v1 JSON service.",
                        systemImage: "gear.badge.questionmark"
                    )
                    .foregroundStyle(.secondary)
                case .failed:
                    Label(session.errorMessage ?? "Search failed.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                case .cancelled:
                    Label("Search cancelled.", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                case .completed:
                    if session.results.isEmpty {
                        Text("No structured results were returned.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(session.results) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            browser.openSearchResult(result)
                        } label: {
                            Text(result.title)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        Text(result.urlString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(result.snippet)
                            .foregroundStyle(.secondary)
                        Text(String(result.commitment.prefix(22)))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let synthesis {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Cited synthesis", systemImage: "checkmark.seal")
                            .font(.headline)
                        Text(synthesis.answer)
                            .textSelection(.enabled)
                        ForEach(synthesis.citations) { citation in
                            Link(destination: URL(string: citation.source.urlString)!) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(citation.source.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(citation.claim)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if let synthesisError = browser.researchSynthesisErrorsBySessionID[session.id] {
                    Label(synthesisError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("native-search-results")
    }
}

private struct CopilotPanelView: View {
    private enum WorkflowScheduleChoice: String, CaseIterable, Identifiable {
        case manual
        case everyLaunch
        case intervalHours

        var id: String { rawValue }

        var title: String {
            switch self {
            case .manual: "Manual"
            case .everyLaunch: "Every launch"
            case .intervalHours: "Hour interval"
            }
        }
    }

    @ObservedObject var browser: BrowserViewModel
    @StateObject private var voiceInput = BrowserVoiceInputController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var draftMessage = "Summarize this page and suggest next actions."
    @State private var correctionTargetID: String?
    @State private var correctionText = ""
    @State private var draftAttachments: [LLMTextFileAttachment] = []
    @State private var showsFileImporter = false
    @State private var attachmentError: String?
    @State private var showsWorkflowEditor = false
    @State private var workflowTitle = "Saved Copilot prompt"
    @State private var workflowTargetPattern = ""
    @State private var workflowScheduleChoice = WorkflowScheduleChoice.manual
    @State private var workflowIntervalHours = 24
    @State private var showsEarlierRuns = false
    @State private var visibleEarlierRunCount = 4

    private var latestRun: CopilotRun? {
        conversationRuns.first
    }

    private var conversationRuns: [CopilotRun] {
        browser.copilotRuns.filter { $0.conversationID == browser.llmConversation.id }
    }

    private var activeRun: CopilotRun? {
        browser.copilotRuns.first { $0.status == .queued || $0.status == .running }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    PanelHeaderView(
                        title: "Copilot",
                        systemImage: BrowserPanel.copilot.systemImage,
                        subtitle: "Work with the tabs you choose while keeping the page in view."
                    )
                    Spacer(minLength: 8)
                    Button {
                        browser.selectPanel(nil)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Close Copilot")
                    .accessibilityLabel("Close Copilot")
                    .accessibilityIdentifier("copilot-sidecar-close")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Conversation")
                            .font(.headline)
                        Spacer()
                        Menu {
                            ForEach(browser.llmConversations.sorted { $0.updatedAt > $1.updatedAt }) { conversation in
                                Button {
                                    browser.selectLLMConversation(conversation.id)
                                } label: {
                                    Label(
                                        conversation.title,
                                        systemImage: conversation.id == browser.llmConversation.id
                                            ? "checkmark.circle.fill"
                                            : "message"
                                    )
                                }
                            }
                        } label: {
                            Label("History", systemImage: "sidebar.left")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!browser.canChangeLLMConversation)
                        .help("Open a persisted conversation")
                        .accessibilityIdentifier("copilot-conversation-list")

                        Button {
                            browser.startNewLLMConversation()
                        } label: {
                            Label("New", systemImage: "plus.message")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!browser.canChangeLLMConversation)
                        .help("Start a new conversation")
                        .accessibilityIdentifier("copilot-new-conversation")

                        Picker(
                            "Model",
                            selection: Binding(
                                get: { browser.selectedLLMModelID },
                                set: { browser.selectLLMModel($0) }
                            )
                        ) {
                            ForEach(browser.llmModelOptions) { model in
                                Text(model.displayName)
                                    .tag(model.id)
                                    .disabled(!model.availability.isRunnable)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("copilot-model-picker")
                    }

                    HStack(spacing: 8) {
                        Label(browser.activeLLMModel.trustBoundary.title, systemImage: modelBoundarySystemImage(browser.activeLLMModel))
                        Text(browser.activeLLMModel.availability.message)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    CopilotContextPicker(browser: browser)

                    BrowserConnectorSectionView(coordinator: browser.connectorCoordinator)

                    if browser.activeLLMModel.providerKind == .llmGateway || !browser.llmGatewayServiceSnapshot.tokenPackages.isEmpty {
                        LLMGatewayTokenPurchaseSectionView(browser: browser)
                    }

                    LLMConversationTranscriptView(browser: browser)

                    TextEditor(text: $draftMessage)
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("copilot-prompt")

                    if !draftAttachments.isEmpty || attachmentError != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(draftAttachments) { attachment in
                                HStack(spacing: 8) {
                                    Label(attachment.displayName, systemImage: "doc.text")
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(attachment.textUTF8ByteCount) B")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                    Button {
                                        draftAttachments.removeAll { $0.id == attachment.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Remove \(attachment.displayName)")
                                }
                            }
                            if let attachmentError {
                                Label(attachmentError, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("copilot-file-attachments")
                    }

                    if voiceInput.state.isCapturingAudio || !voiceInput.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(voiceInputStatusText, systemImage: "waveform")
                                .font(.caption.weight(.semibold))
                            TextEditor(
                                text: Binding(
                                    get: { voiceInput.transcript },
                                    set: { voiceInput.editTranscript($0) }
                                )
                            )
                            .frame(minHeight: 70)
                            .padding(6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .accessibilityIdentifier("copilot-voice-transcript")
                            HStack(spacing: 8) {
                                Button("Use transcript") {
                                    let transcript = voiceInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !transcript.isEmpty else { return }
                                    draftMessage = transcript
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(voiceInput.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Clear") {
                                    voiceInput.clearTranscript()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(browser.activeTab?.displayURL ?? "Home")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            Button {
                                showsFileImporter = true
                            } label: {
                                Label("Attach text files", systemImage: "paperclip")
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .disabled(draftAttachments.count >= LLMTextFileAttachmentPolicy.maximumAttachments)
                            .help("Attach up to four bounded text files")
                            .accessibilityIdentifier("copilot-file-attachment")

                            Button {
                                Task {
                                    if voiceInput.state.isCapturingAudio {
                                        voiceInput.stopFromUserAction()
                                    } else {
                                        await voiceInput.startFromUserAction()
                                    }
                                }
                            } label: {
                                Label(
                                    voiceInput.state.isCapturingAudio ? "Stop voice input" : "Voice input",
                                    systemImage: voiceInput.state.isCapturingAudio ? "stop.circle" : "mic"
                                )
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .disabled(!voiceInput.state.isCapturingAudio && !voiceInput.canStartFromUserAction)
                            .help(voiceInput.state.isCapturingAudio ? "Stop voice input" : "Start on-device voice input")
                            .accessibilityIdentifier("copilot-voice-input")

                            Button {
                                browser.requestPageSnapshot()
                            } label: {
                                Label("Snapshot", systemImage: "doc.viewfinder")
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .help("Capture the current page")
                            .accessibilityLabel("Capture current page")
                            .accessibilityIdentifier("copilot-snapshot")
                            .disabled(!browser.canRequestActivePageSnapshot)

                            Button {
                                browser.requestTextSelection()
                            } label: {
                                Label("Capture selection", systemImage: "character.cursor.ibeam")
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .help("Capture the current page text selection for inline assistance")
                            .accessibilityLabel("Capture selected page text")
                            .accessibilityIdentifier("copilot-inline-selection")
                            .disabled(!browser.canRequestActivePageSnapshot)

                            Button {
                                prepareWorkflowEditor()
                            } label: {
                                Label("Save", systemImage: "tray.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .help("Configure and save as a manual or scheduled workflow")
                            .accessibilityLabel("Configure and save workflow")
                            .accessibilityIdentifier("copilot-save-workflow")
                            .disabled(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer(minLength: 8)

                            if let activeRun {
                                Button {
                                    browser.cancelCopilotRun(activeRun.id)
                                } label: {
                                    Label("Stop", systemImage: "stop.circle")
                                }
                                .buttonStyle(.bordered)
                                .labelStyle(.iconOnly)
                                .help("Stop Copilot run")
                                .accessibilityLabel("Stop Copilot run")
                                .accessibilityIdentifier("copilot-stop")
                            } else if browser.llmConversation.latestAssistantMessage != nil {
                                Button {
                                    browser.regenerateLastAssistantMessage()
                                } label: {
                                    Label("Regenerate", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .labelStyle(.iconOnly)
                                .help("Regenerate the last response with fresh page context")
                                .accessibilityIdentifier("copilot-regenerate")
                            }

                            Button {
                                sendMessage()
                            } label: {
                                Label(
                                    activeRun == nil ? "Send" : "Running",
                                    systemImage: "paperplane.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                activeRun != nil
                                    || !browser.canSendCopilotMessageWithFreshContext
                                    || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                            .accessibilityIdentifier("copilot-run")
                        }
                    }

                    if let selection = browser.latestTextSelection {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Selected page text", systemImage: "text.quote")
                                .font(.caption.weight(.semibold))
                            Text(selection.text)
                                .font(.caption)
                                .lineLimit(4)
                            HStack {
                                Text(String(selection.commitment.prefix(12)))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Add to composer") {
                                    draftMessage = "Help with this selected passage:\n\n\(selection.text)"
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("copilot-inline-selection-preview")
                    }

                    if browser.activeLLMModel.providerKind == .afMarket, !browser.availableAFMPacks.isEmpty {
                        Picker(
                            "Runner pack",
                            selection: Binding(
                                get: { browser.selectedAFMPackID ?? "" },
                                set: { browser.selectAFMPack($0.isEmpty ? nil : $0) }
                            )
                        ) {
                            Text("Router choice").tag("")
                            ForEach(browser.availableAFMPacks) { pack in
                                Text(pack.displayName).tag(pack.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("copilot-afm-pack-picker")
                    }

                    DeveloperWorkflowDeckView(browser: browser, activeRun: activeRun)
                }

                if let snapshot = browser.latestPageSnapshot {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Page Snapshot", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                        Text("\(snapshot.visibleText.count) text characters, \(snapshot.links.count) links, \(snapshot.buttons.count) buttons, \(snapshot.formControls.count) form controls")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let latestRun {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(latestRun.result?.title ?? "Copilot run")
                            .font(.headline)
                        HStack(spacing: 8) {
                            Text(latestRun.status.rawValue.capitalized)
                            if let usage = latestRun.usage {
                                Text("\(NSDecimalNumber(decimal: usage.creditsSpent).stringValue) credits")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let presentation = browser.copilotRunPresentations[latestRun.id] {
                            Label(
                                presentation.statusMessage,
                                systemImage: presentation.phase == .streaming ? "waveform" : "circle.dotted"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if !presentation.partialText.isEmpty,
                               latestRun.status == .queued || latestRun.status == .running {
                                Text(presentation.partialText)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if let summary = latestRun.result?.summary {
                            Text(summary)
                                .foregroundStyle(.secondary)
                        }

                        if latestRun.status == .completed, latestRun.result != nil {
                            Button {
                                _ = browser.requestOpenMindWriteback(for: latestRun.id)
                            } label: {
                                Label("Remember", systemImage: "brain")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("copilot-openmind-writeback")
                        }

                        ForEach(latestRun.events) { event in
                            Label(event.message, systemImage: event.kind == .approvalRequired ? "exclamationmark.triangle" : "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("copilot-result")
                }

                if conversationRuns.count > 1 {
                    DisclosureGroup("Earlier run activity", isExpanded: $showsEarlierRuns) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(conversationRuns.dropFirst().prefix(visibleEarlierRunCount)) { run in
                                earlierRunActivityCard(run)
                            }
                            if conversationRuns.count - 1 > visibleEarlierRunCount {
                                Button("Show more runs") {
                                    visibleEarlierRunCount += 4
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("copilot-run-history")
                }

                if !browser.copilotToolProposals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Tool approvals", systemImage: "checkmark.shield")
                            .font(.headline)
                        ForEach(browser.copilotToolProposals.prefix(6)) { proposal in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(proposal.toolName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(proposal.status.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(proposal.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(proposal.command.approvalSummary)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let targetTab = browser.tabs.first(where: { $0.id == proposal.targetTabID }) {
                                    Text("Exact current page: \(targetTab.urlString)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text("Page \(proposal.targetPageCommitment.map { String($0.prefix(12)) } ?? "legacy/unbound") · command \(proposal.commandCommitment.map { String($0.prefix(12)) } ?? "legacy/unbound") · arguments \(String(proposal.argumentCommitment.prefix(12))) · binding \(proposal.approvalBindingCommitment.map { String($0.prefix(12)) } ?? "legacy/unbound")")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if proposal.status == .pendingApproval {
                                    HStack(spacing: 8) {
                                        Button("Approve once") {
                                            browser.approveToolProposal(proposal.id)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        Button("Deny") {
                                            browser.denyToolProposal(proposal.id)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("copilot-tool-proposals")
                }

                if let recall = browser.latestOpenMindRecall {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("OpenMind Memory", systemImage: "brain")
                            .font(.headline)
                        Text(openMindRecallSummary(recall))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !recall.memories.isEmpty {
                            ForEach(recall.memories.prefix(3)) { memory in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(memory.summary)
                                        .font(.caption)
                                        .lineLimit(2)
                                    Spacer()
                                    Button {
                                        correctionTargetID = memory.id
                                        correctionText = ""
                                    } label: {
                                        Label("Correct", systemImage: "exclamationmark.bubble")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        if let correctionTargetID {
                            Divider()
                            Text("Correction for \(correctionTargetID)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("Correction", text: $correctionText)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("copilot-openmind-correction-text")
                            HStack(spacing: 8) {
                                Button {
                                    _ = browser.requestOpenMindCorrection(
                                        targetID: correctionTargetID,
                                        correctionText: correctionText
                                    )
                                    self.correctionTargetID = nil
                                    correctionText = ""
                                } label: {
                                    Label("Submit correction", systemImage: "checkmark.message")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("copilot-openmind-correction-submit")

                                Button {
                                    self.correctionTargetID = nil
                                    correctionText = ""
                                } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if let bundle = recall.evidenceBundle {
                            Divider()
                            Label("Evidence bundle \(bundle.bundleID): \(bundle.items.count) item\(bundle.items.count == 1 ? "" : "s").", systemImage: "doc.badge.magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let note = bundle.governanceNotes.first {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        if recall.decision.status == .stepUpRequired {
                            Divider()
                            Button {
                                _ = browser.requestOpenMindStepUp()
                            } label: {
                                Label("Request step-up", systemImage: "checkmark.shield")
                            }
                            .buttonStyle(.bordered)
                            .disabled((browser.latestOpenMindStepUpRequest ?? recall.stepUpRequest) != nil)
                            .accessibilityIdentifier("copilot-openmind-step-up")
                        }
                        if let stepUpRequest = browser.latestOpenMindStepUpRequest ?? recall.stepUpRequest {
                            Divider()
                            Label(openMindStepUpSummary(stepUpRequest), systemImage: "checkmark.shield")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let writeback = browser.latestOpenMindWriteback {
                            Divider()
                            Label(openMindWritebackSummary(writeback), systemImage: openMindWritebackSystemImage(writeback))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let correction = browser.latestOpenMindCorrection {
                            Divider()
                            Label(openMindCorrectionSummary(correction), systemImage: openMindCorrectionSystemImage(correction))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("copilot-openmind-memory")
                }

                if !browser.copilotWorkflows.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workflows")
                            .font(.headline)
                        ForEach(browser.copilotWorkflows) { workflow in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workflow.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(workflow.promptTemplate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(workflowScheduleLabel(workflow))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button {
                                    _ = browser.runWorkflow(workflow.id)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.borderless)
                                .disabled(!workflow.isEnabled || activeRun != nil)
                                .help("Run workflow")
                            }
                            .padding(.vertical, 6)

                            if let state = browser.scheduledWorkflowStates.first(where: { $0.workflowID == workflow.id }) {
                                Label(state.message, systemImage: state.phase == .waitingForUser ? "person.crop.circle.badge.clock" : "clock.arrow.circlepath")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("copilot-workflows")
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-copilot")
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.plainText, .utf8PlainText, .json, .commaSeparatedText, .sourceCode],
            allowsMultipleSelection: true
        ) { result in
            importTextAttachments(result)
        }
        .sheet(isPresented: $showsWorkflowEditor) {
            workflowEditor
        }
        .onDisappear {
            voiceInput.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                voiceInput.cancel()
            }
        }
        .onChange(of: browser.llmConversation.id) { _, _ in
            showsEarlierRuns = false
            visibleEarlierRunCount = 4
        }
    }

    private var voiceInputStatusText: String {
        switch voiceInput.state {
        case .recording:
            "Recording on device"
        case .transcribing:
            "Transcribing on device"
        case .stopped:
            "Editable voice transcript"
        case .unavailable(let reason), .denied(let reason):
            reason
        case .failed(let message):
            message
        }
    }

    private var workflowEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save workflow")
                .font(.title2.weight(.semibold))
            Text("Scheduled workflows run only while dBrowser is open, on a visible fully loaded tab that exactly matches the target. Browser and connector mutations still require their normal approvals.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Workflow title", text: $workflowTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("copilot-workflow-title")
            TextField("Target URL pattern (blank allows any eligible tab)", text: $workflowTargetPattern)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("copilot-workflow-target")

            Picker("Schedule", selection: $workflowScheduleChoice) {
                ForEach(WorkflowScheduleChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("copilot-workflow-schedule")

            if workflowScheduleChoice == .intervalHours {
                Stepper(
                    "Run every \(workflowIntervalHours) hour\(workflowIntervalHours == 1 ? "" : "s")",
                    value: $workflowIntervalHours,
                    in: 1...720
                )
                .accessibilityIdentifier("copilot-workflow-interval")
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showsWorkflowEditor = false
                }
                .buttonStyle(.bordered)
                Button("Save workflow") {
                    saveWorkflow()
                    showsWorkflowEditor = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    workflowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("copilot-workflow-save-confirm")
            }
        }
        .padding(24)
        .frame(maxWidth: 560)
    }

    private func earlierRunActivityCard(_ run: CopilotRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.result?.title ?? "Copilot run")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(run.status.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let summary = run.result?.summary {
                Text(summary)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            if let usage = run.usage {
                Text("\(NSDecimalNumber(decimal: usage.creditsSpent).stringValue) credits")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(run.events) { event in
                Label(
                    event.message,
                    systemImage: event.kind == .approvalRequired
                        ? "exclamationmark.triangle"
                        : "checkmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func prepareWorkflowEditor() {
        let tabTitle = browser.activeTab?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        workflowTitle = tabTitle.isEmpty ? "Saved Copilot prompt" : "\(tabTitle) workflow"
        workflowTargetPattern = workflowDefaultTargetPattern()
        workflowScheduleChoice = .manual
        workflowIntervalHours = 24
        showsWorkflowEditor = true
    }

    private func saveWorkflow() {
        let target = workflowTargetPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let schedule: CopilotWorkflowSchedule = switch workflowScheduleChoice {
        case .manual:
            .manual
        case .everyLaunch:
            .everyLaunch
        case .intervalHours:
            .interval(hours: workflowIntervalHours)
        }
        _ = browser.saveCopilotWorkflow(
            title: workflowTitle,
            promptTemplate: draftMessage,
            targetURLPattern: target.isEmpty ? nil : target,
            allowedActions: [.click, .focus, .scroll, .waitForSelector],
            schedule: schedule
        )
    }

    private func workflowDefaultTargetPattern() -> String {
        guard let rawURL = browser.activeTab?.urlString,
              let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else {
            return ""
        }
        var target = "\(scheme)://\(host)"
        if let port = components.port {
            target += ":\(port)"
        }
        return target
    }

    private func workflowScheduleLabel(_ workflow: SavedCopilotWorkflow) -> String {
        let schedule: String = switch workflow.schedule.kind {
        case .manual:
            "Manual"
        case .everyLaunch:
            "Every launch while dBrowser is open"
        case .intervalHours:
            "Every \(workflow.schedule.intervalHours ?? 1) hour(s) while dBrowser is open"
        }
        return "\(schedule) · Target: \(workflow.targetURLPattern ?? "any eligible visible tab")"
    }

    private func sendMessage() {
        if browser.sendLLMMessageWithFreshContext(
            draftMessage,
            fileAttachments: draftAttachments
        ) != nil {
            draftMessage = ""
            draftAttachments = []
            attachmentError = nil
        }
    }

    private func importTextAttachments(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var imported = draftAttachments
            for url in urls where imported.count < LLMTextFileAttachmentPolicy.maximumAttachments {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: LLMTextFileAttachmentPolicy.textUTF8ByteLimit + 1) ?? Data()
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                let mediaType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "text/plain"
                imported.append(
                    LLMTextFileAttachment(
                        displayName: url.lastPathComponent,
                        mediaType: mediaType,
                        text: text
                    )
                )
            }
            draftAttachments = imported
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func modelBoundarySystemImage(_ model: LLMModelProfile) -> String {
        switch model.trustBoundary {
        case .onDevice:
            return "cpu"
        case .serviceBacked:
            return "server.rack"
        case .remoteGateway:
            return "network"
        }
    }

    private func openMindWritebackSummary(_ outcome: OpenMindWritebackOutcome) -> String {
        switch outcome.status {
        case .recorded:
            return "Writeback recorded\(outcome.revisionID.map { " as \($0)" } ?? "")."
        case .proposed:
            return "Writeback proposed: \(outcome.message)"
        case .denied:
            return "Writeback denied: \(outcome.message)"
        case .unavailable:
            return "Writeback unavailable: \(outcome.message)"
        }
    }

    private func openMindStepUpSummary(_ request: OpenMindStepUpRequest) -> String {
        let scopeText = request.requestedScopes.isEmpty ? "" : " for \(request.requestedScopes.joined(separator: ", "))"
        return "Step-up \(request.status)\(scopeText): \(request.requestID)"
    }

    private func openMindWritebackSystemImage(_ outcome: OpenMindWritebackOutcome) -> String {
        switch outcome.status {
        case .recorded:
            return "checkmark.seal"
        case .proposed:
            return "doc.badge.clock"
        case .denied:
            return "hand.raised"
        case .unavailable:
            return "xmark.seal"
        }
    }

    private func openMindCorrectionSummary(_ outcome: OpenMindCorrectionOutcome) -> String {
        switch outcome.status {
        case .recorded:
            return "Correction recorded\(outcome.correctionID.map { " as \($0)" } ?? "")."
        case .proposed:
            return "Correction queued: \(outcome.message)"
        case .denied:
            return "Correction denied: \(outcome.message)"
        case .unavailable:
            return "Correction unavailable: \(outcome.message)"
        }
    }

    private func openMindCorrectionSystemImage(_ outcome: OpenMindCorrectionOutcome) -> String {
        switch outcome.status {
        case .recorded:
            return "checkmark.message"
        case .proposed:
            return "doc.badge.clock"
        case .denied:
            return "hand.raised"
        case .unavailable:
            return "xmark.seal"
        }
    }

    private func openMindRecallSummary(_ recall: OpenMindMemoryRecallResult) -> String {
        switch recall.decision.status {
        case .allowed:
            let memoryText = "Allowed \(recall.memories.count) item\(recall.memories.count == 1 ? "" : "s")."
            guard let evidenceBundle = recall.evidenceBundle else {
                return memoryText
            }
            return "\(memoryText) Evidence bundle has \(evidenceBundle.items.count) item\(evidenceBundle.items.count == 1 ? "" : "s")."
        case .denied:
            return "Denied: \(recall.decision.reason)"
        case .stepUpRequired:
            return "Step-up required: \(recall.decision.stepUpPrompt ?? recall.decision.reason)"
        case .unavailable:
            return "Unavailable: \(recall.decision.reason)"
        }
    }
}

private struct CopilotContextPicker: View {
    @ObservedObject var browser: BrowserViewModel

    private var selectedCount: Int {
        browser.copilotContextTabOptions.filter(\.isSelected).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let activeTab = browser.activeTab {
                HStack(spacing: 8) {
                    Label(
                        browser.isWaitingForActivePageContext
                            ? "Waiting for page"
                            : (browser.canAttachActivePageToCopilotContext ? "Current tab" : "Page context off"),
                        systemImage: browser.isWaitingForActivePageContext
                            ? "clock"
                            : (browser.canAttachActivePageToCopilotContext ? "globe" : "shield.slash")
                    )
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(activeTab.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(
                        systemName: browser.canAttachActivePageToCopilotContext
                            ? "checkmark.circle.fill"
                            : (browser.isWaitingForActivePageContext ? "circle.dotted" : "minus.circle.fill")
                    )
                        .foregroundStyle(browser.canAttachActivePageToCopilotContext ? Color.accentColor : Color.gray)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    browser.isWaitingForActivePageContext
                        ? "Waiting for current tab to finish loading, \(activeTab.title)"
                        : browser.canAttachActivePageToCopilotContext
                        ? "Current tab context, \(activeTab.title)"
                        : "Page context off, \(activeTab.title)"
                )
                .accessibilityHint(activeTab.displayURL)
            }

            HStack(spacing: 8) {
                Label("Related tabs", systemImage: "square.stack.3d.up")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Menu {
                    if browser.copilotContextTabOptions.isEmpty {
                        Text("No tabs available")
                    } else {
                        ForEach(browser.copilotContextTabOptions) { option in
                            Button {
                                if option.isAvailable || option.isSelected {
                                    browser.setCopilotContextTab(option.id, isSelected: !option.isSelected)
                                } else {
                                    browser.prepareInactiveTabCapture(option.id)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(
                                        "\(option.title) · \(option.availabilityLabel)",
                                        systemImage: option.isSelected
                                            ? "checkmark.circle.fill"
                                            : (option.isAvailable ? "circle" : "camera.viewfinder")
                                    )
                                    Text(option.displayURL)
                                        .font(.caption2)
                                }
                            }
                            .accessibilityLabel(option.title)
                            .accessibilityValue(option.isSelected ? "Selected" : "Not selected")
                            .accessibilityHint("\(option.displayURL). \(option.availabilityLabel)")
                            .accessibilityIdentifier("copilot-context-tab-\(option.id)")
                        }
                    }
                } label: {
                    Label(
                        selectedCount == 1 ? "1 related" : "\(selectedCount) related",
                        systemImage: "chevron.down"
                    )
                }
                .fixedSize()
                .help("Choose related open tabs Copilot may use with the current tab")
                .accessibilityLabel("Choose related Copilot tabs")
                .accessibilityValue("\(selectedCount) related tabs selected")
                .accessibilityIdentifier("copilot-context-picker")
            }

            if browser.inactiveTabCaptureState.phase != .idle {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        browser.inactiveTabCaptureState.tabTitle ?? "Inactive tab capture",
                        systemImage: "eye.trianglebadge.exclamationmark"
                    )
                    .font(.caption.weight(.semibold))
                    Text(browser.inactiveTabCaptureState.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let displayURL = browser.inactiveTabCaptureState.displayURLString {
                        Text(displayURL)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if browser.inactiveTabCaptureState.phase == .awaitingConfirmation {
                        HStack(spacing: 8) {
                            Button("Capture once") {
                                browser.confirmInactiveTabCapture()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Cancel") {
                                browser.cancelInactiveTabCapture()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if browser.inactiveTabCaptureState.phase == .captured
                                || browser.inactiveTabCaptureState.phase == .failed {
                        Button("Dismiss") {
                            browser.cancelInactiveTabCapture()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("copilot-inactive-tab-capture")
            }

            if selectedCount == 0 {
                Text(
                    browser.isWaitingForActivePageContext
                        ? "Waiting for the current tab to finish loading before a fresh snapshot can be attached."
                        : browser.canAttachActivePageToCopilotContext
                        ? "Current tab only. Visit another tab to capture it before adding it as context."
                        : "This tab contributes no current URL or snapshot. Prior conversation context remains in the selected model's minimized ledger."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(browser.copilotContextTabOptions.filter(\.isSelected)) { option in
                            Button {
                                browser.setCopilotContextTab(option.id, isSelected: false)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(option.title)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(option.displayURL)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.semibold))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(option.title) from context")
                            .accessibilityLabel("Remove \(option.title) from Copilot context")
                            .accessibilityHint("\(option.displayURL). \(option.availabilityLabel)")
                            .accessibilityIdentifier("copilot-context-chip-\(option.id)")
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("copilot-context")
    }
}

private struct DeveloperWorkflowDeckView: View {
    @ObservedObject var browser: BrowserViewModel
    let activeRun: CopilotRun?

    private let surfaceColumns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    private var templates: [BrowserDeveloperWorkflowTemplate] {
        browser.developerWorkflowTemplates
    }

    private var surfaces: [BrowserDeveloperAutomationSurface] {
        browser.developerAutomationSurfaces
    }

    private var readySurfaceCount: Int {
        surfaces.filter { $0.status == .ready }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Developer Workflows", systemImage: "hammer")
                        .font(.headline)
                    Text("Local evidence runs for CI, PR review, QA, flags, monitoring, console work, and routines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Label("\(readySurfaceCount)/\(surfaces.count) ready", systemImage: "checkmark.seal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityIdentifier("developer-workflow-ready-count")
            }

            LazyVGrid(columns: surfaceColumns, alignment: .leading, spacing: 8) {
                ForEach(surfaces) { surface in
                    DeveloperWorkflowSurfaceChip(surface: surface)
                }
            }

            Divider()

            ViewThatFits {
                HStack(spacing: 8) {
                    workflowFactLabels
                }
                VStack(alignment: .leading, spacing: 4) {
                    workflowFactLabels
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(templates) { template in
                    DeveloperWorkflowTemplateLaunchRow(
                        template: template,
                        activeRun: activeRun,
                        start: { _ = browser.startDeveloperWorkflow(template) }
                    )
                }
            }

            if let latestDeveloperRun = browser.developerWorkflowRuns.first {
                Divider()
                DeveloperWorkflowLatestRunView(run: latestDeveloperRun)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("copilot-developer-workflows")
    }

    @ViewBuilder
    private var workflowFactLabels: some View {
        Label("\(templates.count) templates", systemImage: "square.stack.3d.up")
        Label("Local ledger", systemImage: "lock.doc")
        Label("Approval gates", systemImage: "checkmark.shield")
    }
}

private struct DeveloperWorkflowSurfaceChip: View {
    let surface: BrowserDeveloperAutomationSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(statusColor)
                Text(surface.id.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Text(surface.status.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            Text(surface.privacyBoundary.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(surface.invocation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("developer-workflow-surface-\(surface.id.rawValue)")
    }

    private var systemImage: String {
        switch surface.id {
        case .copilot:
            return "sparkles"
        case .mcp:
            return "point.3.connected.trianglepath.dotted"
        case .localREPL:
            return "terminal"
        case .routine:
            return "calendar.badge.clock"
        }
    }

    private var statusColor: Color {
        switch surface.status {
        case .ready:
            return .green
        case .staged:
            return .orange
        }
    }
}

private struct DeveloperWorkflowTemplateLaunchRow: View {
    let template: BrowserDeveloperWorkflowTemplate
    let activeRun: CopilotRun?
    let start: () -> Void

    private var evidenceSummary: String {
        template.defaultEvidenceKinds.prefix(4).map(\.title).joined(separator: " / ")
    }

    private var approvalSummary: String {
        template.protectedActions.isEmpty
            ? "No protected mutations"
            : "\(template.protectedActions.count) approval gate\(template.protectedActions.count == 1 ? "" : "s")"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(evidenceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Label(approvalSummary, systemImage: template.protectedActions.isEmpty ? "doc.badge.magnifyingglass" : "checkmark.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                start()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(activeRun != nil)
            .help(activeRun == nil ? "Start local evidence workflow" : "Wait for the active Copilot run to finish")
            .accessibilityIdentifier("developer-workflow-start-\(template.id)")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct DeveloperWorkflowLatestRunView: View {
    let run: BrowserDeveloperWorkflowRun

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: run.requiresApprovalBeforeMutation ? "checkmark.shield" : "doc.badge.magnifyingglass")
                .foregroundStyle(run.requiresApprovalBeforeMutation ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.title)
                    .font(.caption.weight(.semibold))
                Text("\(run.status.rawValue) - \(run.reviewSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label("\(run.evidenceItems.count) evidence", systemImage: "tray.full")
                    Label(run.requiresApprovalBeforeMutation ? "approval required" : "local evidence only", systemImage: "lock")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("developer-workflow-latest-run")
    }
}

private struct LLMGatewayTokenPurchaseSectionView: View {
    @ObservedObject var browser: BrowserViewModel

    private var packages: [LLMGatewayTokenPackage] {
        browser.llmGatewayServiceSnapshot.tokenPackages
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Gateway Tokens", systemImage: "ticket")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await browser.refreshLLMGatewayTokenPackages() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Refresh gateway token packages")
                .accessibilityIdentifier("llm-gateway-token-refresh")
            }

            if let message = browser.llmGatewayServiceSnapshot.tokenPurchaseMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if packages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No token packages")
                        .font(.subheadline.weight(.semibold))
                    Text("Configure a gateway token package or connect to a gateway that advertises token packages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(packages.enumerated()), id: \.element.id) { index, package in
                    VStack(spacing: 8) {
                        if index > 0 {
                            Divider()
                        }
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(package.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(package.ticketCount) \(package.tokenClass.rawValue) tickets - \(package.amountText) - \(package.network)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let detail = package.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await browser.buyLLMGatewayTokens(packageID: package.id) }
                            } label: {
                                Label("Buy", systemImage: "cart.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(browser.isBuyingLLMGatewayTokens || !package.isPurchasable)
                            .accessibilityIdentifier("llm-gateway-token-buy-\(package.id)")
                        }
                    }
                }
            }

            if let receipt = browser.latestLLMGatewayTokenPurchase {
                Label(
                    "Stored \(receipt.ticketCount) \(receipt.tokenClass.rawValue) tickets from \(receipt.packageID).",
                    systemImage: "checkmark.seal"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = browser.llmGatewayTokenPurchaseError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("llm-gateway-token-purchase")
    }
}

private struct LLMConversationTranscriptView: View {
    @ObservedObject var browser: BrowserViewModel
    @State private var visibleMessageCount = 20
    @State private var visibleEventCount = 20
    @State private var showsAuditEvents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if browser.llmConversation.messages.isEmpty {
                Text("No messages yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                if browser.llmConversation.messages.count > visibleMessageCount {
                    Button(
                        "Show \(min(20, browser.llmConversation.messages.count - visibleMessageCount)) older messages"
                    ) {
                        visibleMessageCount += 20
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("copilot-show-older-messages")
                }
                ForEach(browser.llmConversation.messages.suffix(visibleMessageCount)) { message in
                    LLMConversationMessageRow(
                        message: message,
                        modelName: modelName(for: message.modelID)
                    )
                }
            }

            if !browser.llmConversation.events.isEmpty {
                DisclosureGroup(
                    "Conversation audit · \(browser.llmConversation.events.count) events",
                    isExpanded: $showsAuditEvents
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        if browser.llmConversation.events.count > visibleEventCount {
                            Button("Show older audit events") {
                                visibleEventCount += 20
                            }
                            .buttonStyle(.bordered)
                        }
                        ForEach(browser.llmConversation.events.suffix(visibleEventCount)) { event in
                            Label(event.message, systemImage: conversationEventSystemImage(event.kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                }
                .accessibilityIdentifier("copilot-conversation-audit")
            }
        }
        .onChange(of: browser.llmConversation.id) { _, _ in
            visibleMessageCount = 20
            visibleEventCount = 20
            showsAuditEvents = false
        }
        .accessibilityIdentifier("copilot-conversation")
    }

    private func modelName(for id: String?) -> String? {
        guard let id else { return nil }
        return browser.llmModelOptions.first { $0.id == id }?.displayName ?? id
    }

    private func conversationEventSystemImage(_ kind: LLMConversationEventKind) -> String {
        switch kind {
        case .conversationCreated:
            return "message"
        case .modelSwitched:
            return "arrow.triangle.2.circlepath"
        case .userMessageAdded:
            return "person"
        case .assistantRunStarted:
            return "sparkles"
        case .assistantMessageAdded:
            return "checkmark.circle"
        case .pageSnapshotAttached:
            return "doc.viewfinder"
        case .memoryContextAttached:
            return "brain"
        case .contextCompressed:
            return "rectangle.compress.vertical"
        case .providerFallback:
            return "arrow.uturn.backward.circle"
        case .toolProposed:
            return "wrench.and.screwdriver"
        case .toolApproved:
            return "checkmark.shield"
        case .toolDenied:
            return "xmark.shield"
        case .toolExecuted:
            return "play.square.stack"
        case .summaryArtifactCreated:
            return "rectangle.compress.vertical"
        case .researchSourcesAttached:
            return "text.book.closed"
        case .regenerated:
            return "arrow.clockwise.circle"
        }
    }
}

private struct LLMConversationMessageRow: View {
    let message: LLMConversationMessage
    let modelName: String?

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(isUser ? "You" : (modelName ?? "Assistant"), systemImage: isUser ? "person.crop.circle" : "sparkles")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let usage = message.usage {
                    Text("\(NSDecimalNumber(decimal: usage.creditsSpent).stringValue) credits")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let provenance = message.providerProvenance {
                Label(
                    "\(provenance.providerDisplayName) · \(provenance.trustBoundary.title) · \(provenance.actualModelID)",
                    systemImage: provenance.trustBoundary == .onDevice ? "cpu" : "network"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help(provenance.boundarySummary)
            }

            if let snapshot = message.snapshotAttachment {
                Label(snapshot.title, systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !message.memoryCitations.isEmpty {
                Text(message.memoryCitations.map(\.id).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ForEach(message.fileAttachments) { attachment in
                Label(
                    "\(attachment.displayName) · \(String(attachment.contentSHA256.prefix(18)))",
                    systemImage: "doc.text"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            ForEach(message.sourceCitations) { citation in
                if let urlString = citation.urlString, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label(citation.title, systemImage: "link")
                    }
                    .font(.caption)
                } else {
                    Label(citation.title, systemImage: "text.book.closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if message.regeneratedFromMessageID != nil {
                Label("Regenerated response", systemImage: "arrow.clockwise.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUser ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MCPServersPanelView: View {
    @ObservedObject var browser: BrowserViewModel

    private var inventory: MCPServerInventory {
        MCPServerInventory(servers: browser.mcpServers)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "MCP Servers",
                    systemImage: BrowserPanel.mcp.systemImage,
                    subtitle: "Connect tool, resource, and prompt servers for Copilot and agent workflows."
                )

                HStack(alignment: .firstTextBaseline) {
                    Label(inventory.summary, systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    MCPAddServerButton(title: "Add HTTP", systemImage: "globe", transport: .http, browser: browser)
                    MCPAddServerButton(title: "Add WebSocket", systemImage: "point.3.connected.trianglepath.dotted", transport: .websocket, browser: browser)
                    MCPAddServerButton(title: "Add STDIO", systemImage: "terminal", transport: .stdio, browser: browser)
                }

                if browser.mcpServers.isEmpty {
                    EmptyPanelView(
                        title: "No MCP servers",
                        message: "Add an MCP server profile before connecting tools to the runtime."
                    )
                } else {
                    ForEach(browser.mcpServers) { server in
                        MCPServerCardView(browser: browser, server: server)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-mcp")
    }
}

private struct A2UITokenPanelView: View {
    @StateObject private var appStore = A2UIAppStore()
    @StateObject private var renderer = A2UITokenRenderer()
    @State private var tokenText = A2UIAppStoreListing.travelBooker.tokenStream
    @State private var pendingTokenText: String?
    @State private var isRendering = false
    @State private var didRenderInitialSample = false
    @State private var selectedStoreAppID = A2UIAppStoreListing.featured.first?.id ?? ""
    @State private var selectedRuntimeID = A2UIAppStoreListing.travelBooker.runtimeProfileID
    @State private var previewFocusRequest = 0

    private var statusColor: Color {
        if !renderer.errors.isEmpty {
            return .orange
        }
        return renderer.hasSurface ? .green : .secondary
    }

    private var selectedRuntime: A2UIRuntimeProfile {
        A2UIRuntimeProfile.available.first { $0.id == selectedRuntimeID } ?? .logosBasecamp
    }

    private var selectedStoreApp: A2UIAppStoreListing {
        appStore.listings.first { $0.id == selectedStoreAppID } ?? appStore.listings.first ?? .travelBooker
    }

    private var previewedStoreApp: A2UIAppStoreListing {
        appStore.previewingListing ?? selectedStoreApp
    }

    var body: some View {
        ScrollViewReader { previewScrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "A2UI App Store",
                    systemImage: BrowserPanel.a2ui.systemImage,
                    subtitle: "Install A2UI-powered apps, bind them to a runtime profile, and inspect token streams when needed."
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                    A2UIMetricTile(title: "Apps", value: "\(appStore.listings.count) listed", systemImage: "square.grid.3x3")
                    A2UIMetricTile(title: "Installed", value: "\(appStore.installedCount)", systemImage: "checkmark.seal")
                    A2UIMetricTile(title: "Runtime", value: selectedRuntime.title, systemImage: "shippingbox")
                    A2UIMetricTile(title: "Surface", value: renderer.hasSurface ? "Rendered" : "Empty", systemImage: renderer.hasSurface ? "checkmark.circle" : "circle")
                }

                A2UIAppStoreSectionView(
                    appStore: appStore,
                    selectedAppID: $selectedStoreAppID,
                    previewingAppID: appStore.previewingListingID,
                    onInstall: installStoreApp,
                    onOpen: openStoreApp,
                    onPreview: loadStoreAppPreview,
                    onUninstall: uninstallStoreApp
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Runtime")
                        .font(.headline)
                    Picker("Runtime", selection: $selectedRuntimeID) {
                        ForEach(A2UIRuntimeProfile.available) { runtime in
                            Text(runtime.title).tag(runtime.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("a2ui-runtime-picker")

                    A2UIRuntimeProfileView(profile: selectedRuntime)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(renderer.renderSummary.statusText, systemImage: renderer.hasSurface ? "square.grid.2x2" : "square.dashed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor)
                        Spacer()
                    }

                    if !renderer.renderedTextEvents.isEmpty {
                        Text(renderer.renderedTextEvents.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !renderer.errors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(renderer.errors, id: \.self) { error in
                                Text(error)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.orange)
                                    .lineLimit(3)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Developer token stream")
                        .font(.headline)
                    Text("Loaded from \(previewedStoreApp.title) or the sample stream. Edit the stream to inspect how A2UI output becomes native widgets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $tokenText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 220)
                        .padding(8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                        }
                        .accessibilityIdentifier("a2ui-token-editor")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                        Button {
                            Task { await renderTokens() }
                        } label: {
                            Label(isRendering ? "Rendering" : "Render", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRendering)
                        .accessibilityIdentifier("a2ui-render")

                        Button {
                            tokenText = A2UITokenRenderer.sampleTokens
                            Task { await renderTokens() }
                        } label: {
                            Label("Sample", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            renderer.clearActionLog()
                        } label: {
                            Label("Clear Log", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(renderer.actionLog.isEmpty)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Previewing \(previewedStoreApp.title)", systemImage: "eye")
                            .font(.headline)
                        Spacer()
                        Text(previewedStoreApp.runtimeProfile.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(previewedStoreApp.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    A2UITokenSurfacePreview(renderer: renderer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .id("a2ui-app-preview")
                .accessibilityIdentifier("a2ui-app-preview")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Action log")
                        .font(.headline)
                    if renderer.actionLog.isEmpty {
                        Text("No widget actions yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(renderer.actionLog) { action in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(action.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(action.sourceComponentID) - \(action.contextSummary)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .background(platformBackgroundColor)
            .accessibilityIdentifier("panel-content-a2ui")
            .task {
                guard !didRenderInitialSample else { return }
                didRenderInitialSample = true
                await renderTokens()
            }
            .onChange(of: previewFocusRequest) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    previewScrollProxy.scrollTo("a2ui-app-preview", anchor: .top)
                }
            }
        }
    }

    @MainActor
    private func renderTokens() async {
        guard !isRendering else {
            pendingTokenText = tokenText
            return
        }

        isRendering = true
        var tokenTextToRender: String? = tokenText

        while let rawTokens = tokenTextToRender {
            pendingTokenText = nil
            await renderer.render(rawTokens: rawTokens)
            tokenTextToRender = pendingTokenText
        }

        isRendering = false
    }

    private func installStoreApp(_ listing: A2UIAppStoreListing) {
        selectedStoreAppID = listing.id
        appStore.install(listing)
    }

    private func openStoreApp(_ listing: A2UIAppStoreListing) {
        appStore.open(listing)
        loadStoreAppPreview(listing)
    }

    private func loadStoreAppPreview(_ listing: A2UIAppStoreListing) {
        selectedStoreAppID = listing.id
        selectedRuntimeID = listing.runtimeProfileID
        appStore.preview(listing)
        tokenText = listing.tokenStream
        renderer.clearActionLog()
        previewFocusRequest += 1
        Task { await renderTokens() }
    }

    private func uninstallStoreApp(_ listing: A2UIAppStoreListing) {
        appStore.uninstall(listing)
    }
}

private struct A2UIAppStoreSectionView: View {
    @ObservedObject var appStore: A2UIAppStore
    @Binding var selectedAppID: String
    let previewingAppID: String?
    let onInstall: (A2UIAppStoreListing) -> Void
    let onOpen: (A2UIAppStoreListing) -> Void
    let onPreview: (A2UIAppStoreListing) -> Void
    let onUninstall: (A2UIAppStoreListing) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("App Store")
                    .font(.headline)
                Spacer()
                Label("\(appStore.installedCount) installed", systemImage: "checkmark.seal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(appStore.listings) { listing in
                    A2UIAppStoreCardView(
                        listing: listing,
                        state: appStore.state(for: listing),
                        isSelected: selectedAppID == listing.id,
                        isPreviewing: previewingAppID == listing.id,
                        onSelect: { selectedAppID = listing.id },
                        onInstall: { onInstall(listing) },
                        onOpen: { onOpen(listing) },
                        onPreview: { onPreview(listing) },
                        onUninstall: { onUninstall(listing) }
                    )
                }
            }
        }
    }
}

private struct A2UIAppStoreCardView: View {
    let listing: A2UIAppStoreListing
    let state: A2UIAppInstallState
    let isSelected: Bool
    let isPreviewing: Bool
    let onSelect: () -> Void
    let onInstall: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onUninstall: () -> Void

    private var borderColor: Color {
        if isPreviewing {
            return .green
        }
        return isSelected ? Color.accentColor : Color.secondary.opacity(0.2)
    }

    private var cardBackground: Color {
        if isPreviewing {
            return Color.green.opacity(0.10)
        }
        return isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.08)
    }

    private var previewButtonTitle: String {
        isPreviewing ? "Previewing" : "Preview"
    }

    private var previewButtonSymbol: String {
        isPreviewing ? "eye.fill" : "rectangle.on.rectangle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: listing.systemImage)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(listing.title)
                        .font(.subheadline.weight(.semibold))
                    Text(listing.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    A2UIInstallStateBadge(state: state)
                    if isPreviewing {
                        A2UIPreviewStateBadge()
                    }
                }
            }

            Text(listing.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(listing.runtimeProfile.title, systemImage: "cpu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(listing.requiredCapabilities.prefix(4), id: \.self) { capability in
                    A2UIAppCapabilityPill(title: capability)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(listing.installNotes, id: \.self) { note in
                    Label(note, systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(listing.samplePrompt)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                if state.isInstalled {
                    Button(action: onOpen) {
                        Label(state.title == "Running" ? "Running" : "Open", systemImage: state.systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onPreview) {
                        Label(previewButtonTitle, systemImage: previewButtonSymbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onUninstall) {
                        Label("Remove", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onInstall) {
                        Label("Install", systemImage: state.systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onPreview) {
                        Label(previewButtonTitle, systemImage: previewButtonSymbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: isPreviewing || isSelected ? 1.5 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onSelect)
        .accessibilityIdentifier("a2ui-store-app-\(listing.id)")
    }
}

private struct A2UIInstallStateBadge: View {
    let state: A2UIAppInstallState

    var body: some View {
        Label(state.title, systemImage: state.systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct A2UIPreviewStateBadge: View {
    var body: some View {
        Label("Previewing", systemImage: "eye.fill")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.16))
            .foregroundStyle(.green)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct A2UIAppCapabilityPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct A2UIRuntimeProfileView: View {
    let profile: A2UIRuntimeProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.title)
                        .font(.subheadline.weight(.semibold))
                    Text(profile.status)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                HStack(spacing: 8) {
                    if let repositoryURL = profile.repositoryURL {
                        Link(destination: repositoryURL) {
                            Label("Repo", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .font(.caption)
                    }
                    if let documentationURL = profile.documentationURL {
                        Link(destination: documentationURL) {
                            Label("Docs", systemImage: "book")
                        }
                        .font(.caption)
                    }
                }
            }

            Text(profile.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(profile.capabilities) { capability in
                    A2UIRuntimeCapabilityView(capability: capability)
                }
            }

            if !profile.setupCommands.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Setup", systemImage: "terminal")
                        .font(.caption.weight(.semibold))
                    ForEach(profile.setupCommands, id: \.self) { command in
                        Text(command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            ForEach(profile.runtimeNotes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("a2ui-runtime-profile-\(profile.id)")
    }
}

private struct A2UIRuntimeCapabilityView: View {
    let capability: A2UIRuntimeCapability

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: capability.systemImage)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.title)
                    .font(.caption.weight(.semibold))
                Text(capability.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct A2UIMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MCPAddServerButton: View {
    let title: String
    let systemImage: String
    let transport: MCPServerTransport
    @ObservedObject var browser: BrowserViewModel

    var body: some View {
        Button {
            Task {
                await browser.addMCPServer(transport: transport)
            }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("mcp-add-\(transport.id)")
    }
}

private struct MCPServerCardView: View {
    @ObservedObject var browser: BrowserViewModel
    let server: MCPServerConfiguration
    @State private var draft: MCPServerConfiguration
    @State private var isWorking = false

    init(browser: BrowserViewModel, server: MCPServerConfiguration) {
        self.browser = browser
        self.server = server
        _draft = State(initialValue: server)
    }

    private var statusColor: Color {
        switch draft.status.state {
        case .connected: Color.green
        case .failed: Color.red
        case .disabled, .disconnected: Color.secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.name.isEmpty ? "Unnamed MCP server" : draft.name)
                        .font(.headline)
                    Text(draft.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Label(draft.status.state.title, systemImage: draft.status.state == .connected ? "checkmark.circle" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption.weight(.semibold))
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Transport")
                        .font(.caption.weight(.semibold))
                    Picker("Transport", selection: $draft.transport) {
                        ForEach(MCPServerTransport.allCases) { transport in
                            Text(transport.title).tag(transport)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Capability")
                        .font(.caption.weight(.semibold))
                    TextField("Default capability", text: capabilityBinding)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Timeout")
                        .font(.caption.weight(.semibold))
                    Stepper(value: $draft.timeoutMS, in: 500...120_000, step: 500) {
                        Text("\(draft.timeoutMS) ms")
                            .font(.caption.monospaced())
                    }
                }
            }

            if draft.transport.requiresEndpoint {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Endpoint")
                        .font(.caption.weight(.semibold))
                    TextField(draft.transport == .websocket ? "wss://example.com/mcp" : "https://example.com/mcp", text: $draft.endpoint)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }

            if draft.transport.requiresProgram {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Program")
                            .font(.caption.weight(.semibold))
                        TextField("./bin/mcp-server", text: $draft.program)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Arguments")
                            .font(.caption.weight(.semibold))
                        TextField("--stdio", text: $draft.argumentsText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Headers")
                        .font(.caption.weight(.semibold))
                    TextField("Authorization=Bearer token", text: $draft.headersText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Environment")
                        .font(.caption.weight(.semibold))
                    TextField("API_KEY=value", text: $draft.environmentText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }

            Toggle(isOn: $draft.enabled) {
                Text("Enabled")
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Blockchain Access", systemImage: "link.badge.plus")
                    .font(.subheadline.weight(.semibold))
                Text(draft.blockchainAccess.installSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading, spacing: 8) {
                    Toggle("Read chains", isOn: $draft.blockchainAccess.readChainData)
                    Toggle("Read wallet", isOn: $draft.blockchainAccess.readWalletState)
                    Toggle("Prepare", isOn: $draft.blockchainAccess.prepareTransactions)
                    Toggle("Simulate", isOn: $draft.blockchainAccess.simulateTransactions)
                    Toggle("Request signing", isOn: $draft.blockchainAccess.requestSigning)
                    Toggle("Request broadcast", isOn: $draft.blockchainAccess.requestBroadcast)
                }
                .font(.caption)

                Picker("Account scope", selection: $draft.blockchainAccess.accountScope) {
                    ForEach(WalletAccountScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Allowed chains")
                        .font(.caption.weight(.semibold))
                    TextField("ethereum-mainnet, base-mainnet, solana-mainnet", text: allowedChainRefsBinding)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text(draft.blockchainAccess.hostTools.joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.status.message)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                if !draft.status.discoveredTools.isEmpty {
                    Text(draft.status.discoveredTools.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                Button {
                    Task { await saveDraft() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await connectDraft() }
                } label: {
                    Label("Connect", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await disconnectDraft() }
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    Task {
                        await browser.removeMCPServer(server.id)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .disabled(isWorking)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onChange(of: server) { _, updated in
            draft = updated
        }
        .accessibilityIdentifier("mcp-server-\(server.id)")
    }

    private var capabilityBinding: Binding<String> {
        Binding(
            get: { draft.defaultCapability ?? "" },
            set: { draft.defaultCapability = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }

    private var allowedChainRefsBinding: Binding<String> {
        Binding(
            get: { draft.blockchainAccess.allowedChainRefs.joined(separator: ", ") },
            set: { value in
                draft.blockchainAccess.allowedChainRefs = value
                    .split(separator: ",")
                    .map { ChainTrustStatus.normalized(String($0)) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func saveDraft() async {
        isWorking = true
        let servers = await browser.updateMCPServer(draft)
        if let updated = servers.first(where: { $0.id == draft.id }) {
            draft = updated
        }
        isWorking = false
    }

    private func connectDraft() async {
        isWorking = true
        let servers = await browser.updateMCPServer(draft)
        if let updated = servers.first(where: { $0.id == draft.id }) {
            draft = updated
        }
        if let connected = await browser.connectMCPServer(draft.id) {
            draft = connected
        }
        isWorking = false
    }

    private func disconnectDraft() async {
        isWorking = true
        if let disconnected = await browser.disconnectMCPServer(draft.id) {
            draft = disconnected
        }
        isWorking = false
    }
}

private struct RuntimePanelView: View {
    @ObservedObject var browser: BrowserViewModel
    let onSelectFeature: (RuntimeFeatureState) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "Runtime",
                    systemImage: BrowserPanel.runtime.systemImage,
                    subtitle: "Native and bridged capabilities available to the iOS shell."
                )

                RuntimeFeatureGrid(features: browser.runtimeFeatureStates, onSelect: onSelectFeature)

                ChainTrustPanelView(registry: browser.chainTrustSnapshot)
                AFMServicesPanelView(
                    snapshot: browser.afmServiceSnapshot,
                    trainingJobs: browser.afmTrainingJobs,
                    latestA2ACall: browser.latestAFMA2ACallResult,
                    onCreateTrainingJob: {
                        Task { await browser.createDemoAFMExpertTrainingJob() }
                    },
                    onPublishTrainingJob: { job in
                        Task { await browser.publishAFMExpertTrainingJob(job.id) }
                    },
                    onPrepareA2ACall: { expert in
                        Task {
                            _ = await browser.callAFMPeerExpert(
                                AFMA2ACallRequest(
                                    expertID: expert.id,
                                    prompt: "Preview this peer expert before sending production A2A traffic.",
                                    contextCommitment: "local-preview",
                                    userApproved: false
                                )
                            )
                        }
                    }
                )
                OpenMindMemoryPanelView(
                    state: browser.openMindCapabilityState,
                    continuity: browser.openMindContinuityState,
                    posture: browser.openMindPostureState,
                    reviewTasks: browser.openMindReviewTasks
                )
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-runtime")
    }
}

private struct OpenMindMemoryPanelView: View {
    let state: OpenMindMemoryCapabilityState
    let continuity: OpenMindContinuityState
    let posture: OpenMindPostureState
    let reviewTasks: [OpenMindReviewTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("OpenMind Memory", systemImage: "brain")
                .font(.headline)
            Text(state.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let transport = state.transport {
                Text("Transport: \(transport.displaySummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !state.capabilities.isEmpty {
                Text(state.capabilities.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let posture = state.posture {
                Text("Posture: \(posture)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !reviewTasks.isEmpty {
                Label("\(reviewTasks.count) memory review task\(reviewTasks.count == 1 ? "" : "s")", systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Label(continuity.summary, systemImage: continuity.pendingStepUps > 0 ? "person.badge.clock" : "point.3.connected.trianglepath.dotted")
                .font(.caption)
                .foregroundStyle(.secondary)
            if continuity.pendingStepUps > 0 {
                Text("\(continuity.pendingStepUps) step-up request\(continuity.pendingStepUps == 1 ? "" : "s") pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(posture.summary, systemImage: posture.allowsMemoryWriteback ? "checkmark.shield" : "hand.raised")
                .font(.caption)
                .foregroundStyle(posture.allowsMemoryWriteback ? Color.secondary : Color.orange)
            Text(posture.requiresExplicitConfirmation ? "Memory writeback requires explicit confirmation." : "Memory writeback follows current posture policy.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("runtime-openmind-memory")
    }
}

private struct BrowserHomeView: View {
    @ObservedObject var browser: BrowserViewModel
    @State private var selectedFeature: RuntimeFeatureState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("dBrowser")
                        .font(.largeTitle.bold())
                    Text("Native iOS shell for the Advatar decentralized browser runtime.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    QuickActionButton(title: "Search", systemImage: "magnifyingglass") {
                        browser.addressText = "zero knowledge browser"
                        browser.navigateFromAddress()
                    }
                    QuickActionButton(title: "Docs", systemImage: "doc.text") {
                        browser.navigate("https://github.com/advatar/browser")
                    }
                    QuickActionButton(title: "IPFS", systemImage: "link") {
                        browser.navigate(DecentralizedStartingPoint.featured.first?.address ?? "ipns://docs.ipfs.tech")
                    }
                }

                RuntimeGatewayStartingPointsView(points: RuntimeGatewayStartingPoint.featured) { point in
                    browser.navigate(point.urlString)
                }

                DecentralizedStartingPointsView(points: DecentralizedStartingPoint.featured) { point in
                    browser.navigate(point.address)
                }

                RuntimeFeatureGrid(features: browser.runtimeFeatureStates) { feature in
                    selectedFeature = feature
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(item: $selectedFeature) { feature in
            RuntimeFeatureDetailView(state: feature)
        }
    }
}

private struct RuntimeGatewayStartingPointsView: View {
    let points: [RuntimeGatewayStartingPoint]
    let onOpen: (RuntimeGatewayStartingPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect through gateways", systemImage: "shield.lefthalf.filled")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(points) { point in
                    Button {
                        onOpen(point)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: point.systemImage)
                                    .frame(width: 22)
                                    .foregroundStyle(point.isZeroKnowledgeGateway ? Color.accentColor : Color.secondary)
                                Text(point.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.forward")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(point.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Text(point.urlString)
                                .font(.caption.monospaced())
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(point.title)
                    .accessibilityHint("Open gateway")
                    .accessibilityIdentifier("gateway-start-\(point.title.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
            }
        }
        .accessibilityIdentifier("gateway-starting-points")
    }
}

private struct DecentralizedStartingPointsView: View {
    let points: [DecentralizedStartingPoint]
    let onOpen: (DecentralizedStartingPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Start on IPFS", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(points) { point in
                    Button {
                        onOpen(point)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: point.systemImage)
                                    .frame(width: 22)
                                    .foregroundStyle(Color.accentColor)
                                Text(point.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.forward")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(point.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Text(point.address)
                                .font(.caption.monospaced())
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(point.title)
                    .accessibilityHint("Open decentralized web starting point")
                    .accessibilityIdentifier("ipfs-start-\(point.title.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
            }
        }
        .accessibilityIdentifier("ipfs-starting-points")
    }
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }
}

private struct RuntimeFeatureGrid: View {
    let features: [RuntimeFeatureState]
    let onSelect: (RuntimeFeatureState) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            ForEach(features) { state in
                Button {
                    onSelect(state)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: state.feature.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(state.isAvailable ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.feature.title)
                                .font(.headline)
                            Text(state.status)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(state.mode.title)
                                .font(.caption)
                                .foregroundStyle(state.isAvailable ? Color.accentColor : Color.secondary)
                        }
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Show runtime details")
            }
        }
    }
}

private struct RuntimeFeatureDetailView: View {
    let state: RuntimeFeatureState
    @Environment(\.dismiss) private var dismiss

    private var explanation: RuntimeFeatureExplanation {
        state.feature.explanation
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: state.feature.systemImage)
                        .font(.title2)
                        .frame(width: 34, height: 34)
                        .foregroundStyle(state.isAvailable ? Color.accentColor : Color.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.feature.title)
                            .font(.title2.bold())
                        Text("\(state.mode.title) - \(state.status)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text(explanation.overview)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bridge Behavior")
                        .font(.headline)
                    Text(explanation.bridgeBehavior)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Details")
                        .font(.headline)
                    ForEach(explanation.detailPoints, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Color.accentColor)
                            Text(point)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(platformBackgroundColor)
    }
}

private struct RuntimeNoticeView: View {
    let urlString: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Runtime bridge", systemImage: "server.rack")
                .font(.title2.bold())
            Text(urlString)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Text(message)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(platformBackgroundColor)
    }
}

#if os(macOS)
private struct BrowserSidebar: View {
    @ObservedObject var browser: BrowserViewModel

    var body: some View {
        List {
            Section("Browse") {
                Button {
                    browser.selectPanel(nil)
                } label: {
                    Label("Browser", systemImage: "globe")
                }
                .fontWeight(browser.selectedPanel == nil ? .semibold : .regular)

                ForEach(BrowserPanel.primaryPanels) { panel in
                    Button {
                        browser.selectPanel(panel)
                    } label: {
                        Label(panel.title, systemImage: panel.systemImage)
                    }
                    .fontWeight(browser.selectedPanel == panel ? .semibold : .regular)
                    .accessibilityIdentifier(panel == .wallet ? "sidebar-wallet" : "sidebar-\(panel.id)")
                }
            }

            Section("Advanced") {
                ForEach(BrowserPanel.advancedPanels) { panel in
                    Button {
                        browser.selectPanel(panel)
                    } label: {
                        Label(panel.title, systemImage: panel.systemImage)
                    }
                    .fontWeight(browser.selectedPanel == panel ? .semibold : .regular)
                }
            }

            Section("Bookmarks") {
                ForEach(browser.bookmarks) { bookmark in
                    Button {
                        browser.openBookmark(bookmark)
                    } label: {
                        Text(bookmark.title)
                            .lineLimit(1)
                    }
                }
            }

            Section("Recent") {
                ForEach(browser.history.prefix(8)) { entry in
                    Button {
                        browser.openHistoryEntry(entry)
                    } label: {
                        Text(entry.title)
                            .lineLimit(1)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }
}
#endif

#Preview {
    ContentView()
}
