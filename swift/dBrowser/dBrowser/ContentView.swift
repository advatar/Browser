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
            tabStrip
            Divider()
            browserSurface
            Divider()
            statusBar
        }
        .background(platformBackgroundColor)
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
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

            TextField("Search or enter address", text: $browser.addressText)
                .focused($addressFieldFocused)
                .browserAddressFieldStyle()
                .onSubmit {
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
        if let index = browser.activeTabIndex {
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

private struct BrowserHomeView: View {
    @ObservedObject var browser: BrowserViewModel

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
                        browser.navigate("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi")
                    }
                }

                RuntimeFeatureGrid(features: browser.runtimeFeatureStates)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
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

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            ForEach(features) { state in
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
                }
                .padding(14)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
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
        List(selection: $browser.selectedPanel) {
            Section("Browser") {
                ForEach(BrowserPanel.allCases) { panel in
                    Label(panel.title, systemImage: panel.systemImage)
                        .tag(panel)
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
