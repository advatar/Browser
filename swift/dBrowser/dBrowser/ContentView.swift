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

private var platformBackgroundColor: Color {
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
            case .copilot:
                CopilotPanelView(browser: browser)
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

private struct PanelHeaderView: View {
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

private struct EmptyPanelView: View {
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
                                Text(memory.summary)
                                    .font(.caption)
                                    .lineLimit(2)
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

                AFMServicesPanelView(snapshot: browser.afmServiceSnapshot)
                OpenMindMemoryPanelView(
                    state: browser.openMindCapabilityState,
                    continuity: browser.openMindContinuityState,
                    posture: browser.openMindPostureState
                )
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-runtime")
    }
}

private struct AFMServicesPanelView: View {
    let snapshot: AFMServiceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AFM Services", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Text(snapshot.serviceStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(
                snapshot.nodeAvailable ? "Node install, dispatch, attestation, proof, and settlement online" : "Node install, dispatch, attestation, proof, and settlement offline",
                systemImage: snapshot.nodeAvailable ? "checkmark.seal" : "xmark.seal"
            )
            .font(.caption)
            .foregroundStyle(snapshot.nodeAvailable ? Color.green : Color.secondary)
            Text("Registry v1: \(snapshot.registryExperts.count) expert\(snapshot.registryExperts.count == 1 ? "" : "s"), \(snapshot.registryBundles.count) bundle\(snapshot.registryBundles.count == 1 ? "" : "s").")
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshot.availablePacks.isEmpty {
                Text("No runner packs reported by router or registry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.availablePacks.prefix(6)) { pack in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text([pack.id, pack.version, pack.modelID, pack.status].compactMap { $0 }.joined(separator: " / "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let maintainer = pack.maintainer {
                            Text(maintainer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("runtime-afm-services")
    }
}

private struct OpenMindMemoryPanelView: View {
    let state: OpenMindMemoryCapabilityState
    let continuity: OpenMindContinuityState
    let posture: OpenMindPostureState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("OpenMind Memory", systemImage: "brain")
                .font(.headline)
            Text(state.message)
                .font(.caption)
                .foregroundStyle(.secondary)
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

                ForEach(BrowserPanel.allCases) { panel in
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
                        browser.navigate(entry.urlString)
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
