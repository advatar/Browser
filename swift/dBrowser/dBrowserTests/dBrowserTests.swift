//
//  dBrowserTests.swift
//  dBrowserTests
//
//  Created by Johan Sellström on 2026-05-15.
//

import Testing
import Foundation
import CryptoKit
import MLXLMCommon
@testable import dBrowser

@MainActor
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

    @Test func decentralizedStorageRegistryCoversAppDistributionNetworks() {
        let requiredNetworkIDs = [
            "ipfs",
            "ipns",
            "swarm",
            "arweave",
            "filecoin",
            "walrus",
            "iroh",
            "hypercore",
            "sia",
            "storj",
            "tahoe-lafs",
            "autonomi",
            "bittorrent",
            "ceramic",
            "orbitdb",
            "radicle"
        ]
        let schemes = DecentralizedStorageNetwork.supportedSchemes
        let requiredSchemes = [
            "ipfs",
            "ipns",
            "bzz",
            "bzzr",
            "swarm",
            "ar",
            "arweave",
            "filecoin",
            "piececid",
            "fil",
            "walrus",
            "iroh",
            "iroh-blob",
            "hyper",
            "hypercore",
            "hyperdrive",
            "pear",
            "dat",
            "sia",
            "storj",
            "tahoe",
            "lafs",
            "autonomi",
            "safe",
            "magnet",
            "bittorrent",
            "webtorrent",
            "ceramic",
            "ceramic-stream",
            "orbitdb",
            "rad",
            "radicle"
        ]
        let registeredNetworkIDs = Set(DecentralizedStorageNetwork.supported.map(\.id))

        #expect(registeredNetworkIDs == Set(requiredNetworkIDs))

        for scheme in requiredSchemes {
            #expect(schemes.contains(scheme))
        }

        let swarm = DecentralizedStorageNetwork.profile(forScheme: "bzz")
        let arweave = DecentralizedStorageNetwork.profile(forScheme: "ar")
        let filecoin = DecentralizedStorageNetwork.profile(forScheme: "fil")
        let filecoinInput = "fil://f01234/app.car"
        let filecoinRemoteURL = filecoin?.remoteRuntimeURL(
            for: filecoinInput,
            url: URL(string: filecoinInput)!,
            baseURL: RuntimeBridgeConfiguration.exampleRemoteRuntimeBaseURL
        )
        let filecoinRemoteQuery = remoteResolverQueryItems(for: filecoinRemoteURL?.absoluteString)

        #expect(swarm?.distributionRole.contains("dapp") == true)
        #expect(swarm?.gatewayURL(for: URL(string: "bzz://abcdef/app.json")!)?.absoluteString == "https://gateway.ethswarm.org/bzz/abcdef/app.json")
        #expect(arweave?.gatewayURL(for: URL(string: "ar://abc123/app.json?download=1#v1")!)?.absoluteString == "https://arweave.net/abc123/app.json?download=1#v1")
        #expect(filecoinRemoteURL?.host == "storage-resolver.example")
        #expect(filecoinRemoteURL?.path == "/dweb/filecoin/resolve")
        #expect(filecoinRemoteQuery["network"] == "filecoin")
        #expect(filecoinRemoteQuery["scheme"] == "fil")
        #expect(filecoinRemoteQuery["adapter"] == "filecoin.piece-car")
        #expect(filecoinRemoteQuery["resolution_stage"] == DecentralizedStorageAdapterStage.remoteRuntimeHandoff.rawValue)
        #expect(filecoinRemoteQuery["locator_kind"] == "Filecoin CID, piece CID, or storage deal reference")
        #expect(filecoinRemoteQuery["locator"] == "f01234/app.car")
        #expect(filecoinRemoteQuery["native_issue"] == "119")
        #expect(filecoinRemoteQuery["uri"] == filecoinInput)
    }

    @Test func decentralizedStorageAdaptersTrackNativeProtocolIssues() {
        let expectedIssues = [
            "filecoin": 119,
            "walrus": 120,
            "iroh": 121,
            "hypercore": 122,
            "sia": 123,
            "storj": 124,
            "tahoe-lafs": 125,
            "autonomi": 126,
            "bittorrent": 127,
            "ceramic": 128,
            "orbitdb": 129,
            "radicle": 130
        ]

        for network in DecentralizedStorageNetwork.supported where expectedIssues.keys.contains(network.id) {
            #expect(network.adapter.issueNumber == expectedIssues[network.id])
            #expect(network.adapter.stage == .remoteRuntimeHandoff)
            #expect(!network.adapter.handlerID.isEmpty)
            #expect(!network.adapter.locatorKind.isEmpty)
            #expect(!network.adapter.trustBoundary.isEmpty)
            #expect(network.adapter.verificationRequirements.count >= 2)

            let input = sampleDecentralizedStorageURI(forScheme: network.primaryScheme)
            let url = URL(string: input)!
            let remoteURL = network.remoteRuntimeURL(
                for: input,
                url: url,
                baseURL: RuntimeBridgeConfiguration.exampleRemoteRuntimeBaseURL
            )
            let query = remoteResolverQueryItems(for: remoteURL?.absoluteString)

            #expect(remoteURL?.path == expectedRemoteResolverPath(for: network))
            #expect(query["adapter"] == network.adapter.handlerID)
            #expect(query["native_issue"] == String(expectedIssues[network.id] ?? 0))
            #expect(query["locator_kind"] == network.adapter.locatorKind)
            #expect(query["locator"]?.isEmpty == false)
        }
    }

    @Test func decentralizedStorageContentResolutionDistinguishesLoadableBytesFromResolverRequirements() {
        let filecoin = DecentralizedStorageNetwork.profile(forScheme: "filecoin")
        let walrus = DecentralizedStorageNetwork.profile(forScheme: "walrus")
        let iroh = DecentralizedStorageNetwork.profile(forScheme: "iroh")
        let magnet = DecentralizedStorageNetwork.profile(forScheme: "magnet")

        let filecoinInput = "filecoin://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/app.json"
        let filecoinResolution = filecoin?.contentResolution(
            for: filecoinInput,
            url: URL(string: filecoinInput)!,
            nativeAdapters: .localDefaults,
            remoteRuntimeBaseURL: nil,
            decentralizedGatewayHost: "dweb.link",
            walrusAggregatorBaseURL: URL(string: "https://aggregator.walrus-mainnet.walrus.space")!
        )

        let walrusInput = "walrus://abc123xyz"
        let walrusResolution = walrus?.contentResolution(
            for: walrusInput,
            url: URL(string: walrusInput)!,
            nativeAdapters: .localDefaults,
            remoteRuntimeBaseURL: nil,
            decentralizedGatewayHost: "dweb.link",
            walrusAggregatorBaseURL: URL(string: "https://aggregator.walrus-mainnet.walrus.space")!
        )

        let irohInput = "iroh://example-storage-root/app.json"
        let irohResolution = iroh?.contentResolution(
            for: irohInput,
            url: URL(string: irohInput)!,
            nativeAdapters: .disabled,
            remoteRuntimeBaseURL: nil,
            decentralizedGatewayHost: "dweb.link",
            walrusAggregatorBaseURL: URL(string: "https://aggregator.walrus-mainnet.walrus.space")!
        )

        let magnetInput = "magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01&ws=https%3A%2F%2Fexample.com%2Fbundle.car"
        let magnetResolution = magnet?.contentResolution(
            for: magnetInput,
            url: URL(string: magnetInput)!,
            nativeAdapters: .localDefaults,
            remoteRuntimeBaseURL: nil,
            decentralizedGatewayHost: "dweb.link",
            walrusAggregatorBaseURL: URL(string: "https://aggregator.walrus-mainnet.walrus.space")!
        )

        #expect(filecoinResolution?.state == .loadableGateway)
        #expect(filecoinResolution?.url?.absoluteString == "https://dweb.link/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/app.json")
        #expect(filecoinResolution?.isLoadable == true)
        #expect(walrusResolution?.state == .loadableGateway)
        #expect(walrusResolution?.url?.absoluteString == "https://aggregator.walrus-mainnet.walrus.space/v1/blobs/abc123xyz")
        #expect(irohResolution?.state == .localResolverRequired)
        #expect(irohResolution?.isLoadable == false)
        #expect(irohResolution?.requirement?.resolverName.contains("Iroh") == true)
        #expect(magnetResolution?.state == .loadableGateway)
        #expect(magnetResolution?.url?.absoluteString == "https://example.com/bundle.car")
    }

    @Test func decentralizedStorageNativeAdaptersCoverResolverBackedProtocols() {
        let nativeNetworkIDs: Set<String> = [
            "filecoin",
            "walrus",
            "iroh",
            "hypercore",
            "sia",
            "storj",
            "tahoe-lafs",
            "autonomi",
            "bittorrent",
            "ceramic",
            "orbitdb",
            "radicle"
        ]

        #expect(DecentralizedStorageNativeAdapterConfiguration.localDefaults.enabledNetworkIDs == nativeNetworkIDs)

        for network in DecentralizedStorageNetwork.supported where nativeNetworkIDs.contains(network.id) {
            let endpoint = DecentralizedStorageNativeAdapterConfiguration.localDefaults.endpoint(for: network.id)
            #expect(endpoint?.baseURL.host == "127.0.0.1")
            #expect(endpoint?.routePath.contains(network.id) == true)
            #expect(endpoint?.displayName.contains("Local") == true)

            for scheme in network.schemes {
                let input = sampleDecentralizedStorageURI(forScheme: scheme)
                let url = URL(string: input)!
                let nativeURL = network.nativeAdapterURL(for: input, url: url, endpoint: endpoint!)
                let query = remoteResolverQueryItems(for: nativeURL?.absoluteString)

                #expect(nativeURL?.host == "127.0.0.1")
                #expect(nativeURL?.path == expectedNativeAdapterPath(for: network))
                #expect(query["network"] == network.id)
                #expect(query["scheme"] == scheme)
                #expect(query["adapter"] == network.adapter.handlerID)
                #expect(query["native_issue"] == network.adapter.issueNumber.map { String($0) })
                #expect(query["resolution_stage"] == DecentralizedStorageAdapterStage.nativeLocalAdapter.rawValue)
                #expect(query["locator_kind"] == network.adapter.locatorKind)
                #expect(query["locator"]?.isEmpty == false)
                #expect(query["credential_scoped"] == (endpoint?.requiresCredentialScope == true ? "true" : "false"))
                #expect(query["uri"] == input)
            }
        }
    }

    @Test func decentralizedStorageURIsDelegateToRuntimeBridgeBeforeSearchFallback() {
        for network in DecentralizedStorageNetwork.supported {
            for scheme in network.schemes {
                let input = sampleDecentralizedStorageURI(forScheme: scheme)
                let resolved = BrowserURLResolver.resolve(input)
                guard case .unsupported(let raw, let message) = resolved else {
                    Issue.record("Expected runtime bridge delegation for \(input)")
                    continue
                }

                #expect(raw == input)
                #expect(message.contains(network.title))
                #expect(message.contains("runtime bridge"))
            }
        }
    }

    @Test func unknownURIsArePreservedInsteadOfSearched() {
        let resolved = BrowserURLResolver.resolve("mailto:team@example.com")
        guard case .unsupported(let raw, let message) = resolved else {
            Issue.record("Expected unknown URI preservation")
            return
        }

        #expect(raw == "mailto:team@example.com")
        #expect(message.contains("preserving this mailto"))
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

    @Test func mcpDefaultServersMirrorDesktopSeedProfile() {
        let servers = MCPServerConfiguration.defaultServers
        let demo = servers.first { $0.id == "demo-weather" }
        let stdio = servers.first { $0.id == "local-stdio" }

        #expect(servers.map(\.id) == ["demo-weather", "local-stdio"])
        #expect(demo?.name == "Local Demo MCP")
        #expect(demo?.transport == .http)
        #expect(demo?.endpoint == "http://127.0.0.1:7410/mcp")
        #expect(demo?.enabled == false)
        #expect(demo?.status.state == .disabled)
        #expect(stdio?.name == "Local STDIO MCP")
        #expect(stdio?.transport == .stdio)
        #expect(stdio?.program == "./bin/mcp-server")
        #expect(stdio?.argumentsText == "--stdio")
        #expect(stdio?.environmentText == "API_KEY=set-me")
    }

    @MainActor
    @Test func a2uiRendererParsesSampleTokensIntoSurface() async {
        let renderer = A2UITokenRenderer()

        await renderer.render(rawTokens: A2UITokenRenderer.sampleTokens)

        #expect(renderer.renderSummary.messageCount == 2)
        #expect(renderer.renderSummary.rootComponentID == "root")
        #expect(renderer.renderSummary.statusText.contains("2 A2UI messages"))
        #expect(renderer.hasSurface)
        #expect(renderer.errors.isEmpty)
    }

    @Test func a2uiAppStoreCatalogOffersInstallableApps() {
        let catalog = A2UIAppStoreListing.featured
        let catalogText = catalog.flatMap { listing in
            [
                listing.id,
                listing.title,
                listing.category,
                listing.summary,
                listing.runtimeProfileID,
                listing.samplePrompt,
                listing.tokenStream
            ] + listing.requiredCapabilities + listing.installNotes
        }.joined(separator: " ")

        #expect(catalog.count >= 6)
        #expect(Set(catalog.map(\.id)).count == catalog.count)
        #expect(catalog.contains { $0.id == "travel-booker" })
        #expect(catalog.contains { $0.id == "imageboard-agent" })
        #expect(catalog.contains { $0.id == "wallet-policy-concierge" })
        #expect(Set(catalog.map(\.runtimeProfileID)).contains(A2UIRuntimeProfile.nativeSwiftUI.id))
        #expect(Set(catalog.map(\.runtimeProfileID)).contains(A2UIRuntimeProfile.logosBasecamp.id))
        #expect(Set(catalog.map(\.runtimeProfileID)).contains(A2UIRuntimeProfile.aztecNetwork.id))
        #expect(catalogText.contains("A2UI v0.9"))
        #expect(catalogText.contains("ZeroK"))
        #expect(catalogText.contains("https://zerok.cloud"))
        #expect(catalogText.contains("https://llmos.showntell.dev"))
        #expect(catalogText.contains("IPFS"))
        #expect(catalogText.contains("Wallet"))

        for listing in catalog {
            #expect(!listing.title.isEmpty)
            #expect(!listing.category.isEmpty)
            #expect(!listing.summary.isEmpty)
            #expect(!listing.requiredCapabilities.isEmpty)
            #expect(!listing.installNotes.isEmpty)
            #expect(!listing.samplePrompt.isEmpty)
            #expect(listing.tokenStream.contains("\"createSurface\""))
            #expect(listing.tokenStream.contains("\"updateComponents\""))
            #expect(listing.tokenStream.contains(listing.id))
            #expect(A2UIRuntimeProfile.available.contains { $0.id == listing.runtimeProfileID })
        }
    }

    @MainActor
    @Test func a2uiAppStoreInstallOpenAndUninstallStateTransitions() {
        let installDate = Date(timeIntervalSince1970: 10)
        let openDate = Date(timeIntervalSince1970: 20)
        let store = A2UIAppStore()
        let listing = A2UIAppStoreListing.walletPolicy

        #expect(store.state(for: listing) == .available)
        #expect(store.installedCount == 0)

        store.install(listing, installedAt: installDate)

        #expect(store.state(for: listing) == .installed(installDate))
        #expect(store.installedCount == 1)

        store.open(listing, openedAt: openDate)

        #expect(store.state(for: listing) == .running(openDate))
        #expect(store.runningListingID == listing.id)
        #expect(store.installedCount == 1)

        store.uninstall(listing)

        #expect(store.state(for: listing) == .available)
        #expect(store.runningListingID == nil)
        #expect(store.installedCount == 0)
    }

    @MainActor
    @Test func a2uiAppStorePreviewStateDoesNotRequireInstallAndFollowsOpen() {
        let openDate = Date(timeIntervalSince1970: 30)
        let store = A2UIAppStore()
        let previewListing = A2UIAppStoreListing.formConcierge
        let openedListing = A2UIAppStoreListing.walletPolicy

        #expect(store.previewingListingID == nil)
        #expect(store.previewingListing == nil)

        store.preview(previewListing)

        #expect(store.previewingListingID == previewListing.id)
        #expect(store.previewingListing == previewListing)
        #expect(store.state(for: previewListing) == .available)
        #expect(store.installedCount == 0)

        store.open(openedListing, openedAt: openDate)

        #expect(store.previewingListingID == openedListing.id)
        #expect(store.previewingListing == openedListing)
        #expect(store.state(for: openedListing) == .running(openDate))
        #expect(store.installedCount == 1)

        store.uninstall(openedListing)

        #expect(store.previewingListingID == nil)
        #expect(store.previewingListing == nil)
        #expect(store.state(for: openedListing) == .available)
        #expect(store.runningListingID == nil)
    }

    @MainActor
    @Test func a2uiStoreListingsRenderA2UITokenPreviews() async {
        let renderer = A2UITokenRenderer()

        for listing in A2UIAppStoreListing.featured {
            await renderer.render(rawTokens: listing.tokenStream)

            #expect(renderer.renderSummary.messageCount == 2)
            #expect(renderer.renderSummary.rootComponentID == "root")
            #expect(renderer.hasSurface)
            #expect(renderer.errors.isEmpty)
        }
    }

    @Test func a2uiRuntimeProfilesOfferLogosBasecamp() {
        let logos = A2UIRuntimeProfile.logosBasecamp
        let searchableText = (
            [
                logos.title,
                logos.status,
                logos.description
            ] + logos.setupCommands + logos.runtimeNotes + logos.capabilities.flatMap { [$0.title, $0.detail] }
        ).joined(separator: " ")

        #expect(A2UIRuntimeProfile.available.contains(where: { $0.id == logos.id }))
        #expect(logos.repositoryURL?.absoluteString == "https://github.com/logos-co/logos-basecamp")
        #expect(logos.documentationURL?.absoluteString == "https://github.com/logos-co/logos-docs")
        #expect(searchableText.contains("Logos Basecamp"))
        #expect(searchableText.contains("local-first"))
        #expect(searchableText.contains("decentralised"))
        #expect(searchableText.contains("nix build '.#bin-macos-app'"))
        #expect(searchableText.contains("--user-dir"))
        #expect(searchableText.contains("LOGOS_USER_DIR"))
        #expect(searchableText.contains("Discovery"))
        #expect(searchableText.contains("peering"))
        #expect(searchableText.contains("mixnet"))
        #expect(searchableText.contains("Blockchain / Execution Zone"))
        #expect(searchableText.contains("Storage"))
        #expect(searchableText.contains("Messaging"))
        #expect(searchableText.contains("LEZ Wallet"))
        #expect(searchableText.contains("MCP/QML Inspector"))
    }

    @Test func a2uiRuntimeProfilesOfferAztecProtocol() {
        let aztec = A2UIRuntimeProfile.aztecNetwork
        let searchableText = (
            [
                aztec.title,
                aztec.status,
                aztec.description
            ] + aztec.setupCommands + aztec.runtimeNotes + aztec.capabilities.flatMap { [$0.title, $0.detail] }
        ).joined(separator: " ")

        #expect(A2UIRuntimeProfile.available.contains(where: { $0.id == aztec.id }))
        #expect(aztec.repositoryURL?.absoluteString == "https://github.com/AztecProtocol/aztec-packages")
        #expect(aztec.documentationURL?.absoluteString == "https://docs.aztec.network/")
        #expect(searchableText.contains("Aztec Network"))
        #expect(searchableText.contains("Privacy-first Ethereum L2"))
        #expect(searchableText.contains("private smart-contract"))
        #expect(searchableText.contains("PXE"))
        #expect(searchableText.contains("Private Execution Environment"))
        #expect(searchableText.contains("nullifier keys"))
        #expect(searchableText.contains("viewing keys"))
        #expect(searchableText.contains("Aztec.nr / Noir"))
        #expect(searchableText.contains("Aztec.js"))
        #expect(searchableText.contains("Public/private state"))
        #expect(searchableText.contains("Ethereum L1"))
        #expect(searchableText.contains("sequencers"))
        #expect(searchableText.contains("provers"))
        #expect(searchableText.contains("aztec compile"))
        #expect(searchableText.contains("@aztec/aztec.js@4.2.0"))
        #expect(searchableText.contains("@aztec/mcp-server"))
        #expect(searchableText.contains("nargo compile/test"))
    }

    @MainActor
    @Test func a2uiRenderingIsTopLevelPanelAndRuntimeFeature() {
        #expect(BrowserPanel.allCases.contains(.a2ui))
        #expect(BrowserPanel.advancedPanels.contains(.a2ui))

        let bridge = MobileRuntimeBridge()
        let state = bridge.featureStates.first { $0.feature == .a2uiRendering }
        let logosState = bridge.featureStates.first { $0.feature == .logosRuntime }
        let aztecState = bridge.featureStates.first { $0.feature == .aztecProtocol }
        let explanation = MobileRuntimeFeature.a2uiRendering.explanation
        let logosExplanation = MobileRuntimeFeature.logosRuntime.explanation
        let aztecExplanation = MobileRuntimeFeature.aztecProtocol.explanation
        let searchableText = (
            [
                MobileRuntimeFeature.a2uiRendering.title,
                MobileRuntimeFeature.a2uiRendering.status,
                explanation.overview,
                explanation.bridgeBehavior
            ] + explanation.detailPoints
        ).joined(separator: " ")
        let logosSearchableText = (
            [
                MobileRuntimeFeature.logosRuntime.title,
                MobileRuntimeFeature.logosRuntime.status,
                logosExplanation.overview,
                logosExplanation.bridgeBehavior
            ] + logosExplanation.detailPoints
        ).joined(separator: " ")
        let aztecSearchableText = (
            [
                MobileRuntimeFeature.aztecProtocol.title,
                MobileRuntimeFeature.aztecProtocol.status,
                aztecExplanation.overview,
                aztecExplanation.bridgeBehavior
            ] + aztecExplanation.detailPoints
        ).joined(separator: " ")

        #expect(state?.mode == .native)
        #expect(state?.isAvailable == true)
        #expect(state?.status.contains("A2UISwiftUI") == true)
        #expect(logosState?.mode == .local)
        #expect(logosState?.isAvailable == true)
        #expect(logosState?.status.contains("Logos Basecamp") == true)
        #expect(aztecState?.mode == .local)
        #expect(aztecState?.isAvailable == true)
        #expect(aztecState?.status.contains("Aztec PXE") == true)
        #expect(searchableText.contains("A2UIStreamParser"))
        #expect(searchableText.contains("SurfaceViewModel"))
        #expect(searchableText.contains("A2UISurfaceView"))
        #expect(searchableText.contains("A2UISwiftCore"))
        #expect(searchableText.contains("A2UISwiftUI"))
        #expect(searchableText.contains("A2UI App Store"))
        #expect(searchableText.contains("Logos Basecamp"))
        #expect(searchableText.contains("Aztec Network"))
        #expect(searchableText.contains("https://zerok.cloud"))
        #expect(searchableText.contains("https://llmos.showntell.dev"))
        #expect(logosSearchableText.contains("Logos Basecamp"))
        #expect(logosSearchableText.contains("https://github.com/logos-co/logos-basecamp"))
        #expect(logosSearchableText.contains("https://github.com/logos-co/logos-docs"))
        #expect(logosSearchableText.contains("local-first"))
        #expect(logosSearchableText.contains("decentralised"))
        #expect(logosSearchableText.contains("mixnet"))
        #expect(logosSearchableText.contains("Storage"))
        #expect(logosSearchableText.contains("Messaging"))
        #expect(logosSearchableText.contains("Blockchain / Execution Zone"))
        #expect(logosSearchableText.contains("LEZ Wallet"))
        #expect(logosSearchableText.contains("--user-dir"))
        #expect(logosSearchableText.contains("MCP/QML Inspector"))
        #expect(aztecSearchableText.contains("Aztec Network"))
        #expect(aztecSearchableText.contains("https://docs.aztec.network/"))
        #expect(aztecSearchableText.contains("https://github.com/AztecProtocol/aztec-packages"))
        #expect(aztecSearchableText.contains("privacy-first Layer 2 zkRollup"))
        #expect(aztecSearchableText.contains("not EVM compatible"))
        #expect(aztecSearchableText.contains("Private Execution Environment (PXE)"))
        #expect(aztecSearchableText.contains("Aztec Virtual Machine"))
        #expect(aztecSearchableText.contains("nullifier keys"))
        #expect(aztecSearchableText.contains("Aztec.nr"))
        #expect(aztecSearchableText.contains("Noir"))
        #expect(aztecSearchableText.contains("aztec compile"))
        #expect(aztecSearchableText.contains("@aztec/aztec.js@4.2.0"))
        #expect(aztecSearchableText.contains("sequencers"))
        #expect(aztecSearchableText.contains("decentralized provers"))
        #expect(aztecSearchableText.contains("L1 to L2 messaging"))
        #expect(aztecSearchableText.contains("@aztec/mcp-server"))
        #expect(aztecSearchableText.contains("noir-mcp-server"))
    }

    @MainActor
    @Test func localLLMManagementIsTopLevelPanel() {
        #expect(BrowserPanel.allCases.contains(.localLLM))
        #expect(BrowserPanel.advancedPanels.contains(.localLLM))
        #expect(BrowserPanel.localLLM.title == "Local LLMs")
        #expect(BrowserPanel.localLLM.systemImage == "cpu")
    }

    @Test func architectureOverviewExplainsAFMarketZeroKAndLLMGateway() {
        let feature = MobileRuntimeFeature.architectureOverview
        let explanation = feature.explanation
        let searchableText = (
            [
                feature.title,
                feature.status,
                explanation.overview,
                explanation.bridgeBehavior
            ] + explanation.detailPoints
        ).joined(separator: " ")

        #expect(searchableText.contains("AF Market"))
        #expect(searchableText.contains("AFM router"))
        #expect(searchableText.contains("embedded blockchain light clients"))
        #expect(searchableText.contains("Ethereum-compatible"))
        #expect(searchableText.contains("Substrate/Polkadot"))
        #expect(searchableText.contains("centralized RPC"))
        #expect(searchableText.contains("escrow status"))
        #expect(searchableText.contains("proof settlement"))
        #expect(searchableText.contains("ZeroK"))
        #expect(searchableText.contains("LLM Gateway"))
        #expect(searchableText.contains("https://zerok.cloud"))
        #expect(searchableText.contains("https://llmos.showntell.dev"))
        #expect(searchableText.contains("encrypted envelopes"))
        #expect(searchableText.contains("token-class padding"))
        #expect(searchableText.contains("privacy relay"))
        #expect(searchableText.contains("Provider boundary"))
    }

    @MainActor
    @Test func runtimeBridgeExposesArchitectureOverviewButton() {
        let bridge = MobileRuntimeBridge()
        let architecture = bridge.featureStates.first { $0.feature == .architectureOverview }

        #expect(architecture?.mode == .gateway)
        #expect(architecture?.isAvailable == true)
        #expect(architecture?.status.contains("AF Market") == true)
        #expect(architecture?.status.contains("Light clients") == true)
        #expect(architecture?.status.contains("ZeroK") == true)
        #expect(architecture?.status.contains("LLM Gateway") == true)
    }

    @Test func decentralizedProtocolExplanationKeepsLightClientsAsTrustRoot() {
        let explanation = MobileRuntimeFeature.decentralizedProtocols.explanation
        let searchableText = ([explanation.overview, explanation.bridgeBehavior] + explanation.detailPoints)
            .joined(separator: " ")

        #expect(searchableText.contains("embedded light-client contract"))
        #expect(searchableText.contains("Swarm"))
        #expect(searchableText.contains("Arweave"))
        #expect(searchableText.contains("content-loadable"))
        #expect(searchableText.contains("local native adapter endpoints"))
        #expect(searchableText.contains("original URI"))
        #expect(searchableText.contains("Ethereum"))
        #expect(searchableText.contains("Substrate/Polkadot"))
        #expect(searchableText.contains("centralized RPC"))
        #expect(searchableText.contains("verify block headers"))
        #expect(searchableText.contains("wallet state"))
        #expect(searchableText.contains("AFM settlement"))
    }

    @Test func decentralizedStartingPointsAreRuntimeResolvable() {
        let points = DecentralizedStartingPoint.featured
        #expect(points.count >= 4)

        for point in points {
            #expect(!point.title.isEmpty)
            #expect(point.description.count > 30)
            #expect(!point.systemImage.isEmpty)

            guard let url = URL(string: point.address), let scheme = url.scheme?.lowercased() else {
                Issue.record("Expected URL-like decentralized address for \(point.title)")
                continue
            }

            #expect(["ipfs", "ipns", "ens"].contains(scheme))
        }
    }

    @Test func gatewayStartingPointsIncludeRequiredHTTPSGateways() {
        let points = RuntimeGatewayStartingPoint.featured
        let urls = Set(points.map(\.urlString))

        #expect(urls.contains("https://llmos.showntell.dev"))
        #expect(urls.contains("https://zerok.cloud"))
        #expect(points.first { $0.urlString == "https://zerok.cloud" }?.isZeroKnowledgeGateway == true)

        for point in points {
            let resolved = BrowserURLResolver.resolve(point.urlString)
            guard case .web(let url) = resolved else {
                Issue.record("Expected HTTPS gateway URL for \(point.title)")
                continue
            }
            #expect(url.scheme == "https")
        }
    }

    @Test func bundledLLMSelectsIPhoneSizedGemma4Model() {
        let selection = BundledLLMSelection.recommended
        let profile = selection.profile

        #expect(profile.displayName == "Gemma 4 E2B IT 4-bit MLX")
        #expect(profile.isRecommendedForIPhone)
        #expect(profile.localDiskFootprintGB < 4)
        #expect(profile.recommendedMinimumMemoryGB == 8)
        #expect(profile.swiftPackageURL == "https://github.com/ml-explore/mlx-swift-lm")
        #expect(profile.swiftPackageMinimumVersion == "3.31.3")
        #expect(profile.swiftPackageProducts == ["MLXVLM", "MLXLMCommon"])
        #expect(profile.loaderSupport.isRunnableWithCurrentSwiftLoader)
        #expect(profile.readinessSummary.contains("MLXVLM"))
    }

    @Test func localLLMRecommendedImportUsesSwiftLMPackageProfile() {
        let recommended = LocalLLMRecommendedImport.current()
        let bundledProfile = BundledLLMSelection.recommended.profile

        #expect(recommended.displayName == bundledProfile.displayName)
        #expect(recommended.packageSummary == bundledProfile.swiftPackageSummary)
        #expect(recommended.readinessSummary == bundledProfile.readinessSummary)
        #expect(recommended.packageSummary.contains("mlx-swift-lm"))
        #expect(recommended.sourceRef == bundledProfile.localWorkspacePath || recommended.sourceRef == bundledProfile.huggingFaceID)
    }

    @Test func dBrowserUsesVendoredSwiftLMPackageForLocalLLMRuntime() throws {
        let repoRoot = Self.repositoryRootURL
        let projectFile = repoRoot.appendingPathComponent("swift/dBrowser/dBrowser.xcodeproj/project.pbxproj")
        let projectText = try String(contentsOf: projectFile, encoding: .utf8)

        #expect(projectText.contains("relativePath = ../Packages/SwiftLM;"))
        #expect(projectText.contains("../../../Packages/SwiftLM") == false)

        let packageRoot = repoRoot.appendingPathComponent("swift/Packages/SwiftLM")
        let packageManifest = packageRoot.appendingPathComponent("Package.swift")
        let packageText = try String(contentsOf: packageManifest, encoding: .utf8)

        #expect(packageText.contains("name: \"ControlPlane\""))
        #expect(packageText.contains("name: \"Contracts\""))
        #expect(packageText.contains("name: \"RuntimeAdapters\""))
        #expect(packageText.contains("name: \"swiflm-control-plane\""))

        let requiredPackageFiles = [
            "Sources/Contracts/Models.swift",
            "Sources/ControlPlane/ControlPlaneClient.swift",
            "Sources/ControlPlane/ControlPlaneService.swift",
            "Sources/ControlPlane/HuggingFaceModelCatalog.swift",
            "Sources/ControlPlane/RuntimeInstaller.swift",
            "Sources/ControlPlane/EngineRuntime.swift",
            "Sources/Storage/Resources/Migrations/001_initial.sql"
        ]

        for relativePath in requiredPackageFiles {
            #expect(FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(relativePath).path))
        }

        let clientText = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/ControlPlane/ControlPlaneClient.swift"),
            encoding: .utf8
        )
        #expect(clientText.contains("func searchModels(query: String"))
        #expect(clientText.contains("func importModel(_ payload: ImportModelRequest)"))
        #expect(clientText.contains("func fetchChatCompletion(_ payload: OpenAIChatCompletionRequest)"))
    }

    @MainActor
    @Test func browserViewModelRefreshesLocalLLMManagementThroughInjectedSwiftLMManager() async {
        let expectedState = Self.localLLMConnectedFixture(statusLine: "Connected from unit test.")
        let manager = MockLocalLLMManager(initialState: .disconnected(), refreshState: expectedState)
        let model = makeIsolatedBrowserViewModel(localLLMManager: manager)

        await model.refreshLocalLLMManagement()

        #expect(manager.calls == ["refresh"])
        #expect(model.localLLMState == expectedState)
        #expect(model.localLLMState.models.first?.displayName == "Gemma 4 E2B IT 4-bit MLX")
    }

    @MainActor
    @Test func browserViewModelRoutesLocalLLMActionsToSwiftLMManager() async {
        let connectedState = Self.localLLMConnectedFixture(statusLine: "Action completed.")
        let manager = MockLocalLLMManager(initialState: .disconnected(), refreshState: connectedState)
        let model = makeIsolatedBrowserViewModel(localLLMManager: manager)

        await model.connectLocalLLMControlPlane()
        await model.bootstrapLocalLLMControlPlane()
        await model.importRecommendedLocalLLM()
        await model.inspectLocalLLMModel("model.gemma")
        await model.validateLocalLLMModel("model.gemma")
        await model.warmLocalLLMModel("model.gemma")
        await model.stopLocalLLMEngine("engine.gemma")
        await model.installLocalLLMBackend("mlx-swift")

        #expect(manager.calls == [
            "connect",
            "bootstrap",
            "importRecommended",
            "inspect:model.gemma",
            "validate:model.gemma",
            "warm:model.gemma",
            "stop:engine.gemma",
            "install:mlx-swift"
        ])
        #expect(model.localLLMState.statusLine == "Action completed.")
    }

    @Test func bundledLLMUsesLocalMLXArtifactWhenPresent() {
        let selection = BundledLLMSelection.recommended
        // The model directory is only present on a configured developer machine; off such a
        // machine the resolver correctly falls back to Hugging Face. Both outcomes are valid.
        switch selection.modelLocation() {
        case .localDirectory(let url):
            #expect(url.path.hasSuffix("/diskspace-gemma/models/gemma-4-e2b-it-4bit-mlx"))
        case .huggingFace(let id):
            #expect(id == selection.profile.huggingFaceID)
        }
    }

    @Test func bundledLLMResolvesModelDirectoryFromEnvironmentOverride() throws {
        let selection = BundledLLMSelection.recommended
        let fileManager = FileManager.default
        let modelDir = fileManager.temporaryDirectory
            .appendingPathComponent("dbrowser-mlx-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: modelDir) }
        for file in ["config.json", "tokenizer.json", "model.safetensors"] {
            try Data("{}".utf8).write(to: modelDir.appendingPathComponent(file))
        }
        let unusedHome = fileManager.temporaryDirectory
            .appendingPathComponent("dbrowser-home-\(UUID().uuidString)", isDirectory: true)

        // An explicit override resolves regardless of the host machine layout.
        let resolved = selection.localWorkspaceModelURL(
            environment: ["DBROWSER_MLX_MODEL_DIR": modelDir.path],
            homeDirectory: unusedHome
        )
        #expect(resolved?.standardizedFileURL == modelDir.standardizedFileURL)

        // With no override and a home directory that has no checkout, resolution is nil rather
        // than depending on a hard-coded absolute path.
        let unresolved = selection.localWorkspaceModelURL(
            environment: [:],
            homeDirectory: unusedHome
        )
        #expect(unresolved == nil)
    }

    @Test func bundledLLMModelConfigurationUsesMLXVLMRegistry() {
        let selection = BundledLLMSelection.recommended
        let configuration = selection.modelConfiguration()

        // When the local artifact is present the configuration is directory-backed; otherwise it
        // is the registry (Hugging Face) configuration. The prompt/EOS metadata holds either way.
        if case .directory(let url) = configuration.id {
            #expect(url.path.hasSuffix("/diskspace-gemma/models/gemma-4-e2b-it-4bit-mlx"))
        }
        #expect(configuration.defaultPrompt == "Describe the image in English")
        #expect(configuration.extraEOSTokens.contains("<end_of_turn>"))
    }

    @MainActor
    @Test func llmConversationRendererCompressesWithoutMutatingLedger() {
        var conversation = LLMConversation(activeModelID: LLMModelRegistry.localGemmaID)
        for index in 0..<12 {
            conversation.appendMessage(
                LLMConversationMessage(
                    role: index.isMultiple(of: 2) ? .user : .assistant,
                    text: "Message \(index) " + String(repeating: "context ", count: 80),
                    modelID: index.isMultiple(of: 2) ? nil : LLMModelRegistry.localGemmaID
                )
            )
        }
        let originalMessageIDs = conversation.messages.map(\.id)
        let smallModel = LLMModelProfile(
            id: "unit.small",
            displayName: "Small Test Model",
            providerKind: .localMLX,
            trustBoundary: .onDevice,
            contextWindowTokens: 700,
            supportsTools: false,
            supportsMemoryCitations: true,
            runtimeMode: .local,
            availability: .available,
            detail: "Small context test model."
        )

        let rendered = LLMConversationContextRenderer.render(
            conversation: conversation,
            model: smallModel,
            latestPageSnapshot: nil
        )

        #expect(rendered.wasCompressed)
        #expect(!rendered.compressedMessageIDs.isEmpty)
        #expect(rendered.includedMessageIDs.contains(originalMessageIDs.last!))
        #expect(rendered.prompt.contains("Compressed prior context"))
        #expect(conversation.messages.map(\.id) == originalMessageIDs)
    }

    @MainActor
    @Test func llmContextRendererCarriesPruneAndSwiftLMMinimizationState() {
        var conversation = LLMConversation(activeModelID: LLMModelRegistry.localGemmaID)
        conversation.appendMessage(
            LLMConversationMessage(
                role: .user,
                text: "Summarize the active page with only the approved context.",
                modelID: nil
            )
        )
        let model = LLMModelRegistry.model(withID: LLMModelRegistry.localGemmaID)!

        let rendered = LLMConversationContextRenderer.render(
            conversation: conversation,
            model: model,
            latestPageSnapshot: nil
        )

        #expect(rendered.contextMinimization.packerID == "prune.context-pack.signatures-first")
        #expect(rendered.contextMinimization.localRuntimeID == "SwiftLM/MLX")
        #expect(rendered.contextMinimization.disclosureBoundary.contains("On-device"))
        #expect(rendered.prompt.contains("Context minimization: prune.context-pack.signatures-first via SwiftLM/MLX"))
        #expect(rendered.prompt.contains("Use Prune-style signatures-first context packing"))
        #expect(rendered.estimatedPromptTokens <= rendered.contextMinimization.maxPromptTokens)
    }

    @MainActor
    @Test func runtimeBridgeForwardsRenderedConversationContextToAFMServices() async {
        let capturedRequests = JSONRequestCapture()
        let serviceHarness = Self.makeAFMServiceSession(key: "llmcontext") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port
            capturedRequests.capture(request)

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://conversation",
                            "name": "Conversation Runner",
                            "skills": ["summarize"],
                            "status": "healthy"
                        ]
                    ]
                ])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/route" {
                return Self.jsonResponse(for: request, body: [
                    "selection": [
                        "id": "afm://conversation",
                        "name": "Conversation Runner",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-context",
                    "status": "queued"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )
        var conversation = LLMConversation(activeModelID: LLMModelRegistry.afMarketRouterID)
        conversation.appendMessage(LLMConversationMessage(role: .user, text: "Summarize the current report."))
        conversation.appendMessage(
            LLMConversationMessage(
                role: .assistant,
                text: "Earlier context should remain available.",
                modelID: LLMModelRegistry.localGemmaID
            )
        )
        let model = LLMModelRegistry.model(withID: LLMModelRegistry.afMarketRouterID)!
        let rendered = LLMConversationContextRenderer.render(
            conversation: conversation,
            model: model,
            latestPageSnapshot: nil
        )

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Continue",
                pageURLString: "https://example.com",
                preferredModelID: model.id,
                conversationID: conversation.id,
                renderedConversationContext: rendered
            )
        )
        let routeBody = capturedRequests.body(for: "/route")
        let jobBody = capturedRequests.body(for: "/jobs")
        let jobPayload = jobBody?["payload"] as? [String: Any]

        #expect(result.mode == .service)
        #expect((routeBody?["prompt"] as? String)?.contains("Conversation messages") == true)
        #expect((routeBody?["prompt"] as? String)?.contains("Earlier context should remain available.") == true)
        #expect((jobPayload?["prompt"] as? String)?.contains("Active model: AFMarket Router") == true)
    }

    @MainActor
    @Test func llmRouterServiceClientLoadsSnapshotAndCompletes() async throws {
        let capturedRequests = JSONRequestCapture()
        let harness = Self.makeLLMRouterSession(key: "llmrouterclient") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/health" {
                return Self.jsonResponse(for: request, body: [
                    "ok": true,
                    "local_available": true,
                    "message": "router ready"
                ])
            }

            if path == "/models" {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "apple.foundation",
                            "provider": "apple_foundation",
                            "display_name": "Apple Foundation via LLM Router",
                            "context_window_tokens": 16_384,
                            "supports_tools": true,
                            "available": true,
                            "detail": "Local-first Foundation model route"
                        ]
                    ]
                ])
            }

            if path == "/v1/complete" {
                return Self.jsonResponse(for: request, body: [
                    "text": "Router answer with preserved context.",
                    "provider": "apple_foundation",
                    "model_id": "apple.foundation",
                    "usage": [
                        "prompt_tokens": 21,
                        "completion_tokens": 7,
                        "total_tokens": 28
                    ],
                    "tool_calls": [
                        [
                            "id": "tool-1",
                            "name": "browser.query",
                            "arguments": ["selector": "main"],
                            "approval_required": true
                        ]
                    ],
                    "route": "local-first"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = LLMRouterServiceClient(configuration: harness.configuration, session: harness.session)
        let conversationID = UUID()
        let runID = UUID()

        let snapshot = await client.snapshot()
        let response = try await client.complete(
            LLMRouterCompletionRequest(
                prompt: "Conversation messages:\nUSER: Hello",
                modelID: LLMRouterProvider.appleFoundation.modelID,
                policy: LLMRouterRoutingPolicy(preferLocal: true, noEgress: true, forceProvider: .appleFoundation),
                options: LLMRouterCompletionOptions(temperature: 0.6, maxTokens: 256, systemPrompt: "Unit test"),
                context: LLMRouterCompletionContext(
                    conversationID: conversationID,
                    runID: runID,
                    pageURLString: "https://example.com",
                    snapshotCommitment: "fnv1a64:abc",
                    memoryContextIDs: ["mem-1"],
                    estimatedPromptTokens: 21,
                    includedMessageIDs: [UUID()],
                    compressedMessageIDs: []
                )
            )
        )
        let completionBody = capturedRequests.body(for: "/v1/complete")
        let policyBody = completionBody?["policy"] as? [String: Any]
        let contextBody = completionBody?["context"] as? [String: Any]

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.isModelAvailable(provider: .appleFoundation))
        #expect(snapshot.models.first?.contextWindowTokens == 16_384)
        #expect(response.text == "Router answer with preserved context.")
        #expect(response.usage?.totalTokens == 28)
        #expect(response.toolCalls.first?.name == "browser.query")
        #expect(completionBody?["model_id"] as? String == "apple.foundation")
        #expect(policyBody?["no_egress"] as? Bool == true)
        #expect(policyBody?["force_provider"] as? String == "apple_foundation")
        #expect(contextBody?["conversation_id"] as? String == conversationID.uuidString)
        #expect(contextBody?["run_id"] as? String == runID.uuidString)
        #expect((contextBody?["memory_context_ids"] as? [String]) == ["mem-1"])
    }

    @MainActor
    @Test func swiftLLMConversationUsesLLMRouterSelectedModel() async {
        let capturedRequests = JSONRequestCapture()
        let routerHarness = Self.makeLLMRouterSession(key: "llmroutervm") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/health" {
                return Self.jsonResponse(for: request, body: [
                    "ok": true,
                    "local_available": true,
                    "message": "router ready"
                ])
            }

            if path == "/models" {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "apple.foundation",
                            "provider": "apple_foundation",
                            "display_name": "Apple Foundation via LLM Router",
                            "context_window_tokens": 16_384,
                            "supports_tools": true,
                            "available": true
                        ]
                    ]
                ])
            }

            if path == "/v1/complete" {
                return Self.jsonResponse(for: request, body: [
                    "text": "Router answer for the Swift conversation.",
                    "provider": "apple_foundation",
                    "model_id": "apple.foundation",
                    "usage": [
                        "prompt_tokens": 32,
                        "completion_tokens": 9,
                        "total_tokens": 41
                    ],
                    "tool_calls": [
                        [
                            "id": "tool-vm",
                            "name": "browser.query",
                            "arguments": ["selector": "article"],
                            "approval_required": true
                        ]
                    ],
                    "route": "local-first"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineAFM = Self.makeAFMServiceSession(key: "llmrouterafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: offlineAFM.configuration,
                llmRouter: routerHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: offlineAFM.configuration,
                session: offlineAFM.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(
                configuration: routerHarness.configuration,
                session: routerHarness.session
            )
        )
        let model = makeIsolatedBrowserViewModel(runtimeBridge: bridge)
        model.navigate("https://example.com")
        await model.refreshRuntimeBridgeStatus()

        model.selectLLMModel(LLMModelRegistry.llmRouterAppleFoundationID)
        guard let runID = model.sendLLMMessage("Use the router and keep context.") else {
            Issue.record("Expected LLM router conversation run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)
        let completionBody = capturedRequests.body(for: "/v1/complete")
        let contextBody = completionBody?["context"] as? [String: Any]
        let eventKinds = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(completed)
        #expect(model.selectedLLMModelID == LLMModelRegistry.llmRouterAppleFoundationID)
        #expect(model.llmConversation.messages.contains { $0.role == .assistant && $0.modelID == LLMModelRegistry.llmRouterAppleFoundationID })
        #expect(model.llmConversation.latestAssistantMessage?.text.contains("Router answer for the Swift conversation.") == true)
        #expect((completionBody?["prompt"] as? String)?.contains("Conversation messages") == true)
        #expect((completionBody?["prompt"] as? String)?.contains("Use the router and keep context.") == true)
        #expect(contextBody?["conversation_id"] as? String == model.llmConversation.id.uuidString)
        #expect(contextBody?["run_id"] as? String == runID.uuidString)
        #expect(eventKinds.contains(.modelCompleted))
        #expect(eventKinds.contains(.actionRequested))
    }

    @MainActor
    @Test func llmChatModelSwitchPreservesContextAndRecordsFallback() async {
        let offlineServices = Self.makeAFMServiceSession(key: "llmfallback") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: offlineServices.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: offlineServices.configuration,
                session: offlineServices.session
            )
        )
        let model = makeIsolatedBrowserViewModel(runtimeBridge: bridge)
        model.navigate("https://example.com")
        let conversationID = model.llmConversation.id

        model.selectLLMModel(LLMModelRegistry.afMarketRouterID)
        guard let runID = model.sendLLMMessage("Keep the prior context while changing models.") else {
            Issue.record("Expected LLM conversation run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)
        let eventKinds = model.llmConversation.events.map(\.kind)
        let run = model.copilotRuns.first { $0.id == runID }

        #expect(completed)
        #expect(model.llmConversation.id == conversationID)
        #expect(model.llmConversation.activeModelID == LLMModelRegistry.afMarketRouterID)
        #expect(model.llmConversation.messages.contains { $0.role == .user })
        #expect(model.llmConversation.messages.contains { $0.role == .assistant && $0.modelID == LLMModelRegistry.afMarketRouterID })
        #expect(eventKinds.contains(.modelSwitched))
        #expect(eventKinds.contains(.assistantMessageAdded))
        #expect(eventKinds.contains(.providerFallback))
        #expect(run?.conversationID == conversationID)
        #expect(run?.modelID == LLMModelRegistry.afMarketRouterID)
    }

    @MainActor
    @Test func llmConversationStoreRestoresConversationAndModelSelection() async {
        let storeURL = Self.temporaryJSONStoreURL(named: "llm-conversation-restore")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let firstModel = makeIsolatedBrowserViewModel(
            llmConversationStore: LLMConversationStore(fileURL: storeURL)
        )
        firstModel.navigate("https://example.com")
        firstModel.selectLLMModel(LLMModelRegistry.afMarketRouterID)
        guard let runID = firstModel.sendLLMMessage("Persist this conversation state.") else {
            Issue.record("Expected persisted conversation run ID")
            return
        }
        firstModel.cancelCopilotRun(runID)

        let restoredModel = makeIsolatedBrowserViewModel(
            llmConversationStore: LLMConversationStore(fileURL: storeURL)
        )

        #expect(restoredModel.llmConversation.id == firstModel.llmConversation.id)
        #expect(restoredModel.selectedLLMModelID == LLMModelRegistry.afMarketRouterID)
        #expect(restoredModel.llmConversation.activeModelID == LLMModelRegistry.afMarketRouterID)
        #expect(restoredModel.llmConversation.messages.contains { $0.text == "Persist this conversation state." })
        #expect(restoredModel.copilotRuns.isEmpty)
    }

    @MainActor
    @Test func llmConversationResetClearsPersistedThread() {
        let storeURL = Self.temporaryJSONStoreURL(named: "llm-conversation-reset")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let model = makeIsolatedBrowserViewModel(
            llmConversationStore: LLMConversationStore(fileURL: storeURL)
        )
        model.navigate("https://example.com")
        guard let runID = model.sendLLMMessage("This should be cleared.") else {
            Issue.record("Expected reset test conversation run ID")
            return
        }
        model.cancelCopilotRun(runID)
        let previousConversationID = model.llmConversation.id

        model.startNewLLMConversation()
        let restoredModel = makeIsolatedBrowserViewModel(
            llmConversationStore: LLMConversationStore(fileURL: storeURL)
        )

        #expect(model.llmConversation.id != previousConversationID)
        #expect(model.llmConversation.messages.isEmpty)
        #expect(restoredModel.llmConversation.id == model.llmConversation.id)
        #expect(restoredModel.llmConversation.messages.isEmpty)
    }

    @MainActor
    @Test func llmConversationRestoreFallsBackFromUnavailableModel() {
        let unavailableConversation = LLMConversation(activeModelID: LLMModelRegistry.llmGatewayID)
        let store = LLMConversationStore.ephemeral(
            seed: LLMConversationStorePayload(
                conversation: unavailableConversation,
                selectedModelID: LLMModelRegistry.llmGatewayID
            )
        )

        let model = makeIsolatedBrowserViewModel(llmConversationStore: store)

        #expect(model.selectedLLMModelID == LLMModelRegistry.defaultModelID)
        #expect(model.llmConversation.activeModelID == LLMModelRegistry.defaultModelID)
        #expect(model.llmConversation.events.contains { $0.kind == .modelSwitched })
    }

    @MainActor
    @Test func decentralizedStartingPointsResolveToRenderableGatewayURLs() async {
        let bridge = MobileRuntimeBridge()

        for point in DecentralizedStartingPoint.featured {
            let resolution = await bridge.resolve(point.address)

            #expect(resolution.resolvedURLString?.hasPrefix("https://") == true)
            #expect(resolution.message?.contains("Resolved") == true)

            guard let resolvedURLString = resolution.resolvedURLString,
                  let resolvedURL = URL(string: resolvedURLString) else {
                Issue.record("Expected gateway URL for \(point.title)")
                continue
            }

            #expect(resolvedURL.host == "dweb.link")
            #expect(resolvedURL.path.hasPrefix("/ipfs/") || resolvedURL.path.hasPrefix("/ipns/"))
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

        let swarm = await bridge.resolve("bzz://abcdef/app.json")
        #expect(swarm.source == .decentralizedStorageGateway)
        #expect(swarm.resolvedURLString == "https://gateway.ethswarm.org/bzz/abcdef/app.json")

        let arweave = await bridge.resolve("ar://abc123/app.json")
        #expect(arweave.source == .decentralizedStorageGateway)
        #expect(arweave.resolvedURLString == "https://arweave.net/abc123/app.json")

        let filecoinCID = await bridge.resolve("filecoin://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/app.json")
        #expect(filecoinCID.source == .decentralizedStorageGateway)
        #expect(filecoinCID.resolvedURLString == "https://dweb.link/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/app.json")
        #expect(filecoinCID.isContentLoadable)

        let walrus = await bridge.resolve("walrus://blob-id")
        #expect(walrus.source == .decentralizedStorageGateway)
        #expect(walrus.resolvedURLString == "https://aggregator.walrus-mainnet.walrus.space/v1/blobs/blob-id")
        #expect(walrus.isContentLoadable)
        #expect(walrus.contentAccess == .loadableGateway)
        #expect(walrus.message?.contains("Walrus") == true)
    }

    @MainActor
    @Test func runtimeBridgeHandlesEveryDecentralizedStorageNetwork() async {
        let bridge = MobileRuntimeBridge()

        for network in DecentralizedStorageNetwork.supported {
            let input = sampleDecentralizedStorageURI(forScheme: network.primaryScheme)
            let resolution = await bridge.resolve(input)

            #expect(resolution.originalInput == input)
            #expect(resolution.message?.contains(network.title) == true)

            switch network.id {
            case "ipfs":
                #expect(resolution.source == .ipfsGateway)
                #expect(resolution.resolvedURLString?.contains("/ipfs/") == true)
            case "ipns":
                #expect(resolution.source == .ipnsGateway)
                #expect(resolution.resolvedURLString?.contains("/ipns/") == true)
            case "swarm":
                #expect(resolution.source == .decentralizedStorageGateway)
                #expect(resolution.resolvedURLString == "https://gateway.ethswarm.org/bzz/abcdef/app.json")
            case "arweave":
                #expect(resolution.source == .decentralizedStorageGateway)
                #expect(resolution.resolvedURLString == "https://arweave.net/abc123/app.json")
            case "walrus":
                #expect(resolution.source == .decentralizedStorageGateway)
                #expect(resolution.resolvedURLString?.contains("aggregator.walrus-mainnet.walrus.space/v1/blobs/") == true)
                #expect(resolution.isContentLoadable)
            default:
                #expect(resolution.source == .decentralizedStorageNativeAdapter)
                #expect(URL(string: resolution.resolvedURLString ?? "")?.host == "127.0.0.1")
                #expect(URL(string: resolution.resolvedURLString ?? "")?.path == expectedNativeAdapterPath(for: network))
                #expect(resolution.isContentLoadable)
                #expect(resolution.contentAccess == .nativeAdapter)
                #expect(resolution.message?.contains(network.adapter.handlerID) == true)
            }
        }
    }

    @MainActor
    @Test func runtimeBridgeRemoteResolverHandlesEveryStorageSchemeAlias() async {
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                nativeStorageAdapters: .disabled,
                remoteRuntimeBaseURL: RuntimeBridgeConfiguration.exampleRemoteRuntimeBaseURL
            )
        )
        let remoteRuntimeNetworkIDs: Set<String> = [
            "filecoin",
            "walrus",
            "iroh",
            "hypercore",
            "sia",
            "storj",
            "tahoe-lafs",
            "autonomi",
            "bittorrent",
            "ceramic",
            "orbitdb",
            "radicle"
        ]

        for network in DecentralizedStorageNetwork.supported where remoteRuntimeNetworkIDs.contains(network.id) {
            for scheme in network.schemes {
                let input = network.id == "walrus"
                    ? "\(scheme)://abc123xyz/site/index.html"
                    : sampleDecentralizedStorageURI(forScheme: scheme)
                let resolution = await bridge.resolve(input)
                let query = remoteResolverQueryItems(for: resolution.resolvedURLString)

                #expect(resolution.source == .remoteRuntime)
                #expect(URL(string: resolution.resolvedURLString ?? "")?.host == "storage-resolver.example")
                #expect(URL(string: resolution.resolvedURLString ?? "")?.path == expectedRemoteResolverPath(for: network))
                #expect(query["network"] == network.id)
                #expect(query["scheme"] == scheme)
                #expect(query["adapter"] == network.adapter.handlerID)
                #expect(query["native_issue"] == network.adapter.issueNumber.map { String($0) })
                #expect(query["resolution_stage"] == DecentralizedStorageAdapterStage.remoteRuntimeHandoff.rawValue)
                #expect(query["locator_kind"] == network.adapter.locatorKind)
                #expect(query["locator"]?.isEmpty == false)
                #expect(query["uri"] == input)
                #expect(resolution.message?.contains(network.title) == true)
                #expect(resolution.message?.contains(network.adapter.handlerID) == true)
            }
        }
    }

    @MainActor
    @Test func runtimeBridgeReportsResolverRequirementWhenNoStorageResolverIsConfigured() async {
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(nativeStorageAdapters: .disabled)
        )

        let resolution = await bridge.resolve("filecoin://baga6ea4seaqaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/app.car")

        #expect(resolution.source == .decentralizedStorageResolverRequired)
        #expect(resolution.resolvedURLString == nil)
        #expect(resolution.isContentLoadable == false)
        #expect(resolution.contentAccess == .localResolverRequired)
        #expect(resolution.message?.contains("Filecoin retrieval client") == true)
        #expect(resolution.message?.contains("#119") == true)
    }

    @MainActor
    @Test func runtimeBridgeNamesResolverRequirementsForNonGatewayStorageProtocols() async {
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(nativeStorageAdapters: .disabled)
        )
        let requirementsByScheme = [
            "piececid": "Filecoin retrieval client",
            "iroh": "Iroh endpoint",
            "hyper": "Hypercore",
            "sia": "Sia renterd",
            "storj": "Storj access grant",
            "tahoe": "Tahoe-LAFS gateway",
            "autonomi": "Autonomi client",
            "magnet": "BitTorrent/WebTorrent engine",
            "ceramic": "Ceramic node",
            "orbitdb": "OrbitDB/IPFS",
            "rad": "Radicle node"
        ]

        for (scheme, requiredText) in requirementsByScheme {
            let input = sampleDecentralizedStorageURI(forScheme: scheme)
            let resolution = await bridge.resolve(input)

            #expect(resolution.source == .decentralizedStorageResolverRequired)
            #expect(resolution.resolvedURLString == nil)
            #expect(resolution.isContentLoadable == false)
            #expect(resolution.message?.contains(requiredText) == true)
            #expect(resolution.message?.contains("Native adapter issue") == true)
        }
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
    @Test func runtimeBridgeConnectsAndValidatesMCPServers() async {
        let bridge = MobileRuntimeBridge()
        var http = bridge.mcpServers.first { $0.id == "demo-weather" }!
        http.enabled = true

        _ = await bridge.updateMCPServer(http)
        let connected = await bridge.connectMCPServer(http.id)
        let mcpFeature = bridge.featureStates.first { $0.feature == .mcpServers }

        #expect(connected?.status.state == .connected)
        #expect(connected?.status.discoveredTools.contains("tools/list") == true)
        #expect(mcpFeature?.mode == .service)
        #expect(mcpFeature?.status.contains("1 connected") == true)

        let invalidWebSocket = MCPServerConfiguration(
            id: "bad-ws",
            name: "Bad WebSocket",
            transport: .websocket,
            endpoint: "https://example.com/mcp",
            enabled: true
        )
        _ = await bridge.updateMCPServer(invalidWebSocket)
        let failed = await bridge.connectMCPServer(invalidWebSocket.id)
        #expect(failed?.status.state == .failed)
        #expect(failed?.status.message.contains("WS") == true)

        let disconnected = await bridge.disconnectMCPServer(http.id)
        #expect(disconnected?.status.state == .disconnected)
    }

    @Test func blockchainCapabilityGrantDefaultsExposeBrokeredHostTools() {
        let appGrant = BlockchainCapabilityGrant.defaultForA2UIApp()
        let mcpGrant = BlockchainCapabilityGrant.defaultForMCPServer()

        #expect(appGrant.requestSigning)
        #expect(appGrant.requestBroadcast)
        #expect(appGrant.hostTools.contains("dbrowser.tx.request_signature"))
        #expect(appGrant.hostTools.contains("dbrowser.tx.request_broadcast"))
        #expect(mcpGrant.readChainData)
        #expect(mcpGrant.prepareTransactions)
        #expect(!mcpGrant.requestSigning)
        #expect(!mcpGrant.requestBroadcast)
        #expect(mcpGrant.hostTools.contains("dbrowser.chain.get_status"))
        #expect(!mcpGrant.hostTools.contains("dbrowser.tx.request_signature"))
        #expect(mcpGrant.installSummary.contains("Selected account"))
    }

    @MainActor
    @Test func mcpServerBlockchainGrantAddsInjectedHostTools() async {
        let bridge = MobileRuntimeBridge()
        var server = bridge.mcpServers.first { $0.id == "demo-weather" }!
        server.enabled = true
        server.blockchainAccess = .defaultForMCPServer()

        _ = await bridge.updateMCPServer(server)
        let connected = await bridge.connectMCPServer(server.id)

        #expect(connected?.status.state == .connected)
        #expect(connected?.status.discoveredTools.contains("dbrowser.chain.get_status") == true)
        #expect(connected?.status.discoveredTools.contains("dbrowser.wallet.get_portfolio") == true)
        #expect(connected?.status.discoveredTools.contains("dbrowser.tx.prepare") == true)
        #expect(connected?.status.discoveredTools.contains("dbrowser.tx.request_signature") == false)
        #expect(connected?.status.message.contains("Read chain data") == true)
    }

    @Test func blockchainExplorerCatalogBuildsChainSpecificURLs() {
        let catalog = BlockchainExplorerCatalog.default

        let ethereumAccount = catalog.url(
            for: BlockchainExplorerTarget(
                chainRef: "ethereum-mainnet",
                kind: .account,
                value: "0xabc"
            )
        )
        let bitcoinTransaction = catalog.url(
            for: BlockchainExplorerTarget(
                chainRef: "bitcoin-mainnet",
                kind: .transaction,
                value: "tx123"
            )
        )
        let solanaAccount = catalog.url(
            for: BlockchainExplorerTarget(
                chainRef: "solana-mainnet",
                kind: .account,
                value: "So11111111111111111111111111111111111111112"
            )
        )

        #expect(ethereumAccount?.absoluteString == "https://etherscan.io/address/0xabc")
        #expect(bitcoinTransaction?.absoluteString == "https://mempool.space/tx/tx123")
        #expect(solanaAccount?.absoluteString == "https://solscan.io/account/So11111111111111111111111111111111111111112")
    }

    @Test func walletNetworksCoverTrackedChainFamilies() {
        let networks = WalletNetwork.defaultNetworks()
        let families = Set(networks.map(\.family))

        #expect(families.contains(.bitcoin))
        #expect(families.contains(.ethereum))
        #expect(families.contains(.evmLayer2))
        #expect(families.contains(.solana))
        #expect(families.contains(.cosmosTendermint))
        #expect(families.contains(.polkadotSubstrate))
        #expect(families.contains(.avalanche))
        #expect(families.contains(.tron))
        #expect(families.contains(.xrpLedger))
        #expect(families.contains(.sui))
        #expect(families.contains(.aptos))
        #expect(networks.allSatisfy { $0.explorer != nil })
    }

    @MainActor
    @Test func runtimeBridgeWalletExplorerPreviewsAndRecordsPolicyReceipts() async {
        let bridge = MobileRuntimeBridge()

        let connected = await bridge.createEmbeddedWallet(label: "Test embedded wallet")
        #expect(connected.isConnected)
        #expect(connected.address?.hasPrefix("0x") == true)
        #expect(connected.explorerURLString?.contains("etherscan.io/address") == true)
        #expect(bridge.walletPortfolio.connectionKind == .nativeEmbedded)
        #expect(bridge.walletPortfolio.embeddedWallet?.displayName == "Test embedded wallet")
        #expect(bridge.walletPortfolio.accounts.count == bridge.walletPortfolio.networks.count)

        let switched = await bridge.switchWalletNetwork("base-sepolia")
        #expect(switched.activeChainRef == "base-sepolia")
        guard let activeAddress = bridge.walletPortfolio.activeAccount?.address else {
            Issue.record("Expected active wallet account")
            return
        }

        let request = WalletTransferRequest(
            amount: Decimal(10),
            destination: activeAddress,
            reason: "Test transfer"
        )
        let preview = await bridge.previewWalletTransfer(request)
        #expect(preview.status == .ready)
        #expect(preview.requiresApproval == false)
        #expect(preview.broadcastMode == .unavailable)
        #expect(preview.chainTrustSummary.contains("Base Sepolia"))
        #expect(preview.explorerURL?.absoluteString.contains("sepolia.basescan.org/address") == true)

        let receipt = await bridge.signWalletTransfer(request)
        #expect(receipt.status == .policySigned)
        #expect(receipt.transactionHash == nil)
        #expect(receipt.signatureDigest?.isEmpty == false)
        #expect(receipt.broadcastMode == .unavailable)
        #expect(bridge.walletPortfolio.recentReceipts.first?.id == receipt.id)
    }

    @MainActor
    @Test func runtimeBridgeWalletPolicyRejectsInvalidTransfersAndRequiresApprovalAboveLimit() async {
        let bridge = MobileRuntimeBridge()
        let disconnectedPreview = await bridge.previewWalletTransfer(
            WalletTransferRequest(amount: Decimal(1), destination: "0xabc", reason: "Disconnected")
        )
        #expect(disconnectedPreview.status == .rejected)

        _ = await bridge.connectWallet()
        let invalidAmount = await bridge.previewWalletTransfer(
            WalletTransferRequest(amount: Decimal.zero, destination: "0xabc", reason: "Invalid")
        )
        #expect(invalidAmount.status == .rejected)

        let largeTransfer = await bridge.previewWalletTransfer(
            WalletTransferRequest(amount: Decimal(100), destination: "0x1111111111111111111111111111111111111111", reason: "Large")
        )
        #expect(largeTransfer.status == .needsApproval)
        let receipt = await bridge.signWalletTransfer(
            WalletTransferRequest(amount: Decimal(100), destination: "0x1111111111111111111111111111111111111111", reason: "Large")
        )
        #expect(receipt.status == .needsApproval)
        #expect(receipt.signatureDigest == nil)
    }

    @Test func keychainWalletSeedStoreGeneratesAndPersistsSecureSeed() {
        let account = "unit-test-\(UUID().uuidString)"
        let store = KeychainWalletSeedStore(service: "dbrowser-unit-test-\(UUID().uuidString)")
        defer { store.deleteSeed(account: account) }

        // Nothing stored yet.
        #expect(store.loadSeed(account: account) == nil)

        // First access generates 256 bits (64 hex chars) of secure entropy, not a UUID.
        let created = store.loadOrCreateSeed(account: account)
        #expect(created.count == 64)
        #expect(created.allSatisfy { $0.isHexDigit })

        // The seed is stable across loads rather than regenerated on every wallet creation.
        #expect(store.loadOrCreateSeed(account: account) == created)
        #expect(store.loadSeed(account: account) == created)

        // Freshly generated seeds are unique and correctly sized.
        #expect(WalletSeedFactory.generateSeedHex() != WalletSeedFactory.generateSeedHex())
        #expect(WalletSeedFactory.generateSeedHex().count == 64)
    }

    @MainActor
    @Test func brokeredWalletTransactionContractsEnforceSigningAndBroadcastPermissions() async {
        let bridge = MobileRuntimeBridge()
        _ = await bridge.createEmbeddedWallet(label: "Contract wallet")
        let principal = LocalCapabilityPrincipal(id: "travel-booker", name: "Travel Booker", kind: .a2uiApp)
        let destination = bridge.walletPortfolio.activeAccount?.address ?? "0x1111111111111111111111111111111111111111"
        let request = WalletTransferRequest(
            amount: Decimal(10),
            destination: destination,
            reason: "Booking deposit"
        )

        let mcpGrant = BlockchainCapabilityGrant.defaultForMCPServer()
        let mcpPrepared = await bridge.prepareWalletTransaction(request, principal: principal, grant: mcpGrant)
        let simulation = await bridge.simulateWalletTransaction(mcpPrepared)
        let mcpSignature = await bridge.requestWalletSignature(mcpPrepared, grant: mcpGrant)
        let mcpBroadcast = await bridge.requestWalletBroadcast(mcpSignature, principal: principal, grant: mcpGrant)

        #expect(mcpPrepared.status == .ready)
        #expect(simulation.status == .success)
        #expect(mcpSignature.status == .rejected)
        #expect(mcpSignature.message.contains("Request signing"))
        #expect(mcpBroadcast.status == .denied)

        let appGrant = BlockchainCapabilityGrant.defaultForA2UIApp()
        let contract = bridge.blockchainHostContract(for: principal, grant: appGrant)
        let appPrepared = await bridge.prepareWalletTransaction(request, principal: principal, grant: appGrant)
        let appSignature = await bridge.requestWalletSignature(appPrepared, grant: appGrant)
        let appBroadcast = await bridge.requestWalletBroadcast(appSignature, principal: principal, grant: appGrant)

        #expect(contract.hostTools.contains("dbrowser.tx.request_signature"))
        #expect(!contract.chains.isEmpty)
        #expect(appPrepared.status == .ready)
        #expect(appSignature.status == .policySigned)
        #expect(appBroadcast.status == .unavailable)
        #expect(appBroadcast.message.contains("unavailable"))
    }

    @MainActor
    @Test func runtimeBridgeUsesAFMServicesForStatusAndCopilot() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "online") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "name": "Demo Writer",
                            "skills": ["summarize"],
                            "status": "healthy"
                        ]
                    ]
                ])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "maintainer": "core",
                            "version": "0.1.0",
                            "checksum": "0xabc"
                        ]
                    ]
                ])
            }

            if path == "/route" {
                return Self.jsonResponse(for: request, body: [
                    "selection": [
                        "id": "afm://demo-writer",
                        "name": "Demo Writer",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-1",
                    "status": "queued"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let afmServices = states.first { $0.feature == .afmServices }
        #expect(afmServices?.mode == .service)
        #expect(afmServices?.isAvailable == true)
        #expect(afmServices?.status.contains("router online") == true)

        let copilot = await bridge.runCopilot(
            CopilotRunRequest(prompt: "Summarize this page", pageURLString: "https://example.com")
        )
        #expect(copilot.mode == .service)
        #expect(copilot.summary.contains("Demo Writer"))
        #expect(copilot.summary.contains("job-1"))
        #expect(copilot.suggestions.contains { $0.contains("Registry has 1 pack") })
    }

    @MainActor
    @Test func browserViewModelSurfacesAFMServicePacks() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "surface") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "name": "Demo Writer",
                            "skills": ["summarize"],
                            "status": "healthy"
                        ]
                    ]
                ])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "maintainer": "core",
                            "version": "0.1.0",
                            "checksum": "0xabc"
                        ]
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )
        let model = makeIsolatedBrowserViewModel(runtimeBridge: bridge)

        await model.refreshRuntimeBridgeStatus()

        #expect(model.afmServiceSnapshot.allServicesAvailable)
        #expect(model.availableAFMPacks.first?.id == "afm://demo-writer")
        #expect(model.availableAFMPacks.first?.maintainer == "core")

        model.selectAFMPack("afm://demo-writer")
        #expect(model.selectedAFMPackID == "afm://demo-writer")

        let trainingJob = await model.createDemoAFMExpertTrainingJob()
        #expect(model.afmTrainingJobs.first?.id == trainingJob.id)
        #expect(model.afmPeerExperts.contains { $0.id == trainingJob.outputRunnerID })
        #expect(model.runtimeFeatureStates.first { $0.feature == .afmServices }?.status.contains("local expert training") == true)

        let a2aPreview = await model.callAFMPeerExpert(
            AFMA2ACallRequest(
                expertID: trainingJob.outputRunnerID,
                prompt: "Preview a local trained expert.",
                userApproved: false
            )
        )
        #expect(a2aPreview.status == .requiresApproval)
        #expect(model.latestAFMA2ACallResult?.id == a2aPreview.id)
    }

    @MainActor
    @Test func afmServicesClientLoadsV1RegistryExpertsAndBundles() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "v1registry") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: [
                    "experts": [
                        [
                            "id": "exp-001",
                            "name": "demo-afm",
                            "payoutAddr": "0x000000000000000000000000000000000000dead",
                            "nodePub": "node-public-key-000000000000000000000000000000",
                            "capability": [0.12, 0.01, 0.75],
                            "pricePer1k": 2.5,
                            "latencyP50": 320,
                            "tags": ["afm", "legal"],
                            "baseModel": "apple.afm.demo",
                            "coverage": 0.85,
                            "reputation": 0.72,
                            "stake": 250.0,
                            "attestation": "cbor+base64",
                            "ingestUrl": "http://localhost:8686",
                            "profileSig": "hex-hmac"
                        ]
                    ]
                ])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: [
                    "bundles": [
                        [
                            "id": "bundle-001",
                            "runnerId": "afm://demo-writer",
                            "version": "1.0.0",
                            "capability": [0.12, 0.01, 0.75],
                            "hashes": [
                                "manifest": "sha256:manifest",
                                "bundle": "sha256:bundle"
                            ],
                            "attestation": ["secure-enclave"],
                            "bundleUrl": "https://example.com/demo-writer.tar",
                            "runner_root": "0xrunnerroot",
                            "bundleSig": "0xsig"
                        ]
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = AFMServicesClient(
            configuration: serviceHarness.configuration,
            session: serviceHarness.session
        )

        let snapshot = await client.snapshot()
        let bundlePack = snapshot.availablePacks.first { $0.id == "afm://demo-writer" }

        #expect(snapshot.registryExperts.first?.id == "exp-001")
        #expect(snapshot.registryExperts.first?.pricePer1K == 2.5)
        #expect(snapshot.peerExperts.first?.id == "exp-001")
        #expect(snapshot.peerExperts.first?.transport == .registryIngest)
        #expect(snapshot.peerExperts.first?.availabilitySummary.contains("apple.afm.demo") == true)
        #expect(snapshot.registryBundles.first?.runnerID == "afm://demo-writer")
        #expect(snapshot.registryBundles.first?.hashes.bundle == "sha256:bundle")
        #expect(bundlePack?.checksum == "sha256:bundle")
        #expect(bundlePack?.bundleURL == "https://example.com/demo-writer.tar")
    }

    @Test func afmExpertTrainingJobBuildsLocalPeerExpertContract() {
        let request = AFMExpertTrainingRequest(
            displayName: "Local Medical Policy Expert",
            objective: "Answer questions from approved policy examples.",
            datasetSummary: "Redacted Q&A examples and policy snippets.",
            sampleCount: 18,
            policy: AFMExpertTrainingPolicy(
                baseModelID: "apple.foundation-model.local",
                method: .profileAdapter,
                privacyMode: .redactedA2A,
                allowA2A: true,
                publishToAFMarket: true,
                domainTags: ["medical", "policy", "medical"]
            )
        )

        let job = AFMExpertTrainingJob(request: request)
        let peer = job.peerExpert

        #expect(job.status == .readyForLocalUse)
        #expect(job.publishReadiness == .needsAttestation)
        #expect(job.localAdapterID.hasPrefix("afm-local-"))
        #expect(job.outputRunnerID.hasSuffix("@draft"))
        #expect(job.request.policy.domainTags == ["medical", "policy"])
        #expect(peer.transport == .localEmbedded)
        #expect(peer.baseModelID == "apple.foundation-model.local")
        #expect(peer.publishReadiness == .needsAttestation)
        #expect(peer.availabilitySummary.contains("Local embedded"))
        #expect(job.adapterStatus.contains("Production Apple Foundation Model fine-tune"))
    }

    @MainActor
    @Test func runtimeBridgeCreatesEmbeddedAFMTrainingJobAndA2APreview() async {
        var afmConfig = AFMServiceEndpointConfiguration.local
        afmConfig.marketplaceBaseURL = nil
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: afmConfig)
        )
        let job = await bridge.createAFMExpertTrainingJob(.demo)

        #expect(bridge.afmTrainingJobs.count == 1)
        #expect(bridge.afmTrainingJobs.first?.outputRunnerID == job.outputRunnerID)
        #expect(bridge.featureStates.first { $0.feature == .afmServices }?.status.contains("local expert training") == true)

        let approvalRequired = await bridge.callAFMPeerExpert(
            AFMA2ACallRequest(
                expertID: job.outputRunnerID,
                prompt: "Ask the local expert.",
                contextCommitment: "fnv1a64:test",
                userApproved: false
            )
        )
        #expect(approvalRequired.status == .requiresApproval)
        #expect(approvalRequired.summary.contains("requires explicit user approval"))

        let preview = await bridge.callAFMPeerExpert(
            AFMA2ACallRequest(
                expertID: job.outputRunnerID,
                prompt: "Ask the local expert.",
                contextCommitment: "fnv1a64:test",
                userApproved: true
            )
        )
        #expect(preview.status == .localPreview)
        #expect(preview.expert?.transport == .localEmbedded)
        #expect(preview.summary.contains("local adapter artifact"))
        #expect(bridge.latestAFMA2ACallResult?.id == preview.id)
    }

    @MainActor
    @Test func afmServicesClientLoadsMarketplaceRunnerPacks() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "marketpacks", includesMarketplace: true) { request in
            let path = request.url?.path ?? ""

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: ["experts": []])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: ["bundles": []])
            }

            if path == "/api/packs" {
                return Self.jsonResponse(for: request, body: [
                    [
                        "runner_id": "eu-law@v1",
                        "afm": [
                            "model_id": "apple.afm.medium:2025.10"
                        ],
                        "prompting": [
                            "system": "You are a concise EU law specialist.",
                            "template": "{{input}}",
                            "params": [
                                "temperature": 0.2,
                                "top_p": 0.9,
                                "max_tokens": 750
                            ]
                        ],
                        "policy": [
                            "allowed_domains": ["law:eu"],
                            "max_context": 160000
                        ],
                        "royalties": [
                            "creator_bps": 700,
                            "data_bps": 200
                        ],
                        "attestation": ["secure-enclave"],
                        "capability_vector": [0.12, 0.01, 0.75],
                        "hashes": [
                            "manifest": "sha256:manifest",
                            "bundle": "sha256:bundle"
                        ],
                        "bundle_url": "https://market.example/eu-law.tar",
                        "signature": "0xsig",
                        "runner_root": "0xdf6a4e",
                        "owner_id": "creator-1",
                        "created_at": 1762127512523
                    ]
                ])
            }

            if path == "/api/experts" {
                return Self.jsonResponse(for: request, body: [
                    "experts": [
                        Self.localAFMExpertBody(runnerID: "eu-law@v1")
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = AFMServicesClient(
            configuration: serviceHarness.configuration,
            session: serviceHarness.session
        )

        let snapshot = await client.snapshot()
        let pack = snapshot.availablePacks.first { $0.id == "eu-law@v1" }

        #expect(snapshot.marketplaceAvailable == true)
        #expect(snapshot.marketplacePacks.first?.runnerID == "eu-law@v1")
        #expect(snapshot.marketplaceExperts.first?.id == "eu-law@v1")
        #expect(snapshot.peerExperts.first?.id == "eu-law@v1")
        #expect(snapshot.marketplacePacks.first?.prompting.params.temperature == 0.2)
        #expect(snapshot.marketplacePacks.first?.hashes?.preferredChecksum == "sha256:bundle")
        #expect(pack?.modelID == "apple.afm.medium:2025.10")
        #expect(pack?.bundleURL == "https://market.example/eu-law.tar")
        #expect(pack?.runnerRoot == "0xdf6a4e")
        #expect(pack?.allowedDomains == ["law:eu"])
        #expect(pack?.maxContext == 160000)
        #expect(pack?.creatorRoyaltyBPS == 700)
        #expect(pack?.dataRoyaltyBPS == 200)
        #expect(pack?.signature == "0xsig")
        #expect(pack?.ownerID == "creator-1")
        #expect(pack?.createdAtMillis == 1762127512523)
    }

    @MainActor
    @Test func afmServicesClientCreatesAndPublishesMarketplaceTrainingJob() async throws {
        let serviceHarness = Self.makeAFMServiceSession(key: "markettrain", includesMarketplace: true) { request in
            let path = request.url?.path ?? ""

            if path == "/api/training-jobs", request.httpMethod == "POST" {
                return Self.jsonResponse(for: request, status: 201, body: [
                    "job": Self.localAFMMarketplaceJobBody()
                ])
            }

            if path == "/api/training-jobs/train-demo/publish", request.httpMethod == "POST" {
                return Self.jsonResponse(for: request, body: [
                    "job": Self.localAFMMarketplaceJobBody(
                        publishStatus: "published",
                        status: "publishReady",
                        publishReadiness: "readyForAFMarket"
                    ),
                    "pack": Self.localAFMRunnerPackBody(),
                    "expert": Self.localAFMExpertBody()
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = AFMServicesClient(
            configuration: serviceHarness.configuration,
            session: serviceHarness.session
        )

        let created = try await client.createMarketplaceTrainingJob(.demo)
        #expect(created.id == "train-demo")
        #expect(created.publishStatus == "draft")
        #expect(created.runnerPack?.runnerID == "afm-local-demo@v1")
        #expect(created.peerExpert?.id == "afm-local-demo@v1")

        let published = try await client.publishMarketplaceTrainingJob(id: created.id)
        #expect(published.job.status == .publishReady)
        #expect(published.job.publishReadiness == .readyForAFMarket)
        #expect(published.job.publishStatus == "published")
        #expect(published.pack?.packSummary.id == "afm-local-demo@v1")
        #expect(published.expert?.baseModel == "apple.foundation-model.local")
    }

    @MainActor
    @Test func runtimeBridgePublishesLocalAFMTrainingJobIntoMarketplacePacks() async {
        var published = false
        let serviceHarness = Self.makeAFMServiceSession(key: "runtimeafmtrain", includesMarketplace: true) { request in
            let path = request.url?.path ?? ""

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: ["experts": []])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: ["bundles": []])
            }

            if path == "/api/training-jobs", request.httpMethod == "POST" {
                return Self.jsonResponse(for: request, status: 201, body: [
                    "job": Self.localAFMMarketplaceJobBody()
                ])
            }

            if path == "/api/training-jobs/train-demo/publish", request.httpMethod == "POST" {
                published = true
                return Self.jsonResponse(for: request, body: [
                    "job": Self.localAFMMarketplaceJobBody(
                        publishStatus: "published",
                        status: "publishReady",
                        publishReadiness: "readyForAFMarket"
                    ),
                    "pack": Self.localAFMRunnerPackBody(),
                    "expert": Self.localAFMExpertBody()
                ])
            }

            if path == "/api/packs" {
                return Self.jsonResponse(for: request, body: [
                    "packs": published ? [Self.localAFMRunnerPackBody()] : []
                ])
            }

            if path == "/api/experts" {
                return Self.jsonResponse(for: request, body: [
                    "experts": published ? [Self.localAFMExpertBody()] : []
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )

        let draft = await bridge.createAFMExpertTrainingJob(.demo)
        #expect(draft.marketplaceJobID == "train-demo")
        #expect(draft.marketplacePublishStatus == "draft")
        #expect(draft.manifestHash == "sha256:manifest-local")

        let publishedJob = await bridge.publishAFMExpertTrainingJob(draft.id)
        #expect(publishedJob?.isPublishedToMarketplace == true)
        #expect(bridge.afmServiceSnapshot.marketplacePacks.first?.runnerID == "afm-local-demo@v1")
        #expect(bridge.afmServiceSnapshot.marketplaceExperts.first?.id == "afm-local-demo@v1")
        #expect(bridge.afmServiceSnapshot.peerExperts.first?.transport == .registryIngest)
        #expect(bridge.featureStates.first { $0.feature == .afmServices }?.status.contains("1 published") == true)
    }

    @MainActor
    @Test func afmServicesClientRoutesThroughV1ContractAndFallsBackToLocal() async {
        let capturedV1Requests = JSONRequestCapture()
        let v1Harness = Self.makeAFMServiceSession(key: "v1route") { request in
            let path = request.url?.path ?? ""
            capturedV1Requests.capture(request)

            if path == "/v1/route" {
                return Self.jsonResponse(for: request, body: [
                    "primary": [
                        "node_id": "exp-001",
                        "lease_id": "lease-001",
                        "verifier": "attestation-ref",
                        "payout_address": "0x000000000000000000000000000000000000dead",
                        "dispatch": [
                            "status": "ok",
                            "http_status": 202
                        ]
                    ],
                    "backups": [
                        [
                            "node_id": "exp-002",
                            "lease_id": "lease-002"
                        ]
                    ],
                    "lease_ttl_ms": 15000,
                    "explain": [
                        [
                            "expert_id": "exp-001",
                            "score": 0.81,
                            "vrf_ratio": 0.12,
                            "rendezvous": 0.34
                        ]
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let v1Client = AFMServicesClient(
            configuration: v1Harness.configuration,
            session: v1Harness.session
        )

        var v1Route: AFMRouteResult?
        do {
            v1Route = try await v1Client.route(
                skill: "summarize",
                prompt: "Summarize v1 route",
                pageURLString: "https://example.com",
                pageSnapshotCommitment: "snapshot-commitment",
                memoryContextIDs: ["mem-1"]
            )
        } catch {
            Issue.record("Expected v1 route, got \(error)")
            v1Route = nil
        }
        let v1Body = capturedV1Requests.body(for: "/v1/route")
        let hpkeInfo = v1Body?["hpke_info"] as? [String: Any]
        let sla = v1Body?["sla"] as? [String: Any]

        #expect(v1Route?.contract == "afmarket-v1")
        #expect(v1Route?.primary?.leaseID == "lease-001")
        #expect(v1Route?.backups.first?.nodeID == "exp-002")
        #expect(v1Route?.request?.chainRef == "base-sepolia")
        #expect(v1Body?["task_id"] as? String != nil)
        #expect(v1Body?["input_commitment"] as? String == "snapshot-commitment")
        #expect(v1Body?["chain_ref"] as? String == "base-sepolia")
        #expect((v1Body?["task_tags"] as? [String])?.contains("summarize") == true)
        #expect(sla?["max_latency_ms"] as? Int == 12_000)
        #expect(hpkeInfo?["version"] as? String == "X25519-HKDF-SHA256/CHACHA20POLY1305-v1")

        let capturedFallbackRequests = JSONRequestCapture()
        let fallbackHarness = Self.makeAFMServiceSession(key: "v1fallback") { request in
            let path = request.url?.path ?? ""
            capturedFallbackRequests.capture(request)

            if path == "/v1/route" {
                return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
            }

            if path == "/route" {
                return Self.jsonResponse(for: request, body: [
                    "selection": [
                        "id": "afm://demo-writer",
                        "name": "Demo Writer",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let fallbackClient = AFMServicesClient(
            configuration: fallbackHarness.configuration,
            session: fallbackHarness.session
        )

        var fallbackRoute: AFMRouteResult?
        do {
            fallbackRoute = try await fallbackClient.route(
                skill: "summarize",
                prompt: "Summarize local route",
                pageURLString: "https://example.com",
                preferredPackID: "afm://demo-writer",
                pageSnapshotCommitment: "snapshot-commitment"
            )
        } catch {
            Issue.record("Expected fallback route, got \(error)")
            fallbackRoute = nil
        }
        let fallbackBody = capturedFallbackRequests.body(for: "/route")

        #expect(capturedFallbackRequests.body(for: "/v1/route") != nil)
        #expect(fallbackRoute?.contract == "local")
        #expect(fallbackRoute?.selection?.id == "afm://demo-writer")
        #expect(fallbackRoute?.request?.inputCommitment == "snapshot-commitment")
        #expect(fallbackBody?["preferredPackID"] as? String == "afm://demo-writer")
    }

    @Test func afmNodeVerificationReportRecognizesChainAnchoredEvidence() {
        let taskID = "task-prod"
        let outputCommitment = "0x\(String(repeating: "11", count: 32))"
        let nonce = AFMNodeVerificationReport.bindingNonceHex(
            taskID: taskID,
            outputCommitment: outputCommitment
        )
        let nodeTask = AFMNodeTaskResult(
            ok: true,
            id: taskID,
            taskID: taskID,
            packID: "eu-law@v1",
            installID: "install-prod",
            status: "completed",
            mode: "production",
            result: AFMNodeTaskOutput(
                summary: "production completed",
                outputCommitment: outputCommitment,
                completedAt: "2026-05-16T00:00:01Z"
            ),
            attestation: AFMAttestedRun(
                mode: "secure-enclave",
                taskID: taskID,
                outputCommitment: outputCommitment,
                nonce: nonce ?? "",
                tokenCount: 42,
                contextPassages: 2,
                attestationToken: "cbor-base64"
            ),
            proof: AFMProofState(
                proofID: "proof-prod",
                status: "verified",
                verifier: "0xverifier",
                publicInputs: [
                    "taskID": taskID,
                    "outputCommitment": outputCommitment,
                    "deadline": "1730203600"
                ],
                proofBytes: "0xproof",
                publicInputsABI: "0xinputs",
                deadline: 1730203600,
                payoutAddress: "0x000000000000000000000000000000000000dead",
                modelIDHash: "0xmodel"
            ),
            settlement: AFMSettlementState(
                id: "settlement-prod",
                status: "settled",
                chainRef: "base-sepolia",
                escrowID: "escrow-prod",
                escrowContract: "0xescrow",
                transactionHash: "0xtx",
                blockNumber: 123,
                deadline: 1730203600,
                verifier: "0xverifier",
                mode: "production",
                settledAt: "2026-05-16T00:00:02Z"
            )
        )

        let report = nodeTask.verificationReport

        #expect(nonce != nil)
        #expect(report.state == .chainAnchored)
        #expect(report.checks.allSatisfy { $0.status == .passed })
        #expect(report.summary.contains("chain-anchored"))
        #expect(report.transactionHash == "0xtx")
    }

    @MainActor
    @Test func chainTrustRegistrySeedsSupportedFamiliesAndLabelsFallback() {
        let registry = ChainTrustRegistry.defaultRegistry
        let families = Set(registry.statuses.map(\.family))
        let base = registry.status(forChainRef: "base-sepolia")

        #expect(families.isSuperset(of: Set(ChainTrustFamily.allCases.filter { $0 != .unknown })))
        #expect(registry.statuses.count >= 12)
        #expect(base?.family == .evmLayer2)
        #expect(base?.state == .rpcFallback)
        #expect(base?.displaySummary.contains("Gateway/RPC fallback") == true)
        #expect(registry.runtimeStatusText.contains("gateway/RPC fallback only"))
        #expect(registry.fallbackWarning.contains("not local light-client verification"))
    }

    @MainActor
    @Test func chainTrustRegistryRecordsAFMarketSettlementEvidence() {
        var registry = ChainTrustRegistry.defaultRegistry
        let taskID = "task-chain-registry"
        let outputCommitment = "0x\(String(repeating: "22", count: 32))"
        let nodeTask = Self.chainAnchoredNodeTask(taskID: taskID, outputCommitment: outputCommitment)

        let update = registry.recordAFMarketVerification(nodeTask.verificationReport)
        let base = registry.status(forChainRef: "base-sepolia")

        #expect(update?.state == .proofChecked)
        #expect(update?.trustSource == .afMarketSettlement)
        #expect(update?.latestCheckpoint?.height == 456)
        #expect(base?.state == .proofChecked)
        #expect(base?.evidence.first?.taskID == taskID)
        #expect(base?.evidence.first?.transactionHash == "0xtx-chain")
        #expect(base?.displaySummary.contains("proof-checked evidence") == true)
    }

    @MainActor
    @Test func runtimeBridgeSurfacesChainTrustFeatureState() {
        var registry = ChainTrustRegistry.defaultRegistry
        let nodeTask = Self.chainAnchoredNodeTask(
            taskID: "task-chain-feature",
            outputCommitment: "0x\(String(repeating: "33", count: 32))"
        )
        _ = registry.recordAFMarketVerification(nodeTask.verificationReport)
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(chainTrustRegistry: registry)
        )
        let chainTrust = bridge.featureStates.first { $0.feature == .chainTrust }

        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.isAvailable == true)
        #expect(chainTrust?.status.contains("Base Sepolia proof checked") == true)
    }

    @MainActor
    @Test func runtimeBridgeRecordsAFMarketSettlementInChainTrustRegistry() async {
        let taskID = "task-chain-runtime"
        let outputCommitment = "0x\(String(repeating: "44", count: 32))"
        let nonce = AFMNodeVerificationReport.bindingNonceHex(
            taskID: taskID,
            outputCommitment: outputCommitment
        ) ?? ""
        let serviceHarness = Self.makeAFMServiceSession(key: "chaintrust") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "name": "Demo Writer",
                            "skills": ["summarize"],
                            "status": "healthy",
                            "checksum": "0xabc"
                        ]
                    ]
                ])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: ["experts": []])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: ["bundles": []])
            }

            if path == "/route" {
                return Self.jsonResponse(for: request, body: [
                    "selection": [
                        "id": "afm://demo-writer",
                        "name": "Demo Writer",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-chain",
                    "status": "queued"
                ])
            }

            if path == "/packs/install" {
                return Self.jsonResponse(for: request, status: 201, body: [
                    "id": "install-chain",
                    "packID": "afm://demo-writer",
                    "checksum": "0xabc",
                    "status": "installed",
                    "mode": "production"
                ])
            }

            if path == "/tasks" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "id": taskID,
                    "taskID": taskID,
                    "packID": "afm://demo-writer",
                    "installID": "install-chain",
                    "status": "completed",
                    "mode": "production",
                    "result": [
                        "summary": "production completed",
                        "outputCommitment": outputCommitment
                    ],
                    "attestation": [
                        "mode": "secure-enclave",
                        "taskID": taskID,
                        "outputCommitment": outputCommitment,
                        "nonce": nonce,
                        "tokenCount": 20,
                        "contextPassages": 1
                    ],
                    "proof": [
                        "proofID": "proof-chain",
                        "status": "verified",
                        "verifier": "0xverifier",
                        "publicInputs": [
                            "taskID": taskID,
                            "outputCommitment": outputCommitment
                        ],
                        "proofBytes": "0xproof",
                        "publicInputsABI": "0xinputs"
                    ],
                    "settlement": [
                        "id": "settlement-chain",
                        "status": "settled",
                        "chainRef": "base-sepolia",
                        "escrowID": "escrow-chain",
                        "escrowContract": "0xescrow",
                        "transactionHash": "0xtx-chain",
                        "blockNumber": 456,
                        "verifier": "0xverifier",
                        "mode": "production"
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Summarize with chain evidence",
                pageURLString: "https://example.com",
                preferredAFMPackID: "afm://demo-writer"
            )
        )
        let base = bridge.chainTrustSnapshot.status(forChainRef: "base-sepolia")
        let feature = bridge.featureStates.first { $0.feature == .chainTrust }

        #expect(result.mode == .service)
        #expect(result.afmNodeTask?.verificationReport.state == .chainAnchored)
        #expect(result.chainTrustUpdate?.state == .proofChecked)
        #expect(base?.state == .proofChecked)
        #expect(base?.latestCheckpoint?.height == 456)
        #expect(feature?.mode == .service)
        #expect(feature?.status.contains("Base Sepolia proof checked") == true)
        #expect(result.suggestions.contains { $0.contains("Chain trust Proof checked") })
    }

    @Test func bitcoinLightClientVerifiesGenesisHeaderAndMerkleFixture() {
        let genesis = BitcoinBlockHeader.mainnetGenesis
        let merkleProof = BitcoinMerkleProof(
            transactionID: genesis.merkleRoot,
            blockHash: genesis.validatedHash,
            merkleRoot: genesis.merkleRoot,
            transactionIndex: 0,
            siblings: []
        )
        let inclusion = BitcoinTransactionInclusionProof(header: genesis, proof: merkleProof)
        let result = inclusion.verify()

        #expect(genesis.computedHash == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")
        #expect(genesis.validatesAdvertisedHash)
        #expect(merkleProof.verifiesMerkleRoot)
        #expect(result.verified)
        #expect(result.state == .synced)
        #expect(result.height == 0)
    }

    @Test func bitcoinProofOfWorkDecodesTargetAndChecksRealWork() {
        // Known 256-bit target for the genesis nBits 0x1d00ffff.
        var expectedTarget = [UInt8](repeating: 0, count: 32)
        expectedTarget[4] = 0xff
        expectedTarget[5] = 0xff
        #expect(BitcoinProofOfWork.target(fromCompactBits: 0x1d00ffff) == expectedTarget)

        // The real genesis block hash meets its real difficulty.
        let genesis = BitcoinBlockHeader.mainnetGenesis
        #expect(genesis.meetsProofOfWork)

        // The same hash does NOT satisfy a harder target, and an all-FF hash never satisfies the
        // easiest standard target — i.e. insufficient work is detected.
        #expect(BitcoinProofOfWork.meets(hashHex: genesis.validatedHash, bits: 0x1b00ffff) == false)
        #expect(BitcoinProofOfWork.meets(hashHex: String(repeating: "f", count: 64), bits: 0x1d00ffff) == false)
    }

    @Test func bitcoinInclusionProofRejectsHeaderThatDoesNotMeetProofOfWork() {
        let genesis = BitcoinBlockHeader.mainnetGenesis

        // A header that is self-consistent (hash == computedHash) but claims a difficulty far
        // beyond the work actually performed. SPV must reject it instead of trusting the inclusion.
        let underworked = BitcoinBlockHeader(
            height: genesis.height,
            version: genesis.version,
            previousBlockHash: genesis.previousBlockHash,
            merkleRoot: genesis.merkleRoot,
            timestamp: genesis.timestamp,
            bits: 0x1b00ffff,
            nonce: genesis.nonce,
            hash: nil
        )
        #expect(underworked.meetsProofOfWork == false)

        let proof = BitcoinMerkleProof(
            transactionID: genesis.merkleRoot,
            blockHash: underworked.validatedHash,
            merkleRoot: genesis.merkleRoot,
            transactionIndex: 0,
            siblings: []
        )
        let result = BitcoinTransactionInclusionProof(header: underworked, proof: proof).verify()
        #expect(result.verified == false)
        #expect(result.state == .failed)
        #expect(result.summary.contains("proof-of-work"))
    }

    @Test func bitcoinHeaderChainValidationRequiresWorkAndLinkage() {
        let genesis = BitcoinBlockHeader.mainnetGenesis

        // A single real, PoW-valid header is a valid chain.
        #expect(BitcoinProofOfWork.validatesHeaderChain([genesis]))

        // A synthetic follow-on header does not meet proof-of-work, so the chain is invalid.
        let synthetic = BitcoinBlockHeader(
            height: 1,
            version: 1,
            previousBlockHash: genesis.validatedHash,
            merkleRoot: String(repeating: "1", count: 64),
            timestamp: 1_231_006_600,
            bits: 0x1d00ffff,
            nonce: 1
        )
        #expect(BitcoinProofOfWork.validatesHeaderChain([genesis, synthetic]) == false)
        #expect(BitcoinProofOfWork.validatesHeaderChain([]) == false)
    }

    @Test func bitcoinHeaderTrackerOrdersByChainWorkAndLabelsReorgs() {
        let genesis = BitcoinBlockHeader.mainnetGenesis
        let firstHeader = BitcoinBlockHeader(
            height: 1,
            version: 1,
            previousBlockHash: genesis.validatedHash,
            merkleRoot: String(repeating: "1", count: 64),
            timestamp: 1_231_006_600,
            bits: 0x1d00ffff,
            nonce: 1,
            chainWork: "02"
        )
        let weakerSibling = BitcoinBlockHeader(
            height: 1,
            version: 1,
            previousBlockHash: genesis.validatedHash,
            merkleRoot: String(repeating: "2", count: 64),
            timestamp: 1_231_006_700,
            bits: 0x1d00ffff,
            nonce: 2,
            chainWork: "01"
        )
        let strongerSibling = BitcoinBlockHeader(
            height: 1,
            version: 1,
            previousBlockHash: genesis.validatedHash,
            merkleRoot: String(repeating: "3", count: 64),
            timestamp: 1_231_006_800,
            bits: 0x1d00ffff,
            nonce: 3,
            chainWork: "03"
        )
        var tracker = BitcoinHeaderChainTracker(anchor: genesis)

        let accepted = tracker.apply(firstHeader)
        let stale = tracker.apply(weakerSibling)
        let reorg = tracker.apply(strongerSibling)

        #expect(accepted.transition == .accepted)
        #expect(accepted.state == .synced)
        #expect(stale.transition == .stale)
        #expect(stale.state == .stale)
        #expect(reorg.transition == .reorg)
        #expect(reorg.state == .reorg)
        #expect(reorg.reorgDepth == 1)
        #expect(tracker.activeTip?.validatedHash == strongerSibling.validatedHash)
    }

    @MainActor
    @Test func bitcoinLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let serviceHarness = Self.makeBitcoinLightClientSession(key: "bitcoinregistry") { request in
            if request.url?.path == "/v1/bitcoin/status" {
                return Self.jsonResponse(for: request, body: Self.bitcoinGenesisServiceStatus())
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = BitcoinLightClientServiceClient(
            configuration: serviceHarness.configuration,
            session: serviceHarness.session
        )
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordBitcoinLightClientSnapshot(snapshot)
        let bitcoin = registry.status(forChainRef: "bitcoin-mainnet")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .synced)
        #expect(status.state == .verified)
        #expect(status.trustSource == .embeddedLightClient)
        #expect(status.latestCheckpoint?.height == 0)
        #expect(bitcoin?.state == .verified)
        #expect(bitcoin?.evidence.first?.source == .embeddedLightClient)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesBitcoinLightClientState() async {
        let bitcoinHarness = Self.makeBitcoinLightClientSession(key: "bitcoinruntime") { request in
            if request.url?.path == "/v1/bitcoin/status" {
                return Self.jsonResponse(for: request, body: Self.bitcoinGenesisServiceStatus())
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "bitcoinruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                bitcoinLightClient: bitcoinHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(
                configuration: bitcoinHarness.configuration,
                session: bitcoinHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let bitcoin = bridge.chainTrustSnapshot.status(forChainRef: "bitcoin-mainnet")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(bitcoin?.state == .verified)
        #expect(bitcoin?.latestCheckpoint?.blockHash == BitcoinBlockHeader.mainnetGenesis.validatedHash)
        #expect(chainTrust?.mode == .local)
        #expect(chainTrust?.status.contains("Bitcoin light-client verified") == true)
    }

    @Test func evmChainRoutingDistinguishesMainnetAndLayer2Finality() {
        #expect(EVMChain.known(from: "1") == .ethereumMainnet)
        #expect(EVMChain.known(from: "84532") == .baseSepolia)
        #expect(EVMChain.ethereumMainnet.family == .ethereum)
        #expect(EVMChain.baseSepolia.family == .evmLayer2)
        #expect(EVMChain.baseSepolia.finalityModel == .rollupSettlement)
        #expect(EVMChain.baseSepolia.l2SettlementSummary?.contains("sequencer") == true)
    }

    @Test func evmLocalProofVerifiesAccountStorageAndReceiptFixtures() {
        let accountLeaf = EVMLocalProof.fixtureLeafHash(
            kind: .account,
            subject: "0x1111111111111111111111111111111111111111",
            value: "0x01"
        )
        let accountSibling = EVMProofWitness(hash: EVMHex.sha256Hex("account-sibling"), position: .right)
        let accountRoot = EVMLocalProof.computeRoot(leafHash: accountLeaf, witnesses: [accountSibling])!
        let receiptLeaf = EVMLocalProof.fixtureLeafHash(kind: .receipt, subject: "0xtx", value: "0x01")
        let receiptRoot = EVMLocalProof.computeRoot(leafHash: receiptLeaf, witnesses: [])!
        let header = EVMExecutionHeaderSnapshot(
            chain: .ethereumMainnet,
            number: 17_000_000,
            hash: EVMHex.sha256Hex("ethereum-mainnet-17000000-header"),
            parentHash: EVMHex.sha256Hex("ethereum-mainnet-16999999-header"),
            stateRoot: accountRoot,
            receiptsRoot: receiptRoot,
            timestamp: 1_680_000_000,
            finalized: true,
            source: "fixture"
        )
        let accountProof = EVMLocalProof(
            proofID: "account-proof",
            kind: .account,
            chain: .ethereumMainnet,
            subject: "0x1111111111111111111111111111111111111111",
            expectedValue: "0x01",
            blockHash: header.hash,
            blockNumber: header.number,
            expectedRoot: accountRoot,
            leafHash: accountLeaf,
            witnesses: [accountSibling],
            source: "fixture"
        )
        let receiptProof = EVMLocalProof(
            proofID: "receipt-proof",
            kind: .receipt,
            chain: .ethereumMainnet,
            subject: "0xtx",
            expectedValue: "0x01",
            blockHash: header.hash,
            blockNumber: header.number,
            expectedRoot: receiptRoot,
            leafHash: receiptLeaf,
            witnesses: [],
            source: "fixture"
        )
        let storageLeaf = EVMLocalProof.fixtureLeafHash(
            kind: .storage,
            subject: "0x2222222222222222222222222222222222222222",
            key: "0x00",
            value: "0x2a"
        )
        let storageRoot = EVMLocalProof.computeRoot(leafHash: storageLeaf, witnesses: [])!
        let storageHeader = EVMExecutionHeaderSnapshot(
            chain: .baseSepolia,
            number: 12_345,
            hash: EVMHex.sha256Hex("base-sepolia-12345-header"),
            stateRoot: storageRoot,
            receiptsRoot: receiptRoot,
            finalized: false,
            source: "fixture"
        )
        let storageProof = EVMLocalProof(
            proofID: "storage-proof",
            kind: .storage,
            chain: .baseSepolia,
            subject: "0x2222222222222222222222222222222222222222",
            storageKey: "0x00",
            expectedValue: "0x2a",
            blockHash: storageHeader.hash,
            blockNumber: storageHeader.number,
            expectedRoot: storageRoot,
            leafHash: storageLeaf,
            witnesses: [],
            source: "fixture"
        )

        let accountResult = EVMLocalProofBundle(header: header, proof: accountProof).verify()
        let receiptResult = EVMLocalProofBundle(header: header, proof: receiptProof).verify()
        let storageResult = EVMLocalProofBundle(header: storageHeader, proof: storageProof).verify()

        #expect(accountResult.verified)
        #expect(accountResult.state == .synced)
        #expect(receiptResult.verified)
        #expect(receiptResult.kind == .receipt)
        #expect(storageResult.verified)
        #expect(storageResult.state == .proofChecked)
    }

    @MainActor
    @Test func evmLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let capturedRequests = JSONRequestCapture()
        let evmHarness = Self.makeEVMLightClientSession(key: "evmregistry", chain: .ethereumMainnet) { request in
            capturedRequests.capture(request)
            if request.url?.path == "/v1/evm/status" {
                return Self.jsonResponse(for: request, body: Self.evmServiceStatus(chain: .ethereumMainnet))
            }
            if request.url?.path == "/v1/evm/verify-proof" {
                return Self.jsonResponse(for: request, body: Self.evmProofResultBody(
                    verified: true,
                    state: "synced",
                    proofID: "account-proof",
                    kind: "account",
                    chain: .ethereumMainnet
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = EVMLightClientServiceClient(
            configuration: evmHarness.configuration,
            session: evmHarness.session
        )
        let snapshot = await client.snapshot()
        let proofResult = try! await client.verifyProofViaService(Self.evmProofBundle(chain: .ethereumMainnet))
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordEVMLightClientSnapshot(snapshot)
        let ethereum = registry.status(forChainRef: "ethereum-mainnet")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .synced)
        #expect(snapshot.finalizedCheckpoint?.number == 17_000_000)
        #expect(status.state == .verified)
        #expect(status.trustSource == .embeddedLightClient)
        #expect(ethereum?.evidence.first?.source == .embeddedLightClient)
        #expect(proofResult.verified)
        #expect(proofResult.state == .synced)
        #expect(capturedRequests.body(for: "/v1/evm/verify-proof")?["proof"] != nil)
    }

    @MainActor
    @Test func evmLightClientFallsBackWhenServiceDisabled() async {
        let client = EVMLightClientServiceClient(configuration: .disabled)
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordEVMLightClientSnapshot(snapshot)

        #expect(snapshot.serviceAvailable == false)
        #expect(snapshot.syncState == .unavailable)
        #expect(status.state == .rpcFallback)
        #expect(status.trustSource == .gatewayRPCFallback)
        #expect(status.displaySummary.contains("Gateway/RPC fallback") == true)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesEVMLightClientState() async {
        let evmHarness = Self.makeEVMLightClientSession(key: "evmruntime", chain: .baseSepolia) { request in
            if request.url?.path == "/v1/evm/status" {
                return Self.jsonResponse(for: request, body: Self.evmServiceStatus(chain: .baseSepolia, syncState: "proof_checked"))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "evmruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                evmLightClient: evmHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(configuration: .disabled),
            evmLightClientServiceClient: EVMLightClientServiceClient(
                configuration: evmHarness.configuration,
                session: evmHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let base = bridge.chainTrustSnapshot.status(forChainRef: "base-sepolia")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(base?.state == .proofChecked)
        #expect(base?.trustSource == .localProof)
        #expect(base?.displaySummary.contains("proof-checked evidence") == true)
        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.status.contains("Base Sepolia proof checked") == true)
    }

    @Test func solanaClusterRoutingAndStaleFallbackAreExplicit() {
        #expect(SolanaCluster.known(from: "mainnet-beta") == .mainnetBeta)
        #expect(SolanaCluster.known(from: "solana-devnet") == .devnet)
        #expect(SolanaCluster.mainnetBeta.chainRef == "solana-mainnet")

        let staleSnapshot = SolanaSlotRootSnapshot(
            cluster: .mainnetBeta,
            slot: 10_000,
            rootSlot: 9_000,
            blockhash: SolanaHex.sha256Hex("slot-10000"),
            commitment: .finalized,
            accountRoot: SolanaHex.sha256Hex("account-root"),
            transactionStatusRoot: SolanaHex.sha256Hex("tx-root"),
            source: "fixture"
        )
        let rpcSnapshot = SolanaLightClientServiceSnapshot.fallback(
            cluster: .mainnetBeta,
            lastError: "disabled"
        )

        #expect(staleSnapshot.rootLag() == 1_000)
        #expect(staleSnapshot.isStale(maxRootLag: 512))
        #expect(rpcSnapshot.syncState == .unavailable)
        #expect(rpcSnapshot.chainTrustStatus.state == .rpcFallback)
        #expect(rpcSnapshot.statusSummary.contains("trusted RPC fallback remains labeled"))
    }

    @Test func solanaFixtureProofVerifiesAccountAndTransactionStatus() {
        let accountBundle = Self.solanaProofBundle(kind: .account)
        let transactionBundle = Self.solanaProofBundle(kind: .transactionStatus)
        let accountResult = accountBundle.verify()
        let transactionResult = transactionBundle.verify()

        #expect(accountResult.verified)
        #expect(accountResult.state == .synced)
        #expect(accountResult.chainRef == "solana-mainnet")
        #expect(transactionResult.verified)
        #expect(transactionResult.kind == .transactionStatus)
    }

    @MainActor
    @Test func solanaLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let capturedRequests = JSONRequestCapture()
        let solanaHarness = Self.makeSolanaLightClientSession(key: "solanaregistry", cluster: .mainnetBeta) { request in
            capturedRequests.capture(request)
            if request.url?.path == "/v1/solana/status" {
                return Self.jsonResponse(for: request, body: Self.solanaServiceStatus(cluster: .mainnetBeta))
            }
            if request.url?.path == "/v1/solana/verify-proof" {
                return Self.jsonResponse(for: request, body: Self.solanaProofResultBody(
                    verified: true,
                    state: "synced",
                    proofID: "solana-account-proof",
                    kind: "account",
                    cluster: .mainnetBeta
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = SolanaLightClientServiceClient(
            configuration: solanaHarness.configuration,
            session: solanaHarness.session
        )
        let snapshot = await client.snapshot()
        let proofResult = try! await client.verifyProofViaService(Self.solanaProofBundle(kind: .account))
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordSolanaLightClientSnapshot(snapshot)
        let solana = registry.status(forChainRef: "solana-mainnet")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .synced)
        #expect(snapshot.slotRoot?.rootSlot == 281_474_976_700)
        #expect(status.state == .verified)
        #expect(status.trustSource == .embeddedLightClient)
        #expect(solana?.evidence.first?.source == .embeddedLightClient)
        #expect(proofResult.verified)
        #expect(proofResult.state == .synced)
        #expect(capturedRequests.body(for: "/v1/solana/verify-proof")?["proof"] != nil)
    }

    @MainActor
    @Test func solanaLightClientFallsBackWhenServiceDisabled() async {
        let client = SolanaLightClientServiceClient(configuration: .disabled)
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordSolanaLightClientSnapshot(snapshot)

        #expect(snapshot.serviceAvailable == false)
        #expect(snapshot.syncState == .unavailable)
        #expect(status.state == .rpcFallback)
        #expect(status.trustSource == .gatewayRPCFallback)
        #expect(status.displaySummary.contains("Gateway/RPC fallback") == true)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesSolanaLightClientState() async {
        let solanaHarness = Self.makeSolanaLightClientSession(key: "solanaruntime", cluster: .devnet) { request in
            if request.url?.path == "/v1/solana/status" {
                return Self.jsonResponse(for: request, body: Self.solanaServiceStatus(
                    cluster: .devnet,
                    syncState: "proof_checked",
                    commitment: "confirmed"
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "solanaruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                solanaLightClient: solanaHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(configuration: .disabled),
            evmLightClientServiceClient: EVMLightClientServiceClient(configuration: .disabled),
            solanaLightClientServiceClient: SolanaLightClientServiceClient(
                configuration: solanaHarness.configuration,
                session: solanaHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let solana = bridge.chainTrustSnapshot.status(forChainRef: "solana-devnet")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(solana?.state == .proofChecked)
        #expect(solana?.trustSource == .localProof)
        #expect(solana?.displaySummary.contains("proof-checked evidence") == true)
        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.status.contains("Solana Devnet proof checked") == true)
    }

    @Test func cosmosChainRoutingAndFallbackAreExplicit() {
        #expect(CosmosChain.known(from: "cosmoshub-4") == .cosmosHub)
        #expect(CosmosChain.known(from: "cosmos-hub") == .cosmosHub)
        #expect(CosmosChain.known(from: "osmosis") == .osmosis)
        #expect(CosmosChain.cosmosHub.bech32Prefix == "cosmos")

        let fallback = CosmosLightClientServiceSnapshot.fallback(
            chain: .cosmosHub,
            lastError: "disabled"
        )

        #expect(fallback.syncState == .unavailable)
        #expect(fallback.chainTrustStatus.state == .rpcFallback)
        #expect(fallback.statusSummary.contains("trusted RPC fallback remains labeled"))
    }

    @Test func tendermintHeaderCommitVerifiesValidatorPowerThreshold() {
        let bundle = Self.cosmosHeaderBundle(chain: .cosmosHub)
        let result = bundle.verify(nowUnixSeconds: 1_778_889_600)
        var weakBundle = bundle
        weakBundle.commit.signatures = [bundle.commit.signatures[0]]
        let weakResult = weakBundle.verify(nowUnixSeconds: 1_778_889_600)

        #expect(bundle.validatorSet.validatesHash)
        #expect(bundle.validatorSet.totalVotingPower == 100)
        #expect(result.verified)
        #expect(result.state == .synced)
        #expect(result.chainRef == "cosmos-hub")
        #expect(weakResult.verified == false)
        #expect(weakResult.state == .failed)
        #expect(weakResult.summary.contains("two-thirds"))
    }

    @Test func tendermintRejectsUnverifiedAndForgedCommitSignatures() {
        let bundle = Self.cosmosHeaderBundle(chain: .cosmosHub)

        // A validator merely flagged `signed` but carrying no verifiable signature bytes must not
        // count toward the two-thirds threshold (this is the trust gap that is now closed).
        var flagOnly = bundle
        flagOnly.commit.signatures[1] = TendermintCommitSignature(
            validatorAddress: bundle.validatorSet.validators[1].address,
            blockIDHash: bundle.header.hash,
            signed: true,
            signature: nil
        )
        let flagOnlyResult = flagOnly.verify(nowUnixSeconds: 1_778_889_600)
        #expect(flagOnlyResult.verified == false)
        #expect(flagOnlyResult.summary.contains("two-thirds"))

        // A signature produced by the wrong validator key does not verify and is not counted.
        var forged = bundle
        forged.commit.signatures[1] = Self.cosmosCommitSignature(
            Self.cosmosValidatorKey(0xC3),
            address: bundle.validatorSet.validators[1].address,
            chain: .cosmosHub,
            height: bundle.header.height,
            round: 0,
            blockIDHash: bundle.header.hash
        )
        let forgedResult = forged.verify(nowUnixSeconds: 1_778_889_600)
        #expect(forgedResult.verified == false)
    }

    @Test func evmSyncCommitteeVerifiesRealBLSAggregateSignature() {
        let signingRoot = Data(repeating: 0xAB, count: 32)
        // 7 of 9 committee members sign with real BLS keys (supermajority).
        let update = EVMSyncCommitteeTestSupport.signedUpdate(committeeSize: 9, signingRoot: signingRoot, participation: 7)

        let result = EVMSyncCommitteeVerifier.verify(update)
        #expect(result.status == .verified)
        #expect(result.verified)
        #expect(result.participantCount == 7)
        #expect(result.committeeSize == 9)
        #expect(result.chainTrustState == .proofChecked)
    }

    @Test func evmSyncCommitteeRejectsInsufficientParticipation() {
        let signingRoot = Data(repeating: 0xCD, count: 32)
        // 5 of 9 is below the two-thirds supermajority (needs >= 6).
        let update = EVMSyncCommitteeTestSupport.signedUpdate(committeeSize: 9, signingRoot: signingRoot, participation: 5)

        let result = EVMSyncCommitteeVerifier.verify(update)
        #expect(result.status == .insufficientParticipation)
        #expect(result.chainTrustState == .rpcFallback)
    }

    @Test func evmSyncCommitteeRejectsSignatureOverDifferentRoot() {
        let signedRoot = Data(repeating: 0x01, count: 32)
        var update = EVMSyncCommitteeTestSupport.signedUpdate(committeeSize: 9, signingRoot: signedRoot, participation: 8)
        // The committee signed `signedRoot`, but the update now claims a different signing root.
        update.signingRoot = Data(repeating: 0x02, count: 32)

        let result = EVMSyncCommitteeVerifier.verify(update)
        #expect(result.status == .signatureInvalid)
        #expect(result.verified == false)
    }

    @Test func evmSyncCommitteeRejectsMalformedUpdate() {
        let signingRoot = Data(repeating: 0x09, count: 32)
        var update = EVMSyncCommitteeTestSupport.signedUpdate(committeeSize: 4, signingRoot: signingRoot, participation: 4)
        update.participationBits = [true, true] // bitfield length no longer matches the committee

        #expect(EVMSyncCommitteeVerifier.verify(update).status == .malformed)
    }

    @Test func tendermintTrustPeriodExpiryAndConflictingCommitsAreExplicit() {
        let bundle = Self.cosmosHeaderBundle(chain: .cosmosHub)
        let expiredResult = bundle.verify(nowUnixSeconds: bundle.trustPolicy.trustedTimeUnixSeconds + bundle.trustPolicy.trustPeriodSeconds + 1)
        var conflictBundle = bundle
        let conflictingHash = TendermintHex.sha256Hex("conflicting-block")
        // The same validators (a, b) double-sign a conflicting block with real Ed25519 signatures,
        // so the equivocation is detected via cryptographic verification, not a flag.
        conflictBundle.conflictingCommit = TendermintCommit(
            height: bundle.header.height,
            round: 0,
            blockIDHash: conflictingHash,
            signatures: [
                Self.cosmosCommitSignature(Self.cosmosValidatorKey(0xA1), address: bundle.validatorSet.validators[0].address, chain: .cosmosHub, height: bundle.header.height, round: 0, blockIDHash: conflictingHash),
                Self.cosmosCommitSignature(Self.cosmosValidatorKey(0xB2), address: bundle.validatorSet.validators[1].address, chain: .cosmosHub, height: bundle.header.height, round: 0, blockIDHash: conflictingHash)
            ],
            source: "fixture"
        )
        let conflictResult = conflictBundle.verify(nowUnixSeconds: 1_778_889_600)

        #expect(expiredResult.verified == false)
        #expect(expiredResult.state == .stale)
        #expect(expiredResult.summary.contains("expired"))
        #expect(conflictResult.verified == false)
        #expect(conflictResult.state == .failed)
        #expect(conflictResult.summary.contains("Conflicting Tendermint commits"))
    }

    @MainActor
    @Test func cosmosLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let capturedRequests = JSONRequestCapture()
        let cosmosHarness = Self.makeCosmosLightClientSession(key: "cosmosregistry", chain: .cosmosHub) { request in
            capturedRequests.capture(request)
            if request.url?.path == "/v1/cosmos/status" {
                return Self.jsonResponse(for: request, body: Self.cosmosServiceStatus(chain: .cosmosHub))
            }
            if request.url?.path == "/v1/cosmos/verify-header" {
                return Self.jsonResponse(for: request, body: Self.cosmosProofResultBody(
                    verified: true,
                    state: "synced",
                    chain: .cosmosHub
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = CosmosLightClientServiceClient(
            configuration: cosmosHarness.configuration,
            session: cosmosHarness.session
        )
        let snapshot = await client.snapshot()
        let proofResult = try! await client.verifyHeaderViaService(Self.cosmosHeaderBundle(chain: .cosmosHub))
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordCosmosLightClientSnapshot(snapshot)
        let cosmos = registry.status(forChainRef: "cosmos-hub")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .synced)
        #expect(snapshot.latestHeader?.height == 19_700_000)
        #expect(status.state == .verified)
        #expect(status.trustSource == .embeddedLightClient)
        #expect(cosmos?.evidence.first?.source == .embeddedLightClient)
        #expect(proofResult.verified)
        #expect(proofResult.state == .synced)
        #expect(capturedRequests.body(for: "/v1/cosmos/verify-header")?["validator_set"] != nil)
    }

    @MainActor
    @Test func cosmosLightClientFallsBackWhenServiceDisabled() async {
        let client = CosmosLightClientServiceClient(configuration: .disabled)
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordCosmosLightClientSnapshot(snapshot)

        #expect(snapshot.serviceAvailable == false)
        #expect(snapshot.syncState == .unavailable)
        #expect(status.state == .rpcFallback)
        #expect(status.trustSource == .gatewayRPCFallback)
        #expect(status.displaySummary.contains("Gateway/RPC fallback") == true)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesCosmosLightClientState() async {
        let cosmosHarness = Self.makeCosmosLightClientSession(key: "cosmosruntime", chain: .osmosis) { request in
            if request.url?.path == "/v1/cosmos/status" {
                return Self.jsonResponse(for: request, body: Self.cosmosServiceStatus(
                    chain: .osmosis,
                    syncState: "proof_checked"
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "cosmosruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                cosmosLightClient: cosmosHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(configuration: .disabled),
            evmLightClientServiceClient: EVMLightClientServiceClient(configuration: .disabled),
            solanaLightClientServiceClient: SolanaLightClientServiceClient(configuration: .disabled),
            cosmosLightClientServiceClient: CosmosLightClientServiceClient(
                configuration: cosmosHarness.configuration,
                session: cosmosHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let osmosis = bridge.chainTrustSnapshot.status(forChainRef: "osmosis")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(osmosis?.state == .proofChecked)
        #expect(osmosis?.trustSource == .localProof)
        #expect(osmosis?.displaySummary.contains("proof-checked evidence") == true)
        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.status.contains("Osmosis proof checked") == true)
    }

    @Test func substrateChainSpecRoutingAndFallbackAreExplicit() {
        #expect(SubstrateChain.known(from: "polkadot") == .polkadot)
        #expect(SubstrateChain.known(from: "dot") == .polkadot)
        #expect(SubstrateChain.known(from: "asset-hub-polkadot") == .assetHubPolkadot)
        #expect(SubstrateChain.assetHubPolkadot.relayChain == .polkadot)

        let fallback = SubstrateLightClientServiceSnapshot.fallback(
            chain: .polkadot,
            lastError: "disabled"
        )

        #expect(fallback.syncState == .unavailable)
        #expect(fallback.chainTrustStatus.state == .rpcFallback)
        #expect(fallback.statusSummary.contains("trusted RPC fallback remains labeled"))
    }

    @Test func substrateStorageProofVerifiesGrandpaFinalityAndStateRoot() {
        let bundle = Self.substrateProofBundle(chain: .polkadot)
        let result = bundle.verify()
        var weakBundle = bundle
        weakBundle.justification.signatures = [bundle.justification.signatures[0]]
        let weakResult = weakBundle.verify()

        #expect(bundle.authoritySet.validatesHash)
        #expect(bundle.authoritySet.totalWeight == 100)
        #expect(result.verified)
        #expect(result.state == .synced)
        #expect(result.chainRef == "polkadot")
        #expect(result.storageKey == Self.substrateStorageKey)
        #expect(weakResult.verified == false)
        #expect(weakResult.state == .failed)
        #expect(weakResult.summary.contains("two-thirds"))
    }

    @Test func substrateConflictingGrandpaJustificationsAreFailed() {
        let bundle = Self.substrateProofBundle(chain: .polkadot)
        var conflictBundle = bundle
        let conflictingHash = SubstrateHex.sha256Hex("conflicting-grandpa-block")
        conflictBundle.conflictingJustification = GRANDPAFinalityJustification(
            round: 43,
            setID: bundle.authoritySet.setID,
            targetHash: conflictingHash,
            targetNumber: bundle.header.number,
            signatures: [
                Self.grandpaSignature(Self.substrateAuthorityKey(0xD1), setID: bundle.authoritySet.setID, round: 43, blockHash: conflictingHash),
                Self.grandpaSignature(Self.substrateAuthorityKey(0xE2), setID: bundle.authoritySet.setID, round: 43, blockHash: conflictingHash)
            ],
            source: "fixture"
        )
        let result = conflictBundle.verify()

        #expect(result.verified == false)
        #expect(result.state == .failed)
        #expect(result.summary.contains("Conflicting GRANDPA"))
    }

    @MainActor
    @Test func substrateLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let capturedRequests = JSONRequestCapture()
        let substrateHarness = Self.makeSubstrateLightClientSession(key: "substrateregistry", chain: .polkadot) { request in
            capturedRequests.capture(request)
            if request.url?.path == "/v1/substrate/status" {
                return Self.jsonResponse(for: request, body: Self.substrateServiceStatus(chain: .polkadot))
            }
            if request.url?.path == "/v1/substrate/verify-storage-proof" {
                return Self.jsonResponse(for: request, body: Self.substrateProofResultBody(
                    verified: true,
                    state: "synced",
                    chain: .polkadot
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = SubstrateLightClientServiceClient(
            configuration: substrateHarness.configuration,
            session: substrateHarness.session
        )
        let snapshot = await client.snapshot()
        let proofResult = try! await client.verifyStorageProofViaService(Self.substrateProofBundle(chain: .polkadot))
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordSubstrateLightClientSnapshot(snapshot)
        let polkadot = registry.status(forChainRef: "polkadot")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .synced)
        #expect(snapshot.latestFinalizedHeader?.number == 21_000_000)
        #expect(status.state == .verified)
        #expect(status.trustSource == .embeddedLightClient)
        #expect(polkadot?.evidence.first?.source == .embeddedLightClient)
        #expect(proofResult.verified)
        #expect(proofResult.state == .synced)
        #expect(capturedRequests.body(for: "/v1/substrate/verify-storage-proof")?["storage_proof"] != nil)
    }

    @MainActor
    @Test func substrateLightClientFallsBackWhenServiceDisabled() async {
        let client = SubstrateLightClientServiceClient(configuration: .disabled)
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordSubstrateLightClientSnapshot(snapshot)

        #expect(snapshot.serviceAvailable == false)
        #expect(snapshot.syncState == .unavailable)
        #expect(status.state == .rpcFallback)
        #expect(status.trustSource == .gatewayRPCFallback)
        #expect(status.displaySummary.contains("Gateway/RPC fallback") == true)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesSubstrateLightClientState() async {
        let substrateHarness = Self.makeSubstrateLightClientSession(key: "substrateruntime", chain: .assetHubPolkadot) { request in
            if request.url?.path == "/v1/substrate/status" {
                return Self.jsonResponse(for: request, body: Self.substrateServiceStatus(
                    chain: .assetHubPolkadot,
                    syncState: "proof_checked"
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "substrateruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                substrateLightClient: substrateHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(configuration: .disabled),
            evmLightClientServiceClient: EVMLightClientServiceClient(configuration: .disabled),
            solanaLightClientServiceClient: SolanaLightClientServiceClient(configuration: .disabled),
            cosmosLightClientServiceClient: CosmosLightClientServiceClient(configuration: .disabled),
            substrateLightClientServiceClient: SubstrateLightClientServiceClient(
                configuration: substrateHarness.configuration,
                session: substrateHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let assetHub = bridge.chainTrustSnapshot.status(forChainRef: "asset-hub-polkadot")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(assetHub?.state == .proofChecked)
        #expect(assetHub?.trustSource == .localProof)
        #expect(assetHub?.displaySummary.contains("proof-checked evidence") == true)
        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.status.contains("Asset Hub Polkadot proof checked") == true)
    }

    @Test func avalancheRoutingAndFallbackAreExplicit() {
        #expect(AvalancheNetwork.known(from: "avalanche") == .cChain)
        #expect(AvalancheNetwork.known(from: "43114") == .cChain)
        #expect(AvalancheNetwork.cChain.evmChain == .avalancheCChain)
        #expect(EVMChain.avalancheCChain.finalityModel == .snowmanFinality)

        let fallback = AvalancheLightClientServiceSnapshot.fallback(
            network: .cChain,
            lastError: "disabled"
        )

        #expect(fallback.finalityModel == .rpcFallback)
        #expect(fallback.syncState == .unavailable)
        #expect(fallback.chainTrustStatus.state == .rpcFallback)
        #expect(fallback.statusSummary.contains("Gateway/RPC fallback remains labeled"))
    }

    @Test func avalancheStateProofVerifiesSnowmanFinalityAndCChainProof() {
        let bundle = Self.avalancheProofBundle(network: .cChain)
        let result = bundle.verify()
        var weakBundle = bundle
        weakBundle.finalityEvidence.signatures = [bundle.finalityEvidence.signatures[0]]
        let weakResult = weakBundle.verify()
        var ethereumBundle = bundle
        ethereumBundle.evmProof?.header.chain = .ethereumMainnet
        let ethereumResult = ethereumBundle.verify()

        #expect(bundle.validatorSet.validatesHash)
        #expect(bundle.validatorSet.totalWeight == 100)
        #expect(bundle.validatorSet.hasAcceptedQuorum(validatorIDs: bundle.finalityEvidence.verifiedValidatorIDs(validators: bundle.validatorSet.validators)))
        #expect(bundle.evmProof?.header.chain == .avalancheCChain)
        #expect(result.verified)
        #expect(result.state == .proofChecked)
        #expect(result.chainRef == "avalanche-c")
        #expect(result.summary.contains("C-Chain EVM proof"))
        #expect(weakResult.verified == false)
        #expect(weakResult.summary.contains("validator-weight quorum"))
        #expect(ethereumResult.verified == false)
        #expect(ethereumResult.summary.contains("must not use Ethereum mainnet"))
    }

    @Test func avalancheConflictingAcceptedEvidenceIsFailed() {
        let bundle = Self.avalancheProofBundle(network: .cChain)
        var conflictBundle = bundle
        let conflictingHash = EVMHex.sha256Hex("conflicting-avalanche-accepted-block")
        conflictBundle.conflictingEvidence = AvalancheFinalityEvidence(
            setID: bundle.validatorSet.setID,
            targetHash: conflictingHash,
            targetHeight: bundle.acceptedBlock.height,
            signatures: [
                Self.avalancheFinalitySignature(
                    Self.avalancheValidatorKey(0xA1),
                    nodeID: bundle.validatorSet.validators[0].nodeID,
                    setID: bundle.validatorSet.setID,
                    targetHeight: bundle.acceptedBlock.height,
                    blockHash: conflictingHash
                ),
                Self.avalancheFinalitySignature(
                    Self.avalancheValidatorKey(0xB2),
                    nodeID: bundle.validatorSet.validators[1].nodeID,
                    setID: bundle.validatorSet.setID,
                    targetHeight: bundle.acceptedBlock.height,
                    blockHash: conflictingHash
                )
            ],
            source: "fixture"
        )
        let result = conflictBundle.verify()

        #expect(result.verified == false)
        #expect(result.state == .failed)
        #expect(result.summary.contains("Conflicting Avalanche"))
    }

    @Test func avalancheRejectsFlagOnlyAndWrongKeyFinalityEvidence() {
        let bundle = Self.avalancheProofBundle(network: .cChain)
        var flagOnlyBundle = bundle
        flagOnlyBundle.finalityEvidence.signatures = [
            AvalancheFinalitySignature(
                nodeID: bundle.validatorSet.validators[0].nodeID,
                blockHash: bundle.acceptedBlock.blockHash,
                signed: true,
                signature: nil
            ),
            AvalancheFinalitySignature(
                nodeID: bundle.validatorSet.validators[1].nodeID,
                blockHash: bundle.acceptedBlock.blockHash,
                signed: true,
                signature: nil
            )
        ]
        var wrongKeyBundle = bundle
        wrongKeyBundle.finalityEvidence.signatures[1] = Self.avalancheFinalitySignature(
            Self.avalancheValidatorKey(0xEE),
            nodeID: bundle.validatorSet.validators[1].nodeID,
            setID: bundle.validatorSet.setID,
            targetHeight: bundle.acceptedBlock.height,
            blockHash: bundle.acceptedBlock.blockHash
        )

        let flagOnlyResult = flagOnlyBundle.verify()
        let wrongKeyResult = wrongKeyBundle.verify()

        #expect(flagOnlyResult.verified == false)
        #expect(flagOnlyResult.summary.contains("validator-weight quorum"))
        #expect(wrongKeyResult.verified == false)
        #expect(wrongKeyResult.summary.contains("validator-weight quorum"))
    }

    @MainActor
    @Test func avalancheLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let capturedRequests = JSONRequestCapture()
        let avalancheHarness = Self.makeAvalancheLightClientSession(key: "avalancheregistry", network: .cChain) { request in
            capturedRequests.capture(request)
            if request.url?.path == "/v1/avalanche/status" {
                return Self.jsonResponse(for: request, body: Self.avalancheServiceStatus(network: .cChain))
            }
            if request.url?.path == "/v1/avalanche/verify-state" {
                return Self.jsonResponse(for: request, body: Self.avalancheProofResultBody(
                    verified: true,
                    state: "proof_checked",
                    network: .cChain
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = AvalancheLightClientServiceClient(
            configuration: avalancheHarness.configuration,
            session: avalancheHarness.session
        )
        let snapshot = await client.snapshot()
        let proofResult = try! await client.verifyStateViaService(Self.avalancheProofBundle(network: .cChain))
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordAvalancheLightClientSnapshot(snapshot)
        let avalanche = registry.status(forChainRef: "avalanche-c")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .proofChecked)
        #expect(snapshot.acceptedBlock?.height == 50_000_000)
        #expect(status.state == .proofChecked)
        #expect(status.trustSource == .localProof)
        #expect(avalanche?.family == .avalanche)
        #expect(avalanche?.evidence.first?.source == .localProof)
        #expect(proofResult.verified)
        #expect(proofResult.state == .proofChecked)
        #expect(capturedRequests.body(for: "/v1/avalanche/verify-state")?["evm_proof"] != nil)
    }

    @MainActor
    @Test func avalancheLightClientFallsBackWhenServiceDisabled() async {
        let client = AvalancheLightClientServiceClient(configuration: .disabled)
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordAvalancheLightClientSnapshot(snapshot)

        #expect(snapshot.serviceAvailable == false)
        #expect(snapshot.syncState == .unavailable)
        #expect(status.state == .rpcFallback)
        #expect(status.trustSource == .gatewayRPCFallback)
        #expect(status.displaySummary.contains("Gateway/RPC fallback") == true)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesAvalancheLightClientState() async {
        let avalancheHarness = Self.makeAvalancheLightClientSession(key: "avalancheruntime", network: .cChain) { request in
            if request.url?.path == "/v1/avalanche/status" {
                return Self.jsonResponse(for: request, body: Self.avalancheServiceStatus(
                    network: .cChain,
                    syncState: "proof_checked"
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "avalancheruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                avalancheLightClient: avalancheHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(configuration: .disabled),
            evmLightClientServiceClient: EVMLightClientServiceClient(configuration: .disabled),
            solanaLightClientServiceClient: SolanaLightClientServiceClient(configuration: .disabled),
            cosmosLightClientServiceClient: CosmosLightClientServiceClient(configuration: .disabled),
            substrateLightClientServiceClient: SubstrateLightClientServiceClient(configuration: .disabled),
            avalancheLightClientServiceClient: AvalancheLightClientServiceClient(
                configuration: avalancheHarness.configuration,
                session: avalancheHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let avalanche = bridge.chainTrustSnapshot.status(forChainRef: "avalanche-c")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(avalanche?.state == .proofChecked)
        #expect(avalanche?.trustSource == .localProof)
        #expect(avalanche?.evidence.first?.summary.contains("distinct from Ethereum mainnet finality") == true)
        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.status.contains("Avalanche C-Chain proof checked") == true)
    }

    @Test func tronRoutingStaleAndFallbackAreExplicit() {
        #expect(TronNetwork.known(from: "tron") == .mainnet)
        #expect(TronNetwork.known(from: "nile") == .nile)
        #expect(TronNetwork.mainnet.supportedProofTypes.contains("witness-quorum"))

        let fallback = TronLightClientServiceSnapshot.fallback(
            network: .mainnet,
            lastError: "disabled"
        )
        let stale = TronLightClientServiceSnapshot(
            serviceAvailable: true,
            network: .mainnet,
            syncState: .stale,
            source: "fixture",
            latestSolidBlock: Self.tronProofBundle(network: .mainnet).header,
            stale: true
        )

        #expect(fallback.syncState == .unavailable)
        #expect(fallback.chainTrustStatus.state == .rpcFallback)
        #expect(fallback.statusSummary.contains("API/RPC fallback remains labeled"))
        #expect(stale.chainTrustStatus.state == .stale)
        #expect(stale.statusSummary.contains("stale"))
    }

    @Test func tronProofVerifiesWitnessQuorumAndTokenRoot() {
        let bundle = Self.tronProofBundle(network: .mainnet)
        let result = bundle.verify()
        var weakBundle = bundle
        weakBundle.finalityProof.signatures = [bundle.finalityProof.signatures[0]]
        let weakResult = weakBundle.verify()
        var apiOnlyBundle = bundle
        apiOnlyBundle.header.solid = false
        let apiOnlyResult = apiOnlyBundle.verify()

        #expect(bundle.witnessSet.validatesHash)
        #expect(bundle.witnessSet.totalWeight == 27)
        #expect(bundle.witnessSet.hasQuorum(addresses: bundle.finalityProof.signedWitnessAddresses))
        #expect(result.verified)
        #expect(result.state == .proofChecked)
        #expect(result.chainRef == "tron-mainnet")
        #expect(result.kind == .token)
        #expect(weakResult.verified == false)
        #expect(weakResult.summary.contains("witness quorum"))
        #expect(apiOnlyResult.verified == false)
        #expect(apiOnlyResult.summary.contains("API/RPC data must remain fallback-labeled"))
    }

    @MainActor
    @Test func tronLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let capturedRequests = JSONRequestCapture()
        let tronHarness = Self.makeTronLightClientSession(key: "tronregistry", network: .mainnet) { request in
            capturedRequests.capture(request)
            if request.url?.path == "/v1/tron/status" {
                return Self.jsonResponse(for: request, body: Self.tronServiceStatus(network: .mainnet))
            }
            if request.url?.path == "/v1/tron/verify-proof" {
                return Self.jsonResponse(for: request, body: Self.tronProofResultBody(
                    verified: true,
                    state: "proof_checked",
                    network: .mainnet
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = TronLightClientServiceClient(
            configuration: tronHarness.configuration,
            session: tronHarness.session
        )
        let snapshot = await client.snapshot()
        let proofResult = try! await client.verifyProofViaService(Self.tronProofBundle(network: .mainnet))
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordTronLightClientSnapshot(snapshot)
        let tron = registry.status(forChainRef: "tron-mainnet")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .proofChecked)
        #expect(snapshot.latestSolidBlock?.number == 60_000_000)
        #expect(status.state == .proofChecked)
        #expect(status.trustSource == .localProof)
        #expect(tron?.family == .tron)
        #expect(tron?.evidence.first?.source == .localProof)
        #expect(proofResult.verified)
        #expect(proofResult.state == .proofChecked)
        #expect(capturedRequests.body(for: "/v1/tron/verify-proof")?["finality_proof"] != nil)
    }

    @MainActor
    @Test func tronLightClientFallsBackWhenServiceDisabled() async {
        let client = TronLightClientServiceClient(configuration: .disabled)
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordTronLightClientSnapshot(snapshot)

        #expect(snapshot.serviceAvailable == false)
        #expect(snapshot.syncState == .unavailable)
        #expect(status.state == .rpcFallback)
        #expect(status.trustSource == .gatewayRPCFallback)
        #expect(status.displaySummary.contains("Gateway/RPC fallback") == true)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesTronLightClientState() async {
        let tronHarness = Self.makeTronLightClientSession(key: "tronruntime", network: .mainnet) { request in
            if request.url?.path == "/v1/tron/status" {
                return Self.jsonResponse(for: request, body: Self.tronServiceStatus(
                    network: .mainnet,
                    syncState: "proof_checked"
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "tronruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                tronLightClient: tronHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(configuration: .disabled),
            evmLightClientServiceClient: EVMLightClientServiceClient(configuration: .disabled),
            solanaLightClientServiceClient: SolanaLightClientServiceClient(configuration: .disabled),
            cosmosLightClientServiceClient: CosmosLightClientServiceClient(configuration: .disabled),
            substrateLightClientServiceClient: SubstrateLightClientServiceClient(configuration: .disabled),
            avalancheLightClientServiceClient: AvalancheLightClientServiceClient(configuration: .disabled),
            tronLightClientServiceClient: TronLightClientServiceClient(
                configuration: tronHarness.configuration,
                session: tronHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let tron = bridge.chainTrustSnapshot.status(forChainRef: "tron-mainnet")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(tron?.state == .proofChecked)
        #expect(tron?.trustSource == .localProof)
        #expect(tron?.evidence.first?.summary.contains("production TRON light-client verification is not claimed") == true)
        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.status.contains("TRON proof checked") == true)
    }

    @Test func xrplRoutingStaleAndFallbackAreExplicit() {
        #expect(XRPLNetwork.known(from: "xrpl") == .mainnet)
        #expect(XRPLNetwork.known(from: "xrp-testnet") == .testnet)
        #expect(XRPLNetwork.mainnet.supportedProofTypes.contains("unl-quorum"))

        let fallback = XRPLLightClientServiceSnapshot.fallback(
            network: .mainnet,
            lastError: "disabled"
        )
        let stale = XRPLLightClientServiceSnapshot(
            serviceAvailable: true,
            network: .mainnet,
            syncState: .stale,
            source: "fixture",
            latestValidatedLedger: Self.xrplProofBundle(network: .mainnet).ledger,
            stale: true
        )

        #expect(fallback.syncState == .unavailable)
        #expect(fallback.chainTrustStatus.state == .rpcFallback)
        #expect(fallback.statusSummary.contains("API/RPC fallback remains labeled"))
        #expect(stale.chainTrustStatus.state == .stale)
        #expect(stale.statusSummary.contains("stale"))
    }

    @Test func xrplProofVerifiesUNLQuorumAndLedgerRoots() {
        let accountBundle = Self.xrplProofBundle(network: .mainnet, kind: .account)
        let trustLineBundle = Self.xrplProofBundle(network: .mainnet, kind: .trustLine)
        let paymentBundle = Self.xrplProofBundle(network: .mainnet, kind: .payment)
        let accountResult = accountBundle.verify()
        let trustLineResult = trustLineBundle.verify()
        let paymentResult = paymentBundle.verify()
        var weakBundle = accountBundle
        weakBundle.validationProof.votes = Array(accountBundle.validationProof.votes.prefix(3))
        let weakResult = weakBundle.verify()
        var apiOnlyBundle = accountBundle
        apiOnlyBundle.ledger.validated = false
        let apiOnlyResult = apiOnlyBundle.verify()

        #expect(accountBundle.unlSet.validatesHash)
        #expect(accountBundle.unlSet.configuredWeight == 5)
        #expect(accountBundle.unlSet.effectiveWeight == 4)
        #expect(accountBundle.unlSet.requiredQuorumWeight == 4)
        #expect(accountBundle.unlSet.hasQuorum(validatorPublicKeys: accountBundle.validationProof.verifiedValidatorPublicKeys(
            ledgerHash: accountBundle.ledger.ledgerHash,
            ledgerIndex: accountBundle.ledger.ledgerIndex
        )))
        #expect(accountResult.verified)
        #expect(accountResult.state == .proofChecked)
        #expect(trustLineResult.verified)
        #expect(trustLineResult.kind == .trustLine)
        #expect(paymentResult.verified)
        #expect(paymentResult.kind == .payment)
        #expect(weakResult.verified == false)
        #expect(weakResult.summary.contains("UNL quorum"))
        #expect(apiOnlyResult.verified == false)
        #expect(apiOnlyResult.summary.contains("API/RPC data must remain fallback-labeled"))
    }

    @Test func xrplRejectsFlagOnlyAndWrongKeyUNLVotes() {
        let bundle = Self.xrplProofBundle(network: .mainnet, kind: .account)
        var flagOnlyBundle = bundle
        flagOnlyBundle.validationProof.votes = Array(bundle.unlSet.validators.prefix(4)).map { validator in
            XRPLValidationVote(
                validatorPublicKey: validator.validatorPublicKey,
                ledgerHash: bundle.ledger.ledgerHash,
                ledgerIndex: bundle.ledger.ledgerIndex,
                signed: true,
                signature: nil
            )
        }
        var wrongKeyBundle = bundle
        wrongKeyBundle.validationProof.votes[3] = Self.xrplValidationVote(
            Self.xrplValidatorKey(0xFE),
            listID: bundle.unlSet.listID,
            ledgerHash: bundle.ledger.ledgerHash,
            ledgerIndex: bundle.ledger.ledgerIndex,
            validatorPublicKey: bundle.unlSet.validators[3].validatorPublicKey
        )

        let flagOnlyResult = flagOnlyBundle.verify()
        let wrongKeyResult = wrongKeyBundle.verify()

        #expect(flagOnlyResult.verified == false)
        #expect(flagOnlyResult.summary.contains("UNL quorum"))
        #expect(wrongKeyResult.verified == false)
        #expect(wrongKeyResult.summary.contains("UNL quorum"))
    }

    @MainActor
    @Test func xrplLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let capturedRequests = JSONRequestCapture()
        let xrplHarness = Self.makeXRPLLightClientSession(key: "xrplregistry", network: .mainnet) { request in
            capturedRequests.capture(request)
            if request.url?.path == "/v1/xrpl/status" {
                return Self.jsonResponse(for: request, body: Self.xrplServiceStatus(network: .mainnet))
            }
            if request.url?.path == "/v1/xrpl/verify-proof" {
                return Self.jsonResponse(for: request, body: Self.xrplProofResultBody(
                    verified: true,
                    state: "proof_checked",
                    network: .mainnet
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = XRPLLightClientServiceClient(
            configuration: xrplHarness.configuration,
            session: xrplHarness.session
        )
        let snapshot = await client.snapshot()
        let proofResult = try! await client.verifyProofViaService(Self.xrplProofBundle(network: .mainnet))
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordXRPLLightClientSnapshot(snapshot)
        let xrpl = registry.status(forChainRef: "xrp-ledger")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .proofChecked)
        #expect(snapshot.latestValidatedLedger?.ledgerIndex == 90_000_000)
        #expect(status.state == .proofChecked)
        #expect(status.trustSource == .localProof)
        #expect(xrpl?.family == .xrpLedger)
        #expect(xrpl?.evidence.first?.source == .localProof)
        #expect(proofResult.verified)
        #expect(proofResult.state == .proofChecked)
        #expect(capturedRequests.body(for: "/v1/xrpl/verify-proof")?["validation_proof"] != nil)
    }

    @MainActor
    @Test func xrplLightClientFallsBackWhenServiceDisabled() async {
        let client = XRPLLightClientServiceClient(configuration: .disabled)
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordXRPLLightClientSnapshot(snapshot)

        #expect(snapshot.serviceAvailable == false)
        #expect(snapshot.syncState == .unavailable)
        #expect(status.state == .rpcFallback)
        #expect(status.trustSource == .gatewayRPCFallback)
        #expect(status.displaySummary.contains("Gateway/RPC fallback") == true)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesXRPLLightClientState() async {
        let xrplHarness = Self.makeXRPLLightClientSession(key: "xrplruntime", network: .mainnet) { request in
            if request.url?.path == "/v1/xrpl/status" {
                return Self.jsonResponse(for: request, body: Self.xrplServiceStatus(
                    network: .mainnet,
                    syncState: "proof_checked"
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "xrplruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                xrplLightClient: xrplHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(configuration: .disabled),
            evmLightClientServiceClient: EVMLightClientServiceClient(configuration: .disabled),
            solanaLightClientServiceClient: SolanaLightClientServiceClient(configuration: .disabled),
            cosmosLightClientServiceClient: CosmosLightClientServiceClient(configuration: .disabled),
            substrateLightClientServiceClient: SubstrateLightClientServiceClient(configuration: .disabled),
            avalancheLightClientServiceClient: AvalancheLightClientServiceClient(configuration: .disabled),
            tronLightClientServiceClient: TronLightClientServiceClient(configuration: .disabled),
            xrplLightClientServiceClient: XRPLLightClientServiceClient(
                configuration: xrplHarness.configuration,
                session: xrplHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let xrpl = bridge.chainTrustSnapshot.status(forChainRef: "xrp-ledger")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(xrpl?.state == .proofChecked)
        #expect(xrpl?.trustSource == .localProof)
        #expect(xrpl?.evidence.first?.summary.contains("production XRPL verifier integration is not claimed") == true)
        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.status.contains("XRP Ledger proof checked") == true)
    }

    @Test func moveRoutingStaleAndFallbackAreExplicit() {
        #expect(MoveChain.known(from: "sui") == .suiMainnet)
        #expect(MoveChain.known(from: "aptos") == .aptosMainnet)
        #expect(MoveChain.suiMainnet.supportedProofTypes.contains("checkpoint-committee-quorum"))
        #expect(MoveChain.aptosMainnet.supportedProofTypes.contains("ledger-info-validator-quorum"))

        let fallback = MoveLightClientServiceSnapshot.fallback(
            chain: .suiMainnet,
            lastError: "disabled"
        )
        let stale = MoveLightClientServiceSnapshot(
            serviceAvailable: true,
            chain: .aptosMainnet,
            syncState: .stale,
            source: "fixture",
            latestCheckpoint: Self.moveProofBundle(chain: .aptosMainnet, kind: .aptosAccount).checkpoint,
            stale: true
        )

        #expect(fallback.syncState == .unavailable)
        #expect(fallback.chainTrustStatus.state == .rpcFallback)
        #expect(fallback.statusSummary.contains("API/RPC fallback remains labeled"))
        #expect(stale.chainTrustStatus.state == .stale)
        #expect(stale.statusSummary.contains("stale"))
    }

    @Test func moveProofVerifiesSuiAndAptosQuorumAndRoots() {
        let suiObjectBundle = Self.moveProofBundle(chain: .suiMainnet, kind: .suiObject)
        let suiEffectsBundle = Self.moveProofBundle(chain: .suiMainnet, kind: .suiTransactionEffects)
        let aptosAccountBundle = Self.moveProofBundle(chain: .aptosMainnet, kind: .aptosAccount)
        let aptosTransactionBundle = Self.moveProofBundle(chain: .aptosMainnet, kind: .aptosTransaction)
        let suiObjectResult = suiObjectBundle.verify()
        let suiEffectsResult = suiEffectsBundle.verify()
        let aptosAccountResult = aptosAccountBundle.verify()
        let aptosTransactionResult = aptosTransactionBundle.verify()
        var weakBundle = suiObjectBundle
        weakBundle.finalityProof.signatures = Array(suiObjectBundle.finalityProof.signatures.prefix(1))
        let weakResult = weakBundle.verify()
        var apiOnlyBundle = aptosAccountBundle
        apiOnlyBundle.checkpoint.finalized = false
        let apiOnlyResult = apiOnlyBundle.verify()

        #expect(suiObjectBundle.validatorSet.validatesHash)
        #expect(suiObjectBundle.validatorSet.configuredWeight == 100)
        #expect(suiObjectBundle.validatorSet.requiredQuorumWeight == 67)
        #expect(suiObjectBundle.validatorSet.hasQuorum(validatorIDs: suiObjectBundle.finalityProof.verifiedValidatorIDs(
            targetDigest: suiObjectBundle.checkpoint.digest,
            targetSequenceNumber: suiObjectBundle.checkpoint.sequenceNumber,
            validators: suiObjectBundle.validatorSet.validators,
            chain: suiObjectBundle.validatorSet.chain
        )))
        #expect(suiObjectResult.verified)
        #expect(suiObjectResult.state == .proofChecked)
        #expect(suiEffectsResult.verified)
        #expect(suiEffectsResult.kind == .suiTransactionEffects)
        #expect(aptosAccountResult.verified)
        #expect(aptosAccountResult.chainRef == "aptos-mainnet")
        #expect(aptosTransactionResult.verified)
        #expect(aptosTransactionResult.kind == .aptosTransaction)
        #expect(weakResult.verified == false)
        #expect(weakResult.summary.contains("validator quorum"))
        #expect(apiOnlyResult.verified == false)
        #expect(apiOnlyResult.summary.contains("API/RPC data must remain fallback-labeled"))
    }

    @Test func moveRejectsFlagOnlyAndWrongKeyFinalityEvidence() {
        let suiBundle = Self.moveProofBundle(chain: .suiMainnet, kind: .suiObject)
        var flagOnlySuiBundle = suiBundle
        flagOnlySuiBundle.finalityProof.signatures = Array(suiBundle.validatorSet.validators.prefix(2)).map { validator in
            MoveValidatorSignature(
                validatorID: validator.validatorID,
                checkpointDigest: suiBundle.checkpoint.digest,
                sequenceNumber: suiBundle.checkpoint.sequenceNumber,
                signed: true,
                signature: nil
            )
        }
        var wrongKeySuiBundle = suiBundle
        wrongKeySuiBundle.finalityProof.signatures[1] = Self.moveValidatorSignature(
            Self.moveValidatorKey(0xEE),
            validatorID: suiBundle.validatorSet.validators[1].validatorID,
            chain: suiBundle.validatorSet.chain,
            epoch: suiBundle.validatorSet.epoch,
            checkpointDigest: suiBundle.checkpoint.digest,
            sequenceNumber: suiBundle.checkpoint.sequenceNumber
        )

        let aptosBundle = Self.moveProofBundle(chain: .aptosMainnet, kind: .aptosAccount)
        var flagOnlyAptosBundle = aptosBundle
        flagOnlyAptosBundle.finalityProof.signatures = Array(aptosBundle.validatorSet.validators.prefix(2)).map { validator in
            MoveValidatorSignature(
                validatorID: validator.validatorID,
                checkpointDigest: aptosBundle.checkpoint.digest,
                sequenceNumber: aptosBundle.checkpoint.sequenceNumber,
                signed: true,
                signature: nil
            )
        }
        var wrongKeyAptosBundle = aptosBundle
        wrongKeyAptosBundle.finalityProof.signatures[1] = Self.moveValidatorSignature(
            Self.moveValidatorKey(0xEF),
            validatorID: aptosBundle.validatorSet.validators[1].validatorID,
            chain: aptosBundle.validatorSet.chain,
            epoch: aptosBundle.validatorSet.epoch,
            checkpointDigest: aptosBundle.checkpoint.digest,
            sequenceNumber: aptosBundle.checkpoint.sequenceNumber
        )

        let flagOnlySuiResult = flagOnlySuiBundle.verify()
        let wrongKeySuiResult = wrongKeySuiBundle.verify()
        let flagOnlyAptosResult = flagOnlyAptosBundle.verify()
        let wrongKeyAptosResult = wrongKeyAptosBundle.verify()

        #expect(flagOnlySuiResult.verified == false)
        #expect(flagOnlySuiResult.summary.contains("validator quorum"))
        #expect(wrongKeySuiResult.verified == false)
        #expect(wrongKeySuiResult.summary.contains("validator quorum"))
        #expect(flagOnlyAptosResult.verified == false)
        #expect(flagOnlyAptosResult.summary.contains("validator quorum"))
        #expect(wrongKeyAptosResult.verified == false)
        #expect(wrongKeyAptosResult.summary.contains("validator quorum"))
    }

    @MainActor
    @Test func moveLightClientServiceSnapshotUpdatesChainTrustRegistry() async {
        let capturedRequests = JSONRequestCapture()
        let moveHarness = Self.makeMoveLightClientSession(key: "moveregistry", chain: .suiMainnet) { request in
            capturedRequests.capture(request)
            if request.url?.path == "/v1/move/status" {
                return Self.jsonResponse(for: request, body: Self.moveServiceStatus(chain: .suiMainnet))
            }
            if request.url?.path == "/v1/move/verify-proof" {
                return Self.jsonResponse(for: request, body: Self.moveProofResultBody(
                    verified: true,
                    state: "proof_checked",
                    chain: .suiMainnet,
                    kind: .suiObject
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = MoveLightClientServiceClient(
            configuration: moveHarness.configuration,
            session: moveHarness.session
        )
        let snapshot = await client.snapshot()
        let proofResult = try! await client.verifyProofViaService(Self.moveProofBundle(chain: .suiMainnet, kind: .suiObject))
        var registry = ChainTrustRegistry.defaultRegistry
        let suiStatus = registry.recordMoveLightClientSnapshot(snapshot)
        let aptosStatus = registry.recordMoveLightClientSnapshot(MoveLightClientServiceSnapshot(
            serviceAvailable: true,
            chain: .aptosMainnet,
            syncState: .proofChecked,
            source: "fixture",
            latestCheckpoint: Self.moveProofBundle(chain: .aptosMainnet, kind: .aptosAccount).checkpoint,
            validatorSet: Self.moveProofBundle(chain: .aptosMainnet, kind: .aptosAccount).validatorSet,
            proofSource: "fixture-aptos-ledger-account-proof"
        ))
        let sui = registry.status(forChainRef: "sui-mainnet")
        let aptos = registry.status(forChainRef: "aptos-mainnet")

        #expect(snapshot.serviceAvailable)
        #expect(snapshot.syncState == .proofChecked)
        #expect(snapshot.latestCheckpoint?.sequenceNumber == 1_000_000)
        #expect(suiStatus.state == .proofChecked)
        #expect(suiStatus.trustSource == .localProof)
        #expect(sui?.family == .sui)
        #expect(sui?.evidence.first?.source == .localProof)
        #expect(aptosStatus.state == .proofChecked)
        #expect(aptos?.family == .aptos)
        #expect(proofResult.verified)
        #expect(proofResult.state == .proofChecked)
        #expect(capturedRequests.body(for: "/v1/move/verify-proof")?["finality_proof"] != nil)
    }

    @MainActor
    @Test func moveLightClientFallsBackWhenServiceDisabled() async {
        let client = MoveLightClientServiceClient(configuration: .disabled(chain: .aptosMainnet))
        let snapshot = await client.snapshot()
        var registry = ChainTrustRegistry.defaultRegistry
        let status = registry.recordMoveLightClientSnapshot(snapshot)

        #expect(snapshot.serviceAvailable == false)
        #expect(snapshot.syncState == .unavailable)
        #expect(status.state == .rpcFallback)
        #expect(status.trustSource == .gatewayRPCFallback)
        #expect(status.displaySummary.contains("Gateway/RPC fallback") == true)
    }

    @MainActor
    @Test func runtimeBridgeRefreshesMoveLightClientState() async {
        let suiHarness = Self.makeMoveLightClientSession(key: "moveruntimesui", chain: .suiMainnet) { request in
            if request.url?.path == "/v1/move/status" {
                return Self.jsonResponse(for: request, body: Self.moveServiceStatus(
                    chain: .suiMainnet,
                    syncState: "proof_checked"
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let aptosHarness = Self.makeMoveLightClientSession(key: "moveruntimeaptos", chain: .aptosMainnet) { request in
            if request.url?.path == "/v1/move/status" {
                return Self.jsonResponse(for: request, body: Self.moveServiceStatus(
                    chain: .aptosMainnet,
                    syncState: "proof_checked"
                ))
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let afmHarness = Self.makeAFMServiceSession(key: "moveruntimeafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                afmServices: afmHarness.configuration,
                llmRouter: .disabled,
                suiMoveLightClient: suiHarness.configuration,
                aptosMoveLightClient: aptosHarness.configuration
            ),
            afmServicesClient: AFMServicesClient(
                configuration: afmHarness.configuration,
                session: afmHarness.session
            ),
            llmRouterServiceClient: LLMRouterServiceClient(configuration: .disabled),
            bitcoinLightClientServiceClient: BitcoinLightClientServiceClient(configuration: .disabled),
            evmLightClientServiceClient: EVMLightClientServiceClient(configuration: .disabled),
            solanaLightClientServiceClient: SolanaLightClientServiceClient(configuration: .disabled),
            cosmosLightClientServiceClient: CosmosLightClientServiceClient(configuration: .disabled),
            substrateLightClientServiceClient: SubstrateLightClientServiceClient(configuration: .disabled),
            avalancheLightClientServiceClient: AvalancheLightClientServiceClient(configuration: .disabled),
            tronLightClientServiceClient: TronLightClientServiceClient(configuration: .disabled),
            xrplLightClientServiceClient: XRPLLightClientServiceClient(configuration: .disabled),
            suiMoveLightClientServiceClient: MoveLightClientServiceClient(
                configuration: suiHarness.configuration,
                session: suiHarness.session
            ),
            aptosMoveLightClientServiceClient: MoveLightClientServiceClient(
                configuration: aptosHarness.configuration,
                session: aptosHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let sui = bridge.chainTrustSnapshot.status(forChainRef: "sui-mainnet")
        let aptos = bridge.chainTrustSnapshot.status(forChainRef: "aptos-mainnet")
        let chainTrust = states.first { $0.feature == .chainTrust }

        #expect(sui?.state == .proofChecked)
        #expect(sui?.trustSource == .localProof)
        #expect(sui?.evidence.first?.summary.contains("production Sui verifier integration is not claimed") == true)
        #expect(aptos?.state == .proofChecked)
        #expect(aptos?.trustSource == .localProof)
        #expect(aptos?.evidence.first?.summary.contains("production Aptos verifier integration is not claimed") == true)
        #expect(chainTrust?.mode == .service)
        #expect(chainTrust?.status.contains("Sui proof checked") == true)
    }

    @MainActor
    @Test func runtimeBridgeForwardsSelectedAFMPackAndContextToServices() async {
        let capturedRequests = JSONRequestCapture()
        let serviceHarness = Self.makeAFMServiceSession(key: "forward") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port
            capturedRequests.capture(request)

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "name": "Demo Writer",
                            "skills": ["summarize"],
                            "status": "healthy"
                        ]
                    ]
                ])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/route" {
                return Self.jsonResponse(for: request, body: [
                    "selection": [
                        "id": "afm://demo-writer",
                        "name": "Demo Writer",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-42",
                    "status": "queued"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )
        let snapshot = PageSnapshot(
            urlString: "https://example.com",
            title: "Example",
            visibleText: "Service-backed context",
            headings: [],
            links: [],
            buttons: [],
            formControls: [],
            metadata: [:],
            truncated: false,
            redactionCount: 0
        )
        let memoryRecall = OpenMindMemoryRecallResult(
            decision: OpenMindAccessDecision(
                status: .allowed,
                allowedScopes: ["profile"],
                reason: "allowed",
                redactionCount: 0,
                stepUpPrompt: nil
            ),
            memories: [
                OpenMindMemoryRecord(
                    id: "mem-1",
                    summary: "Prefers concise summaries",
                    source: "test",
                    sensitivity: "normal",
                    evidenceURLString: nil
                )
            ],
            notices: []
        )

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Summarize",
                pageURLString: "https://example.com",
                pageSnapshot: snapshot,
                preferredAFMPackID: "afm://demo-writer",
                memoryRecall: memoryRecall
            )
        )

        let routeBody = capturedRequests.body(for: "/route")
        let jobBody = capturedRequests.body(for: "/jobs")
        let jobPayload = jobBody?["payload"] as? [String: Any]

        #expect(result.mode == .service)
        #expect(result.summary.contains("OpenMind approved 1 governed memory item"))
        #expect(routeBody?["preferredPackID"] as? String == "afm://demo-writer")
        #expect(routeBody?["pageSnapshotCommitment"] as? String != nil)
        #expect(routeBody?["memoryContextIDs"] as? [String] == ["mem-1"])
        #expect(jobPayload?["preferredPackID"] as? String == "afm://demo-writer")
        #expect(jobPayload?["memoryContextIDs"] as? [String] == ["mem-1"])
    }

    @MainActor
    @Test func runtimeBridgeSurfacesAFMarketV1RouteLeaseMetadata() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "runtimev1route") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": port != 4840])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: [
                    "experts": [
                        [
                            "id": "exp-001",
                            "name": "demo-afm",
                            "nodePub": "node-public-key-000000000000000000000000000000",
                            "capability": [0.12, 0.01, 0.75],
                            "pricePer1k": 2.5,
                            "latencyP50": 320,
                            "tags": ["afm"],
                            "baseModel": "apple.afm.demo"
                        ]
                    ]
                ])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: [
                    "bundles": [
                        [
                            "runnerId": "afm://demo-writer",
                            "version": "1.0.0",
                            "capability": [0.12, 0.01, 0.75],
                            "hashes": ["manifest": "sha256:manifest"]
                        ]
                    ]
                ])
            }

            if path == "/v1/route" {
                return Self.jsonResponse(for: request, body: [
                    "primary": [
                        "node_id": "exp-001",
                        "lease_id": "lease-v1",
                        "verifier": "attestation-ref",
                        "payout_address": "0x000000000000000000000000000000000000dead"
                    ],
                    "backups": [],
                    "lease_ttl_ms": 15000,
                    "explain": [
                        [
                            "expert_id": "exp-001",
                            "score": 0.81
                        ]
                    ]
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-v1",
                    "status": "queued"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )

        let result = await bridge.runCopilot(
            CopilotRunRequest(prompt: "Summarize through AFMarket v1", pageURLString: "https://example.com")
        )

        #expect(result.mode == .service)
        #expect(result.summary.contains("lease-v1"))
        #expect(result.summary.contains("base-sepolia"))
        #expect(result.suggestions.contains { $0.contains("AFMarket v1 primary lease lease-v1") })
        #expect(result.suggestions.contains { $0.contains("Route afmarket-v1 used chain base-sepolia") })
        #expect(result.suggestions.contains { $0.contains("1 bundle") && $0.contains("1 expert") })
        #expect(result.suggestions.contains { $0.contains("Node agent unavailable") })
    }

    @MainActor
    @Test func runtimeBridgeSurfacesAFMarketMarketplacePacks() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "runtimemarket", includesMarketplace: true) { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": port != 4840])
            }

            if path == "/packs" {
                return Self.jsonResponse(for: request, body: ["data": []])
            }

            if path == "/v1/experts" {
                return Self.jsonResponse(for: request, body: ["experts": []])
            }

            if path == "/v1/bundles" {
                return Self.jsonResponse(for: request, body: ["bundles": []])
            }

            if path == "/api/packs" {
                return Self.jsonResponse(for: request, body: [
                    [
                        "runner_id": "eu-law@v1",
                        "afm": ["model_id": "apple.afm.medium:2025.10"],
                        "prompting": [
                            "system": "You are a concise EU law specialist.",
                            "template": "{{input}}",
                            "params": [
                                "temperature": 0.2,
                                "top_p": 0.9,
                                "max_tokens": 750
                            ]
                        ],
                        "policy": [
                            "allowed_domains": ["law:eu"],
                            "max_context": 160000
                        ],
                        "royalties": [
                            "creator_bps": 700,
                            "data_bps": 200
                        ],
                        "hashes": ["bundle": "sha256:bundle"],
                        "bundle_url": "https://market.example/eu-law.tar",
                        "runner_root": "0xdf6a4e",
                        "owner_id": "creator-1",
                        "created_at": 1762127512523
                    ]
                ])
            }

            if path == "/v1/route" {
                return Self.jsonResponse(for: request, body: [
                    "primary": [
                        "node_id": "exp-001",
                        "lease_id": "lease-market",
                        "verifier": "attestation-ref",
                        "payout_address": "0x000000000000000000000000000000000000dead"
                    ],
                    "backups": [],
                    "lease_ttl_ms": 15000,
                    "explain": []
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-market",
                    "status": "queued"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Summarize with marketplace pack",
                pageURLString: "https://example.com",
                preferredAFMPackID: "eu-law@v1"
            )
        )
        let marketplacePack = bridge.afmServiceSnapshot.availablePacks.first { $0.id == "eu-law@v1" }

        #expect(result.mode == .service)
        #expect(result.suggestions.contains { $0.contains("Marketplace has 1 runner pack") })
        #expect(result.suggestions.contains { $0.contains("Copilot requested runner pack eu-law@v1") })
        #expect(marketplacePack?.modelID == "apple.afm.medium:2025.10")
        #expect(marketplacePack?.creatorRoyaltyBPS == 700)
        #expect(marketplacePack?.bundleURL == "https://market.example/eu-law.tar")
    }

    @MainActor
    @Test func runtimeBridgeInstallsAndDispatchesThroughAFMNode() async {
        let capturedRequests = JSONRequestCapture()
        let serviceHarness = Self.makeAFMServiceSession(key: "node") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port
            capturedRequests.capture(request)

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "name": "Demo Writer",
                            "skills": ["summarize"],
                            "status": "healthy"
                        ]
                    ]
                ])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "maintainer": "core",
                            "version": "0.1.0",
                            "checksum": "0xabc"
                        ]
                    ]
                ])
            }

            if path == "/route" {
                return Self.jsonResponse(for: request, body: [
                    "selection": [
                        "id": "afm://demo-writer",
                        "name": "Demo Writer",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-node",
                    "status": "queued"
                ])
            }

            if path == "/packs/install" {
                return Self.jsonResponse(for: request, status: 201, body: [
                    "ok": true,
                    "id": "install-1",
                    "packID": "afm://demo-writer",
                    "checksum": "0xabc",
                    "status": "installed",
                    "mode": "local-mock",
                    "installedAt": "2026-05-16T00:00:00Z",
                    "receipt": [
                        "mode": "local-mock",
                        "installCommitment": "0xinstall",
                        "verifier": "local-dev"
                    ]
                ])
            }

            if path == "/tasks" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "task-1",
                    "taskID": "task-1",
                    "packID": "afm://demo-writer",
                    "installID": "install-1",
                    "status": "completed",
                    "mode": "local-mock",
                    "result": [
                        "summary": "node completed",
                        "outputCommitment": "0xoutput",
                        "completedAt": "2026-05-16T00:00:01Z"
                    ],
                    "attestation": [
                        "mode": "local-mock",
                        "taskID": "task-1",
                        "outputCommitment": "0xoutput",
                        "nonce": "nonce-1",
                        "tokenCount": 12,
                        "contextPassages": 1
                    ],
                    "proof": [
                        "id": "proof-1",
                        "proofID": "proof-1",
                        "status": "mock",
                        "verifier": "local-dev",
                        "publicInputs": [
                            "packID": "afm://demo-writer",
                            "pageSnapshotCommitment": "0xsnapshot",
                            "outputCommitment": "0xoutput"
                        ]
                    ],
                    "settlement": [
                        "id": "settlement-1",
                        "status": "mock",
                        "chainRef": "local-devnet",
                        "verifier": "local-dev",
                        "mode": "local-mock",
                        "settledAt": "2026-05-16T00:00:02Z"
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )
        let memoryRecall = OpenMindMemoryRecallResult(
            decision: OpenMindAccessDecision(
                status: .allowed,
                allowedScopes: ["profile"],
                reason: "allowed",
                redactionCount: 0,
                stepUpPrompt: nil
            ),
            memories: [
                OpenMindMemoryRecord(
                    id: "mem-node",
                    summary: "Use AFMarket node evidence.",
                    source: "test",
                    sensitivity: "normal",
                    evidenceURLString: nil
                )
            ],
            notices: []
        )

        let result = await bridge.runCopilot(
            CopilotRunRequest(
                prompt: "Summarize",
                pageURLString: "https://example.com",
                preferredAFMPackID: "afm://demo-writer",
                memoryRecall: memoryRecall
            )
        )

        let installBody = capturedRequests.body(for: "/packs/install")
        let taskBody = capturedRequests.body(for: "/tasks")

        #expect(result.mode == .service)
        #expect(result.afmInstall?.status == "installed")
        #expect(result.afmInstall?.mode == "local-mock")
        #expect(result.afmNodeTask?.attestation.mode == "local-mock")
        #expect(result.afmNodeTask?.proof.status == "mock")
        #expect(result.afmNodeTask?.settlement.status == "mock")
        #expect(result.afmNodeTask?.verificationReport.state == .mock)
        #expect(result.summary.contains("local-mock attestation"))
        #expect(result.summary.contains("local/mock only"))
        #expect(result.suggestions.contains { $0.contains("Node installed afm://demo-writer") })
        #expect(result.suggestions.contains { $0.contains("Verification Mock") })
        #expect(result.suggestions.contains { $0.contains("Local mock attestation") })
        #expect(installBody?["checksum"] as? String == "0xabc")
        #expect(taskBody?["selectedPackID"] as? String == "afm://demo-writer")
        #expect(taskBody?["memoryContextIDs"] as? [String] == ["mem-node"])
    }

    @MainActor
    @Test func copilotRunRecordsAFMarketNodeActivity() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "nodeevents") { request in
            let path = request.url?.path ?? ""
            let port = request.url?.port

            if path == "/health" {
                return Self.jsonResponse(for: request, body: ["ok": true])
            }

            if path == "/packs" && port == 4810 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "name": "Demo Writer",
                            "skills": ["summarize"],
                            "status": "healthy"
                        ]
                    ]
                ])
            }

            if path == "/packs" && port == 4820 {
                return Self.jsonResponse(for: request, body: [
                    "data": [
                        [
                            "id": "afm://demo-writer",
                            "checksum": "0xabc"
                        ]
                    ]
                ])
            }

            if path == "/route" {
                return Self.jsonResponse(for: request, body: [
                    "selection": [
                        "id": "afm://demo-writer",
                        "name": "Demo Writer",
                        "skills": ["summarize"],
                        "status": "healthy"
                    ],
                    "requestedSkill": "summarize"
                ])
            }

            if path == "/jobs" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "ok": true,
                    "id": "job-node-events",
                    "status": "queued"
                ])
            }

            if path == "/packs/install" {
                return Self.jsonResponse(for: request, status: 201, body: [
                    "id": "install-events",
                    "packID": "afm://demo-writer",
                    "checksum": "0xabc",
                    "status": "installed",
                    "mode": "local-mock"
                ])
            }

            if path == "/tasks" {
                return Self.jsonResponse(for: request, status: 202, body: [
                    "id": "task-events",
                    "taskID": "task-events",
                    "packID": "afm://demo-writer",
                    "installID": "install-events",
                    "status": "completed",
                    "mode": "local-mock",
                    "result": [
                        "summary": "node completed",
                        "outputCommitment": "0xevents"
                    ],
                    "attestation": [
                        "mode": "local-mock",
                        "taskID": "task-events",
                        "outputCommitment": "0xevents",
                        "nonce": "nonce-events",
                        "tokenCount": 10,
                        "contextPassages": 0
                    ],
                    "proof": [
                        "proofID": "proof-events",
                        "status": "mock",
                        "verifier": "local-dev"
                    ],
                    "settlement": [
                        "status": "mock",
                        "chainRef": "local-devnet",
                        "mode": "local-mock"
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )
        let model = makeIsolatedBrowserViewModel(runtimeBridge: bridge)
        model.navigate("https://example.com")

        guard let runID = model.runCopilot(prompt: "Summarize with node") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)
        let events = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(completed)
        #expect(events.contains(.afMarketInstallCompleted))
        #expect(events.contains(.afMarketDispatchCompleted))
        #expect(events.contains(.afMarketAttestationRecorded))
        #expect(events.contains(.afMarketSettlementRecorded))
        #expect(events.contains(.afMarketVerificationRecorded))
    }

    @MainActor
    @Test func runtimeBridgeFallsBackWhenAFMServicesAreOffline() async {
        let serviceHarness = Self.makeAFMServiceSession(key: "offline") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: serviceHarness.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: serviceHarness.configuration,
                session: serviceHarness.session
            )
        )

        let states = await bridge.refreshStatus()
        let afmServices = states.first { $0.feature == .afmServices }
        #expect(afmServices?.mode == .unavailable)
        #expect(afmServices?.isAvailable == false)

        let copilot = await bridge.runCopilot(
            CopilotRunRequest(prompt: "Summarize this page", pageURLString: "https://example.com")
        )
        #expect(copilot.mode == .local)
        #expect(copilot.summary.contains("Summarize this page"))
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
    @Test func viewModelLoadsRemoteStorageResolverHandoffs() async {
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(
                nativeStorageAdapters: .disabled,
                remoteRuntimeBaseURL: RuntimeBridgeConfiguration.exampleRemoteRuntimeBaseURL
            )
        )
        let model = BrowserViewModel(initialURL: "about:home", runtimeBridge: bridge)
        let uri = "filecoin://baga6ea4seaqaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/app.car"
        let expectedURLString = await model.runtimeBridge.resolve(uri).resolvedURLString

        model.navigate(uri)

        let resolved = await waitForActiveURL(
            in: model,
            expectedURLString ?? ""
        )
        let query = remoteResolverQueryItems(for: model.activeTab?.urlString)

        #expect(resolved)
        #expect(query["network"] == "filecoin")
        #expect(query["scheme"] == "filecoin")
        #expect(query["uri"] == uri)
        #expect(model.activeTab?.loadableURL?.host == "storage-resolver.example")
        #expect(model.activeTab?.mobileNotice == nil)
    }

    @MainActor
    @Test func viewModelLoadsNativeStorageAdapterHandoffs() async {
        let model = BrowserViewModel()
        let uri = "iroh://example-storage-root/app.json"
        let expectedURLString = await model.runtimeBridge.resolve(uri).resolvedURLString

        model.navigate(uri)

        let resolved = await waitForActiveURL(
            in: model,
            expectedURLString ?? ""
        )
        let query = remoteResolverQueryItems(for: model.activeTab?.urlString)

        #expect(resolved)
        #expect(query["network"] == "iroh")
        #expect(query["scheme"] == "iroh")
        #expect(query["resolution_stage"] == DecentralizedStorageAdapterStage.nativeLocalAdapter.rawValue)
        #expect(query["uri"] == uri)
        #expect(model.activeTab?.loadableURL?.host == "127.0.0.1")
        #expect(model.activeTab?.mobileNotice == nil)
    }

    @MainActor
    @Test func viewModelLoadsFeaturedIPFSStartingPointsThroughRuntimeBridge() async {
        for point in DecentralizedStartingPoint.featured {
            let model = BrowserViewModel()
            let resolution = await model.runtimeBridge.resolve(point.address)

            guard let resolvedURLString = resolution.resolvedURLString else {
                Issue.record("Expected resolved URL for \(point.title)")
                continue
            }

            model.navigate(point.address)

            let resolved = await waitForActiveURL(in: model, resolvedURLString)
            #expect(resolved)
            #expect(model.activeTab?.mobileNotice == nil)
            #expect(model.history.first?.urlString == resolvedURLString)
        }
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
    @Test func openingCurrentRecentReloadsActivePage() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com")
        guard let entry = model.history.first else {
            Issue.record("Expected a recent history entry")
            return
        }

        model.selectPanel(.history)
        model.openHistoryEntry(entry)

        #expect(model.selectedPanel == nil)
        #expect(model.activeTab?.urlString == "https://example.com")
        #expect(model.webCommand?.tabID == model.activeTabID)
        #expect(model.webCommand?.command == .reload)
        #expect(model.history.first?.urlString == "https://example.com")
        #expect(model.history.filter { $0.urlString == "https://example.com" }.count == 1)
    }

    @MainActor
    @Test func openingOlderRecentNavigatesAndMovesItToTop() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://first.example")
        model.navigate("https://second.example")
        model.navigate("https://third.example")
        guard let firstEntry = model.history.first(where: { $0.urlString == "https://first.example" }) else {
            Issue.record("Expected the first URL in history")
            return
        }

        model.selectPanel(.history)
        model.openHistoryEntry(firstEntry)

        #expect(model.selectedPanel == nil)
        #expect(model.activeTab?.urlString == "https://first.example")
        #expect(model.addressText == "https://first.example")
        #expect(model.activeTab?.isLoading == true)
        #expect(model.history.map(\.urlString) == [
            "https://first.example",
            "https://third.example",
            "https://second.example"
        ])
        #expect(model.history.filter { $0.urlString == "https://first.example" }.count == 1)
    }

    @MainActor
    @Test func defaultBookmarksExposeRequiredGateways() {
        let model = BrowserViewModel()
        let urls = Set(model.bookmarks.map(\.urlString))

        #expect(urls.contains("https://llmos.showntell.dev"))
        #expect(urls.contains("https://zerok.cloud"))
    }

    @MainActor
    @Test func addressAutocompleteUsesPreviouslyVisitedURLs() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/docs/start")
        model.navigate("https://docs.ipfs.tech/concepts/ipns")
        model.addressText = "exa"

        let suggestions = model.addressAutocompleteSuggestions()

        #expect(suggestions.first?.urlString == "https://example.com/docs/start")
        #expect(suggestions.allSatisfy { suggestion in
            model.history.contains { $0.urlString == suggestion.urlString }
        })
    }

    @MainActor
    @Test func addressAutocompleteRanksURLPrefixMatchesBeforeContainsMatches() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/docs")
        model.navigate("https://docs.example.com/guide")
        model.addressText = "example"

        let suggestions = model.addressAutocompleteSuggestions()

        #expect(suggestions.map(\.urlString) == [
            "https://example.com/docs",
            "https://docs.example.com/guide"
        ])
    }

    @MainActor
    @Test func addressAutocompleteDeduplicatesHistoryAndHidesExactMatch() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://repeat.example/path")
        model.navigate("https://other.example")
        model.navigate("https://repeat.example/path")
        model.addressText = "repeat"

        let suggestions = model.addressAutocompleteSuggestions()

        #expect(suggestions.filter { $0.urlString == "https://repeat.example/path" }.count == 1)

        model.addressText = "https://repeat.example/path"
        #expect(model.addressAutocompleteSuggestions().isEmpty)
    }

    @MainActor
    @Test func automationRequestsAreScopedToTheActiveTab() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com")

        let request = model.requestDOMQuery(DOMQueryRequest(selector: "a", limit: 500))

        #expect(request?.tabID == model.activeTabID)
        guard case .domQuery(let query) = request?.command else {
            Issue.record("Expected DOM query automation request")
            return
        }
        #expect(query.selector == "a")
        #expect(query.limit == 100)
    }

    @MainActor
    @Test func pageSnapshotsUpdateSmartHistoryRecall() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/research")
        let snapshot = PageSnapshot(
            urlString: "https://example.com/research",
            title: "Research Notes",
            visibleText: "A local summary about verifiable Strawberry automation and page actions.",
            headings: ["Research"],
            links: [],
            buttons: [],
            formControls: [],
            metadata: [:],
            truncated: false,
            redactionCount: 0
        )

        model.applyAutomationResult(
            BrowserAutomationResult(
                requestID: UUID(),
                tabID: model.activeTabID,
                status: .success,
                message: "snapshot",
                pageSnapshot: snapshot
            )
        )

        let recall = model.smartHistoryRecall("verifiable automation")
        #expect(recall.first?.entry.urlString == "https://example.com/research")
        #expect(model.latestPageSnapshot == snapshot)
    }

    @MainActor
    @Test func sensitiveDOMActionsRequireApproval() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/login")
        model.applyAutomationResult(
            BrowserAutomationResult(
                requestID: UUID(),
                tabID: model.activeTabID,
                status: .success,
                message: "query",
                domQuery: DOMQueryResult(
                    selector: "input",
                    elements: [
                        DOMElementRecord(
                            index: 0,
                            tagName: "input",
                            role: nil,
                            ariaLabel: "Password",
                            text: nil,
                            value: "[redacted]",
                            href: nil,
                            inputType: "password",
                            name: "password",
                            placeholder: "Password",
                            disabled: false,
                            hidden: false
                        )
                    ],
                    totalMatched: 1,
                    truncated: false
                )
            )
        )

        let request = model.requestDOMAction(
            BrowserDOMAction(kind: .typeText, selector: "password", elementIndex: 0, text: "secret")
        )

        #expect(request == nil)
        #expect(model.automationResults.first?.status == .needsApproval)
        #expect(model.automationResults.first?.approval?.reasons.contains(.credentialField) == true)

        let submitRequest = model.requestDOMAction(BrowserDOMAction(kind: .submit, selector: "form"))
        #expect(submitRequest == nil)
        #expect(model.automationResults.first?.approval?.reasons.contains(.formSubmit) == true)
    }

    @MainActor
    @Test func copilotRunsTrackUsageAndCancellation() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com")

        guard let runID = model.runCopilot(prompt: "Summarize the current page") else {
            Issue.record("Expected Copilot run ID")
            return
        }

        #expect(model.activeCopilotRunCount == 1)
        #expect(model.copilotRuns.first?.usage?.isEstimated == true)
        model.cancelCopilotRun(runID)
        #expect(model.copilotRuns.first?.status == .cancelled)
        #expect(model.copilotRuns.first?.events.contains { $0.kind == .cancelled } == true)
    }

    @Test func navigationUpdateDrivesTabLifecycleAndHistory() {
        let model = makeIsolatedBrowserViewModel()
        let tabID = model.activeTabID

        // A WKWebView load begins: address and loading state update, but nothing is committed
        // to history until the load finishes.
        model.applyNavigationUpdate(
            BrowserNavigationUpdate(
                tabID: tabID,
                urlString: "https://example.com/page",
                title: "Example",
                isLoading: true,
                canGoBack: false,
                canGoForward: false
            )
        )
        #expect(model.activeTab?.isLoading == true)
        #expect(model.activeTab?.urlString == "https://example.com/page")
        #expect(model.addressText == "https://example.com/page")
        #expect(model.history.contains { $0.urlString == "https://example.com/page" } == false)

        // The load finishes: title and back/forward state settle and the page is recorded.
        model.applyNavigationUpdate(
            BrowserNavigationUpdate(
                tabID: tabID,
                urlString: "https://example.com/page",
                title: "Example Domain",
                isLoading: false,
                canGoBack: true,
                canGoForward: false
            )
        )
        #expect(model.activeTab?.isLoading == false)
        #expect(model.activeTab?.title == "Example Domain")
        #expect(model.canGoBack == true)
        #expect(model.history.first?.urlString == "https://example.com/page")
        #expect(model.history.first?.title == "Example Domain")
    }

    @MainActor
    @Test func unresolvableAddressSurfacesRuntimeNoticeWithoutHistory() async {
        let model = makeIsolatedBrowserViewModel()

        // No native handler or gateway can resolve this scheme, so the runtime bridge must
        // surface a labeled notice instead of silently navigating, and must not record history.
        model.navigate("obscureproto://content/item")

        let noticed = await waitForMobileNotice(in: model, containing: "No iOS runtime bridge is registered")
        #expect(noticed)
        #expect(model.activeTab?.urlString == "obscureproto://content/item")
        #expect(model.history.contains { $0.urlString.hasPrefix("obscureproto://") } == false)
    }

    @Test func closingTabCancelsBoundCopilotRuns() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com")
        let tabID = model.activeTabID

        guard let runID = model.runCopilot(prompt: "Summarize the current page") else {
            Issue.record("Expected a Copilot run ID")
            return
        }
        #expect(model.activeCopilotRunCount == 1)

        // Keep at least one tab alive, then close the tab the run is bound to.
        model.newTab()
        model.closeTab(tabID)

        let run = model.copilotRuns.first { $0.id == runID }
        #expect(run?.status == .cancelled)
        #expect(run?.events.contains { $0.kind == .cancelled } == true)
        #expect(model.activeCopilotRunCount == 0)
    }

    @MainActor
    @Test func copilotWorkflowsPersistAndRunWhenEnabled() {
        let workflowStore = CopilotWorkflowStore.ephemeral()
        let firstModel = makeIsolatedBrowserViewModel(workflowStore: workflowStore)
        let workflow = firstModel.saveCopilotWorkflow(
            title: "Daily summary",
            promptTemplate: "Summarize this page",
            allowedActions: [.scroll, .waitForSelector],
            schedule: .interval(hours: 24)
        )

        let secondModel = makeIsolatedBrowserViewModel(workflowStore: workflowStore)
        #expect(secondModel.copilotWorkflows.first?.id == workflow.id)

        secondModel.setWorkflow(workflow.id, isEnabled: false)
        #expect(secondModel.runWorkflow(workflow.id) == nil)

        secondModel.setWorkflow(workflow.id, isEnabled: true)
        secondModel.navigate("https://example.com")
        let runID = secondModel.runWorkflow(workflow.id)
        #expect(runID != nil)
        #expect(secondModel.copilotWorkflows.first?.lastRunAt != nil)
        if let runID {
            secondModel.cancelCopilotRun(runID)
        }
    }

    @MainActor
    @Test func smartHistoryRecallRespectsOptOutAndDeletion() {
        let model = makeIsolatedBrowserViewModel()
        model.navigate("https://example.com/private-notes")
        #expect(model.smartHistoryRecall("private notes").first?.entry.urlString == "https://example.com/private-notes")

        model.setSmartHistoryIndexing(enabled: false, forDomain: "example.com")
        #expect(model.smartHistoryRecall("private notes").isEmpty)

        guard let entryID = model.history.first?.id else {
            Issue.record("Expected history entry")
            return
        }
        model.deleteHistoryEntry(entryID)
        #expect(model.history.isEmpty)
    }

    @Test func creditEstimatorSeparatesBrowserFreeAndAIWork() {
        let zero = CopilotCreditUsage.zeroBrowserOperation
        let estimated = CopilotCreditUsage.estimate(prompt: "Summarize this page", snapshot: nil)

        #expect(zero.creditsSpent == Decimal.zero)
        #expect(!zero.isEstimated)
        #expect(estimated.creditsSpent > Decimal.zero)
        #expect(estimated.isEstimated)
    }

    @MainActor @Test func openMindMemoryClientRecallsAllowedContextAndWriteback() async {
        let memoryHarness = Self.makeOpenMindMemorySession(key: "memory") { request in
            let path = request.url?.path ?? ""

            if path == "/mcp/capabilities" {
                return Self.jsonResponse(for: request, body: [
                    "available": true,
                    "capabilities": ["mind.search_memories", "mind.add_memory"],
                    "posture": "normal",
                    "message": "ready"
                ])
            }

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "allowed",
                    "allowedScopes": ["profile"],
                    "reason": "allowed for test",
                    "redactionCount": 1
                ])
            }

            if path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, body: [
                    "memories": [
                        [
                            "id": "mem-1",
                            "summary": "User prefers short implementation summaries.",
                            "source": "BrIAn",
                            "sensitivity": "normal"
                        ]
                    ],
                    "notices": ["one item redacted"]
                ])
            }

            if path == "/mcp/tools/mind.retrieve_evidence_bundle" {
                return Self.jsonResponse(for: request, body: [
                    "bundleId": "evb-1",
                    "profile": "OMSEM-0.1",
                    "createdAt": "2026-05-16T00:00:00Z",
                    "query": [
                        "text": "Summarize this page",
                        "purpose": "copilot_recall"
                    ],
                    "scope": [
                        "domains": ["example.com"],
                        "maxSensitivity": "normal",
                        "outputMode": "evidence_summary"
                    ],
                    "items": [
                        [
                            "kind": "memory",
                            "id": "mem-evidence",
                            "summary": "Evidence says user prefers audited memory.",
                            "confidence": 0.88,
                            "evidenceRefs": ["event-1"],
                            "why": "matched",
                            "sensitivity": "normal"
                        ]
                    ],
                    "governanceNotes": ["policy filtered"]
                ])
            }

            if path == "/mcp/tools/mind.add_memory" {
                return Self.jsonResponse(for: request, body: [
                    "status": "recorded",
                    "revisionID": "rev-1",
                    "message": "recorded"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let capabilities = await client.refreshCapabilities()
        #expect(capabilities.status == .available)
        #expect(capabilities.capabilities.contains("mind.search_memories"))
        #expect(capabilities.transport?.kind == .directHTTP)

        let recall = await client.recall(
            prompt: "Summarize this page",
            pageURLString: "https://example.com",
            pageSnapshot: nil
        )
        #expect(recall.decision.status == .allowed)
        #expect(recall.memories.first?.id == "mem-1")
        #expect(recall.memories.contains { $0.id == "mem-evidence" })
        #expect(recall.evidenceBundle?.bundleID == "evb-1")
        #expect(recall.evidenceBundle?.items.first?.evidenceRefs == ["event-1"])
        #expect(recall.intent?.purpose == "copilot_recall")
        #expect(recall.notices == ["one item redacted"])

        let outcome = await client.writeback(
            OpenMindWritebackRequest(
                runID: UUID(),
                prompt: "Summarize this page",
                pageURLString: "https://example.com",
                summary: "Completed test run.",
                source: "unit-test",
                snapshotCommitment: nil,
                idempotencyKey: "test-key"
            )
        )
        #expect(outcome.status == .recorded)
        #expect(outcome.revisionID == "rev-1")
    }

    @MainActor @Test func openMindMemoryClientHandlesDeniedStepUpAndUnavailableStates() async {
        let capturedStepRequests = JSONRequestCapture()
        let deniedHarness = Self.makeOpenMindMemorySession(key: "denied") { request in
            if request.url?.path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "denied",
                    "allowedScopes": [],
                    "reason": "private memory blocked",
                    "redactionCount": 0
                ])
            }
            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let stepHarness = Self.makeOpenMindMemorySession(key: "step") { request in
            let path = request.url?.path ?? ""
            capturedStepRequests.capture(request)

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "stepUpRequired",
                    "allowedScopes": [],
                    "reason": "grant required",
                    "redactionCount": 0,
                    "stepUpPrompt": "Confirm memory access"
                ])
            }

            if path == "/mcp/tools/gateway.request_step_up_grant" {
                return Self.jsonResponse(for: request, body: [
                    "requestId": "step-1",
                    "status": "pending",
                    "operation": "memory.search",
                    "requestedScopes": ["mind.read.basic"],
                    "purpose": "copilot_recall",
                    "requestedTtl": "PT1H",
                    "justification": "Confirm memory access"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let unavailableHarness = Self.makeOpenMindMemorySession(key: "down") { request in
            Self.jsonResponse(for: request, status: 503, body: ["error": "offline"])
        }

        let denied = await OpenMindMemoryClient(
            configuration: deniedHarness.configuration,
            session: deniedHarness.session
        ).recall(prompt: "Find memory", pageURLString: nil, pageSnapshot: nil)
        let stepClient = OpenMindMemoryClient(
            configuration: stepHarness.configuration,
            session: stepHarness.session
        )
        let stepUp = await stepClient.recall(prompt: "Find memory", pageURLString: nil, pageSnapshot: nil)
        let stepRequest: OpenMindStepUpRequest?
        if let intent = stepUp.intent {
            stepRequest = await stepClient.requestStepUpGrant(
                intent: intent,
                decision: stepUp.decision,
                justification: stepUp.decision.stepUpPrompt
            )
        } else {
            stepRequest = nil
        }
        let stepBody = capturedStepRequests.body(for: "/mcp/tools/gateway.request_step_up_grant")
        let stepIntentBody = stepBody?["intent"] as? [String: Any]
        let unavailable = await OpenMindMemoryClient(
            configuration: unavailableHarness.configuration,
            session: unavailableHarness.session
        ).recall(prompt: "Find memory", pageURLString: nil, pageSnapshot: nil)

        #expect(denied.decision.status == .denied)
        #expect(denied.memories.isEmpty)
        #expect(stepUp.decision.status == .stepUpRequired)
        #expect(stepUp.decision.stepUpPrompt == "Confirm memory access")
        #expect(stepUp.intent?.purpose == "copilot_recall")
        #expect(stepRequest?.requestID == "step-1")
        #expect(stepRequest?.requestedScopes == ["mind.read.basic"])
        #expect(stepBody?["justification"] as? String == "Confirm memory access")
        #expect(stepIntentBody?["operation"] as? String == "memory.search")
        #expect(unavailable.decision.status == .unavailable)
    }

    @MainActor @Test func openMindMemoryClientLoadsContinuityAndPosture() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "runtime") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/capabilities" {
                return Self.jsonResponse(for: request, body: [
                    "available": true,
                    "capabilities": ["mind.search_memories", "posture.get"],
                    "posture": "normal",
                    "message": "ready"
                ])
            }

            if path == "/mcp/resources/mind/continuity" {
                return Self.jsonResponse(for: request, body: [
                    "version": "omcont/0.1",
                    "mode": "normal",
                    "summary": "Continuity ready",
                    "pendingStepUps": 2,
                    "updatedAt": "2026-05-16T00:00:00Z",
                    "notices": ["review one peer grant"]
                ])
            }

            if path == "/mcp/tools/posture.get" {
                return Self.jsonResponse(for: request, body: [
                    "mode": "protective",
                    "userMessage": "Protective mode is active.",
                    "allowsMemoryWriteback": false,
                    "requiresExplicitConfirmation": true,
                    "summary": "Protective posture",
                    "notices": ["writeback paused"]
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let state = await client.refreshRuntimeState()
        let postureBody = capturedRequests.body(for: "/mcp/tools/posture.get")

        #expect(state.capability.status == .available)
        #expect(state.capability.transport?.kind == .directHTTP)
        #expect(state.continuity.version == "omcont/0.1")
        #expect(state.continuity.pendingStepUps == 2)
        #expect(state.continuity.notices == ["review one peer grant"])
        #expect(state.posture.mode == "protective")
        #expect(state.posture.allowsMemoryWriteback == false)
        #expect(state.posture.requiresExplicitConfirmation)
        #expect(postureBody?["clientID"] as? String == "dBrowser.swift")
    }

    @MainActor @Test func openMindMemoryClientNegotiatesJSONRPCBridgeAndRecallsMemory() async {
        let capturedRPC = JSONRPCRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "memoryrpc") { request in
            guard request.url?.path == "/mcp" else {
                return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
            }

            let payload = capturedRPC.capture(request) ?? [:]
            let method = payload["method"] as? String
            let id = payload["id"] ?? 1

            if method == "initialize" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "protocolVersion": "2025-11-25",
                        "serverInfo": [
                            "name": "openmind-test",
                            "version": "1.0"
                        ],
                        "capabilities": [
                            "tools": [:] as [String: Any],
                            "resources": [:] as [String: Any]
                        ]
                    ]
                ])
            }

            if method == "notifications/initialized" {
                return Self.emptyResponse(for: request)
            }

            if method == "tools/list" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "tools": [
                            ["name": "gateway.evaluate_access_intent"],
                            ["name": "mind.retrieve_evidence_bundle"],
                            ["name": "mind.search_memories"],
                            ["name": "mind.add_memory"],
                            ["name": "posture.get"]
                        ]
                    ]
                ])
            }

            if method == "resources/list" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "resources": [
                            ["uri": "mind://continuity"]
                        ]
                    ]
                ])
            }

            if method == "resources/read" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "contents": [
                            [
                                "uri": "mind://continuity",
                                "mimeType": "application/json",
                                "text": Self.jsonString([
                                    "version": "omcont/0.1",
                                    "mode": "normal",
                                    "summary": "Bridge continuity ready",
                                    "pendingStepUps": 1,
                                    "notices": ["bridge resource"]
                                ])
                            ]
                        ]
                    ]
                ])
            }

            guard method == "tools/call",
                  let params = payload["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                return Self.jsonResponse(for: request, status: 400, body: ["error": "unexpected JSON-RPC request"])
            }

            switch toolName {
            case "posture.get":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "mode": "normal",
                            "allowsMemoryWriteback": true,
                            "requiresExplicitConfirmation": false,
                            "summary": "Bridge posture"
                        ],
                        "isError": false
                    ]
                ])
            case "gateway.evaluate_access_intent":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "status": "allow",
                            "allowedScopes": ["mind.read.private"],
                            "reason": "bridge allowed",
                            "redactionCount": 0
                        ],
                        "isError": false
                    ]
                ])
            case "mind.retrieve_evidence_bundle":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "bundleId": "evb-rpc",
                            "profile": "OMSEM-0.1",
                            "items": [
                                [
                                    "kind": "memory",
                                    "id": "mem-rpc-evidence",
                                    "summary": "RPC evidence memory",
                                    "evidenceRefs": ["event-rpc"],
                                    "sensitivity": "normal"
                                ]
                            ],
                            "governanceNotes": ["rpc governed"]
                        ],
                        "isError": false
                    ]
                ])
            case "mind.search_memories":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "results": [
                                [
                                    "id": "mem-rpc",
                                    "summary": "RPC bridge memory.",
                                    "source": "BrIAn",
                                    "sensitivity": "normal"
                                ]
                            ],
                            "notices": ["rpc notice"]
                        ],
                        "isError": false
                    ]
                ])
            case "mind.add_memory":
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "id": "rev-rpc"
                        ],
                        "isError": false
                    ]
                ])
            default:
                return Self.jsonResponse(for: request, status: 404, body: ["error": "unknown tool"])
            }
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let state = await client.refreshRuntimeState()
        #expect(state.capability.status == .available)
        #expect(state.capability.transport?.kind == .jsonRPCHTTPBridge)
        #expect(state.capability.transport?.serverName == "openmind-test")
        #expect(state.capability.capabilities.contains("mind.search_memories"))
        #expect(state.capability.capabilities.contains("mind://continuity"))
        #expect(state.continuity.version == "omcont/0.1")
        #expect(state.continuity.pendingStepUps == 1)
        #expect(state.posture.mode == "normal")

        let recall = await client.recall(
            prompt: "Summarize via bridge",
            pageURLString: "https://example.com/path",
            pageSnapshot: nil
        )
        #expect(recall.decision.status == .allowed)
        #expect(recall.memories.first?.id == "mem-rpc")
        #expect(recall.memories.contains { $0.id == "mem-rpc-evidence" })
        #expect(recall.evidenceBundle?.bundleID == "evb-rpc")
        #expect(recall.notices == ["rpc notice"])

        let outcome = await client.writeback(
            OpenMindWritebackRequest(
                runID: UUID(),
                prompt: "Summarize via bridge",
                pageURLString: "https://example.com/path",
                summary: "Completed RPC bridge test.",
                source: "unit-test",
                snapshotCommitment: "fnv1a64:abc",
                idempotencyKey: "rpc-key"
            )
        )
        let accessArguments = capturedRPC.toolArguments(named: "gateway.evaluate_access_intent")
        let addArguments = capturedRPC.toolArguments(named: "mind.add_memory")
        let addSource = addArguments?["source"] as? [String: Any]

        #expect(outcome.status == .recorded)
        #expect(outcome.revisionID == "rev-rpc")
        #expect(accessArguments?["operation"] as? String == "memory.search")
        #expect((accessArguments?["requestedDomains"] as? [String]) == ["example.com"])
        #expect(addArguments?["summary"] as? String == "Completed RPC bridge test.")
        #expect(addArguments?["idempotencyKey"] as? String == "rpc-key")
        #expect(addSource?["product"] as? String == "dBrowser.swift")
        #expect(addSource?["clientSource"] as? String == "unit-test")
    }

    @MainActor @Test func openMindMemoryClientLoadsReviewTasksAndCreatesCorrection() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "memoryreview") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/resources/mind/governed-memory/review-tasks" {
                return Self.jsonResponse(for: request, body: [
                    "items": [
                        [
                            "reviewTaskId": "review-1",
                            "taskType": "claim_review",
                            "state": "open",
                            "entityId": "claim-1",
                            "entityType": "Claim",
                            "title": "Review proposed memory claim",
                            "summary": "User prefers terse summaries.",
                            "priority": 5,
                            "recommendedDecision": "review",
                            "createdAt": "2026-05-16T00:00:00Z"
                        ]
                    ]
                ])
            }

            if path == "/mcp/tools/gmem.create_correction" {
                return Self.jsonResponse(for: request, body: [
                    "correctionId": "corr-1",
                    "targetId": "mem-1",
                    "correctionText": "Actually prefers detailed implementation notes.",
                    "mode": "supersede_not_overwrite",
                    "createdAt": "2026-05-16T00:00:00Z"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let reviewTasks = await client.refreshReviewTasks()
        let outcome = await client.createCorrection(
            OpenMindCorrectionRequest(
                targetID: "mem-1",
                correctionText: "Actually prefers detailed implementation notes.",
                actor: "dBrowser.user",
                source: OpenMindActionSource(
                    product: "dBrowser.swift",
                    runID: nil,
                    pageURLString: "https://example.com",
                    snapshotCommitment: "fnv1a64:abc",
                    prompt: "Summarize"
                ),
                idempotencyKey: "correction-key"
            )
        )
        let correctionBody = capturedRequests.body(for: "/mcp/tools/gmem.create_correction")
        let sourceBody = correctionBody?["source"] as? [String: Any]

        #expect(reviewTasks.first?.id == "review-1")
        #expect(reviewTasks.first?.entityID == "claim-1")
        #expect(outcome.status == .recorded)
        #expect(outcome.correctionID == "corr-1")
        #expect(outcome.targetID == "mem-1")
        #expect(outcome.mode == "supersede_not_overwrite")
        #expect(correctionBody?["targetId"] as? String == "mem-1")
        #expect(correctionBody?["correctionText"] as? String == "Actually prefers detailed implementation notes.")
        #expect(correctionBody?["actor"] as? String == "dBrowser.user")
        #expect(correctionBody?["idempotencyKey"] as? String == "correction-key")
        #expect(sourceBody?["product"] as? String == "dBrowser.swift")
    }

    @MainActor @Test func openMindMemoryClientUsesJSONRPCForReviewTasksAndCorrection() async {
        let capturedRPC = JSONRPCRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "memoryreviewrpc") { request in
            guard request.url?.path == "/mcp" else {
                return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
            }

            let payload = capturedRPC.capture(request) ?? [:]
            let method = payload["method"] as? String
            let id = payload["id"] ?? 1

            if method == "resources/read" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "contents": [
                            [
                                "uri": "mind://governed-memory/review-tasks",
                                "mimeType": "application/json",
                                "text": Self.jsonString([
                                    "items": [
                                        [
                                            "id": "review-rpc",
                                            "taskType": "claim_review",
                                            "state": "open",
                                            "entityId": "claim-rpc",
                                            "title": "Review RPC memory claim",
                                            "summary": "RPC review task"
                                        ]
                                    ]
                                ])
                            ]
                        ]
                    ]
                ])
            }

            if method == "tools/call",
               let params = payload["params"] as? [String: Any],
               params["name"] as? String == "gmem.create_correction" {
                return Self.jsonResponse(for: request, body: [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "structuredContent": [
                            "correctionId": "corr-rpc",
                            "targetId": "mem-rpc",
                            "correctionText": "Corrected via bridge",
                            "mode": "supersede_not_overwrite"
                        ],
                        "isError": false
                    ]
                ])
            }

            return Self.jsonResponse(for: request, status: 400, body: ["error": "unexpected JSON-RPC request"])
        }
        let client = OpenMindMemoryClient(
            configuration: memoryHarness.configuration,
            session: memoryHarness.session
        )

        let reviewTasks = await client.refreshReviewTasks()
        let outcome = await client.createCorrection(
            OpenMindCorrectionRequest(
                targetID: "mem-rpc",
                correctionText: "Corrected via bridge",
                actor: "dBrowser.user",
                source: OpenMindActionSource(
                    product: "dBrowser.swift",
                    runID: nil,
                    pageURLString: nil,
                    snapshotCommitment: nil,
                    prompt: nil
                ),
                idempotencyKey: "correction-rpc"
            )
        )
        let correctionArguments = capturedRPC.toolArguments(named: "gmem.create_correction")

        #expect(reviewTasks.first?.id == "review-rpc")
        #expect(reviewTasks.first?.entityID == "claim-rpc")
        #expect(outcome.status == .recorded)
        #expect(outcome.correctionID == "corr-rpc")
        #expect(correctionArguments?["targetId"] as? String == "mem-rpc")
        #expect(correctionArguments?["correctionText"] as? String == "Corrected via bridge")
        #expect(correctionArguments?["idempotencyKey"] as? String == "correction-rpc")
    }

    @MainActor
    @Test func copilotRequestsOpenMindMemoryBeforeModelRun() async {
        let memoryHarness = Self.makeOpenMindMemorySession(key: "copilotmemory") { request in
            if request.url?.path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "allowed",
                    "allowedScopes": ["profile"],
                    "reason": "allowed",
                    "redactionCount": 0
                ])
            }

            if request.url?.path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, body: [
                    "memories": [
                        [
                            "id": "mem-1",
                            "summary": "Use service-backed context when available.",
                            "source": "BrIAn",
                            "sensitivity": "normal"
                        ]
                    ],
                    "notices": []
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineServices = Self.makeAFMServiceSession(key: "memoryoffline") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: offlineServices.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: offlineServices.configuration,
                session: offlineServices.session
            )
        )
        let model = makeIsolatedBrowserViewModel(
            runtimeBridge: bridge,
            openMindMemoryClient: OpenMindMemoryClient(
                configuration: memoryHarness.configuration,
                session: memoryHarness.session
            )
        )
        model.navigate("https://example.com")

        guard let runID = model.runCopilot(prompt: "Summarize with memory") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)

        #expect(completed)
        #expect(model.latestOpenMindRecall?.memories.first?.id == "mem-1")
        #expect(model.copilotRuns.first?.events.contains { $0.kind == .memoryAccessStarted } == true)
        #expect(model.copilotRuns.first?.events.contains { $0.kind == .memoryAccessCompleted } == true)
    }

    @MainActor
    @Test func copilotRequestsOpenMindStepUpGrantFromRecallIntent() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "copilotstep") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "stepUpRequired",
                    "allowedScopes": [],
                    "reason": "grant required",
                    "redactionCount": 0,
                    "stepUpPrompt": "Confirm memory access"
                ])
            }

            if path == "/mcp/tools/gateway.request_step_up_grant" {
                return Self.jsonResponse(for: request, body: [
                    "requestId": "step-copilot",
                    "status": "pending",
                    "operation": "memory.search",
                    "requestedScopes": ["mind.read.basic"],
                    "purpose": "copilot_recall",
                    "requestedTtl": "PT1H",
                    "justification": "Confirm memory access"
                ])
            }

            if path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, status: 500, body: ["error": "search should wait for step-up"])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineServices = Self.makeAFMServiceSession(key: "copilotstepafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: offlineServices.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: offlineServices.configuration,
                session: offlineServices.session
            )
        )
        let model = makeIsolatedBrowserViewModel(
            runtimeBridge: bridge,
            openMindMemoryClient: OpenMindMemoryClient(
                configuration: memoryHarness.configuration,
                session: memoryHarness.session
            )
        )
        model.navigate("https://example.com/private")

        guard let runID = model.runCopilot(prompt: "Find private memory") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)

        #expect(completed)
        #expect(model.latestOpenMindRecall?.decision.status == .stepUpRequired)
        #expect(model.latestOpenMindStepUpRequest == nil)

        let stepTask = model.requestOpenMindStepUp()
        let requested = await waitForOpenMindStepUpRequest(in: model)
        let stepBody = capturedRequests.body(for: "/mcp/tools/gateway.request_step_up_grant")
        let stepIntentBody = stepBody?["intent"] as? [String: Any]

        #expect(stepTask != nil)
        #expect(requested)
        #expect(model.latestOpenMindStepUpRequest?.requestID == "step-copilot")
        #expect(model.latestOpenMindRecall?.stepUpRequest?.requestID == "step-copilot")
        #expect(capturedRequests.body(for: "/mcp/tools/mind.search_memories") == nil)
        #expect(stepBody?["justification"] as? String == "Confirm memory access")
        #expect(stepIntentBody?["prompt"] as? String == "Find private memory")
        #expect((stepIntentBody?["requestedDomains"] as? [String]) == ["example.com"])
    }

    @MainActor
    @Test func copilotMemoryWritebackRequiresExplicitActionAndRecordsOutcome() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "writeback") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "allowed",
                    "allowedScopes": ["profile"],
                    "reason": "allowed",
                    "redactionCount": 0
                ])
            }

            if path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, body: [
                    "memories": [],
                    "notices": []
                ])
            }

            if path == "/mcp/tools/mind.add_memory" {
                return Self.jsonResponse(for: request, body: [
                    "status": "recorded",
                    "revisionID": "rev-writeback",
                    "message": "recorded"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineServices = Self.makeAFMServiceSession(key: "writebackafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: offlineServices.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: offlineServices.configuration,
                session: offlineServices.session
            )
        )
        let model = makeIsolatedBrowserViewModel(
            runtimeBridge: bridge,
            openMindMemoryClient: OpenMindMemoryClient(
                configuration: memoryHarness.configuration,
                session: memoryHarness.session
            )
        )
        model.navigate("https://example.com")
        let snapshot = PageSnapshot(
            urlString: "https://example.com",
            title: "Example",
            visibleText: "Remember governed page context.",
            headings: ["Memory"],
            links: [],
            buttons: [],
            formControls: [],
            metadata: [:],
            truncated: false,
            redactionCount: 0
        )
        model.applyAutomationResult(
            BrowserAutomationResult(
                requestID: UUID(),
                tabID: model.activeTabID,
                status: .success,
                message: "snapshot",
                pageSnapshot: snapshot
            )
        )

        guard let runID = model.runCopilot(prompt: "Summarize and remember") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)

        #expect(completed)
        #expect(capturedRequests.body(for: "/mcp/tools/mind.add_memory") == nil)

        let outcome = await model.writeBackOpenMindMemory(for: runID)
        let writebackBody = capturedRequests.body(for: "/mcp/tools/mind.add_memory")
        let requestBody = writebackBody?["request"] as? [String: Any]
        let events = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(outcome.status == .recorded)
        #expect(outcome.revisionID == "rev-writeback")
        #expect(model.latestOpenMindWriteback == outcome)
        #expect(requestBody?["runID"] as? String == runID.uuidString)
        #expect(requestBody?["prompt"] as? String == "Summarize and remember")
        #expect(requestBody?["pageURLString"] as? String == "https://example.com")
        #expect(requestBody?["source"] as? String == "dBrowser.copilot")
        #expect((requestBody?["summary"] as? String)?.contains("Summarize and remember") == true)
        #expect((requestBody?["snapshotCommitment"] as? String)?.hasPrefix("fnv1a64:") == true)
        #expect(requestBody?["idempotencyKey"] as? String == "copilot-\(runID.uuidString)-writeback")
        #expect(events.contains(.memoryWritebackRequested))
        #expect(events.contains(.memoryWritebackRecorded))
    }

    @MainActor
    @Test func copilotMemoryWritebackRespectsProtectivePosture() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "protective") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/capabilities" {
                return Self.jsonResponse(for: request, body: [
                    "available": true,
                    "capabilities": ["mind.search_memories", "mind.add_memory", "posture.get"],
                    "posture": "protective",
                    "message": "ready"
                ])
            }

            if path == "/mcp/resources/mind/continuity" {
                return Self.jsonResponse(for: request, body: [
                    "summary": "Continuity ready",
                    "pendingStepUps": 0
                ])
            }

            if path == "/mcp/tools/posture.get" {
                return Self.jsonResponse(for: request, body: [
                    "mode": "protective",
                    "userMessage": "Protective posture blocks memory writeback.",
                    "allowsMemoryWriteback": false,
                    "requiresExplicitConfirmation": true
                ])
            }

            if path == "/mcp/tools/gateway.evaluate_access_intent" {
                return Self.jsonResponse(for: request, body: [
                    "status": "allowed",
                    "allowedScopes": ["profile"],
                    "reason": "allowed",
                    "redactionCount": 0
                ])
            }

            if path == "/mcp/tools/mind.search_memories" {
                return Self.jsonResponse(for: request, body: [
                    "memories": [],
                    "notices": []
                ])
            }

            if path == "/mcp/tools/mind.add_memory" {
                return Self.jsonResponse(for: request, status: 500, body: ["error": "writeback should be blocked by posture"])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let offlineServices = Self.makeAFMServiceSession(key: "protectiveafm") { request in
            Self.jsonResponse(for: request, status: 503, body: ["ok": false])
        }
        let bridge = MobileRuntimeBridge(
            configuration: RuntimeBridgeConfiguration(afmServices: offlineServices.configuration),
            afmServicesClient: AFMServicesClient(
                configuration: offlineServices.configuration,
                session: offlineServices.session
            )
        )
        let model = makeIsolatedBrowserViewModel(
            runtimeBridge: bridge,
            openMindMemoryClient: OpenMindMemoryClient(
                configuration: memoryHarness.configuration,
                session: memoryHarness.session
            )
        )

        await model.refreshRuntimeBridgeStatus()
        model.navigate("https://example.com")
        guard let runID = model.runCopilot(prompt: "Summarize without writeback") else {
            Issue.record("Expected Copilot run ID")
            return
        }
        let completed = await waitForCopilotRun(in: model, runID, status: .completed)
        let outcome = await model.writeBackOpenMindMemory(for: runID)
        let events = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(completed)
        #expect(model.openMindPostureState.status == .available)
        #expect(model.openMindPostureState.allowsMemoryWriteback == false)
        #expect(outcome.status == .denied)
        #expect(outcome.message == "Protective posture blocks memory writeback.")
        #expect(capturedRequests.body(for: "/mcp/tools/mind.add_memory") == nil)
        #expect(events.contains(.memoryWritebackDenied))
    }

    @MainActor
    @Test func copilotOpenMindCorrectionRecordsOutcomeAndEvents() async {
        let capturedRequests = JSONRequestCapture()
        let memoryHarness = Self.makeOpenMindMemorySession(key: "correctionvm") { request in
            let path = request.url?.path ?? ""
            capturedRequests.capture(request)

            if path == "/mcp/resources/mind/governed-memory/review-tasks" {
                return Self.jsonResponse(for: request, body: [
                    "items": [
                        [
                            "id": "review-after-correction",
                            "taskType": "claim_review",
                            "state": "open",
                            "entityId": "claim-after",
                            "title": "Review updated memory"
                        ]
                    ]
                ])
            }

            if path == "/mcp/tools/gmem.create_correction" {
                return Self.jsonResponse(for: request, body: [
                    "correctionId": "corr-vm",
                    "targetId": "mem-1",
                    "correctionText": "Correction from Copilot panel",
                    "mode": "supersede_not_overwrite"
                ])
            }

            return Self.jsonResponse(for: request, status: 404, body: ["error": "not found"])
        }
        let model = makeIsolatedBrowserViewModel(
            openMindMemoryClient: OpenMindMemoryClient(
                configuration: memoryHarness.configuration,
                session: memoryHarness.session
            )
        )
        model.navigate("https://example.com")
        let runID = UUID()
        model.copilotRuns = [
            CopilotRun(
                id: runID,
                prompt: "Summarize",
                activeTabID: model.activeTabID,
                targetURLString: "https://example.com",
                status: .completed
            )
        ]

        let task = model.requestOpenMindCorrection(
            targetID: "mem-1",
            correctionText: "Correction from Copilot panel"
        )
        if let task {
            await task.value
        }
        let correctionBody = capturedRequests.body(for: "/mcp/tools/gmem.create_correction")
        let sourceBody = correctionBody?["source"] as? [String: Any]
        let events = model.copilotRuns.first(where: { $0.id == runID })?.events.map(\.kind) ?? []

        #expect(task != nil)
        #expect(model.latestOpenMindCorrection?.correctionID == "corr-vm")
        #expect(model.latestOpenMindCorrection?.status == .recorded)
        #expect(model.openMindReviewTasks.first?.id == "review-after-correction")
        #expect(correctionBody?["targetId"] as? String == "mem-1")
        #expect(correctionBody?["correctionText"] as? String == "Correction from Copilot panel")
        #expect(correctionBody?["actor"] as? String == "dBrowser.user")
        #expect((correctionBody?["idempotencyKey"] as? String)?.hasPrefix("correction-") == true)
        #expect(sourceBody?["product"] as? String == "dBrowser.swift")
        #expect(sourceBody?["runID"] as? String == runID.uuidString)
        #expect(events.contains(.memoryCorrectionRequested))
        #expect(events.contains(.memoryCorrectionRecorded))
    }

    @MainActor
    @Test func panelSelectionShowsPanelsAndNavigationReturnsToBrowser() {
        let model = BrowserViewModel()

        model.selectPanel(.history)
        #expect(model.selectedPanel == .history)

        model.selectPanel(.bookmarks)
        #expect(model.selectedPanel == .bookmarks)

        model.selectPanel(.wallet)
        #expect(model.selectedPanel == .wallet)

        model.selectPanel(.mcp)
        #expect(model.selectedPanel == .mcp)

        model.selectPanel(.advantage)
        #expect(model.selectedPanel == .advantage)

        model.navigate("example.com")
        #expect(model.selectedPanel == nil)

        model.selectPanel(.runtime)
        model.newTab()
        #expect(model.selectedPanel == nil)
        #expect(model.activeTab?.urlString == BrowserURLResolver.homeURLString)
    }

    @Test func walletPanelIsPrimarySurface() {
        #expect(BrowserPanel.allCases.contains(.wallet))
        #expect(BrowserPanel.wallet.title == "Wallet & Identity")
        #expect(BrowserPanel.wallet.systemImage == "wallet.pass")
        #expect(BrowserPanel.wallet.tier == .primary)
        #expect(BrowserPanel.primaryPanels.contains(.wallet))
        #expect(!BrowserPanel.advancedPanels.contains(.wallet))
        // The three primary surfaces are Browser (nil selection), Copilot, and Wallet & Identity.
        #expect(BrowserPanel.primaryPanels == [.copilot, .wallet])
        #expect(BrowserPanel.advancedPanels == [.history, .bookmarks, .mcp, .a2ui, .advantage, .localLLM, .runtime])
    }

    @Test func advantagePanelIsTopLevelNavigationAndTracksStrawberryBaseline() {
        let scorecard = BrowserAdvantageScorecard.current
        let baseline = Set(BrowserAdvantageCategory.strawberryBaseline)

        #expect(BrowserPanel.allCases.contains(.advantage))
        #expect(BrowserPanel.advantage.title == "Advantage")
        #expect(BrowserPanel.advantage.systemImage == "chart.line.uptrend.xyaxis")
        #expect(BrowserPanel.advancedPanels.contains(.advantage))
        #expect(BrowserPanel.advantage.tier == .advanced)
        #expect(scorecard.trackedStrawberryBaselineCategories == baseline)
        #expect(scorecard.capabilities.count > BrowserAdvantageCategory.strawberryBaseline.count)
        #expect(scorecard.exceededCount > scorecard.matchedCount)
        #expect(scorecard.gapCount == 0)
        #expect(scorecard.baselineCoverageText == "12/12 Strawberry areas tracked")
        #expect(scorecard.capabilities.contains { $0.id == "local-first-model-switching" && $0.status == .exceeds })
        #expect(scorecard.capabilities.contains { $0.id == "dweb-chain-trust" && $0.status == .exceeds })
        #expect(scorecard.capabilities.contains { $0.id == "browser-switch-import" && $0.status == .matches })
        #expect(scorecard.capabilities.contains { $0.id == "companion-onboarding" && $0.status == .exceeds })
        #expect(scorecard.capabilities.contains { $0.id == "research-source-ledger" && $0.status == .matches })
        #expect(scorecard.capabilities.contains { $0.id == "workflow-recurring-automation" && $0.status == .matches })
        #expect(scorecard.capabilities.contains { $0.id == "benchmarks-public-runner" && $0.status == .matches && $0.action?.targetPanel == .advantage })
        #expect(scorecard.capabilities.contains { $0.id == "eudi-agentic-payments" && $0.status == .exceeds && $0.action?.targetPanel == .wallet })
    }

    @Test func browserImportPlannerSeparatesSafeDataFromSecrets() {
        let chromePlan = BrowserImportPlanner.plan(source: .chrome)
        let safariPlan = BrowserImportPlanner.plan(source: .safari)

        #expect(chromePlan.readyItems.map(\.kind).contains(.bookmarks))
        #expect(chromePlan.readyItems.map(\.kind).contains(.history))
        #expect(chromePlan.approvalItems.map(\.kind).contains(.passwords))
        #expect(chromePlan.approvalItems.map(\.kind).contains(.cookies))
        #expect(chromePlan.canCompleteWithoutSecrets)
        #expect(chromePlan.summary == "Chrome: 2 ready, 2 approval, 0 unavailable")
        #expect(safariPlan.unavailableItems.map(\.kind).contains(.cookies))
    }

    @Test func companionOnboardingRecommendsAppsMemoryConnectorsModelsAndWorkflows() {
        let profile = BrowserCompanionOnboardingProfile.localResearcher
        let recommendations = BrowserCompanionOnboardingEngine.recommendations(for: profile)
        let kinds = Set(recommendations.map(\.kind))
        let targetPanels = Set(recommendations.map(\.targetPanel))

        #expect(kinds.contains(.a2uiApp))
        #expect(kinds.contains(.workflow))
        #expect(kinds.contains(.connector))
        #expect(kinds.contains(.modelMode))
        #expect(kinds.contains(.memoryPosture))
        #expect(targetPanels.contains(.a2ui))
        #expect(targetPanels.contains(.mcp))
        #expect(targetPanels.contains(.localLLM))
        #expect(recommendations.contains { $0.title == "Keep default runs local" })
    }

    @Test func researchLedgerExportsDatedCitationsMarkdownAndCSV() {
        let retrievedAt = Date(timeIntervalSince1970: 1_767_225_600)
        let ledger = BrowserResearchLedger(
            topic: "AI browser comparison",
            entries: [
                BrowserResearchSourceEntry(
                    title: "Strawberry benchmarks",
                    urlString: "https://strawberrybrowser.com/benchmarks/spec",
                    retrievedAt: retrievedAt,
                    evidence: "12 workflow benchmark specification",
                    confidence: .high
                ),
                BrowserResearchSourceEntry(
                    title: "dBrowser Advantage",
                    urlString: "about:advantage",
                    retrievedAt: retrievedAt,
                    evidence: "Local scorecard, no open Strawberry gaps",
                    confidence: .medium
                )
            ]
        )

        #expect(ledger.datedCitations.count == 2)
        #expect(ledger.datedCitations.first?.contains("https://strawberrybrowser.com/benchmarks/spec") == true)
        #expect(ledger.markdownExport.contains("# AI browser comparison"))
        #expect(ledger.markdownExport.contains("Confidence: high"))
        #expect(ledger.csvExport.contains("\"Local scorecard, no open Strawberry gaps\""))
    }

    @Test func recurringWorkflowAutomationHandlesSchedulesTriggersCooldownsAndNotifications() {
        let now = Date(timeIntervalSince1970: 20_000)
        let dueByInterval = BrowserRecurringWorkflowAutomation(
            title: "Refresh comparison",
            promptTemplate: "Check source changes",
            schedule: .interval(hours: 2),
            triggers: [],
            cooldownHours: 1,
            notificationsEnabled: true,
            approvalMode: .allowLowRisk,
            lastRunAt: now.addingTimeInterval(-3 * 3_600)
        )
        let blockedByCooldown = BrowserRecurringWorkflowAutomation(
            title: "Cooldown",
            promptTemplate: "Too soon",
            schedule: .interval(hours: 1),
            triggers: [.init(kind: .siteVisit, pattern: "example.com")],
            cooldownHours: 2,
            lastRunAt: now.addingTimeInterval(-30 * 60)
        )
        let dueByTrigger = BrowserRecurringWorkflowAutomation(
            title: "Site trigger",
            promptTemplate: "Summarize visit",
            schedule: .manual,
            triggers: [.init(kind: .siteVisit, pattern: "example.com")],
            cooldownHours: 0
        )

        let due = BrowserWorkflowAutomationScheduler.dueAutomations(
            [dueByInterval, blockedByCooldown, dueByTrigger],
            now: now,
            pageURLString: "https://example.com/pricing",
            pageEvent: nil
        )

        #expect(due.map(\.title).contains("Refresh comparison"))
        #expect(due.map(\.title).contains("Site trigger"))
        #expect(!due.map(\.title).contains("Cooldown"))
        #expect(dueByInterval.notificationsEnabled)
        #expect(dueByInterval.approvalMode == .allowLowRisk)
    }

    @Test func strawberryBenchmarkSuiteSupportsTwelveTaskAndCredentialConstrainedRuns() {
        let allTasks = StrawberryBenchmarkSuite.tasks(includeCredentialRequired: true)
        let publicTasks = StrawberryBenchmarkSuite.tasks(includeCredentialRequired: false)
        let results = publicTasks.map {
            StrawberryBenchmarkTaskResult(
                task: $0,
                status: .completed,
                score: 96,
                durationSeconds: 120,
                artifactSummary: $0.expectedArtifact
            )
        } + [
            StrawberryBenchmarkTaskResult(
                task: allTasks.first { $0.id == "B10" }!,
                status: .blocked,
                score: 0,
                durationSeconds: 0,
                artifactSummary: "Skipped",
                blocker: "Sales Navigator credentials not configured"
            )
        ]
        let report = StrawberryBenchmarkReport(results: results)

        #expect(allTasks.count == 12)
        #expect(publicTasks.count == 9)
        #expect(publicTasks.allSatisfy { $0.credentialRequirement == .none })
        #expect(report.completedCount == 9)
        #expect(report.blockedCount == 1)
        #expect(report.averageScore == 96)
        #expect(report.totalDurationSeconds == 1_080)
        #expect(report.publicSummary == "9/10 complete, 1 blocked, avg 96.0")
    }

    @Test func eudiWalletPresentationRequiresStepUpAndMinimizesDisclosure() {
        let request = AgenticPaymentFixtures.eudiRequest
        let document = AgenticPaymentFixtures.eudiDocument
        let unauthenticated = EUDIWalletDecisionEngine.decide(
            request: request,
            documents: [document],
            approvedClaimNames: ["age_over_18"],
            userAuthenticated: false,
            now: AgenticPaymentFixtures.now
        )
        let approved = EUDIWalletDecisionEngine.decide(
            request: request,
            documents: [document],
            approvedClaimNames: ["age_over_18"],
            userAuthenticated: true,
            now: AgenticPaymentFixtures.now
        )

        #expect(EUDIWalletProfile.dbrowserReference.mode == .walletCompatibleClient)
        #expect(!EUDIWalletProfile.dbrowserReference.canUseForProductionWalletProviderClaim)
        #expect(unauthenticated.state == .stepUpRequired)
        #expect(approved.state == .approved)
        #expect(approved.disclosedClaims == ["age_over_18": "true"])
        #expect(approved.omittedClaims.contains("country"))
        #expect(!approved.receiptHash.isEmpty)
    }

    @Test func eudiEmailCredentialImporterAcceptsCliwalletVerifiedEmailForHumanWallet() {
        let rawImport = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            now: AgenticPaymentFixtures.now
        )
        let responseImport = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: AgenticPaymentFixtures.cliwalletVerifiedEmailResponseJSON,
            now: AgenticPaymentFixtures.now
        )
        let jwtOnlyImport = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: Data("header.payload.signature".utf8),
            now: AgenticPaymentFixtures.now
        )

        #expect(EUDIWalletProfile.dbrowserReference.supportedCredentialKinds.contains(.verifiedEmail))
        #expect(rawImport.status == .imported)
        #expect(rawImport.document?.kind == .verifiedEmail)
        #expect(rawImport.document?.claims["email"] == "johan.sellstrom@iproov.com")
        #expect(rawImport.document?.claims["email_verified"] == "true")
        #expect(rawImport.document?.claims["subject_type"] == "user")
        #expect(rawImport.document?.claims["source_credential_hash"]?.isEmpty == false)
        #expect(responseImport.status == .imported)
        #expect(responseImport.document?.id == rawImport.document?.id)
        #expect(jwtOnlyImport.status == .unsupportedFormat)
        // The bare JSON envelope path is explicitly labeled as not cryptographically verified.
        #expect(rawImport.signatureTrust == .unverifiedEnvelope)
        #expect(rawImport.isCryptographicallyVerified == false)
        #expect(rawImport.document?.claims["signature_trust"] == "unverified_envelope")
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func makeES256VCJWT(
        credentialJSON: Data,
        keyID: String,
        privateKey: P256.Signing.PrivateKey,
        extraClaims: [String: Any] = [:]
    ) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
        let credentialObject = try! JSONSerialization.jsonObject(with: credentialJSON) as! [String: Any]
        // W3C VC-JWT requires the JWT `iss` to equal the credential issuer.
        let issuer = credentialObject["issuer"] as? String ?? "https://issuer.example"
        var payloadObject: [String: Any] = ["iss": issuer, "vc": credentialObject]
        payloadObject.merge(extraClaims) { _, new in new }
        let payload = try! JSONSerialization.data(withJSONObject: payloadObject)
        let headerSegment = base64URLEncode(header)
        let payloadSegment = base64URLEncode(payload)
        let signingInput = Data("\(headerSegment).\(payloadSegment)".utf8)
        let signature = try! privateKey.signature(for: signingInput)
        let signatureSegment = base64URLEncode(signature.rawRepresentation)
        return "\(headerSegment).\(payloadSegment).\(signatureSegment)"
    }

    @Test func eudiImportsVerifiedEmailFromIssuerSignedVCJWT() {
        let issuerKey = P256.Signing.PrivateKey()
        let trustStore = EUDIIssuerTrustStore(keys: [
            EUDIIssuerKey(
                keyID: "issuer-key-1",
                issuer: "https://verifiedemail.showntell.dev",
                algorithm: .es256,
                publicKeyRaw: issuerKey.publicKey.rawRepresentation
            )
        ])
        let jwt = Self.makeES256VCJWT(
            credentialJSON: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            keyID: "issuer-key-1",
            privateKey: issuerKey
        )

        let result = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: Data(jwt.utf8),
            trustStore: trustStore,
            now: AgenticPaymentFixtures.now
        )

        #expect(result.status == .imported)
        #expect(result.signatureTrust == .issuerSignatureVerified)
        #expect(result.isCryptographicallyVerified)
        #expect(result.document?.claims["email"] == "johan.sellstrom@iproov.com")
        #expect(result.document?.claims["signature_trust"] == "issuer_signature_verified")
    }

    @Test func eudiImportsPinnedCliwalletVerifiedEmailVCJWTFromTrustedRegistry() {
        let trustedKey = EUDITrustedIssuerRegistry.verifiedEmailTrustStore.key(
            forID: EUDITrustedIssuerRegistry.verifiedEmailKeyID
        )
        let result = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: AgenticPaymentFixtures.cliwalletVerifiedEmailVCJWTData,
            trustStore: EUDITrustedIssuerRegistry.verifiedEmailTrustStore,
            now: AgenticPaymentFixtures.now
        )
        let snapshot = WalletControlPlaneSnapshot.defaultDelegation()
        let verifiedEmail = snapshot.verifiedEmailCredentials.first

        #expect(trustedKey?.issuer == EUDITrustedIssuerRegistry.verifiedEmailIssuer)
        #expect(trustedKey?.source == .pinnedRepositoryConfiguration)
        #expect(result.status == .imported)
        #expect(result.isCryptographicallyVerified)
        #expect(result.document?.isIssuerSignatureVerified == true)
        #expect(result.document?.claims["signature_trust"] == "issuer_signature_verified")
        #expect(verifiedEmail?.isIssuerSignatureVerified == true)
        #expect(snapshot.activeAgentIdentityCredentials.count == 1)
    }

    @Test func eudiUnverifiedEmailEnvelopeDoesNotAuthorizeAgentIdentityIssuance() {
        let rawImport = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            now: AgenticPaymentFixtures.now
        )
        guard let rawDocument = rawImport.document else {
            Issue.record("Expected raw email credential import document")
            return
        }
        var snapshot = WalletControlPlaneSnapshot.defaultDelegation()
        guard let human = snapshot.humanPrincipals.first,
              let agent = snapshot.agentPrincipals.first else {
            Issue.record("Expected default human and agent principals")
            return
        }
        snapshot.humanIdentityCredentials = [rawDocument]
        snapshot.agentIdentityCredentials = []

        let request = EUDIAgentIdentityIssuanceRequest(
            id: "unsigned-agent-email",
            humanPrincipalID: human.id,
            agentPrincipalID: agent.id,
            sourceCredentialID: rawDocument.id,
            requestedClaims: ["email", "email_verified"],
            relyingPartyID: "dbrowser.local",
            relyingPartyName: "dBrowser Wallet Control Plane",
            protocolName: .manualApproval,
            purpose: "Agent identity bootstrap",
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(600),
            requiresRootCredentialAccess: false
        )
        let result = EUDIWalletIdentityIssuer.issueAgentIdentity(
            request,
            snapshot: snapshot,
            now: AgenticPaymentFixtures.now
        )

        #expect(rawImport.signatureTrust == .unverifiedEnvelope)
        #expect(rawDocument.isIssuerSignatureVerified == false)
        #expect(snapshot.verifiedEmailCredentials.isEmpty)
        #expect(result.state == .denied)
        #expect(result.credential == nil)
        #expect(result.reasons.contains { $0.contains("issuer VC-JWT signature trust") })
    }

    @Test func eudiRejectsVCJWTSignedByUntrustedKey() {
        let issuerKey = P256.Signing.PrivateKey()
        let attackerKey = P256.Signing.PrivateKey()
        // Trust store advertises issuer-key-1 but with a DIFFERENT public key than the signer used.
        let trustStore = EUDIIssuerTrustStore(keys: [
            EUDIIssuerKey(
                keyID: "issuer-key-1",
                issuer: "https://verifiedemail.showntell.dev",
                algorithm: .es256,
                publicKeyRaw: issuerKey.publicKey.rawRepresentation
            )
        ])
        let forgedJWT = Self.makeES256VCJWT(
            credentialJSON: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            keyID: "issuer-key-1",
            privateKey: attackerKey
        )

        let result = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: Data(forgedJWT.utf8),
            trustStore: trustStore,
            now: AgenticPaymentFixtures.now
        )

        #expect(result.status == .signatureRejected)
        #expect(result.document == nil)
        #expect(result.isCryptographicallyVerified == false)
    }

    @Test func eudiRejectsVCJWTWithTamperedPayload() {
        let issuerKey = P256.Signing.PrivateKey()
        let trustStore = EUDIIssuerTrustStore(keys: [
            EUDIIssuerKey(
                keyID: "issuer-key-1",
                issuer: "https://verifiedemail.showntell.dev",
                algorithm: .es256,
                publicKeyRaw: issuerKey.publicKey.rawRepresentation
            )
        ])
        let jwt = Self.makeES256VCJWT(
            credentialJSON: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            keyID: "issuer-key-1",
            privateKey: issuerKey
        )
        // Flip the trailing character of the payload segment so the signature no longer matches.
        var segments = jwt.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let payload = segments[1]
        let mutatedLast: Character = payload.last == "A" ? "B" : "A"
        segments[1] = String(payload.dropLast()) + String(mutatedLast)
        let tamperedJWT = segments.joined(separator: ".")

        let result = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: Data(tamperedJWT.utf8),
            trustStore: trustStore,
            now: AgenticPaymentFixtures.now
        )

        #expect(result.status == .signatureRejected)
        #expect(result.isCryptographicallyVerified == false)
    }

    @Test func eudiRejectsVCJWTWithUnknownKeyID() {
        let issuerKey = P256.Signing.PrivateKey()
        let trustStore = EUDIIssuerTrustStore(keys: [
            EUDIIssuerKey(
                keyID: "issuer-key-1",
                issuer: "https://verifiedemail.showntell.dev",
                algorithm: .es256,
                publicKeyRaw: issuerKey.publicKey.rawRepresentation
            )
        ])
        let jwt = Self.makeES256VCJWT(
            credentialJSON: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            keyID: "unknown-key-99",
            privateKey: issuerKey
        )

        let result = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: Data(jwt.utf8),
            trustStore: trustStore,
            now: AgenticPaymentFixtures.now
        )

        #expect(result.status == .signatureRejected)
    }

    @Test func eudiRejectsVCJWTFromKeyNotAuthoritativeForIssuer() {
        let issuerKey = P256.Signing.PrivateKey()
        // The key id is trusted and the signature is valid, but the key is authoritative for a
        // DIFFERENT issuer than the one the credential claims.
        let trustStore = EUDIIssuerTrustStore(keys: [
            EUDIIssuerKey(
                keyID: "issuer-key-1",
                issuer: "https://other-issuer.example",
                algorithm: .es256,
                publicKeyRaw: issuerKey.publicKey.rawRepresentation
            )
        ])
        let jwt = Self.makeES256VCJWT(
            credentialJSON: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            keyID: "issuer-key-1",
            privateKey: issuerKey
        )

        let result = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: Data(jwt.utf8),
            trustStore: trustStore,
            now: AgenticPaymentFixtures.now
        )

        #expect(result.status == .signatureRejected)
        #expect(result.isCryptographicallyVerified == false)
    }

    @Test func eudiRejectsExpiredVCJWT() {
        let issuerKey = P256.Signing.PrivateKey()
        let trustStore = EUDIIssuerTrustStore(keys: [
            EUDIIssuerKey(
                keyID: "issuer-key-1",
                issuer: "https://verifiedemail.showntell.dev",
                algorithm: .es256,
                publicKeyRaw: issuerKey.publicKey.rawRepresentation
            )
        ])
        // Valid signature, but the JWS `exp` is one hour before `now`.
        let expiredAt = AgenticPaymentFixtures.now.timeIntervalSince1970 - 3600
        let jwt = Self.makeES256VCJWT(
            credentialJSON: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            keyID: "issuer-key-1",
            privateKey: issuerKey,
            extraClaims: ["exp": expiredAt]
        )

        let result = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: Data(jwt.utf8),
            trustStore: trustStore,
            now: AgenticPaymentFixtures.now
        )

        #expect(result.status == .expired)
        #expect(result.isCryptographicallyVerified == false)
    }

    @Test func eudiRejectsNotYetValidVCJWT() {
        let issuerKey = P256.Signing.PrivateKey()
        let trustStore = EUDIIssuerTrustStore(keys: [
            EUDIIssuerKey(
                keyID: "issuer-key-1",
                issuer: "https://verifiedemail.showntell.dev",
                algorithm: .es256,
                publicKeyRaw: issuerKey.publicKey.rawRepresentation
            )
        ])
        // Valid signature, but the JWS `nbf` is one hour after `now`.
        let notBefore = AgenticPaymentFixtures.now.timeIntervalSince1970 + 3600
        let jwt = Self.makeES256VCJWT(
            credentialJSON: AgenticPaymentFixtures.cliwalletVerifiedEmailCredentialJSON,
            keyID: "issuer-key-1",
            privateKey: issuerKey,
            extraClaims: ["nbf": notBefore]
        )

        let result = EUDIEmailCredentialImporter.importHumanVerifiedEmail(
            from: Data(jwt.utf8),
            trustStore: trustStore,
            now: AgenticPaymentFixtures.now
        )

        #expect(result.status == .expired)
        #expect(result.isCryptographicallyVerified == false)
    }

    @Test func eudiWalletIdentityIssuerIssuesScopedVerifiedEmailToAgent() {
        let snapshot = WalletControlPlaneSnapshot.defaultDelegation()
        guard let human = snapshot.humanPrincipals.first,
              let agent = snapshot.agentPrincipals.first,
              let sourceCredential = snapshot.verifiedEmailCredentials.first else {
            Issue.record("Expected human, agent, and verified email credential")
            return
        }
        let request = EUDIAgentIdentityIssuanceRequest(
            id: "unit-agent-email",
            humanPrincipalID: human.id,
            agentPrincipalID: agent.id,
            sourceCredentialID: sourceCredential.id,
            requestedClaims: ["email", "email_verified"],
            relyingPartyID: "dbrowser.local",
            relyingPartyName: "dBrowser Wallet Control Plane",
            protocolName: .manualApproval,
            purpose: "Agent identity bootstrap",
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(600),
            requiresRootCredentialAccess: false
        )

        let result = EUDIWalletIdentityIssuer.issueAgentIdentity(
            request,
            snapshot: snapshot,
            now: AgenticPaymentFixtures.now
        )

        #expect(result.state == .issued)
        #expect(result.isIssued)
        #expect(result.decision.grantID == "grant-agent-verified-email")
        #expect(result.credential?.claims == ["email": "johan.sellstrom@iproov.com", "email_verified": "true"])
        #expect(result.credential?.claims["holder_did"] == nil)
        #expect(result.credential?.exposesRootCredential == false)
        #expect(result.receipt.status == .approved)
        #expect(result.receipt.selectiveDisclosureClaims == ["email", "email_verified"])
        #expect(!result.receipt.exposesRootCredential)
        #expect(result.receipt.summary.contains("not the human email VC"))
    }

    @Test func eudiWalletIdentityIssuerDeniesMissingOrRevokedVerifiedEmailGrant() {
        let snapshot = WalletControlPlaneSnapshot.defaultDelegation()
        guard let human = snapshot.humanPrincipals.first,
              let agent = snapshot.agentPrincipals.first,
              let sourceCredential = snapshot.verifiedEmailCredentials.first else {
            Issue.record("Expected human, agent, and verified email credential")
            return
        }
        let request = EUDIAgentIdentityIssuanceRequest(
            id: "unit-agent-email-denied",
            humanPrincipalID: human.id,
            agentPrincipalID: agent.id,
            sourceCredentialID: sourceCredential.id,
            requestedClaims: ["email", "email_verified"],
            relyingPartyID: "dbrowser.local",
            relyingPartyName: "dBrowser Wallet Control Plane",
            protocolName: .manualApproval,
            purpose: "Agent identity bootstrap",
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(600),
            requiresRootCredentialAccess: false
        )
        let missingGrantSnapshot = WalletControlPlaneSnapshot(
            principals: snapshot.principals,
            grants: snapshot.grants.filter { $0.id != "grant-agent-verified-email" },
            receipts: snapshot.receipts,
            humanIdentityCredentials: snapshot.humanIdentityCredentials,
            agentIdentityCredentials: snapshot.agentIdentityCredentials
        )
        var revokedSnapshot = snapshot
        if let grantIndex = revokedSnapshot.grants.firstIndex(where: { $0.id == "grant-agent-verified-email" }) {
            revokedSnapshot.grants[grantIndex].revokedAt = AgenticPaymentFixtures.now
        }
        var rootCredentialRequest = request
        rootCredentialRequest.requiresRootCredentialAccess = true

        let missingGrant = EUDIWalletIdentityIssuer.issueAgentIdentity(
            request,
            snapshot: missingGrantSnapshot,
            now: AgenticPaymentFixtures.now
        )
        let revokedGrant = EUDIWalletIdentityIssuer.issueAgentIdentity(
            request,
            snapshot: revokedSnapshot,
            now: AgenticPaymentFixtures.now
        )
        let rootCredential = EUDIWalletIdentityIssuer.issueAgentIdentity(
            rootCredentialRequest,
            snapshot: snapshot,
            now: AgenticPaymentFixtures.now
        )

        #expect(missingGrant.state == .denied)
        #expect(missingGrant.decision.kind == .deny)
        #expect(missingGrant.receipt.status == .denied)
        #expect(revokedGrant.state == .revoked)
        #expect(revokedGrant.receipt.status == .revoked)
        #expect(rootCredential.state == .rootAccessDenied)
        #expect(rootCredential.receipt.status == .denied)
        #expect(rootCredential.credential == nil)
    }

    @Test func visaTrustedAgentVerifierChecksKeysHeadersAlgorithmsAndPaymentContext() {
        let request = AgenticPaymentFixtures.visaRequest
        let verified = VisaTrustedAgentVerifier.verify(
            request,
            trustedKeyIDs: ["visa-key-1"],
            now: AgenticPaymentFixtures.now
        )
        var missingPaymentContext = request
        missingPaymentContext.paymentContainerHash = nil
        let missingPayment = VisaTrustedAgentVerifier.verify(
            missingPaymentContext,
            trustedKeyIDs: ["visa-key-1"],
            now: AgenticPaymentFixtures.now
        )
        var unsupportedAlgorithm = request
        unsupportedAlgorithm.signature.algorithm = "hmac-sha256"
        let unsupported = VisaTrustedAgentVerifier.verify(
            unsupportedAlgorithm,
            trustedKeyIDs: ["visa-key-1"],
            now: AgenticPaymentFixtures.now
        )

        #expect(verified.status == .verified)
        #expect(verified.isVerified)
        #expect(VisaTrustedAgentVerifier.verify(request, trustedKeyIDs: [], now: AgenticPaymentFixtures.now).status == .unknownKey)
        #expect(missingPayment.status == .missingPaymentContext)
        #expect(unsupported.status == .unsupportedAlgorithm)
    }

    @Test func visaTrustedAgentVerifierCryptographicallyVerifiesSignatureBytes() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        var request = AgenticPaymentFixtures.visaRequest
        request.signature.keyID = "visa-ed-key"
        request.signature.algorithm = "ed25519"

        let keyStore = VisaTrustedAgentKeyStore(keys: [
            VisaTrustedAgentKey(
                keyID: "visa-ed-key",
                algorithm: "ed25519",
                publicKeyRaw: signingKey.publicKey.rawRepresentation
            )
        ])

        let signingBase = VisaTrustedAgentVerifier.canonicalSigningBase(for: request)
        request.signature.signatureValue = try signingKey.signature(for: signingBase).base64EncodedString()

        // A genuine signature over the canonical base verifies.
        #expect(VisaTrustedAgentVerifier.verify(request, keyStore: keyStore, now: AgenticPaymentFixtures.now).status == .verified)

        // Tampering the body digest changes the signing base, so the bytes no longer validate.
        var tampered = request
        tampered.bodyDigest += "0"
        #expect(VisaTrustedAgentVerifier.verify(tampered, keyStore: keyStore, now: AgenticPaymentFixtures.now).status == .signatureInvalid)

        // An empty key store cannot recognize the key.
        #expect(VisaTrustedAgentVerifier.verify(request, keyStore: VisaTrustedAgentKeyStore(), now: AgenticPaymentFixtures.now).status == .unknownKey)

        // Without signature bytes there is nothing to verify.
        var noSignature = request
        noSignature.signature.signatureValue = nil
        #expect(VisaTrustedAgentVerifier.verify(noSignature, keyStore: keyStore, now: AgenticPaymentFixtures.now).status == .missingSignatureValue)

        // RSA-PSS is recognized but not locally verifiable, so it never reaches verified.
        var rsa = request
        rsa.signature.algorithm = "rsa-pss-sha256"
        let rsaKeyStore = VisaTrustedAgentKeyStore(keys: [
            VisaTrustedAgentKey(
                keyID: "visa-ed-key",
                algorithm: "rsa-pss-sha256",
                publicKeyRaw: signingKey.publicKey.rawRepresentation
            )
        ])
        #expect(VisaTrustedAgentVerifier.verify(rsa, keyStore: rsaKeyStore, now: AgenticPaymentFixtures.now).status == .unsupportedAlgorithm)
    }

    @Test func acpCheckoutBindsBasketAndDoesNotStoreRawPaymentCredentials() {
        let checkout = AgenticPaymentFixtures.acpCheckout

        #expect(checkout.totalMinorUnits == 1_999)
        #expect(checkout.isReadyForPayment)
        #expect(checkout.delegatedPaymentToken?.basketHash == checkout.basketHash)
        #expect(checkout.delegatedPaymentToken?.storesRawPaymentCredential == false)
    }

    @Test func walletControlPlaneSeparatesHumanRootAndAgentChildVaults() {
        let snapshot = WalletControlPlaneSnapshot.defaultDelegation()
        guard let human = snapshot.humanPrincipals.first,
              let agent = snapshot.agentPrincipals.first else {
            Issue.record("Expected one human and one agent principal")
            return
        }
        let rootRequest = WalletCapabilityRequest(
            principalID: agent.id,
            capability: .paymentAuthorization,
            protocolName: .agenticCommerceProtocol,
            merchantID: "merchant.example",
            amountMinorUnits: 1_000,
            requestedIdentityClaims: [],
            requiresRootCredentialAccess: true
        )
        let rootDecision = WalletControlPlanePolicyEngine.evaluate(
            rootRequest,
            snapshot: snapshot,
            now: AgenticPaymentFixtures.now
        )

        #expect(human.isRootAuthority)
        #expect(agent.parentPrincipalID == human.id)
        #expect(agent.agentProfile?.trustStatus == .limited)
        #expect(agent.vaults.contains(.identity))
        #expect(agent.vaults.contains(.payment))
        #expect(agent.vaults.contains(.crypto))
        #expect(snapshot.delegationChain(for: agent.id).map(\.id) == [agent.id, human.id])
        #expect(rootDecision.kind == .deny)
        #expect(rootDecision.reasons.joined(separator: " ").contains("root human credentials"))
    }

    @Test func walletControlPlaneGrantBudgetsProtocolsAndRevocationAreEnforced() {
        var snapshot = WalletControlPlaneSnapshot.defaultDelegation()
        guard let agent = snapshot.agentPrincipals.first,
              let paymentGrantIndex = snapshot.grants.firstIndex(where: { $0.capability == .paymentAuthorization }) else {
            Issue.record("Expected delegated agent payment grant")
            return
        }
        let allowedPayment = WalletCapabilityRequest(
            principalID: agent.id,
            capability: .paymentAuthorization,
            protocolName: .agenticCommerceProtocol,
            merchantID: "merchant.example",
            amountMinorUnits: 2_000,
            requestedIdentityClaims: [],
            requiresRootCredentialAccess: false
        )
        var overBudgetPayment = allowedPayment
        overBudgetPayment.amountMinorUnits = 3_500
        var wrongProtocolPayment = allowedPayment
        wrongProtocolPayment.protocolName = .x402

        let allowed = WalletControlPlanePolicyEngine.evaluate(
            allowedPayment,
            snapshot: snapshot,
            now: AgenticPaymentFixtures.now
        )
        let overBudget = WalletControlPlanePolicyEngine.evaluate(
            overBudgetPayment,
            snapshot: snapshot,
            now: AgenticPaymentFixtures.now
        )
        let wrongProtocol = WalletControlPlanePolicyEngine.evaluate(
            wrongProtocolPayment,
            snapshot: snapshot,
            now: AgenticPaymentFixtures.now
        )
        snapshot.grants[paymentGrantIndex].revokedAt = AgenticPaymentFixtures.now
        let revoked = WalletControlPlanePolicyEngine.evaluate(
            allowedPayment,
            snapshot: snapshot,
            now: AgenticPaymentFixtures.now
        )

        #expect(allowed.kind == .allow)
        #expect(allowed.grantID == "grant-merchant-payment")
        #expect(overBudget.kind == .overBudget)
        #expect(wrongProtocol.kind == .deny)
        #expect(revoked.kind == .revoked)
    }

    @Test func walletControlPlaneReceiptsExposeSelectiveProofsAndDelegatedTokensOnly() {
        let snapshot = WalletControlPlaneSnapshot.defaultDelegation()
        guard let identityReceipt = snapshot.receipts.first(where: { $0.kind == .identityDisclosure }),
              let paymentReceipt = snapshot.receipts.first(where: { $0.kind == .paymentAuthorization }) else {
            Issue.record("Expected identity and payment control-plane receipts")
            return
        }

        #expect(identityReceipt.selectiveDisclosureClaims == ["age_over_18"])
        #expect(identityReceipt.summary.contains("not the PID credential"))
        #expect(!identityReceipt.exposesRootCredential)
        #expect(!paymentReceipt.storesRawPaymentCredential)
        #expect(!paymentReceipt.exposesRootCredential)
        #expect(paymentReceipt.bindingHashes.contains("ap2-mandate-ref-merchant-example"))
        #expect(!identityReceipt.receiptHash.isEmpty)
    }

    @Test func walletControlPlaneSurfacesVerifiedEmailAndAgentIdentityCredentials() {
        let snapshot = WalletControlPlaneSnapshot.defaultDelegation()
        guard let verifiedEmail = snapshot.verifiedEmailCredentials.first,
              let agentIdentity = snapshot.activeAgentIdentityCredentials.first else {
            Issue.record("Expected verified email and delegated agent identity credentials")
            return
        }

        #expect(snapshot.policySummary.contains("1 verified email"))
        #expect(snapshot.policySummary.contains("1 agent identity"))
        #expect(verifiedEmail.claims["email_verified"] == "true")
        #expect(verifiedEmail.claims["signature_trust"] == "issuer_signature_verified")
        #expect(verifiedEmail.isIssuerSignatureVerified)
        #expect(agentIdentity.claims["email"] == verifiedEmail.claims["email"])
        #expect(agentIdentity.sourceCredentialID == verifiedEmail.id)
        #expect(!agentIdentity.exposesRootCredential)
        #expect(snapshot.receipts.contains { receipt in
            receipt.id == agentIdentity.receiptID && receipt.summary.contains("not the human email VC")
        })
    }

    @MainActor
    @Test func runtimeBridgeSurfacesWalletControlPlanePrincipalsAndGrants() async {
        let bridge = MobileRuntimeBridge()
        let initialWalletFeature = bridge.featureStates.first { $0.feature == .wallet }

        #expect(bridge.walletPortfolio.controlPlane.humanPrincipals.count == 1)
        #expect(bridge.walletPortfolio.controlPlane.agentPrincipals.count == 1)
        #expect(initialWalletFeature?.status.contains("1 human, 1 agent") == true)

        _ = await bridge.createEmbeddedWallet(label: "Control plane wallet")
        let connectedWalletFeature = bridge.featureStates.first { $0.feature == .wallet }
        let fingerprint = bridge.walletPortfolio.embeddedWallet?.seedFingerprint
        let humanLabels = bridge.walletPortfolio.controlPlane.humanPrincipals.first?.attestationLabels ?? []

        #expect(bridge.walletPortfolio.controlPlane.activeGrants.count == 4)
        #expect(bridge.walletPortfolio.controlPlane.verifiedEmailCredentials.count == 1)
        #expect(bridge.walletPortfolio.controlPlane.activeAgentIdentityCredentials.count == 1)
        #expect(connectedWalletFeature?.status.contains("Native embedded wallet") == true)
        #expect(connectedWalletFeature?.status.contains("4 active grants") == true)
        #expect(connectedWalletFeature?.status.contains("1 verified email") == true)
        #expect(connectedWalletFeature?.status.contains("1 agent identity") == true)
        #expect(fingerprint != nil)
        #expect(humanLabels.contains { label in
            fingerprint.map { label.contains($0) } ?? false
        })
    }

    @Test func agenticPaymentPolicyRequiresUserApprovalBeforeReceiptApproval() {
        let eudiDecision = EUDIWalletDecisionEngine.decide(
            request: AgenticPaymentFixtures.eudiRequest,
            documents: [AgenticPaymentFixtures.eudiDocument],
            approvedClaimNames: ["age_over_18"],
            userAuthenticated: true,
            now: AgenticPaymentFixtures.now
        )
        let trustedAgent = VisaTrustedAgentVerifier.verify(
            AgenticPaymentFixtures.visaRequest,
            trustedKeyIDs: ["visa-key-1"],
            now: AgenticPaymentFixtures.now
        )
        let review = AgenticPaymentReview(
            id: "review-acp",
            intent: AgenticPaymentFixtures.intent,
            eudiDecision: eudiDecision,
            visaTrustedAgent: trustedAgent,
            acpCheckout: AgenticPaymentFixtures.acpCheckout,
            ap2Mandates: [],
            x402Requirement: nil,
            x402Payload: nil,
            notabeneTransfer: nil,
            userApproved: false
        )
        var approvedReview = review
        approvedReview.userApproved = true

        let ask = AgenticPaymentPolicyEngine.evaluate(review, now: AgenticPaymentFixtures.now)
        let allow = AgenticPaymentPolicyEngine.evaluate(approvedReview, now: AgenticPaymentFixtures.now)
        let receipt = AgenticPaymentPolicyEngine.receipt(for: approvedReview, decision: allow, now: AgenticPaymentFixtures.now)

        #expect(ask.kind == .askUser)
        #expect(ask.requiredApprovalLabels.contains("ACP basket"))
        #expect(allow.kind == .allow)
        #expect(receipt.status == .approved)
        #expect(receipt.identityDisclosureHash == eudiDecision.receiptHash)
        #expect(receipt.bindingHashes.contains(AgenticPaymentFixtures.acpCheckout.basketHash))
        #expect(!receipt.storesRawPaymentCredential)
    }

    @Test func ap2MandatesMustIncludeIntentCartAndPaymentBinding() {
        let intentMandate = Self.ap2Mandate(id: "ap2-intent", kind: .intent, prior: [])
        let cartMandate = Self.ap2Mandate(id: "ap2-cart", kind: .cart, prior: [intentMandate.mandateHash])
        let paymentMandate = Self.ap2Mandate(id: "ap2-payment", kind: .payment, prior: [intentMandate.mandateHash, cartMandate.mandateHash])
        let intent = AgenticPaymentIntent(
            id: "ap2-intent",
            objective: "Buy approved cart",
            merchantID: "merchant.example",
            counterpartyID: nil,
            amountMinorUnits: 1_999,
            currencyOrAsset: "USD",
            protocolName: .agentPaymentsProtocol,
            risk: .medium,
            pageSnapshotHash: "page-hash",
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(600),
            recurringPolicy: nil
        )
        let review = AgenticPaymentReview(
            id: "review-ap2",
            intent: intent,
            eudiDecision: nil,
            visaTrustedAgent: nil,
            acpCheckout: nil,
            ap2Mandates: [intentMandate, cartMandate, paymentMandate],
            x402Requirement: nil,
            x402Payload: nil,
            notabeneTransfer: nil,
            userApproved: true
        )
        var incompleteReview = review
        incompleteReview.ap2Mandates = [intentMandate, cartMandate]

        #expect(cartMandate.binds(to: intentMandate))
        #expect(paymentMandate.binds(to: intentMandate))
        #expect(paymentMandate.binds(to: cartMandate))
        #expect(AgenticPaymentPolicyEngine.evaluate(review, now: AgenticPaymentFixtures.now).kind == .allow)
        #expect(AgenticPaymentPolicyEngine.evaluate(incompleteReview, now: AgenticPaymentFixtures.now).kind == .revise)
    }

    @Test func x402AndNotabeneTransfersBindToIntentBeforeApproval() {
        let requirement = X402PaymentRequirement(
            id: "x402-req",
            resourceURLString: "https://api.example.test/research",
            amountMinorUnits: 125,
            asset: "USDC",
            network: "base",
            payTo: "0xmerchant",
            facilitatorURLString: "https://facilitator.example.test",
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(300)
        )
        let payload = X402PaymentPayload(
            requirementHash: requirement.requirementHash,
            walletAccount: "0xwallet",
            transactionReference: "tx-fixture",
            signatureReference: "sig-fixture"
        )
        let x402Intent = AgenticPaymentIntent(
            id: "x402-intent",
            objective: "Pay for API research result",
            merchantID: "api.example.test",
            counterpartyID: nil,
            amountMinorUnits: 125,
            currencyOrAsset: "USDC",
            protocolName: .x402,
            risk: .low,
            pageSnapshotHash: "page-hash",
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(300),
            recurringPolicy: nil
        )
        let x402Review = AgenticPaymentReview(
            id: "review-x402",
            intent: x402Intent,
            eudiDecision: nil,
            visaTrustedAgent: nil,
            acpCheckout: nil,
            ap2Mandates: [],
            x402Requirement: requirement,
            x402Payload: payload,
            notabeneTransfer: nil,
            userApproved: true
        )
        let transfer = NotabeneTransferRequest(
            id: "tap-transfer",
            originatorPartyID: "wallet-user",
            beneficiaryPartyID: "merchant.example",
            asset: "USDC",
            network: "ethereum",
            amountMinorUnits: 500,
            destinationAddressHash: "destination-hash",
            encryptedMessageReference: "encrypted-message",
            state: .authorized,
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(300)
        )
        let tapIntent = AgenticPaymentIntent(
            id: "tap-intent",
            objective: "Authorize blockchain transfer",
            merchantID: nil,
            counterpartyID: "merchant.example",
            amountMinorUnits: 500,
            currencyOrAsset: "USDC",
            protocolName: .notabeneTransactionAuthorization,
            risk: .high,
            pageSnapshotHash: "page-hash",
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(300),
            recurringPolicy: nil
        )
        let tapReview = AgenticPaymentReview(
            id: "review-tap",
            intent: tapIntent,
            eudiDecision: nil,
            visaTrustedAgent: nil,
            acpCheckout: nil,
            ap2Mandates: [],
            x402Requirement: nil,
            x402Payload: nil,
            notabeneTransfer: transfer,
            userApproved: true
        )

        #expect(AgenticPaymentPolicyEngine.evaluate(x402Review, now: AgenticPaymentFixtures.now).kind == .allow)
        #expect(x402Review.bindingHashes.contains(requirement.requirementHash))
        #expect(AgenticPaymentPolicyEngine.evaluate(tapReview, now: AgenticPaymentFixtures.now).kind == .allow)
        #expect(tapReview.bindingHashes.contains(transfer.transferHash))
    }

    private static func ap2Mandate(id: String, kind: AP2MandateKind, prior: [String]) -> AP2Mandate {
        AP2Mandate(
            id: id,
            kind: kind,
            signerID: "wallet-user",
            subjectID: "merchant.example",
            scopeHash: "scope-hash-\(kind.rawValue)",
            amountMinorUnits: 1_999,
            currencyOrAsset: "USD",
            priorMandateHashes: prior,
            signatureReference: "sig-\(id)",
            expiresAt: AgenticPaymentFixtures.now.addingTimeInterval(600),
            revokedAt: nil
        )
    }

    @MainActor
    @Test func browserViewModelCanNavigateFromAdvantageActions() {
        let model = BrowserViewModel()
        let scorecard = BrowserAdvantageScorecard.current
        let targetPanels = Set(
            scorecard.capabilities
                .compactMap { $0.action?.targetPanel }
        )

        #expect(targetPanels.contains(.copilot))
        #expect(targetPanels.contains(.runtime))
        #expect(targetPanels.contains(.a2ui))
        #expect(targetPanels.contains(.wallet))

        model.selectPanel(.advantage)
        #expect(model.selectedPanel == .advantage)

        model.selectPanel(.localLLM)
        #expect(model.selectedPanel == .localLLM)
    }

    @MainActor
    @Test func browserViewModelSurfacesMCPPanelAndConnections() async {
        let model = BrowserViewModel()

        #expect(BrowserPanel.allCases.contains(.mcp))
        #expect(BrowserPanel.mcp.title == "MCP")
        #expect(BrowserPanel.mcp.systemImage == "network")
        #expect(BrowserPanel.advancedPanels.contains(.mcp))

        model.selectPanel(.mcp)
        #expect(model.selectedPanel == .mcp)

        var server = model.mcpServers.first { $0.id == "demo-weather" }!
        server.enabled = true
        await model.updateMCPServer(server)
        let connected = await model.connectMCPServer(server.id)

        #expect(connected?.status.state == .connected)
        #expect(model.mcpServers.first { $0.id == server.id }?.status.state == .connected)
        #expect(model.mcpServers.first { $0.id == server.id }?.status.discoveredTools.contains("dbrowser.wallet.get_portfolio") == true)
        #expect(model.runtimeFeatureStates.first { $0.feature == .mcpServers }?.status.contains("1 connected") == true)
    }

    @MainActor
    @Test func browserViewModelCreatesEmbeddedWallet() async {
        let model = BrowserViewModel()

        #expect(model.walletPortfolio.isConnected == false)
        await model.createEmbeddedWallet(label: "Swift native wallet")

        #expect(model.walletPortfolio.isConnected)
        #expect(model.walletPortfolio.connectionKind == .nativeEmbedded)
        #expect(model.walletPortfolio.embeddedWallet?.displayName == "Swift native wallet")
        #expect(model.walletPortfolio.policySummary.contains("Native embedded wallet"))
        #expect(model.runtimeFeatureStates.first { $0.feature == .wallet }?.status.contains("Native embedded wallet") == true)
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

    private func sampleDecentralizedStorageURI(forScheme scheme: String) -> String {
        switch scheme {
        case "ipfs":
            return "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/app.json"
        case "ipns":
            return "ipns://docs.ipfs.tech/app.json"
        case "bzz", "bzzr", "swarm":
            return "\(scheme)://abcdef/app.json"
        case "ar", "arweave":
            return "\(scheme)://abc123/app.json"
        case "filecoin":
            return "filecoin://baga6ea4seaqaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/app.car"
        case "piececid":
            return "piececid://baga6ea4seaqaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/piece"
        case "fil":
            return "fil://f01234/app.car"
        case "walrus":
            return "walrus://abc123xyz"
        case "magnet":
            return "magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01"
        default:
            return "\(scheme)://example-storage-root/app.json"
        }
    }

    private func remoteResolverQueryItems(for urlString: String?) -> [String: String] {
        guard let urlString, let url = URL(string: urlString) else {
            return [:]
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
    }

    private func expectedRemoteResolverPath(for network: DecentralizedStorageNetwork) -> String {
        "/dweb/\(network.id)/resolve"
    }

    private func expectedNativeAdapterPath(for network: DecentralizedStorageNetwork) -> String {
        "/dweb/\(network.id)/native"
    }

    @MainActor
    private func waitForMobileNotice(in model: BrowserViewModel, containing text: String) async -> Bool {
        for _ in 0..<20 {
            if model.activeTab?.mobileNotice?.contains(text) == true {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
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

    @MainActor
    private func waitForCopilotRun(
        in model: BrowserViewModel,
        _ id: UUID,
        status: CopilotRunStatus
    ) async -> Bool {
        for _ in 0..<40 {
            if model.copilotRuns.first(where: { $0.id == id })?.status == status {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @MainActor
    private func waitForOpenMindStepUpRequest(in model: BrowserViewModel) async -> Bool {
        for _ in 0..<40 {
            if model.latestOpenMindStepUpRequest != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @MainActor
    private func waitForOpenMindCorrection(in model: BrowserViewModel) async -> Bool {
        for _ in 0..<40 {
            if model.latestOpenMindCorrection != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @MainActor
    private func makeIsolatedBrowserViewModel(
        initialURL: String = "about:home",
        runtimeBridge: MobileRuntimeBridge? = nil,
        workflowStore: CopilotWorkflowStore = .ephemeral(),
        smartHistoryStore: SmartHistoryStore = .ephemeral(),
        llmConversationStore: LLMConversationStore = .ephemeral(),
        openMindMemoryClient: OpenMindMemoryClient? = nil,
        localLLMManager: LocalLLMManaging? = nil
    ) -> BrowserViewModel {
        BrowserViewModel(
            initialURL: initialURL,
            runtimeBridge: runtimeBridge ?? MobileRuntimeBridge(),
            copilotWorkflowStore: workflowStore,
            smartHistoryStore: smartHistoryStore,
            llmConversationStore: llmConversationStore,
            openMindMemoryClient: openMindMemoryClient,
            localLLMManager: localLLMManager
        )
    }

    private static func localLLMConnectedFixture(statusLine: String) -> LocalLLMManagementState {
        LocalLLMManagementState(
            mode: .connected,
            statusLine: statusLine,
            baseURL: LocalLLMManager.defaultBaseURLString,
            health: "ok",
            developerKeyPreview: "sk-swiftlm...",
            hardware: LocalLLMHardwareSummary(
                chipFamily: "Apple M-series",
                unifiedMemory: "16 GB",
                freeDisk: "200 GB",
                gpuCores: "16",
                osVersion: "macOS 26.4"
            ),
            backends: [
                LocalLLMBackendSummary(
                    id: "mlx-swift",
                    kind: "mlx-swift",
                    status: "installed",
                    version: "3.31.3",
                    runtimePath: "/usr/local/bin/mlx-swift",
                    capabilities: ["chat", "vision"]
                )
            ],
            models: [
                LocalLLMModelSummary(
                    id: "model.gemma",
                    displayName: "Gemma 4 E2B IT 4-bit MLX",
                    source: "local: /models/gemma",
                    family: "Gemma 4",
                    architecture: "gemma4",
                    quantization: "4-bit MLX",
                    status: "ready",
                    sizeOnDisk: "3.4 GB",
                    contextWindow: "8192",
                    capabilities: ["Chat", "Vision"],
                    warnings: []
                )
            ],
            activeEngines: [
                LocalLLMEngineSummary(
                    id: "engine.gemma",
                    modelID: "model.gemma",
                    backendID: "mlx-swift",
                    queueDepth: "0",
                    outputTokensPerSecond: "42.0 tok/s",
                    peakMemory: "4 GB",
                    isWarm: true
                )
            ],
            recommendedImport: .current(),
            lastError: nil,
            isWorking: false
        )
    }

    private static func chainAnchoredNodeTask(taskID: String, outputCommitment: String) -> AFMNodeTaskResult {
        let nonce = AFMNodeVerificationReport.bindingNonceHex(
            taskID: taskID,
            outputCommitment: outputCommitment
        ) ?? ""
        return AFMNodeTaskResult(
            ok: true,
            id: taskID,
            taskID: taskID,
            packID: "afm://demo-writer",
            installID: "install-chain",
            status: "completed",
            mode: "production",
            result: AFMNodeTaskOutput(
                summary: "production completed",
                outputCommitment: outputCommitment,
                completedAt: "2026-05-16T00:00:01Z"
            ),
            attestation: AFMAttestedRun(
                mode: "secure-enclave",
                taskID: taskID,
                outputCommitment: outputCommitment,
                nonce: nonce,
                tokenCount: 42,
                contextPassages: 2,
                attestationToken: "cbor-base64"
            ),
            proof: AFMProofState(
                proofID: "proof-chain",
                status: "verified",
                verifier: "0xverifier",
                publicInputs: [
                    "taskID": taskID,
                    "outputCommitment": outputCommitment
                ],
                proofBytes: "0xproof",
                publicInputsABI: "0xinputs",
                deadline: 1730203600,
                payoutAddress: "0x000000000000000000000000000000000000dead",
                modelIDHash: "0xmodel"
            ),
            settlement: AFMSettlementState(
                id: "settlement-chain",
                status: "settled",
                chainRef: "base-sepolia",
                escrowID: "escrow-chain",
                escrowContract: "0xescrow",
                transactionHash: "0xtx-chain",
                blockNumber: 456,
                deadline: 1730203600,
                verifier: "0xverifier",
                mode: "production",
                settledAt: "2026-05-16T00:00:02Z"
            )
        )
    }

    private static func temporaryJSONStoreURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dbrowser-\(name)-\(UUID().uuidString).json")
    }

    private static func makeAFMServiceSession(
        key: String,
        includesMarketplace: Bool = false,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: AFMServiceEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoints = AFMServiceEndpointConfiguration(
            routerBaseURL: URL(string: "http://\(key)-router.test:4810")!,
            registryBaseURL: URL(string: "http://\(key)-registry.test:4820")!,
            pipelinesBaseURL: URL(string: "http://\(key)-pipelines.test:4830")!,
            nodeBaseURL: URL(string: "http://\(key)-node.test:4840")!,
            marketplaceBaseURL: includesMarketplace ? URL(string: "http://\(key)-marketplace.test:4850")! : nil
        )
        return (endpoints, URLSession(configuration: configuration))
    }

    private static func localAFMMarketplaceJobBody(
        publishStatus: String = "draft",
        status: String = "readyForLocalUse",
        publishReadiness: String = "needsAttestation",
        runnerID: String = "afm-local-demo@v1"
    ) -> [String: Any] {
        [
            "id": "train-demo",
            "status": status,
            "publishReadiness": publishReadiness,
            "publishStatus": publishStatus,
            "progress": 1.0,
            "localAdapterID": "afm-local-demo",
            "outputRunnerID": runnerID,
            "artifactBundleURL": "local://afm-marketplace/artifacts/\(runnerID).json",
            "manifestHash": "sha256:manifest-local",
            "trainingSummary": "Prepared profile adapter artifact from 42 approved examples.",
            "adapterStatus": "Profile adapter artifact is ready for local use and marketplace publishing.",
            "runnerPack": localAFMRunnerPackBody(runnerID: runnerID),
            "peerExpert": localAFMExpertBody(runnerID: runnerID)
        ]
    }

    private static func localAFMRunnerPackBody(runnerID: String = "afm-local-demo@v1") -> [String: Any] {
        [
            "runner_id": runnerID,
            "afm": [
                "model_id": "apple.foundation-model.local"
            ],
            "prompting": [
                "system": "You are a local policy expert.",
                "template": "{{prompt}}",
                "params": [
                    "temperature": 0.2,
                    "top_p": 0.9,
                    "max_tokens": 900
                ]
            ],
            "policy": [
                "allowed_domains": ["travel", "policy"],
                "max_context": 128000
            ],
            "royalties": [
                "creator_bps": 500,
                "data_bps": 100
            ],
            "attestation": ["method:profileAdapter", "privacy:redactedA2A"],
            "capability_vector": [0.12, 0.34, 0.56],
            "hashes": [
                "manifest": "sha256:manifest-local",
                "adapter": "sha256:adapter-local",
                "bundle": "sha256:bundle-local"
            ],
            "bundle_url": "local://afm-marketplace/artifacts/\(runnerID).json",
            "signature": "local-dev:sig",
            "runner_root": "fnv1a64:local",
            "owner_id": "local-user",
            "created_at": 1798761600000
        ]
    }

    private static func localAFMExpertBody(runnerID: String = "afm-local-demo@v1") -> [String: Any] {
        [
            "id": runnerID,
            "name": "Local Travel Policy Expert",
            "nodePub": "local-node-demo",
            "capability": [0.12, 0.34, 0.56],
            "pricePer1k": 0.0,
            "latencyP50": 5.0,
            "tags": ["travel", "policy"],
            "baseModel": "apple.foundation-model.local",
            "coverage": 1.0,
            "reputation": 0.0,
            "stake": 0.0,
            "attestation": "local-adapter:afm-local-demo",
            "ingestUrl": "local://afm-marketplace/a2a/\(runnerID)",
            "profileSig": "local-profile:sig",
            "createdAt": "2026-01-01T00:00:00.000Z",
            "updatedAt": "2026-01-01T00:00:00.000Z"
        ]
    }

    private static func makeOpenMindMemorySession(
        key: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: OpenMindMemoryEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = OpenMindMemoryEndpointConfiguration(
            httpBaseURL: URL(string: "http://\(key)-memory.test:4840")!
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeLLMRouterSession(
        key: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: LLMRouterEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = LLMRouterEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-llm-router.test:4850")!,
            provider: .appleFoundation,
            preferLocal: true,
            noEgress: true
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeBitcoinLightClientSession(
        key: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: BitcoinLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = BitcoinLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-bitcoin.test:4870")!,
            network: .mainnet
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeEVMLightClientSession(
        key: String,
        chain: EVMChain = .ethereumMainnet,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: EVMLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = EVMLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-evm.test:4870")!,
            chain: chain
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeSolanaLightClientSession(
        key: String,
        cluster: SolanaCluster = .mainnetBeta,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: SolanaLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = SolanaLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-solana.test:4870")!,
            cluster: cluster
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeCosmosLightClientSession(
        key: String,
        chain: CosmosChain = .cosmosHub,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: CosmosLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = CosmosLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-cosmos.test:4870")!,
            chain: chain
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeSubstrateLightClientSession(
        key: String,
        chain: SubstrateChain = .polkadot,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: SubstrateLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = SubstrateLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-substrate.test:4870")!,
            chain: chain
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeAvalancheLightClientSession(
        key: String,
        network: AvalancheNetwork = .cChain,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: AvalancheLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = AvalancheLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-avalanche.test:4870")!,
            network: network
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeTronLightClientSession(
        key: String,
        network: TronNetwork = .mainnet,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: TronLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = TronLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-tron.test:4870")!,
            network: network
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeXRPLLightClientSession(
        key: String,
        network: XRPLNetwork = .mainnet,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: XRPLLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = XRPLLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-xrpl.test:4870")!,
            network: network
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func makeMoveLightClientSession(
        key: String,
        chain: MoveChain = .suiMainnet,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (configuration: MoveLightClientEndpointConfiguration, session: URLSession) {
        AFMServiceMockURLProtocol.register(key: key, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AFMServiceMockURLProtocol.self]
        let endpoint = MoveLightClientEndpointConfiguration(
            baseURL: URL(string: "http://\(key)-move.test:4870")!,
            chain: chain
        )
        return (endpoint, URLSession(configuration: configuration))
    }

    private static func bitcoinGenesisServiceStatus() -> [String: Any] {
        let genesis = BitcoinBlockHeader.mainnetGenesis
        return [
            "ok": true,
            "network": "mainnet",
            "sync_state": "synced",
            "source": "bitcoin-light-client",
            "best_height": genesis.height,
            "best_block_hash": genesis.validatedHash,
            "best_header": [
                "height": genesis.height,
                "version": Int(genesis.version),
                "previous_block_hash": genesis.previousBlockHash,
                "merkle_root": genesis.merkleRoot,
                "timestamp": Int(genesis.timestamp),
                "bits": Int(genesis.bits),
                "nonce": Int(genesis.nonce),
                "hash": genesis.validatedHash,
                "chain_work": genesis.chainWork ?? "01",
                "source": "fixture"
            ],
            "peer_count": 3,
            "filter_source": "bip157"
        ]
    }

    private static func evmServiceStatus(
        chain: EVMChain,
        syncState: String = "synced"
    ) -> [String: Any] {
        let bundle = evmProofBundle(chain: chain)
        let header = bundle.header
        let checkpointKey = syncState == "synced" ? "finalized_checkpoint" : "head"
        return [
            "ok": true,
            "chain": chain.chainRef,
            "chain_ref": chain.chainRef,
            "chain_id": chain.chainID,
            "sync_state": syncState,
            "source": "evm-light-client",
            "finality_model": chain.finalityModel.rawValue,
            checkpointKey: [
                "chain": chain.chainRef,
                "chain_ref": chain.chainRef,
                "number": header.number,
                "hash": header.hash,
                "parent_hash": header.parentHash ?? EVMHex.sha256Hex("\(chain.chainRef)-parent"),
                "state_root": header.stateRoot,
                "receipts_root": header.receiptsRoot,
                "transactions_root": header.transactionsRoot ?? EVMHex.sha256Hex("\(chain.chainRef)-transactions"),
                "timestamp": Int(header.timestamp ?? 1_680_000_000),
                "finalized": syncState == "synced",
                "source": "fixture"
            ],
            "peer_count": 2,
            "proof_source": "fixture-local-merkle"
        ]
    }

    private static func solanaServiceStatus(
        cluster: SolanaCluster,
        syncState: String = "synced",
        commitment: String = "finalized"
    ) -> [String: Any] {
        let bundle = solanaProofBundle(kind: .account, cluster: cluster)
        let slotRoot = bundle.snapshot
        return [
            "ok": true,
            "cluster": cluster.rawValue,
            "chain_ref": cluster.chainRef,
            "sync_state": syncState,
            "source": "solana-light-client",
            "slot_root": [
                "cluster": cluster.rawValue,
                "chain_ref": cluster.chainRef,
                "slot": slotRoot.slot,
                "root_slot": slotRoot.rootSlot,
                "blockhash": slotRoot.blockhash,
                "parent_slot": slotRoot.parentSlot ?? slotRoot.slot - 1,
                "commitment": commitment,
                "account_root": slotRoot.accountRoot ?? "",
                "transaction_status_root": slotRoot.transactionStatusRoot ?? "",
                "source": "fixture"
            ],
            "peer_count": 2,
            "proof_source": "fixture-local-merkle",
            "root_lag": slotRoot.rootLag(),
            "max_root_lag": 512
        ]
    }

    private static func cosmosServiceStatus(
        chain: CosmosChain,
        syncState: String = "synced",
        trustPeriodExpired: Bool = false
    ) -> [String: Any] {
        let bundle = cosmosHeaderBundle(chain: chain)
        return [
            "ok": true,
            "chain": chain.chainID,
            "chain_ref": chain.chainRef,
            "chain_id": chain.chainID,
            "sync_state": syncState,
            "source": "cosmos-tendermint-light-client",
            "latest_header": cosmosHeaderBody(bundle.header),
            "validator_set": cosmosValidatorSetBody(bundle.validatorSet),
            "peer_count": 2,
            "proof_source": "fixture-tendermint-commit",
            "trust_period_expired": trustPeriodExpired,
            "trust_expires_at_unix_seconds": bundle.trustPolicy.trustedTimeUnixSeconds + bundle.trustPolicy.trustPeriodSeconds
        ]
    }

    private static func substrateServiceStatus(
        chain: SubstrateChain,
        syncState: String = "synced"
    ) -> [String: Any] {
        let bundle = substrateProofBundle(chain: chain)
        return [
            "ok": true,
            "chain": chain.chainSpecID,
            "chain_ref": chain.chainRef,
            "chain_spec_id": chain.chainSpecID,
            "sync_state": syncState,
            "source": "substrate-light-client",
            "latest_finalized_header": substrateHeaderBody(bundle.header),
            "authority_set": substrateAuthoritySetBody(bundle.authoritySet),
            "peer_count": 2,
            "proof_source": "fixture-grandpa-storage"
        ]
    }

    private static func avalancheServiceStatus(
        network: AvalancheNetwork,
        syncState: String = "proof_checked"
    ) -> [String: Any] {
        let bundle = avalancheProofBundle(network: network)
        return [
            "ok": true,
            "service_available": true,
            "network": network.chainRef,
            "chain_ref": network.chainRef,
            "chain_id": network.chainID,
            "sync_state": syncState,
            "source": "avalanche-light-client",
            "finality_model": "snowman-accepted",
            "accepted_block": avalancheAcceptedBlockBody(bundle.acceptedBlock),
            "validator_set": avalancheValidatorSetBody(bundle.validatorSet),
            "peer_count": 2,
            "proof_source": "fixture-snowman-evm-proof",
            "limitations": network.limitations
        ]
    }

    private static func tronServiceStatus(
        network: TronNetwork,
        syncState: String = "proof_checked",
        stale: Bool = false
    ) -> [String: Any] {
        let bundle = tronProofBundle(network: network)
        return [
            "ok": true,
            "service_available": true,
            "network": network.chainRef,
            "chain_ref": network.chainRef,
            "sync_state": syncState,
            "source": "tron-light-client",
            "latest_solid_block": tronHeaderBody(bundle.header),
            "witness_set": tronWitnessSetBody(bundle.witnessSet),
            "peer_count": 2,
            "proof_source": "fixture-witness-token-proof",
            "stale": stale,
            "limitations": network.limitations
        ]
    }

    private static func xrplServiceStatus(
        network: XRPLNetwork,
        syncState: String = "proof_checked",
        stale: Bool = false
    ) -> [String: Any] {
        let bundle = xrplProofBundle(network: network)
        return [
            "ok": true,
            "service_available": true,
            "network": network.chainRef,
            "chain_ref": network.chainRef,
            "sync_state": syncState,
            "source": "xrpl-light-client",
            "latest_validated_ledger": xrplLedgerBody(bundle.ledger),
            "unl_set": xrplUNLSetBody(bundle.unlSet),
            "peer_count": 2,
            "proof_source": "fixture-unl-account-payment-proof",
            "stale": stale,
            "limitations": network.limitations
        ]
    }

    private static func moveServiceStatus(
        chain: MoveChain,
        syncState: String = "proof_checked",
        stale: Bool = false
    ) -> [String: Any] {
        let kind: MoveLocalProofKind = chain.kind == .sui ? .suiObject : .aptosAccount
        let bundle = moveProofBundle(chain: chain, kind: kind)
        return [
            "ok": true,
            "service_available": true,
            "chain": chain.chainRef,
            "chain_ref": chain.chainRef,
            "chain_id": chain.chainID,
            "sync_state": syncState,
            "source": "move-light-client",
            "latest_checkpoint": moveCheckpointBody(bundle.checkpoint),
            "validator_set": moveValidatorSetBody(bundle.validatorSet),
            "peer_count": 2,
            "proof_source": chain.kind == .sui ? "fixture-sui-checkpoint-object-proof" : "fixture-aptos-ledger-account-proof",
            "stale": stale,
            "limitations": chain.limitations
        ]
    }

    private static func evmProofBundle(chain: EVMChain) -> EVMLocalProofBundle {
        let subject = "0x1111111111111111111111111111111111111111"
        let leaf = EVMLocalProof.fixtureLeafHash(kind: .account, subject: subject, value: "0x01")
        let root = EVMLocalProof.computeRoot(leafHash: leaf, witnesses: [])!
        let receiptLeaf = EVMLocalProof.fixtureLeafHash(kind: .receipt, subject: "0xtx", value: "0x01")
        let receiptRoot = EVMLocalProof.computeRoot(leafHash: receiptLeaf, witnesses: [])!
        let header = EVMExecutionHeaderSnapshot(
            chain: chain,
            number: 17_000_000,
            hash: EVMHex.sha256Hex("\(chain.chainRef)-17000000-header"),
            parentHash: EVMHex.sha256Hex("\(chain.chainRef)-16999999-header"),
            stateRoot: root,
            receiptsRoot: receiptRoot,
            transactionsRoot: EVMHex.sha256Hex("\(chain.chainRef)-transactions"),
            timestamp: 1_680_000_000,
            finalized: chain == .ethereumMainnet,
            source: "fixture"
        )
        let proof = EVMLocalProof(
            proofID: "account-proof",
            kind: .account,
            chain: chain,
            subject: subject,
            expectedValue: "0x01",
            blockHash: header.hash,
            blockNumber: header.number,
            expectedRoot: root,
            leafHash: leaf,
            witnesses: [],
            source: "fixture"
        )
        return EVMLocalProofBundle(header: header, proof: proof)
    }

    private static func solanaProofBundle(
        kind: SolanaFixtureProofKind,
        cluster: SolanaCluster = .mainnetBeta
    ) -> SolanaProofBundle {
        let accountSubject = "So11111111111111111111111111111111111111112"
        let transactionSubject = "5sUjfixtureTransactionStatus111111111111111111111111111111111"
        let accountLeaf = SolanaFixtureProof.fixtureLeafHash(
            kind: .account,
            subject: accountSubject,
            value: "lamports:1"
        )
        let transactionLeaf = SolanaFixtureProof.fixtureLeafHash(
            kind: .transactionStatus,
            subject: transactionSubject,
            value: "confirmed"
        )
        let snapshot = SolanaSlotRootSnapshot(
            cluster: cluster,
            slot: 281_474_976_710,
            rootSlot: 281_474_976_700,
            blockhash: SolanaHex.sha256Hex("\(cluster.chainRef)-281474976710-blockhash"),
            parentSlot: 281_474_976_709,
            commitment: .finalized,
            accountRoot: accountLeaf,
            transactionStatusRoot: transactionLeaf,
            source: "fixture"
        )
        let proof = SolanaFixtureProof(
            proofID: kind == .account ? "solana-account-proof" : "solana-transaction-proof",
            kind: kind,
            cluster: cluster,
            subject: kind == .account ? accountSubject : transactionSubject,
            slot: snapshot.slot,
            expectedRoot: kind == .account ? accountLeaf : transactionLeaf,
            leafHash: kind == .account ? accountLeaf : transactionLeaf,
            witnesses: [],
            source: "fixture"
        )
        return SolanaProofBundle(snapshot: snapshot, proof: proof)
    }

    static func cosmosValidatorKey(_ seed: UInt8) -> Curve25519.Signing.PrivateKey {
        // Deterministic Ed25519 key from a fixed 32-byte seed so the fixture is both real and stable.
        try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
    }

    static func cosmosCommitSignature(
        _ key: Curve25519.Signing.PrivateKey,
        address: String,
        chain: CosmosChain,
        height: Int,
        round: Int,
        blockIDHash: String
    ) -> TendermintCommitSignature {
        let message = TendermintCommitSignatureVerifier.canonicalSignBytes(
            chainID: chain.chainID,
            height: height,
            round: round,
            blockIDHash: blockIDHash
        )
        let signature = try! key.signature(for: message).base64EncodedString()
        return TendermintCommitSignature(
            validatorAddress: address,
            blockIDHash: blockIDHash,
            signed: true,
            signature: signature
        )
    }

    private static func cosmosHeaderBundle(chain: CosmosChain) -> TendermintHeaderVerificationBundle {
        let keyA = cosmosValidatorKey(0xA1)
        let keyB = cosmosValidatorKey(0xB2)
        let keyC = cosmosValidatorKey(0xC3)
        let validators = [
            TendermintValidator(address: String(repeating: "a1", count: 20), publicKey: keyA.publicKey.rawRepresentation.base64EncodedString(), votingPower: 40, name: "validator-a"),
            TendermintValidator(address: String(repeating: "b2", count: 20), publicKey: keyB.publicKey.rawRepresentation.base64EncodedString(), votingPower: 35, name: "validator-b"),
            TendermintValidator(address: String(repeating: "c3", count: 20), publicKey: keyC.publicKey.rawRepresentation.base64EncodedString(), votingPower: 25, name: "validator-c")
        ]
        let validatorSet = TendermintValidatorSet(
            chain: chain,
            height: 19_700_000,
            validators: validators,
            source: "fixture"
        )
        let header = TendermintHeader(
            chain: chain,
            height: validatorSet.height,
            timeUnixSeconds: 1_778_889_600,
            lastBlockIDHash: TendermintHex.sha256Hex("\(chain.chainID)-19699999"),
            validatorsHash: validatorSet.hash,
            nextValidatorsHash: validatorSet.hash,
            appHash: TendermintHex.sha256Hex("\(chain.chainID)-19700000-app"),
            dataHash: TendermintHex.sha256Hex("\(chain.chainID)-19700000-data"),
            evidenceHash: TendermintHex.sha256Hex("\(chain.chainID)-19700000-evidence"),
            proposerAddress: validators[0].address,
            source: "fixture"
        )
        let commit = TendermintCommit(
            height: header.height,
            round: 0,
            blockIDHash: header.hash,
            signatures: [
                cosmosCommitSignature(keyA, address: validators[0].address, chain: chain, height: header.height, round: 0, blockIDHash: header.hash),
                cosmosCommitSignature(keyB, address: validators[1].address, chain: chain, height: header.height, round: 0, blockIDHash: header.hash),
                TendermintCommitSignature(validatorAddress: validators[2].address, blockIDHash: header.hash, signed: false)
            ],
            source: "fixture"
        )
        let trustPolicy = TendermintTrustPolicy(
            trustedHeight: header.height - 10,
            trustedTimeUnixSeconds: 1_778_800_000,
            trustPeriodSeconds: chain.trustPeriodSeconds
        )
        return TendermintHeaderVerificationBundle(
            header: header,
            validatorSet: validatorSet,
            commit: commit,
            trustPolicy: trustPolicy
        )
    }

    private static let substrateStorageKey = "0x26aa394eea5630e07c48ae0c9558cef7"

    static func substrateAuthorityKey(_ seed: UInt8) -> Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
    }

    static func substratePubkeyHex(_ key: Curve25519.Signing.PrivateKey) -> String {
        key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
    }

    private static func ed25519PublicKeyHex(_ key: Curve25519.Signing.PrivateKey) -> String {
        key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
    }

    static func grandpaSignature(_ key: Curve25519.Signing.PrivateKey, setID: Int, round: Int, blockHash: String) -> GRANDPAJustificationSignature {
        let message = GRANDPAFinalityJustification.canonicalVote(setID: setID, round: round, blockHash: blockHash)
        let signature = try! key.signature(for: message).base64EncodedString()
        return GRANDPAJustificationSignature(authorityID: substratePubkeyHex(key), blockHash: blockHash, signed: true, signature: signature)
    }

    private static func substrateProofBundle(chain: SubstrateChain) -> SubstrateProofVerificationBundle {
        let keyA = substrateAuthorityKey(0xD1)
        let keyB = substrateAuthorityKey(0xE2)
        let keyC = substrateAuthorityKey(0xF3)
        let authorities = [
            GRANDPAAuthority(authorityID: substratePubkeyHex(keyA), weight: 40),
            GRANDPAAuthority(authorityID: substratePubkeyHex(keyB), weight: 35),
            GRANDPAAuthority(authorityID: substratePubkeyHex(keyC), weight: 25)
        ]
        let authoritySet = GRANDPAAuthoritySet(
            chain: chain,
            setID: 1_234,
            authorities: authorities,
            source: "fixture"
        )
        let valueHash = SubstrateHex.sha256Hex("\(chain.chainSpecID)-account-balance:1")
        let leafHash = SubstrateStorageProof.fixtureLeafHash(storageKey: substrateStorageKey, valueHash: valueHash)
        let header = SubstrateHeaderSnapshot(
            chain: chain,
            number: 21_000_000,
            hash: SubstrateHex.sha256Hex("\(chain.chainSpecID)-21000000-header"),
            parentHash: SubstrateHex.sha256Hex("\(chain.chainSpecID)-20999999-header"),
            stateRoot: leafHash,
            extrinsicsRoot: SubstrateHex.sha256Hex("\(chain.chainSpecID)-21000000-extrinsics"),
            digestLogs: ["0x0642414245"],
            finalized: true,
            source: "fixture"
        )
        let justification = GRANDPAFinalityJustification(
            round: 42,
            setID: authoritySet.setID,
            targetHash: header.hash,
            targetNumber: header.number,
            signatures: [
                grandpaSignature(keyA, setID: authoritySet.setID, round: 42, blockHash: header.hash),
                grandpaSignature(keyB, setID: authoritySet.setID, round: 42, blockHash: header.hash),
                GRANDPAJustificationSignature(authorityID: substratePubkeyHex(keyC), blockHash: header.hash, signed: false)
            ],
            source: "fixture"
        )
        let storageProof = SubstrateStorageProof(
            proofID: "substrate-storage-proof",
            chain: chain,
            blockHash: header.hash,
            storageKey: substrateStorageKey,
            expectedValueHash: valueHash,
            leafHash: leafHash,
            witnesses: [],
            source: "fixture"
        )
        return SubstrateProofVerificationBundle(
            header: header,
            authoritySet: authoritySet,
            justification: justification,
            storageProof: storageProof
        )
    }

    private static func avalancheValidatorKey(_ seed: UInt8) -> Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
    }

    private static func avalancheFinalitySignature(
        _ key: Curve25519.Signing.PrivateKey,
        nodeID: String,
        setID: Int,
        targetHeight: Int,
        blockHash: String
    ) -> AvalancheFinalitySignature {
        let message = AvalancheFinalityEvidence.canonicalVote(
            setID: setID,
            targetHeight: targetHeight,
            blockHash: blockHash
        )
        let signature = try! key.signature(for: message).base64EncodedString()
        return AvalancheFinalitySignature(
            nodeID: nodeID,
            blockHash: blockHash,
            signed: true,
            signature: signature
        )
    }

    private static func avalancheProofBundle(network: AvalancheNetwork) -> AvalancheStateVerificationBundle {
        let keyA = avalancheValidatorKey(0xA1)
        let keyB = avalancheValidatorKey(0xB2)
        let keyC = avalancheValidatorKey(0xC3)
        let validators = [
            AvalancheValidator(nodeID: "nodeid-avalanche-fixture-a", weight: 50, publicKey: ed25519PublicKeyHex(keyA)),
            AvalancheValidator(nodeID: "nodeid-avalanche-fixture-b", weight: 30, publicKey: ed25519PublicKeyHex(keyB)),
            AvalancheValidator(nodeID: "nodeid-avalanche-fixture-c", weight: 20, publicKey: ed25519PublicKeyHex(keyC))
        ]
        let validatorSet = AvalancheValidatorSet(
            network: network,
            setID: 9_001,
            validators: validators,
            source: "fixture"
        )
        let subject = "0x2222222222222222222222222222222222222222"
        let leaf = EVMLocalProof.fixtureLeafHash(kind: .account, subject: subject, value: "0x01")
        let receiptLeaf = EVMLocalProof.fixtureLeafHash(kind: .receipt, subject: "0xavalanche-tx-fixture", value: "0x01")
        let acceptedBlock = AvalancheAcceptedBlockSnapshot(
            network: network,
            height: 50_000_000,
            blockHash: EVMHex.sha256Hex("\(network.chainRef)-50000000-accepted-block"),
            parentHash: EVMHex.sha256Hex("\(network.chainRef)-49999999-accepted-block"),
            stateRoot: leaf,
            receiptsRoot: receiptLeaf,
            timestamp: 1_710_000_000,
            accepted: true,
            source: "fixture"
        )
        let proof = EVMLocalProof(
            proofID: "avalanche-fixture-account",
            kind: .account,
            chain: .avalancheCChain,
            subject: subject,
            expectedValue: "0x01",
            blockHash: acceptedBlock.blockHash,
            blockNumber: acceptedBlock.height,
            expectedRoot: acceptedBlock.stateRoot,
            leafHash: leaf,
            witnesses: [],
            source: "fixture"
        )
        let finalityEvidence = AvalancheFinalityEvidence(
            setID: validatorSet.setID,
            targetHash: acceptedBlock.blockHash,
            targetHeight: acceptedBlock.height,
            signatures: [
                avalancheFinalitySignature(keyA, nodeID: validators[0].nodeID, setID: validatorSet.setID, targetHeight: acceptedBlock.height, blockHash: acceptedBlock.blockHash),
                avalancheFinalitySignature(keyB, nodeID: validators[1].nodeID, setID: validatorSet.setID, targetHeight: acceptedBlock.height, blockHash: acceptedBlock.blockHash),
                AvalancheFinalitySignature(nodeID: validators[2].nodeID, blockHash: acceptedBlock.blockHash, signed: false)
            ],
            source: "fixture"
        )
        return AvalancheStateVerificationBundle(
            acceptedBlock: acceptedBlock,
            validatorSet: validatorSet,
            finalityEvidence: finalityEvidence,
            evmProof: EVMLocalProofBundle(
                header: acceptedBlock.executionHeader!,
                proof: proof
            )
        )
    }

    static func tronWitnessKey(_ seed: UInt8) -> Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
    }

    static func tronFinalitySignature(_ key: Curve25519.Signing.PrivateKey, address: String, epoch: Int, blockID: String) -> TronFinalitySignature {
        let message = TronFinalityProof.canonicalVote(epoch: epoch, blockID: blockID)
        let signature = try! key.signature(for: message).base64EncodedString()
        let publicKey = key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        return TronFinalitySignature(witnessAddress: address, blockID: blockID, signed: true, signature: signature, publicKey: publicKey)
    }

    private static func tronProofBundle(network: TronNetwork) -> TronProofVerificationBundle {
        let witnesses = [
            TronWitness(address: "41" + String(repeating: "a1", count: 20), weight: 10, name: "sr-a"),
            TronWitness(address: "41" + String(repeating: "b2", count: 20), weight: 9, name: "sr-b"),
            TronWitness(address: "41" + String(repeating: "c3", count: 20), weight: 8, name: "sr-c")
        ]
        let witnessSet = TronWitnessSet(
            network: network,
            epoch: 7_001,
            witnesses: witnesses,
            source: "fixture"
        )
        let subject = "41" + String(repeating: "d4", count: 20)
        let valueHash = TronHex.sha256Hex("tron-usdt-balance:1")
        let tokenLeaf = TronLocalProof.fixtureLeafHash(kind: .token, subject: subject, tokenID: "trc20-usdt", valueHash: valueHash)
        let receiptLeaf = TronLocalProof.fixtureLeafHash(kind: .receipt, subject: "tron-tx-fixture", valueHash: TronHex.sha256Hex("receipt:success"))
        let header = TronBlockHeaderSnapshot(
            network: network,
            number: 60_000_000,
            blockID: TronHex.sha256Hex("\(network.chainRef)-60000000-solid-block"),
            parentHash: TronHex.sha256Hex("\(network.chainRef)-59999999-solid-block"),
            witnessAddress: witnesses[0].address,
            timestamp: 1_715_000_000,
            accountStateRoot: tokenLeaf,
            receiptRoot: receiptLeaf,
            solid: true,
            source: "fixture"
        )
        let finalityProof = TronFinalityProof(
            epoch: witnessSet.epoch,
            targetBlockID: header.blockID,
            targetNumber: header.number,
            signatures: [
                tronFinalitySignature(tronWitnessKey(0xA1), address: witnesses[0].address, epoch: witnessSet.epoch, blockID: header.blockID),
                tronFinalitySignature(tronWitnessKey(0xB2), address: witnesses[1].address, epoch: witnessSet.epoch, blockID: header.blockID),
                TronFinalitySignature(witnessAddress: witnesses[2].address, blockID: header.blockID, signed: false)
            ],
            source: "fixture"
        )
        let proof = TronLocalProof(
            proofID: "tron-fixture-token",
            kind: .token,
            network: network,
            subject: subject,
            tokenID: "trc20-usdt",
            expectedValueHash: valueHash,
            blockID: header.blockID,
            blockNumber: header.number,
            expectedRoot: header.accountStateRoot,
            leafHash: tokenLeaf,
            witnesses: [],
            source: "fixture"
        )
        return TronProofVerificationBundle(
            header: header,
            witnessSet: witnessSet,
            finalityProof: finalityProof,
            proof: proof
        )
    }

    private static func xrplValidatorKey(_ seed: UInt8) -> Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
    }

    private static func xrplValidationVote(
        _ key: Curve25519.Signing.PrivateKey,
        listID: String,
        ledgerHash: String,
        ledgerIndex: Int,
        validatorPublicKey: String? = nil
    ) -> XRPLValidationVote {
        let message = XRPLLedgerValidationProof.canonicalVote(
            listID: listID,
            ledgerHash: ledgerHash,
            ledgerIndex: ledgerIndex
        )
        let signature = try! key.signature(for: message).base64EncodedString()
        return XRPLValidationVote(
            validatorPublicKey: validatorPublicKey ?? ed25519PublicKeyHex(key),
            ledgerHash: ledgerHash,
            ledgerIndex: ledgerIndex,
            signed: true,
            signature: signature
        )
    }

    private static func xrplProofBundle(
        network: XRPLNetwork,
        kind: XRPLLocalProofKind = .account
    ) -> XRPLProofVerificationBundle {
        let keyA = xrplValidatorKey(0x11)
        let keyB = xrplValidatorKey(0x22)
        let keyC = xrplValidatorKey(0x33)
        let keyD = xrplValidatorKey(0x44)
        let keyE = xrplValidatorKey(0x55)
        let validators = [
            XRPLUNLValidator(validatorPublicKey: ed25519PublicKeyHex(keyA), domain: "validator-a.example"),
            XRPLUNLValidator(validatorPublicKey: ed25519PublicKeyHex(keyB), domain: "validator-b.example"),
            XRPLUNLValidator(validatorPublicKey: ed25519PublicKeyHex(keyC), domain: "validator-c.example"),
            XRPLUNLValidator(validatorPublicKey: ed25519PublicKeyHex(keyD), domain: "validator-d.example"),
            XRPLUNLValidator(validatorPublicKey: ed25519PublicKeyHex(keyE), domain: "validator-e.example", disabled: true)
        ]
        let unlSet = XRPLUNLSet(
            network: network,
            listID: "fixture-default-unl",
            validators: validators,
            negativeUNL: [validators[4].validatorPublicKey],
            source: "fixture"
        )
        let subject = "raccountfixture"
        let counterparty = "rcounterpartyfixture"
        let currency = "USD"
        let transactionHash = XRPLHash.sha256Hex("xrpl-payment-fixture")
        let accountValueHash = XRPLHash.sha256Hex("xrpl-account-balance:100")
        let trustLineValueHash = XRPLHash.sha256Hex("xrpl-trustline-usd:25")
        let paymentValueHash = XRPLHash.sha256Hex("xrpl-payment:tesSUCCESS")
        let accountLeaf = XRPLLocalProof.fixtureLeafHash(kind: .account, subject: subject, valueHash: accountValueHash)
        let trustLineLeaf = XRPLLocalProof.fixtureLeafHash(
            kind: .trustLine,
            subject: subject,
            counterparty: counterparty,
            currency: currency,
            valueHash: trustLineValueHash
        )
        let accountRoot = XRPLLocalProof.computeRoot(
            leafHash: accountLeaf,
            witnesses: [XRPLProofWitness(hash: trustLineLeaf, position: .right)]
        )!
        let paymentLeaf = XRPLLocalProof.fixtureLeafHash(
            kind: .payment,
            subject: subject,
            counterparty: counterparty,
            currency: currency,
            transactionHash: transactionHash,
            valueHash: paymentValueHash
        )
        let ledger = XRPLValidatedLedgerSnapshot(
            network: network,
            ledgerIndex: 90_000_000,
            ledgerHash: XRPLHash.sha256Hex("\(network.chainRef)|90000000|validated-ledger"),
            parentHash: XRPLHash.sha256Hex("\(network.chainRef)|89999999|validated-ledger"),
            accountStateRoot: accountRoot,
            transactionMetadataRoot: paymentLeaf,
            closeTime: 1_716_000_000,
            validated: true,
            source: "fixture"
        )
        let validationProof = XRPLLedgerValidationProof(
            listID: unlSet.listID,
            ledgerHash: ledger.ledgerHash,
            ledgerIndex: ledger.ledgerIndex,
            votes: [
                xrplValidationVote(keyA, listID: unlSet.listID, ledgerHash: ledger.ledgerHash, ledgerIndex: ledger.ledgerIndex),
                xrplValidationVote(keyB, listID: unlSet.listID, ledgerHash: ledger.ledgerHash, ledgerIndex: ledger.ledgerIndex),
                xrplValidationVote(keyC, listID: unlSet.listID, ledgerHash: ledger.ledgerHash, ledgerIndex: ledger.ledgerIndex),
                xrplValidationVote(keyD, listID: unlSet.listID, ledgerHash: ledger.ledgerHash, ledgerIndex: ledger.ledgerIndex),
                XRPLValidationVote(validatorPublicKey: validators[4].validatorPublicKey, ledgerHash: ledger.ledgerHash, ledgerIndex: ledger.ledgerIndex, signed: false)
            ],
            source: "fixture"
        )
        let proof: XRPLLocalProof
        switch kind {
        case .account:
            proof = XRPLLocalProof(
                proofID: "xrpl-fixture-account",
                kind: .account,
                network: network,
                subject: subject,
                expectedValueHash: accountValueHash,
                ledgerHash: ledger.ledgerHash,
                ledgerIndex: ledger.ledgerIndex,
                expectedRoot: ledger.accountStateRoot,
                leafHash: accountLeaf,
                witnesses: [XRPLProofWitness(hash: trustLineLeaf, position: .right)],
                source: "fixture"
            )
        case .trustLine:
            proof = XRPLLocalProof(
                proofID: "xrpl-fixture-trust-line",
                kind: .trustLine,
                network: network,
                subject: subject,
                counterparty: counterparty,
                currency: currency,
                expectedValueHash: trustLineValueHash,
                ledgerHash: ledger.ledgerHash,
                ledgerIndex: ledger.ledgerIndex,
                expectedRoot: ledger.accountStateRoot,
                leafHash: trustLineLeaf,
                witnesses: [XRPLProofWitness(hash: accountLeaf, position: .left)],
                source: "fixture"
            )
        case .payment:
            proof = XRPLLocalProof(
                proofID: "xrpl-fixture-payment",
                kind: .payment,
                network: network,
                subject: subject,
                counterparty: counterparty,
                currency: currency,
                transactionHash: transactionHash,
                expectedValueHash: paymentValueHash,
                ledgerHash: ledger.ledgerHash,
                ledgerIndex: ledger.ledgerIndex,
                expectedRoot: ledger.transactionMetadataRoot,
                leafHash: paymentLeaf,
                witnesses: [],
                source: "fixture"
            )
        }
        return XRPLProofVerificationBundle(
            ledger: ledger,
            unlSet: unlSet,
            validationProof: validationProof,
            proof: proof
        )
    }

    private static func moveValidatorKey(_ seed: UInt8) -> Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: seed, count: 32))
    }

    private static func moveValidatorSignature(
        _ key: Curve25519.Signing.PrivateKey,
        validatorID: String,
        chain: MoveChain,
        epoch: Int,
        checkpointDigest: String,
        sequenceNumber: Int
    ) -> MoveValidatorSignature {
        let message = MoveFinalityProof.canonicalVote(
            chain: chain,
            epoch: epoch,
            targetDigest: checkpointDigest,
            targetSequenceNumber: sequenceNumber
        )
        let signature = try! key.signature(for: message).base64EncodedString()
        return MoveValidatorSignature(
            validatorID: validatorID,
            checkpointDigest: checkpointDigest,
            sequenceNumber: sequenceNumber,
            signed: true,
            signature: signature
        )
    }

    private static func moveProofBundle(
        chain: MoveChain,
        kind: MoveLocalProofKind
    ) -> MoveProofVerificationBundle {
        if chain.kind == .sui {
            let keyA = moveValidatorKey(0xA1)
            let keyB = moveValidatorKey(0xB2)
            let keyC = moveValidatorKey(0xC3)
            let validators = [
                MoveValidator(validatorID: "sui-validator-a", weight: 40, name: "sui-a", publicKey: ed25519PublicKeyHex(keyA)),
                MoveValidator(validatorID: "sui-validator-b", weight: 35, name: "sui-b", publicKey: ed25519PublicKeyHex(keyB)),
                MoveValidator(validatorID: "sui-validator-c", weight: 25, name: "sui-c", publicKey: ed25519PublicKeyHex(keyC))
            ]
            let validatorSet = MoveValidatorSet(
                chain: chain,
                epoch: 42,
                validators: validators,
                source: "fixture"
            )
            let objectID = "0x" + String(repeating: "a1", count: 32)
            let transactionDigest = MoveHash.sha256Hex("sui-transaction-effects-fixture")
            let objectValueHash = MoveHash.sha256Hex("sui-object-owner:fixture")
            let effectsValueHash = MoveHash.sha256Hex("sui-effects:success")
            let objectLeaf = MoveLocalProof.fixtureLeafHash(
                kind: .suiObject,
                subject: "sui-object-fixture",
                objectID: objectID,
                valueHash: objectValueHash
            )
            let effectsLeaf = MoveLocalProof.fixtureLeafHash(
                kind: .suiTransactionEffects,
                subject: "sui-effects-fixture",
                transactionDigest: transactionDigest,
                valueHash: effectsValueHash
            )
            let stateRoot = MoveLocalProof.computeRoot(
                leafHash: objectLeaf,
                witnesses: [MoveProofWitness(hash: effectsLeaf, position: .right)]
            )!
            let checkpoint = MoveCheckpointSnapshot(
                chain: chain,
                sequenceNumber: 1_000_000,
                epoch: validatorSet.epoch,
                digest: MoveHash.sha256Hex("\(chain.chainRef)|1000000|checkpoint"),
                previousDigest: MoveHash.sha256Hex("\(chain.chainRef)|999999|checkpoint"),
                stateRoot: stateRoot,
                transactionEffectsRoot: effectsLeaf,
                timestamp: 1_717_000_000,
                finalized: true,
                source: "fixture"
            )
            let finalityProof = MoveFinalityProof(
                epoch: validatorSet.epoch,
                targetDigest: checkpoint.digest,
                targetSequenceNumber: checkpoint.sequenceNumber,
                signatures: [
                    moveValidatorSignature(keyA, validatorID: validators[0].validatorID, chain: chain, epoch: validatorSet.epoch, checkpointDigest: checkpoint.digest, sequenceNumber: checkpoint.sequenceNumber),
                    moveValidatorSignature(keyB, validatorID: validators[1].validatorID, chain: chain, epoch: validatorSet.epoch, checkpointDigest: checkpoint.digest, sequenceNumber: checkpoint.sequenceNumber),
                    MoveValidatorSignature(validatorID: validators[2].validatorID, checkpointDigest: checkpoint.digest, sequenceNumber: checkpoint.sequenceNumber, signed: false)
                ],
                source: "fixture"
            )
            let proof: MoveLocalProof
            switch kind {
            case .suiObject:
                proof = MoveLocalProof(
                    proofID: "sui-fixture-object",
                    kind: .suiObject,
                    chain: chain,
                    subject: "sui-object-fixture",
                    objectID: objectID,
                    expectedValueHash: objectValueHash,
                    checkpointDigest: checkpoint.digest,
                    sequenceNumber: checkpoint.sequenceNumber,
                    expectedRoot: checkpoint.stateRoot,
                    leafHash: objectLeaf,
                    witnesses: [MoveProofWitness(hash: effectsLeaf, position: .right)],
                    source: "fixture"
                )
            case .suiTransactionEffects:
                proof = MoveLocalProof(
                    proofID: "sui-fixture-effects",
                    kind: .suiTransactionEffects,
                    chain: chain,
                    subject: "sui-effects-fixture",
                    transactionDigest: transactionDigest,
                    expectedValueHash: effectsValueHash,
                    checkpointDigest: checkpoint.digest,
                    sequenceNumber: checkpoint.sequenceNumber,
                    expectedRoot: checkpoint.transactionEffectsRoot,
                    leafHash: effectsLeaf,
                    witnesses: [],
                    source: "fixture"
                )
            case .aptosAccount, .aptosTransaction:
                proof = MoveLocalProof(
                    proofID: "sui-invalid-proof-kind",
                    kind: .suiObject,
                    chain: chain,
                    subject: "sui-object-fixture",
                    objectID: objectID,
                    expectedValueHash: objectValueHash,
                    checkpointDigest: checkpoint.digest,
                    sequenceNumber: checkpoint.sequenceNumber,
                    expectedRoot: checkpoint.stateRoot,
                    leafHash: objectLeaf,
                    witnesses: [MoveProofWitness(hash: effectsLeaf, position: .right)],
                    source: "fixture"
                )
            }
            return MoveProofVerificationBundle(
                checkpoint: checkpoint,
                validatorSet: validatorSet,
                finalityProof: finalityProof,
                proof: proof
            )
        }

        let keyA = moveValidatorKey(0xD1)
        let keyB = moveValidatorKey(0xE2)
        let keyC = moveValidatorKey(0xF3)
        let validators = [
            MoveValidator(validatorID: "aptos-validator-a", weight: 45, name: "aptos-a", publicKey: ed25519PublicKeyHex(keyA)),
            MoveValidator(validatorID: "aptos-validator-b", weight: 35, name: "aptos-b", publicKey: ed25519PublicKeyHex(keyB)),
            MoveValidator(validatorID: "aptos-validator-c", weight: 20, name: "aptos-c", publicKey: ed25519PublicKeyHex(keyC))
        ]
        let validatorSet = MoveValidatorSet(
            chain: chain,
            epoch: 900,
            validators: validators,
            source: "fixture"
        )
        let accountAddress = "0x" + String(repeating: "b2", count: 32)
        let transactionDigest = MoveHash.sha256Hex("aptos-transaction-fixture")
        let accountValueHash = MoveHash.sha256Hex("aptos-account-balance:100")
        let transactionValueHash = MoveHash.sha256Hex("aptos-transaction:success")
        let accountLeaf = MoveLocalProof.fixtureLeafHash(
            kind: .aptosAccount,
            subject: "aptos-account-fixture",
            accountAddress: accountAddress,
            valueHash: accountValueHash
        )
        let transactionLeaf = MoveLocalProof.fixtureLeafHash(
            kind: .aptosTransaction,
            subject: "aptos-transaction-fixture",
            transactionDigest: transactionDigest,
            valueHash: transactionValueHash
        )
        let stateRoot = MoveLocalProof.computeRoot(
            leafHash: accountLeaf,
            witnesses: [MoveProofWitness(hash: transactionLeaf, position: .right)]
        )!
        let checkpoint = MoveCheckpointSnapshot(
            chain: chain,
            sequenceNumber: 250_000_000,
            epoch: validatorSet.epoch,
            digest: MoveHash.sha256Hex("\(chain.chainRef)|250000000|ledger-info"),
            previousDigest: MoveHash.sha256Hex("\(chain.chainRef)|249999999|ledger-info"),
            stateRoot: stateRoot,
            transactionEffectsRoot: transactionLeaf,
            timestamp: 1_718_000_000,
            finalized: true,
            source: "fixture"
        )
        let finalityProof = MoveFinalityProof(
            epoch: validatorSet.epoch,
            targetDigest: checkpoint.digest,
            targetSequenceNumber: checkpoint.sequenceNumber,
            signatures: [
                moveValidatorSignature(keyA, validatorID: validators[0].validatorID, chain: chain, epoch: validatorSet.epoch, checkpointDigest: checkpoint.digest, sequenceNumber: checkpoint.sequenceNumber),
                moveValidatorSignature(keyB, validatorID: validators[1].validatorID, chain: chain, epoch: validatorSet.epoch, checkpointDigest: checkpoint.digest, sequenceNumber: checkpoint.sequenceNumber),
                MoveValidatorSignature(validatorID: validators[2].validatorID, checkpointDigest: checkpoint.digest, sequenceNumber: checkpoint.sequenceNumber, signed: false)
            ],
            source: "fixture"
        )
        let proof: MoveLocalProof
        switch kind {
        case .aptosAccount:
            proof = MoveLocalProof(
                proofID: "aptos-fixture-account",
                kind: .aptosAccount,
                chain: chain,
                subject: "aptos-account-fixture",
                accountAddress: accountAddress,
                expectedValueHash: accountValueHash,
                checkpointDigest: checkpoint.digest,
                sequenceNumber: checkpoint.sequenceNumber,
                expectedRoot: checkpoint.stateRoot,
                leafHash: accountLeaf,
                witnesses: [MoveProofWitness(hash: transactionLeaf, position: .right)],
                source: "fixture"
            )
        case .aptosTransaction:
            proof = MoveLocalProof(
                proofID: "aptos-fixture-transaction",
                kind: .aptosTransaction,
                chain: chain,
                subject: "aptos-transaction-fixture",
                transactionDigest: transactionDigest,
                expectedValueHash: transactionValueHash,
                checkpointDigest: checkpoint.digest,
                sequenceNumber: checkpoint.sequenceNumber,
                expectedRoot: checkpoint.transactionEffectsRoot,
                leafHash: transactionLeaf,
                witnesses: [],
                source: "fixture"
            )
        case .suiObject, .suiTransactionEffects:
            proof = MoveLocalProof(
                proofID: "aptos-invalid-proof-kind",
                kind: .aptosAccount,
                chain: chain,
                subject: "aptos-account-fixture",
                accountAddress: accountAddress,
                expectedValueHash: accountValueHash,
                checkpointDigest: checkpoint.digest,
                sequenceNumber: checkpoint.sequenceNumber,
                expectedRoot: checkpoint.stateRoot,
                leafHash: accountLeaf,
                witnesses: [MoveProofWitness(hash: transactionLeaf, position: .right)],
                source: "fixture"
            )
        }
        return MoveProofVerificationBundle(
            checkpoint: checkpoint,
            validatorSet: validatorSet,
            finalityProof: finalityProof,
            proof: proof
        )
    }

    private static func cosmosHeaderBody(_ header: TendermintHeader) -> [String: Any] {
        [
            "chain": header.chain.chainID,
            "chain_ref": header.chain.chainRef,
            "chain_id": header.chain.chainID,
            "height": header.height,
            "time_unix_seconds": header.timeUnixSeconds,
            "last_block_id_hash": header.lastBlockIDHash,
            "validators_hash": header.validatorsHash,
            "next_validators_hash": header.nextValidatorsHash,
            "app_hash": header.appHash,
            "data_hash": header.dataHash ?? "",
            "evidence_hash": header.evidenceHash ?? "",
            "proposer_address": header.proposerAddress,
            "source": header.source ?? "fixture"
        ]
    }

    private static func cosmosValidatorSetBody(_ validatorSet: TendermintValidatorSet) -> [String: Any] {
        [
            "chain": validatorSet.chain.chainID,
            "chain_ref": validatorSet.chain.chainRef,
            "chain_id": validatorSet.chain.chainID,
            "height": validatorSet.height,
            "validators": validatorSet.validators.map { validator in
                [
                    "address": validator.address,
                    "public_key": validator.publicKey ?? "",
                    "voting_power": validator.votingPower,
                    "name": validator.name ?? ""
                ] as [String: Any]
            },
            "hash": validatorSet.hash,
            "source": validatorSet.source ?? "fixture"
        ]
    }

    private static func substrateHeaderBody(_ header: SubstrateHeaderSnapshot) -> [String: Any] {
        [
            "chain": header.chain.chainSpecID,
            "chain_ref": header.chain.chainRef,
            "chain_spec_id": header.chain.chainSpecID,
            "number": header.number,
            "hash": header.hash,
            "parent_hash": header.parentHash,
            "state_root": header.stateRoot,
            "extrinsics_root": header.extrinsicsRoot,
            "digest_logs": header.digestLogs,
            "finalized": header.finalized,
            "source": header.source ?? "fixture"
        ]
    }

    private static func substrateAuthoritySetBody(_ authoritySet: GRANDPAAuthoritySet) -> [String: Any] {
        [
            "chain": authoritySet.chain.chainSpecID,
            "chain_ref": authoritySet.chain.chainRef,
            "chain_spec_id": authoritySet.chain.chainSpecID,
            "set_id": authoritySet.setID,
            "authorities": authoritySet.authorities.map { authority in
                [
                    "authority_id": authority.authorityID,
                    "weight": authority.weight
                ] as [String: Any]
            },
            "hash": authoritySet.hash,
            "source": authoritySet.source ?? "fixture"
        ]
    }

    private static func avalancheAcceptedBlockBody(_ block: AvalancheAcceptedBlockSnapshot) -> [String: Any] {
        [
            "network": block.network.chainRef,
            "chain_ref": block.network.chainRef,
            "chain_id": block.network.chainID,
            "subnet_id": block.network.subnetID,
            "vm_id": block.network.vmID,
            "height": block.height,
            "block_hash": block.blockHash,
            "parent_hash": block.parentHash,
            "state_root": block.stateRoot,
            "receipts_root": block.receiptsRoot,
            "timestamp": block.timestamp ?? 0,
            "accepted": block.accepted,
            "source": block.source ?? "fixture"
        ]
    }

    private static func avalancheValidatorSetBody(_ validatorSet: AvalancheValidatorSet) -> [String: Any] {
        [
            "network": validatorSet.network.chainRef,
            "chain_ref": validatorSet.network.chainRef,
            "chain_id": validatorSet.network.chainID,
            "set_id": validatorSet.setID,
            "validators": validatorSet.validators.map { validator in
                [
                    "node_id": validator.nodeID,
                    "weight": validator.weight,
                    "public_key": validator.publicKey ?? ""
                ] as [String: Any]
            },
            "hash": validatorSet.hash,
            "source": validatorSet.source ?? "fixture"
        ]
    }

    private static func tronHeaderBody(_ header: TronBlockHeaderSnapshot) -> [String: Any] {
        [
            "network": header.network.chainRef,
            "chain_ref": header.network.chainRef,
            "number": header.number,
            "block_id": header.blockID,
            "parent_hash": header.parentHash,
            "witness_address": header.witnessAddress,
            "timestamp": header.timestamp,
            "account_state_root": header.accountStateRoot,
            "receipt_root": header.receiptRoot,
            "solid": header.solid,
            "source": header.source ?? "fixture"
        ]
    }

    private static func tronWitnessSetBody(_ witnessSet: TronWitnessSet) -> [String: Any] {
        [
            "network": witnessSet.network.chainRef,
            "chain_ref": witnessSet.network.chainRef,
            "epoch": witnessSet.epoch,
            "witnesses": witnessSet.witnesses.map { witness in
                [
                    "address": witness.address,
                    "weight": witness.weight,
                    "name": witness.name ?? ""
                ] as [String: Any]
            },
            "hash": witnessSet.hash,
            "source": witnessSet.source ?? "fixture"
        ]
    }

    private static func xrplLedgerBody(_ ledger: XRPLValidatedLedgerSnapshot) -> [String: Any] {
        [
            "network": ledger.network.chainRef,
            "chain_ref": ledger.network.chainRef,
            "ledger_index": ledger.ledgerIndex,
            "ledger_hash": ledger.ledgerHash,
            "parent_hash": ledger.parentHash,
            "account_state_root": ledger.accountStateRoot,
            "transaction_metadata_root": ledger.transactionMetadataRoot,
            "close_time": ledger.closeTime,
            "validated": ledger.validated,
            "source": ledger.source ?? "fixture"
        ]
    }

    private static func xrplUNLSetBody(_ unlSet: XRPLUNLSet) -> [String: Any] {
        [
            "network": unlSet.network.chainRef,
            "chain_ref": unlSet.network.chainRef,
            "list_id": unlSet.listID,
            "validators": unlSet.validators.map { validator in
                [
                    "validator_public_key": validator.validatorPublicKey,
                    "weight": validator.weight,
                    "domain": validator.domain ?? "",
                    "disabled": validator.disabled
                ] as [String: Any]
            },
            "negative_unl": unlSet.negativeUNL,
            "quorum_numerator": unlSet.quorumNumerator,
            "quorum_denominator": unlSet.quorumDenominator,
            "hash": unlSet.hash,
            "source": unlSet.source ?? "fixture"
        ]
    }

    private static func moveCheckpointBody(_ checkpoint: MoveCheckpointSnapshot) -> [String: Any] {
        [
            "chain": checkpoint.chain.chainRef,
            "chain_ref": checkpoint.chain.chainRef,
            "chain_id": checkpoint.chain.chainID,
            "sequence_number": checkpoint.sequenceNumber,
            "ledger_version": checkpoint.sequenceNumber,
            "epoch": checkpoint.epoch,
            "digest": checkpoint.digest,
            "ledger_info_hash": checkpoint.digest,
            "previous_digest": checkpoint.previousDigest,
            "state_root": checkpoint.stateRoot,
            "transaction_effects_root": checkpoint.transactionEffectsRoot,
            "transaction_accumulator_root": checkpoint.transactionEffectsRoot,
            "timestamp": checkpoint.timestamp,
            "finalized": checkpoint.finalized,
            "source": checkpoint.source ?? "fixture"
        ]
    }

    private static func moveValidatorSetBody(_ validatorSet: MoveValidatorSet) -> [String: Any] {
        [
            "chain": validatorSet.chain.chainRef,
            "chain_ref": validatorSet.chain.chainRef,
            "epoch": validatorSet.epoch,
            "validators": validatorSet.validators.map { validator in
                [
                    "validator_id": validator.validatorID,
                    "weight": validator.weight,
                    "name": validator.name ?? "",
                    "public_key": validator.publicKey ?? "",
                    "disabled": validator.disabled
                ] as [String: Any]
            },
            "quorum_numerator": validatorSet.quorumNumerator,
            "quorum_denominator": validatorSet.quorumDenominator,
            "hash": validatorSet.hash,
            "source": validatorSet.source ?? "fixture"
        ]
    }

    private static func evmProofResultBody(
        verified: Bool,
        state: String,
        proofID: String,
        kind: String,
        chain: EVMChain
    ) -> [String: Any] {
        [
            "verified": verified,
            "state": state,
            "proof_id": proofID,
            "kind": kind,
            "chain_ref": chain.chainRef,
            "block_hash": EVMHex.sha256Hex("\(chain.chainRef)-17000000-header"),
            "block_number": 17_000_000,
            "summary": "EVM \(kind) fixture proof checked."
        ]
    }

    private static func solanaProofResultBody(
        verified: Bool,
        state: String,
        proofID: String,
        kind: String,
        cluster: SolanaCluster
    ) -> [String: Any] {
        [
            "verified": verified,
            "state": state,
            "proof_id": proofID,
            "kind": kind,
            "chain_ref": cluster.chainRef,
            "slot": 281_474_976_710,
            "root_slot": 281_474_976_700,
            "summary": "Solana \(kind) fixture proof checked."
        ]
    }

    private static func cosmosProofResultBody(
        verified: Bool,
        state: String,
        chain: CosmosChain
    ) -> [String: Any] {
        let bundle = cosmosHeaderBundle(chain: chain)
        return [
            "verified": verified,
            "state": state,
            "chain_ref": chain.chainRef,
            "chain_id": chain.chainID,
            "height": bundle.header.height,
            "block_hash": bundle.header.hash,
            "validator_set_hash": bundle.validatorSet.hash,
            "summary": "Tendermint header \(bundle.header.height) verified."
        ]
    }

    private static func substrateProofResultBody(
        verified: Bool,
        state: String,
        chain: SubstrateChain
    ) -> [String: Any] {
        let bundle = substrateProofBundle(chain: chain)
        return [
            "verified": verified,
            "state": state,
            "chain_ref": chain.chainRef,
            "chain_spec_id": chain.chainSpecID,
            "block_number": bundle.header.number,
            "block_hash": bundle.header.hash,
            "proof_id": bundle.storageProof?.proofID ?? "substrate-storage-proof",
            "storage_key": bundle.storageProof?.storageKey ?? substrateStorageKey,
            "summary": "Substrate storage proof checked."
        ]
    }

    private static func avalancheProofResultBody(
        verified: Bool,
        state: String,
        network: AvalancheNetwork
    ) -> [String: Any] {
        let bundle = avalancheProofBundle(network: network)
        return [
            "verified": verified,
            "state": state,
            "chain_ref": network.chainRef,
            "block_number": bundle.acceptedBlock.height,
            "block_hash": bundle.acceptedBlock.blockHash,
            "proof_id": bundle.evmProof?.proof.proofID ?? "avalanche-fixture-account",
            "summary": "Avalanche Snowman accepted block checked with C-Chain proof evidence."
        ]
    }

    private static func tronProofResultBody(
        verified: Bool,
        state: String,
        network: TronNetwork
    ) -> [String: Any] {
        let bundle = tronProofBundle(network: network)
        return [
            "verified": verified,
            "state": state,
            "chain_ref": network.chainRef,
            "block_number": bundle.header.number,
            "block_id": bundle.header.blockID,
            "proof_id": bundle.proof?.proofID ?? "tron-fixture-token",
            "kind": bundle.proof?.kind.rawValue ?? "token",
            "summary": "TRON token proof checked against solid block."
        ]
    }

    private static func xrplProofResultBody(
        verified: Bool,
        state: String,
        network: XRPLNetwork
    ) -> [String: Any] {
        let bundle = xrplProofBundle(network: network)
        return [
            "verified": verified,
            "state": state,
            "chain_ref": network.chainRef,
            "ledger_index": bundle.ledger.ledgerIndex,
            "ledger_hash": bundle.ledger.ledgerHash,
            "proof_id": bundle.proof?.proofID ?? "xrpl-fixture-account",
            "kind": bundle.proof?.kind.rawValue ?? "account",
            "summary": "XRPL account proof checked against validated ledger."
        ]
    }

    private static func moveProofResultBody(
        verified: Bool,
        state: String,
        chain: MoveChain,
        kind: MoveLocalProofKind
    ) -> [String: Any] {
        let bundle = moveProofBundle(chain: chain, kind: kind)
        return [
            "verified": verified,
            "state": state,
            "chain_ref": chain.chainRef,
            "sequence_number": bundle.checkpoint.sequenceNumber,
            "checkpoint_digest": bundle.checkpoint.digest,
            "proof_id": bundle.proof?.proofID ?? "move-fixture-proof",
            "kind": bundle.proof?.kind.rawValue ?? kind.rawValue,
            "summary": "\(chain.displayName) \(kind.rawValue) proof checked against Move checkpoint."
        ]
    }

    private static func jsonResponse(
        for request: URLRequest,
        status: Int = 200,
        body: Any
    ) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

    private static func emptyResponse(
        for request: URLRequest,
        status: Int = 204
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: [:]
        )!
        return (response, Data())
    }

    private static var repositoryRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func jsonString(_ body: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: body)
        return String(data: data, encoding: .utf8)!
    }

}

@MainActor
private final class MockLocalLLMManager: LocalLLMManaging {
    private(set) var currentState: LocalLLMManagementState
    private let refreshState: LocalLLMManagementState
    private(set) var calls: [String] = []

    init(initialState: LocalLLMManagementState, refreshState: LocalLLMManagementState) {
        self.currentState = initialState
        self.refreshState = refreshState
    }

    func refresh() async -> LocalLLMManagementState {
        calls.append("refresh")
        return update()
    }

    func connect() async -> LocalLLMManagementState {
        calls.append("connect")
        return update()
    }

    func bootstrapEmbeddedControlPlane() async -> LocalLLMManagementState {
        calls.append("bootstrap")
        return update()
    }

    func importRecommendedModel() async -> LocalLLMManagementState {
        calls.append("importRecommended")
        return update()
    }

    func inspectModel(id: String) async -> LocalLLMManagementState {
        calls.append("inspect:\(id)")
        return update()
    }

    func validateModel(id: String) async -> LocalLLMManagementState {
        calls.append("validate:\(id)")
        return update()
    }

    func warmModel(id: String) async -> LocalLLMManagementState {
        calls.append("warm:\(id)")
        return update()
    }

    func stopEngine(id: String) async -> LocalLLMManagementState {
        calls.append("stop:\(id)")
        return update()
    }

    func installBackend(id: String) async -> LocalLLMManagementState {
        calls.append("install:\(id)")
        return update()
    }

    private func update() -> LocalLLMManagementState {
        currentState = refreshState
        return refreshState
    }
}

private final class JSONRequestCapture {
    private let lock = NSLock()
    private var bodiesByPath: [String: [String: Any]] = [:]

    func capture(_ request: URLRequest) {
        guard let path = request.url?.path, let data = request.httpBody ?? Self.readBodyStream(request.httpBodyStream) else { return }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        lock.lock()
        bodiesByPath[path] = object
        lock.unlock()
    }

    func body(for path: String) -> [String: Any]? {
        lock.lock()
        let body = bodiesByPath[path]
        lock.unlock()
        return body
    }

    fileprivate static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}

private final class JSONRPCRequestCapture {
    private let lock = NSLock()
    private var bodies: [[String: Any]] = []

    func capture(_ request: URLRequest) -> [String: Any]? {
        guard let data = request.httpBody ?? JSONRequestCapture.readBodyStream(request.httpBodyStream),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        lock.lock()
        bodies.append(object)
        lock.unlock()
        return object
    }

    func toolArguments(named name: String) -> [String: Any]? {
        lock.lock()
        let match = bodies.last { body in
            guard body["method"] as? String == "tools/call",
                  let params = body["params"] as? [String: Any] else {
                return false
            }
            return params["name"] as? String == name
        }
        lock.unlock()

        let params = match?["params"] as? [String: Any]
        return params?["arguments"] as? [String: Any]
    }
}

private final class AFMServiceMockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    private static let lock = NSLock()

    nonisolated static func register(
        key: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        requestHandlers[key] = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let key = request.url?.host?.split(separator: "-").first.map(String.init) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Self.lock.lock()
        let handler = Self.requestHandlers[key]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
