import Foundation

enum BrowserPanel: String, CaseIterable, Hashable, Identifiable {
    case history
    case bookmarks
    case wallet
    case mcp
    case a2ui
    case copilot
    case runtime

    var id: String { rawValue }

    static let browserSidebarPanels: [BrowserPanel] = [
        .history,
        .bookmarks,
        .mcp,
        .a2ui,
        .copilot,
        .runtime
    ]

    var title: String {
        switch self {
        case .history: "History"
        case .bookmarks: "Bookmarks"
        case .wallet: "Wallet"
        case .mcp: "MCP"
        case .a2ui: "A2UI"
        case .copilot: "Copilot"
        case .runtime: "Runtime"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .bookmarks: "bookmark"
        case .wallet: "wallet.pass"
        case .mcp: "network"
        case .a2ui: "square.grid.2x2"
        case .copilot: "sparkles"
        case .runtime: "server.rack"
        }
    }
}

enum BrowserWebCommand: Equatable {
    case back
    case forward
    case reload
    case stop
}

struct BrowserWebCommandRequest: Equatable, Identifiable {
    let id = UUID()
    let tabID: UUID
    let command: BrowserWebCommand
}

struct BrowserNavigationUpdate: Equatable {
    let tabID: UUID
    let urlString: String?
    let title: String?
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
}

struct BrowserTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var isLoading: Bool
    var canGoBack: Bool
    var canGoForward: Bool
    var mobileNotice: String?

    init(
        id: UUID = UUID(),
        title: String = "Home",
        urlString: String = "about:home",
        isLoading: Bool = false,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        mobileNotice: String? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.mobileNotice = mobileNotice
    }

    var loadableURL: URL? {
        guard mobileNotice == nil else { return nil }
        guard urlString != BrowserURLResolver.homeURLString else { return nil }
        return URL(string: urlString)
    }

    var displayURL: String {
        if urlString == BrowserURLResolver.homeURLString {
            return "Home"
        }
        return urlString
    }
}

struct BrowserHistoryEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let title: String
    let urlString: String
    let visitedAt: Date
    var summary: String?
    var isSmartHistoryIndexed: Bool

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        visitedAt: Date,
        summary: String? = nil,
        isSmartHistoryIndexed: Bool = true
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.visitedAt = visitedAt
        self.summary = summary
        self.isSmartHistoryIndexed = isSmartHistoryIndexed
    }
}

struct BrowserAddressSuggestion: Identifiable, Equatable {
    let title: String
    let urlString: String

    var id: String { urlString }
}

struct BrowserBookmark: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let urlString: String

    static let defaults: [BrowserBookmark] = [
        BrowserBookmark(title: "Zero Knowledge Gateway", urlString: RuntimeGatewayStartingPoint.zeroKnowledgeGateway.urlString),
        BrowserBookmark(title: "LLM OS Show and Tell", urlString: RuntimeGatewayStartingPoint.llmOS.urlString),
        BrowserBookmark(title: "Advatar Browser", urlString: "https://github.com/advatar/browser"),
        BrowserBookmark(title: "DuckDuckGo", urlString: "https://duckduckgo.com")
    ]
}

struct RuntimeGatewayStartingPoint: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let urlString: String
    let systemImage: String
    let isZeroKnowledgeGateway: Bool

    init(
        title: String,
        description: String,
        urlString: String,
        systemImage: String,
        isZeroKnowledgeGateway: Bool = false
    ) {
        self.id = urlString
        self.title = title
        self.description = description
        self.urlString = urlString
        self.systemImage = systemImage
        self.isZeroKnowledgeGateway = isZeroKnowledgeGateway
    }

    static let zeroKnowledgeGateway = RuntimeGatewayStartingPoint(
        title: "Zero Knowledge Gateway",
        description: "Primary gateway for zero-knowledge browser capabilities and proofs.",
        urlString: "https://zerok.cloud",
        systemImage: "shield.lefthalf.filled",
        isZeroKnowledgeGateway: true
    )

    static let llmOS = RuntimeGatewayStartingPoint(
        title: "LLM OS",
        description: "Show-and-tell runtime surface for LLM OS integration.",
        urlString: "https://llmos.showntell.dev",
        systemImage: "sparkles"
    )

    static let featured: [RuntimeGatewayStartingPoint] = [
        zeroKnowledgeGateway,
        llmOS
    ]
}

