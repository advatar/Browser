import Foundation

enum BrowserPanel: String, CaseIterable, Hashable, Identifiable {
    case history
    case bookmarks
    case copilot
    case runtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .bookmarks: "Bookmarks"
        case .copilot: "Copilot"
        case .runtime: "Runtime"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .bookmarks: "bookmark"
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

struct BrowserHistoryEntry: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let urlString: String
    let visitedAt: Date
}

struct BrowserBookmark: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let urlString: String
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
    case copilot
    case wallet
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webBrowsing: "Web browsing"
        case .tabs: "Tabs and history"
        case .decentralizedProtocols: "IPFS, IPNS, ENS"
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
                overview: "Resolves IPFS, IPNS, ENS, and compatible wallet-style names into loadable mobile web URLs.",
                bridgeBehavior: "Today the iOS bridge uses gateway fallback through dweb.link and .limo; the contract can later swap to embedded Rust or a trusted remote resolver.",
                detailPoints: [
                    "ipfs:// and ipns:// inputs are converted into HTTPS gateway paths before WKWebView loads them.",
                    "ENS-style names are intercepted before the generic HTTPS fallback so they can use decentralized resolution rules.",
                    "Resolution results preserve a clear source, making it possible to show whether content came from native, gateway, or remote runtime resolution."
                ]
            )
        case .copilot:
            RuntimeFeatureExplanation(
                overview: "Creates a mobile command surface for Copilot tasks tied to the active browsing context.",
                bridgeBehavior: "The local bridge prepares deterministic run summaries and suggested actions; model execution can be connected to the desktop or cloud runtime later.",
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
