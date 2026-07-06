import Foundation
@preconcurrency import WebKit

enum BrowserAdBlockingMode: String, Codable, Equatable {
    case enabled
    case paused

    var isEnabled: Bool {
        self == .enabled
    }

    var toggled: BrowserAdBlockingMode {
        isEnabled ? .paused : .enabled
    }

    var toolbarHelp: String {
        switch self {
        case .enabled:
            return "Ad and tracker blocking is on"
        case .paused:
            return "Ad and tracker blocking is paused"
        }
    }

    var statusText: String {
        switch self {
        case .enabled:
            return "ads blocked"
        case .paused:
            return "ads allowed"
        }
    }

    var systemImage: String {
        switch self {
        case .enabled:
            return "shield.lefthalf.filled"
        case .paused:
            return "shield.slash"
        }
    }
}

enum BrowserAdBlockingSettings {
    static let defaultsKey = "dev.advatar.dBrowser.adBlockingMode"

    static func load(defaults: UserDefaults = .standard) -> BrowserAdBlockingMode {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = BrowserAdBlockingMode(rawValue: rawValue) else {
            return .enabled
        }
        return mode
    }

    static func save(_ mode: BrowserAdBlockingMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }
}

struct BrowserAdBlockingRule: Codable, Equatable {
    struct Trigger: Codable, Equatable {
        var urlFilter: String
        var resourceType: [String]?
        var loadType: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case resourceType = "resource-type"
            case loadType = "load-type"
        }
    }

    struct Action: Codable, Equatable {
        var type: String
        var selector: String?
    }

    var trigger: Trigger
    var action: Action
}

enum BrowserAdBlockingRules {
    static let identifier = "dev.advatar.dBrowser.contentBlocker.v1"

    static let blockedResourceTypes = [
        "document",
        "image",
        "style-sheet",
        "script",
        "font",
        "media",
        "raw",
        "svg-document"
    ]