struct DecentralizedStartingPoint: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let address: String
    let systemImage: String

    init(title: String, description: String, address: String, systemImage: String) {
        self.id = address
        self.title = title
        self.description = description
        self.address = address
        self.systemImage = systemImage
    }

    static let featured: [DecentralizedStartingPoint] = [
        DecentralizedStartingPoint(
            title: "IPFS Docs",
            description: "Protocol guides, concepts, and examples published through IPNS.",
            address: "ipns://docs.ipfs.tech",
            systemImage: "book.closed"
        ),
        DecentralizedStartingPoint(
            title: "IPFS Home",
            description: "The public IPFS project site served through a mutable IPNS name.",
            address: "ipns://ipfs.tech",
            systemImage: "network"
        ),
        DecentralizedStartingPoint(
            title: "Wikipedia on IPFS",
            description: "A decentralized mirror that demonstrates large public knowledge content.",
            address: "ipns://en.wikipedia-on-ipfs.org",
            systemImage: "text.book.closed"
        ),
        DecentralizedStartingPoint(
            title: "Sample CID",
            description: "A content-addressed IPFS object for checking gateway and CID resolution.",
            address: "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi",
            systemImage: "cube.box"
        )
    ]
}

struct RuntimeFeatureExplanation: Equatable {
    let overview: String
    let bridgeBehavior: String
    let detailPoints: [String]
}

