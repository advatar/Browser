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
                    onNavigationUpdate: browser.applyNavigationUpdate
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "History",
                    systemImage: BrowserPanel.history.systemImage,
                    subtitle: "Recently visited pages from this iOS session."
                )

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
    @State private var prompt = "Summarize this page and suggest next actions."
    @State private var result: CopilotRunResult?
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "Copilot",
                    systemImage: BrowserPanel.copilot.systemImage,
                    subtitle: "Prepare an AI run against the active browsing context."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Prompt")
                        .font(.headline)
                    TextEditor(text: $prompt)
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
                            runCopilot()
                        } label: {
                            Label(isRunning ? "Running" : "Run Copilot", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                        .accessibilityIdentifier("copilot-run")
                    }
                }

                if let result {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.title)
                            .font(.headline)
                        Text(result.summary)
                            .foregroundStyle(.secondary)
                        ForEach(result.suggestions, id: \.self) { suggestion in
                            Label(suggestion, systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("copilot-result")
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-copilot")
    }

    private func runCopilot() {
        isRunning = true
        let request = CopilotRunRequest(prompt: prompt, pageURLString: browser.activeTab?.urlString)
        Task { @MainActor in
            result = await browser.runtimeBridge.runCopilot(request)
            isRunning = false
        }
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
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-runtime")
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
