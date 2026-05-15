//
//  dBrowserTests.swift
//  dBrowserTests
//
//  Created by Johan Sellström on 2026-05-15.
//

import Testing
import Foundation
@testable import dBrowser

struct dBrowserTests {

    @Test func bareDomainResolvesToHTTPS() {
        let resolved = BrowserURLResolver.resolve("example.com")
        #expect(resolved == .web(URL(string: "https://example.com")!))
    }

    @Test func searchTermsResolveToDuckDuckGoQuery() {
        let resolved = BrowserURLResolver.resolve("zero knowledge proofs")
        guard case .web(let url) = resolved else {
            Issue.record("Expected search URL")
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "q" }?
            .value
        #expect(url.host == "duckduckgo.com")
        #expect(query == "zero knowledge proofs")
    }

    @Test func decentralizedProtocolsAreExplicitlyGatedOnMobile() {
        let resolved = BrowserURLResolver.resolve("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi")
        guard case .unsupported(let raw, let message) = resolved else {
            Issue.record("Expected unsupported mobile runtime feature")
            return
        }
        #expect(raw.hasPrefix("ipfs://"))
        #expect(message.contains("desktop runtime") || message.contains("desktop"))
    }

    @MainActor
    @Test func viewModelTracksNavigationAndBookmarks() {
        let model = BrowserViewModel()
        model.navigate("example.com")
        #expect(model.activeTab?.urlString == "https://example.com")
        #expect(model.history.first?.urlString == "https://example.com")

        model.addActivePageBookmark()
        #expect(model.bookmarks.contains { $0.urlString == "https://example.com" })
    }

    @MainActor
    @Test func closingLastTabReturnsToHome() {
        let model = BrowserViewModel()
        let onlyTab = model.activeTabID
        model.navigate("example.com")
        model.closeTab(onlyTab)
        #expect(model.tabs.count == 1)
        #expect(model.activeTab?.urlString == BrowserURLResolver.homeURLString)
    }

}
