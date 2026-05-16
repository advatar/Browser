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