enum MobileRuntimeFeature: String, CaseIterable, Identifiable {
    case webBrowsing
    case tabs
    case decentralizedProtocols
    case architectureOverview
    case chainTrust
    case mcpServers
    case a2uiRendering
    case logosRuntime
    case afmServices
    case copilot
    case wallet
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webBrowsing: "Web browsing"
        case .tabs: "Tabs and history"
        case .decentralizedProtocols: "IPFS, IPNS, ENS"
        case .architectureOverview: "Architecture"
        case .chainTrust: "Chain trust"
        case .mcpServers: "MCP servers"
        case .a2uiRendering: "A2UI rendering"
        case .logosRuntime: "Logos runtime"
        case .afmServices: "AFM services"
        case .copilot: "AI Copilot"
        case .wallet: "Wallet policies"
        case .downloads: "Downloads"
        }
    }

    var status: String {
        switch self {
        case .webBrowsing: "Native WKWebView"
        case .tabs: "Native Swift state"
        case .decentralizedProtocols: "Gateway bridge"
        case .architectureOverview: "Light clients + AF Market + ZeroK"
        case .chainTrust: "Gateway/RPC fallback"
        case .mcpServers: "HTTP, WebSocket, STDIO"
        case .a2uiRendering: "Native SwiftUI widgets"
        case .logosRuntime: "Basecamp modules"
        case .afmServices: "Router, registry, pipelines"
        case .copilot: "Local command bridge"
        case .wallet: "Local policy bridge"
        case .downloads: "Native URLSession"
        }
    }

    var systemImage: String {
        switch self {
        case .webBrowsing: "safari"
        case .tabs: "rectangle.on.rectangle"
        case .decentralizedProtocols: "link"
        case .architectureOverview: "square.stack.3d.up"
        case .chainTrust: "checkmark.shield"
        case .mcpServers: "network"
        case .a2uiRendering: "square.grid.2x2"
        case .logosRuntime: "shippingbox"
        case .afmServices: "point.3.connected.trianglepath.dotted"
        case .copilot: "sparkles"
        case .wallet: "wallet.pass"
        case .downloads: "arrow.down.circle"
        }
    }

    var isAvailableOnMobile: Bool {
        true
    }

    var explanation: RuntimeFeatureExplanation {
        switch self {
        case .webBrowsing:
            RuntimeFeatureExplanation(
                overview: "Loads standard HTTP and HTTPS pages with native WKWebView while the app keeps browser state in Swift.",
                bridgeBehavior: "This path is fully native on iOS and does not need the desktop Tauri runtime.",
                detailPoints: [
                    "Address-bar input is normalized before WebKit receives a request.",
                    "Page title, loading, and back-forward state flow back into the tab model.",
                    "Unsupported schemes are stopped before WebKit can attempt to open them directly."
                ]
            )
        case .tabs:
            RuntimeFeatureExplanation(
                overview: "Tracks tabs, history, bookmarks, and toolbar commands inside the Swift shell.",
                bridgeBehavior: "The current bridge stores this state in memory so the iOS app can run independently.",
                detailPoints: [
                    "Opening, closing, and activating tabs updates the same model used by the browser surface.",
                    "History entries are deduplicated at the front of the list to avoid repeated reload noise.",
                    "Toolbar actions are translated into typed web-view commands instead of stringly callbacks."
                ]
            )
        case .decentralizedProtocols:
            RuntimeFeatureExplanation(
                overview: "Resolves IPFS, IPNS, ENS, and compatible wallet-style names into loadable mobile web URLs while preserving the embedded light-client contract for chain-backed state.",
                bridgeBehavior: "Today the iOS bridge uses gateway fallback through dweb.link and .limo; parity with the desktop decentralized runtime means bridging to embedded Ethereum and Substrate/Polkadot light clients instead of trusting centralized RPC endpoints.",
                detailPoints: [
                    "ipfs:// and ipns:// inputs are converted into HTTPS gateway paths before WKWebView loads them.",
                    "ENS-style names are intercepted before the generic HTTPS fallback so they can use decentralized resolution rules.",
                    "Embedded light clients verify block headers and essential proofs locally for chain-backed resolution, wallet state, transaction broadcast, and AFM settlement checks.",
                    "External RPC endpoints should remain development or fallback transports; they should not become the trust root for decentralized browsing.",
                    "Resolution results preserve a clear source, making it possible to show whether content came from native, light-client, gateway, or remote runtime resolution."
                ]
            )
        case .architectureOverview:
            RuntimeFeatureExplanation(
                overview: "Explains how the Swift browser shell, embedded blockchain light clients, AF Market, AFM services, ZeroK, and the LLM Gateway fit together.",
                bridgeBehavior: "The iOS shell keeps navigation, history, wallet policy, and selected context local; embedded light clients verify chain state; AF Market routes work through AFM router, registry, and pipelines; privacy-sensitive LLM calls use the ZeroK LLM Gateway path documented in ../ZeroK.",
                detailPoints: [
                    "Embedded Ethereum-compatible and Substrate/Polkadot light clients are the chain-trust layer: they verify headers and essential proofs locally for ENS, wallet state, transaction broadcast, escrow status, and proof settlement.",
                    "Each blockchain needs its own light-client verifier and consensus rules; routing every chain through a centralized RPC provider would collapse the decentralized trust boundary.",
                    "AF Market is the pack discovery and install surface. The AFM router selects an expert or pack, registry supplies deterministic metadata and signing keys, and pipelines queues the selected work.",
                    "ZeroK LLM Gateway calls are sent as encrypted envelopes with token-class padding and ZK-ready usage tickets, so relays cannot read prompts and billing authorization can be proven without revealing identity.",
                    "The optional privacy relay hides the client IP from the gateway, while the gateway still decrypts for provider-bound inference and enforces replay protection with nullifiers.",
                    "The visible HTTPS starting points are https://zerok.cloud for ZeroK and https://llmos.showntell.dev for the LLM Gateway and LLM OS surface.",
                    "The app should send only selected, redacted page context to the gateway; browser history, long-term memory, and tab state remain in the Swift app unless a user action shares them.",
                    "Provider boundary: upstream LLM infrastructure can still correlate decrypted prompt content and timing unless future confidential inference or enclave-backed execution is added."
                ]
            )
        case .chainTrust:
            RuntimeFeatureExplanation(
                overview: "Reports chain trust state through one Swift registry for browser resolution, wallet state, Copilot actions, and AFM settlement evidence.",
                bridgeBehavior: "The current bridge labels gateway/RPC fallback separately from proof-checked settlement evidence and future embedded light-client verification.",
                detailPoints: [
                    "Bitcoin, Ethereum/EVM/L2s, Solana, Cosmos/Tendermint, Polkadot/Substrate, Avalanche, TRON, XRP Ledger, Sui, and Aptos report through the same status model.",
                    "Bitcoin has a Swift light-client contract for SPV header sync, BIP157/158 compact-filter readiness, Merkle inclusion checks, stale peers, and reorg transitions.",
                    "Gateway or RPC data stays marked as fallback and is not presented as local verification.",
                    "AFMarket settlement receipts can raise a chain entry to proof-checked without implying full light-client verification.",
                    "Future chain-specific clients can plug in verified, syncing, stale, failed, and unavailable states without changing UI contracts."
                ]
            )
        case .mcpServers:
            RuntimeFeatureExplanation(
                overview: "Connects Model Context Protocol servers so Copilot and future agent workflows can use external tools, resources, and prompts.",
                bridgeBehavior: "The Swift bridge keeps editable MCP server configuration and connection state in app state today; the same contract can be backed by the desktop MCP profile service later.",
                detailPoints: [
                    "HTTP, WebSocket, and STDIO transports are modeled explicitly so endpoint and program validation match the desktop manifest shape.",
                    "Disabled servers stay inert until the user enables and connects them.",
                    "Connection results record status text and discovered tool names so the UI can show negotiated capability readiness.",
                    "Secrets should move through the existing encrypted MCP profile/keyring service before production use."
                ]
            )
        case .a2uiRendering:
            RuntimeFeatureExplanation(
                overview: "Renders A2UI v0.9 token streams as native SwiftUI widgets through the imported a2ui-swift renderer, while letting app authors choose a runtime profile such as Logos Basecamp.",
                bridgeBehavior: "The A2UI panel feeds raw LLM or gateway output into A2UIStreamParser, processes decoded A2uiMessage values with SurfaceViewModel, renders the result through A2UISurfaceView, and keeps the selected runtime profile available for action routing.",
                detailPoints: [
                    "The app links A2UISwiftCore for token parsing, schema decoding, and surface state.",
                    "The app links A2UISwiftUI for the native widget catalog including text, cards, rows, columns, text fields, and buttons.",
                    "Resolved button actions are logged locally today and can be routed through the same approval boundaries used by Copilot, wallet, MCP, ZeroK, and LLM Gateway flows.",
                    "A2UI apps can stay in the native SwiftUI profile or target Logos Basecamp when they need decentralized storage, messaging, blockchain, wallet, or AI-inspection modules.",
                    "The renderer is isolated behind a Swift wrapper so future tokens from https://zerok.cloud and https://llmos.showntell.dev can use the same surface contract."
                ]
            )
        case .logosRuntime:
            RuntimeFeatureExplanation(
                overview: "Offers Logos Basecamp as the local-first, decentralised runtime profile for A2UI apps that need modular storage, messaging, blockchain, wallet, and AI-inspection capabilities.",
                bridgeBehavior: "The Swift app currently exposes the Logos runtime as a selectable A2UI profile with Basecamp launch and isolation guidance; the next bridge layer should start or attach to Logos modules instead of treating it as an external web page.",
                detailPoints: [
                    "Logos Basecamp lives at https://github.com/logos-co/logos-basecamp and the full docs live at https://github.com/logos-co/logos-docs.",
                    "Basecamp starts the Logos core runtime and loads configured module profiles for decentralized apps.",
                    "The Logos networking layer covers discovery, peering, and mixnet routing so capability discovery is not pinned to a centralized registry.",
                    "Important modules for dBrowser A2UI apps are Storage, Messaging / Logos Delivery, Blockchain / Execution Zone, and LEZ Wallet flows for private and public state.",
                    "Use nix build '.#bin-macos-app' and open result/LogosBasecamp.app for the macOS bundle, or use LogosBasecamp --user-dir <path> / LOGOS_USER_DIR=<path> for isolated app profiles.",
                    "Basecamp also exposes MCP/QML Inspector support, which lines up with the app's MCP server UI and AI assistant control surface."
                ]
            )
        case .afmServices:
            RuntimeFeatureExplanation(
                overview: "Connects the Swift shell to the AFM router, registry, and pipelines services from the shared workspace.",
                bridgeBehavior: "The bridge checks service health, reads pack metadata, asks the router for a Copilot selection, and enqueues work in pipelines when endpoints are reachable.",
                detailPoints: [
                    "Router calls use the same /route contract as the workspace service.",
                    "Registry calls load pack metadata so mobile status reflects the available AFM catalog.",
                    "Pipelines calls queue service-backed Copilot jobs while keeping a local fallback for offline development."
                ]
            )
        case .copilot:
            RuntimeFeatureExplanation(
                overview: "Creates a mobile command surface for Copilot tasks tied to the active browsing context.",
                bridgeBehavior: "The bridge routes through AFM services when available and falls back to deterministic local summaries when those services are offline.",
                detailPoints: [
                    "Prompts can carry the active page URL so Copilot has a target for future page-context extraction.",
                    "Suggested actions stay explicit so wallet and download operations can remain approval-gated.",
                    "The bridge API is asynchronous, matching the shape needed for real model runs and cancellation."
                ]
            )
        case .wallet:
            RuntimeFeatureExplanation(
                overview: "Models wallet connection state and spend-policy decisions for browser actions.",
                bridgeBehavior: "The current iOS bridge is a local policy simulator; it does not custody production keys yet.",
                detailPoints: [
                    "Connect and disconnect actions update a typed wallet state object.",
                    "Spend evaluation rejects invalid requests and requires explicit approval above the local policy limit.",
                    "The same contract can be backed by Secure Enclave keys, WalletConnect, or a desktop wallet bridge."
                ]
            )
        case .downloads:
            RuntimeFeatureExplanation(
                overview: "Starts, tracks, cancels, and completes browser downloads through native iOS networking.",
                bridgeBehavior: "The bridge stores download items in Swift state and uses URLSession for real transfer work.",
                detailPoints: [
                    "Queued mode lets tests and future approval flows create download records without touching the network.",
                    "Completed files are moved into the app temporary directory with the response filename when available.",
                    "Cancellation and failures update typed states so the UI can avoid pretending unsupported actions worked."
                ]
            )
        }
    }
}

