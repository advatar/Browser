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
        guard case .web(let url) = resolved else {
            Issue.record("Expected HTTPS URL")
            return
        }
        #expect(url == URL(string: "https://example.com")!)
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

    @Test func decentralizedProtocolsDelegateToRuntimeBridge() {
        let resolved = BrowserURLResolver.resolve("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi")
        guard case .unsupported(let raw, let message) = resolved else {
            Issue.record("Expected runtime bridge delegation")
            return
        }
        #expect(raw.hasPrefix("ipfs://"))
        #expect(message.contains("runtime bridge"))
    }

    @Test func ensNamesDelegateToRuntimeBridgeBeforeHTTPSFallback() {
        let resolved = BrowserURLResolver.resolve("vitalik.eth")
        guard case .unsupported(let raw, let message) = resolved else {
            Issue.record("Expected runtime bridge delegation")
            return
        }
        #expect(raw == "vitalik.eth")
        #expect(message.contains("decentralized name"))
    }

    @Test func runtimeFeaturesExposeDetailedExplanations() {
        for feature in MobileRuntimeFeature.allCases {
            let explanation = feature.explanation
            #expect(!explanation.overview.isEmpty)
            #expect(!explanation.bridgeBehavior.isEmpty)
            #expect(explanation.detailPoints.count >= 3)
            #expect(explanation.detailPoints.allSatisfy { !$0.isEmpty })
        }
    }

    @MainActor
    @Test func runtimeBridgeResolvesDecentralizedAddresses() async {
        let bridge = MobileRuntimeBridge()

        let ipfs = await bridge.resolve("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/index.html")
        #expect(ipfs.source == .ipfsGateway)
        #expect(ipfs.resolvedURLString == "https://dweb.link/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/index.html")

        let ipns = await bridge.resolve("ipns://docs.ipfs.tech/concepts/ipns")
        #expect(ipns.source == .ipnsGateway)
        #expect(ipns.resolvedURLString == "https://dweb.link/ipns/docs.ipfs.tech/concepts/ipns")

        let ens = await bridge.resolve("vitalik.eth")
        #expect(ens.source == .ensGateway)
        #expect(ens.resolvedURLString == "https://vitalik.eth.limo")
    }

    @MainActor
    @Test func runtimeBridgeProvidesCopilotWalletAndDownloadSurfaces() async {
        let bridge = MobileRuntimeBridge()

        let copilot = await bridge.runCopilot(CopilotRunRequest(prompt: "Summarize this page", pageURLString: "https://example.com"))
        #expect(copilot.mode == .local)
        #expect(copilot.summary.contains("Summarize this page"))
        #expect(!copilot.suggestions.isEmpty)

        let wallet = await bridge.connectWallet()
        #expect(wallet.isConnected)
        #expect(wallet.address?.hasPrefix("0x") == true)

        let decision = await bridge.evaluateSpend(
            WalletSpendRequest(amount: Decimal(10), currency: "USDC", destination: "0xabc", reason: "Test spend")
        )
        #expect(decision.status == .approved)

        let download = await bridge.startDownload(URL(string: "https://example.com/archive.zip")!, autoStart: false)
        #expect(download.state == .queued)
        let cancelled = await bridge.cancelDownload(download.id)
        #expect(cancelled?.state == .cancelled)
    }

    @MainActor
    @Test func viewModelLoadsIPFSAddressesThroughRuntimeBridge() async {
        let model = BrowserViewModel()
        model.navigate("ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/index.html")

        let resolved = await waitForActiveURL(
            in: model,
            "https://dweb.link/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/index.html"
        )

        #expect(resolved)
        #expect(model.activeTab?.mobileNotice == nil)
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

    @MainActor
    private func waitForActiveURL(in model: BrowserViewModel, _ urlString: String) async -> Bool {
        for _ in 0..<20 {
            if model.activeTab?.urlString == urlString {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

}