    static let adNetworkDomains = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com",
        "2mdn.net",
        "adnxs.com",
        "adsrvr.org",
        "amazon-adsystem.com",
        "taboola.com",
        "outbrain.com",
        "pubmatic.com",
        "rubiconproject.com",
        "criteo.com",
        "openx.net",
        "yieldmo.com",
        "sharethrough.com",
        "smartadserver.com",
        "moatads.com"
    ]

    static let trackerDomains = [
        "google-analytics.com",
        "googletagmanager.com",
        "analytics.google.com",
        "facebook.net",
        "connect.facebook.net",
        "facebook.com/tr",
        "scorecardresearch.com",
        "quantserve.com",
        "hotjar.com",
        "hotjar.io",
        "segment.io",
        "segment.com",
        "mixpanel.com",
        "amplitude.com",
        "fullstory.com",
        "newrelic.com",
        "nr-data.net",
        "sentry.io"
    ]

    static let localRouteFilters = [
        #"^https?://localhost"#,
        #"^https?://127\.0\.0\.1"#,
        #"^https?://\[::1\]"#,
        #"^https?://.*\.local"#
    ]

    static var defaultRules: [BrowserAdBlockingRule] {
        adNetworkDomains.map { blockHost($0) }
            + trackerDomains.map { blockHost($0) }
            + cookieStrippingDomains.map { stripTrackingCookies(from: $0) }
            + adPathFilters.map(blockThirdPartyAdPath)
            + [hideCommonAdContainers()]
            + localRouteFilters.map(preserveLocalAndDecentralizedRoute)
    }

    static func contentRuleListJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(defaultRules)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return json
    }

    private static let cookieStrippingDomains = [
        "doubleclick.net",
        "googlesyndication.com",
        "google-analytics.com",
        "facebook.com",
        "facebook.net",
        "scorecardresearch.com",
        "quantserve.com"
    ]

    private static let adPathFilters = [
        "/adservice",
        "/adserver",
        "/adclick",
        "/adsystem",
        "/advertising",
        "/sponsor",
        "/sponsored",
        "/prebid",
        "/pagead"
    ]

    private static func escapedURLFilter(for literal: String) -> String {
        NSRegularExpression.escapedPattern(for: literal)
    }

    private static func blockHost(_ host: String) -> BrowserAdBlockingRule {
        BrowserAdBlockingRule(
            trigger: BrowserAdBlockingRule.Trigger(
                urlFilter: escapedURLFilter(for: host),
                resourceType: blockedResourceTypes,
                loadType: nil
            ),
            action: BrowserAdBlockingRule.Action(type: "block", selector: nil)
        )
    }

    private static func blockThirdPartyAdPath(_ pathFilter: String) -> BrowserAdBlockingRule {
        BrowserAdBlockingRule(
            trigger: BrowserAdBlockingRule.Trigger(
                urlFilter: escapedURLFilter(for: pathFilter),
                resourceType: blockedResourceTypes,
                loadType: ["third-party"]
            ),
            action: BrowserAdBlockingRule.Action(type: "block", selector: nil)
        )
    }

    private static func stripTrackingCookies(from host: String) -> BrowserAdBlockingRule {
        BrowserAdBlockingRule(
            trigger: BrowserAdBlockingRule.Trigger(
                urlFilter: escapedURLFilter(for: host),
                resourceType: blockedResourceTypes,
                loadType: ["third-party"]
            ),
            action: BrowserAdBlockingRule.Action(type: "block-cookies", selector: nil)
        )
    }

    private static func hideCommonAdContainers() -> BrowserAdBlockingRule {
        BrowserAdBlockingRule(
            trigger: BrowserAdBlockingRule.Trigger(
                urlFilter: ".*",
                resourceType: ["document"],
                loadType: nil
            ),
            action: BrowserAdBlockingRule.Action(
                type: "css-display-none",
                selector: ".adsbygoogle, [id^='google_ads_'], [id*='ad-slot'], [id*='ad_slot'], [class*='ad-banner'], [class*='ad_banner'], [class*='sponsored'], iframe[src*='doubleclick.net'], iframe[src*='googlesyndication.com']"
            )
        )
    }

    private static func preserveLocalAndDecentralizedRoute(_ urlFilter: String) -> BrowserAdBlockingRule {
        BrowserAdBlockingRule(
            trigger: BrowserAdBlockingRule.Trigger(
                urlFilter: urlFilter,
                resourceType: blockedResourceTypes,
                loadType: nil
            ),
            action: BrowserAdBlockingRule.Action(type: "ignore-previous-rules", selector: nil)
        )
    }
}

enum BrowserAdBlockerError: Error {
    case contentRuleListStoreUnavailable
}

@MainActor
enum BrowserAdBlocker {
    static func prewarm() {
        installRuleList { _ in }
    }

    static func apply(
        to userContentController: WKUserContentController,
        mode: BrowserAdBlockingMode,
        isCurrent: (() -> Bool)? = nil,
        completion: (() -> Void)? = nil
    ) {
        userContentController.removeAllContentRuleLists()
        guard mode.isEnabled else {
            completion?()
            return
        }
        installRuleList { result in
            if case .success(let ruleList) = result, isCurrent?() ?? true {
                userContentController.removeAllContentRuleLists()
                userContentController.add(ruleList)
            }
            completion?()
        }
    }

    private static func installRuleList(completion: @escaping (Result<WKContentRuleList, Error>) -> Void) {
        guard let store = WKContentRuleListStore.default() else {
            completion(.failure(BrowserAdBlockerError.contentRuleListStoreUnavailable))
            return
        }
        let identifier = BrowserAdBlockingRules.identifier
        store.lookUpContentRuleList(forIdentifier: identifier) { ruleList, _ in
            if let ruleList {
                Task { @MainActor in completion(.success(ruleList)) }
                return
            }

            do {
                let encodedRules = try BrowserAdBlockingRules.contentRuleListJSON()
                store.compileContentRuleList(
                    forIdentifier: identifier,
                    encodedContentRuleList: encodedRules
                ) { ruleList, error in
                    Task { @MainActor in
                        if let ruleList {
                            completion(.success(ruleList))
                        } else {
                            completion(.failure(error ?? CocoaError(.coderInvalidValue)))
                        }
                    }
                }
            } catch {
                Task { @MainActor in completion(.failure(error)) }
            }
        }
    }
}