enum BrowserAddressResolution: Equatable {
    case home
    case web(URL)
    case unsupported(raw: String, message: String)
}

enum BrowserURLResolver {
    static let homeURLString = "about:home"
    static let defaultSearchEndpoint = "https://duckduckgo.com/"

    static func resolve(_ rawInput: String) -> BrowserAddressResolution {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return .home
        }

        if input.caseInsensitiveCompare(homeURLString) == .orderedSame || input.caseInsensitiveCompare("about:blank") == .orderedSame {
            return .home
        }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return .web(url)
            case "ipfs", "ipns", "ens":
                return .unsupported(
                    raw: input,
                    message: "The iOS runtime bridge could not resolve this \(scheme):// address."
                )
            default:
                return .unsupported(
                    raw: input,
                    message: "The iOS shell blocks unsupported URL schemes until a native handler is registered."
                )
            }
        }

        if looksLikeDecentralizedName(input) {
            return .unsupported(
                raw: input,
                message: "The iOS runtime bridge could not resolve this decentralized name."
            )
        }

        if looksLikeHost(input), let url = URL(string: "https://\(input)") {
            return .web(url)
        }

        return .web(searchURL(for: input))
    }

    private static func looksLikeHost(_ input: String) -> Bool {
        guard !input.contains(" ") else { return false }
        guard input.contains(".") || input.caseInsensitiveCompare("localhost") == .orderedSame else { return false }
        return true
    }

    private static func looksLikeDecentralizedName(_ input: String) -> Bool {
        let lowercased = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.contains(" ") else { return false }
        let name = lowercased.split(separator: "/").first.map(String.init) ?? lowercased
        return [".eth", ".crypto", ".blockchain"].contains { name.hasSuffix($0) }
    }

    private static func searchURL(for query: String) -> URL {
        var components = URLComponents(string: defaultSearchEndpoint)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }
}
