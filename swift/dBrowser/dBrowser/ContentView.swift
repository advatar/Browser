//
//  ContentView.swift
//  dBrowser
//
//  Created by Johan Sellström on 2026-05-15.
//

import SwiftUI

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
            await browser.refreshRuntimeBridgeStatus()
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
                    Button {
                        browser.activateTab(tab.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.isLoading ? "circle.dotted" : "globe")
                            Text(tab.title)
                                .lineLimit(1)
                            if browser.tabs.count > 1 {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .onTapGesture {
                                        browser.closeTab(tab.id)
                                    }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: 220, alignment: .leading)
                        .background(tab.id == browser.activeTabID ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var browserSurface: some View {
        if let panel = browser.selectedPanel {
            BrowserPanelContentView(browser: browser, panel: panel)
        } else if let index = browser.activeTabIndex {
            let tab = browser.tabs[index]
            if tab.urlString == BrowserURLResolver.homeURLString {
                BrowserHomeView(browser: browser)
            } else if let notice = tab.mobileNotice {
                RuntimeNoticeView(urlString: tab.urlString, message: notice)
            } else {
                BrowserWebView(
                    tab: $browser.tabs[index],
                    command: browser.webCommand,
                    automationRequest: browser.automationRequest,
                    onNavigationUpdate: browser.applyNavigationUpdate,
                    onAutomationResult: browser.applyAutomationResult
                )
            }
        } else {
            BrowserHomeView(browser: browser)
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

private struct BrowserPanelSelector: View {
    @ObservedObject var browser: BrowserViewModel
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            BrowserPanelSelectorButton(
                title: "Browser",
                systemImage: "globe",
                isSelected: browser.selectedPanel == nil
            ) {
                browser.selectPanel(nil)
            }
            .accessibilityIdentifier("panel-browser")

            ForEach(BrowserPanel.allCases) { panel in
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
                    subtitle: "Track where dBrowser beats Strawberry and jump directly to the work that closes remaining UX gaps."
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

private struct CopilotPanelView: View {
    @ObservedObject var browser: BrowserViewModel
    @State private var draftMessage = "Summarize this page and suggest next actions."
    @State private var correctionTargetID: String?
    @State private var correctionText = ""

    private var latestRun: CopilotRun? {
        browser.copilotRuns.first
    }

    private var activeRun: CopilotRun? {
        browser.copilotRuns.first { $0.status == .queued || $0.status == .running }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "Copilot",
                    systemImage: BrowserPanel.copilot.systemImage,
                    subtitle: "Run, inspect, and stop page-scoped AI work."
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Conversation")
                            .font(.headline)
                        Spacer()
                        Button {
                            browser.startNewLLMConversation()
                        } label: {
                            Label("New", systemImage: "plus.message")
                        }
                        .buttonStyle(.borderless)
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

                    LLMConversationTranscriptView(browser: browser)

                    TextEditor(text: $draftMessage)
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("copilot-prompt")

                    HStack {
                        Text(browser.activeTab?.displayURL ?? "Home")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            browser.requestPageSnapshot()
                        } label: {
                            Label("Snapshot", systemImage: "doc.viewfinder")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            saveWorkflow()
                        } label: {
                            Label("Save", systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(.bordered)

                        if let activeRun {
                            Button {
                                browser.cancelCopilotRun(activeRun.id)
                            } label: {
                                Label("Stop", systemImage: "stop.circle")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("copilot-stop")
                        }

                        Button {
                            if browser.sendLLMMessage(draftMessage) != nil {
                                draftMessage = ""
                            }
                        } label: {
                            Label(activeRun == nil ? "Send" : "Running", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(activeRun != nil || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("copilot-run")
                    }

                    if !browser.availableAFMPacks.isEmpty {
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

                        ForEach(latestRun.events.suffix(5)) { event in
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
    }

    private func saveWorkflow() {
        _ = browser.saveCopilotWorkflow(
            title: "Saved Copilot prompt",
            promptTemplate: draftMessage,
            allowedActions: [.click, .focus, .scroll, .waitForSelector]
        )
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

private struct LLMConversationTranscriptView: View {
    @ObservedObject var browser: BrowserViewModel

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
                ForEach(browser.llmConversation.messages.suffix(8)) { message in
                    LLMConversationMessageRow(
                        message: message,
                        modelName: modelName(for: message.modelID)
                    )
                }
            }

            if let event = browser.llmConversation.events.last {
                Label(event.message, systemImage: conversationEventSystemImage(event.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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
            Section("Browser") {
                Button {
                    browser.selectPanel(nil)
                } label: {
                    Label("Browser", systemImage: "globe")
                }
                .fontWeight(browser.selectedPanel == nil ? .semibold : .regular)

                ForEach(BrowserPanel.browserSidebarPanels) { panel in
                    Button {
                        browser.selectPanel(panel)
                    } label: {
                        Label(panel.title, systemImage: panel.systemImage)
                    }
                    .fontWeight(browser.selectedPanel == panel ? .semibold : .regular)
                }
            }

            Section("Wallet") {
                Button {
                    browser.selectPanel(.wallet)
                } label: {
                    Label(BrowserPanel.wallet.title, systemImage: BrowserPanel.wallet.systemImage)
                }
                .fontWeight(browser.selectedPanel == .wallet ? .semibold : .regular)
                .accessibilityIdentifier("sidebar-wallet")
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
