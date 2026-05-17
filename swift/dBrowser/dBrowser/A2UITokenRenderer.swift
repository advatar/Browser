import Foundation
import Combine
import SwiftUI
import A2UISwiftCore
import A2UISwiftUI

struct A2UITokenRenderSummary: Equatable {
    let messageCount: Int
    let textEventCount: Int
    let parseErrorCount: Int
    let processingErrorCount: Int
    let rootComponentID: String?

    static let empty = A2UITokenRenderSummary(
        messageCount: 0,
        textEventCount: 0,
        parseErrorCount: 0,
        processingErrorCount: 0,
        rootComponentID: nil
    )

    var isSurfaceReady: Bool {
        rootComponentID != nil && processingErrorCount == 0
    }

    var statusText: String {
        if messageCount == 0 && textEventCount == 0 && parseErrorCount == 0 {
            return "No A2UI tokens rendered"
        }

        let messageLabel = "\(messageCount) A2UI message\(messageCount == 1 ? "" : "s")"
        if isSurfaceReady, let rootComponentID {
            return "\(messageLabel), root \(rootComponentID)"
        }
        if parseErrorCount > 0 || processingErrorCount > 0 {
            return "\(messageLabel), \(parseErrorCount + processingErrorCount) issue\(parseErrorCount + processingErrorCount == 1 ? "" : "s")"
        }
        return messageLabel
    }
}

struct A2UIRenderedAction: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let sourceComponentID: String
    let contextSummary: String
    let firedAt: Date

    init(action: ResolvedAction, firedAt: Date = Date()) {
        self.name = action.name
        self.sourceComponentID = action.sourceComponentId
        self.contextSummary = Self.describeContext(action.context)
        self.firedAt = firedAt
    }

    private static func describeContext(_ context: [String: AnyCodable]) -> String {
        guard !context.isEmpty else { return "No context" }
        return context.keys.sorted().map { key in
            "\(key): \(context[key]?.description ?? "null")"
        }.joined(separator: ", ")
    }
}

struct A2UIRuntimeCapability: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String

    init(title: String, detail: String, systemImage: String) {
        self.id = title
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }
}

struct A2UIRuntimeProfile: Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let description: String
    let repositoryURL: URL?
    let documentationURL: URL?
    let setupCommands: [String]
    let capabilities: [A2UIRuntimeCapability]
    let runtimeNotes: [String]

    static let nativeSwiftUI = A2UIRuntimeProfile(
        id: "native-swiftui",
        title: "Native SwiftUI",
        status: "A2UISwiftUI renderer",
        description: "Render A2UI v0.9 tokens directly inside dBrowser with the local Swift catalog.",
        repositoryURL: URL(string: "https://github.com/BBC6BAE9/a2ui-swift"),
        documentationURL: URL(string: "https://github.com/BBC6BAE9/a2ui-swift"),
        setupCommands: [
            "Import A2UISwiftCore and A2UISwiftUI",
            "Parse the token stream with A2UIStreamParser",
            "Render SurfaceViewModel with A2UISurfaceView"
        ],
        capabilities: [
            A2UIRuntimeCapability(
                title: "Native widgets",
                detail: "Text, cards, rows, columns, text fields, and buttons render as SwiftUI views.",
                systemImage: "square.grid.2x2"
            ),
            A2UIRuntimeCapability(
                title: "Local action log",
                detail: "Resolved widget actions stay in the app until a user-approved bridge routes them elsewhere.",
                systemImage: "checklist"
            ),
            A2UIRuntimeCapability(
                title: "Gateway ready",
                detail: "The same token surface can accept output from ZeroK and the LLM Gateway.",
                systemImage: "lock.shield"
            )
        ],
        runtimeNotes: [
            "Best for embedded iOS rendering and fast local previews.",
            "Use this profile when an A2UI app only needs native widgets and dBrowser approval gates."
        ]
    )

    static let logosBasecamp = A2UIRuntimeProfile(
        id: "logos-basecamp",
        title: "Logos Basecamp",
        status: "Local-first decentralized runtime",
        description: "Offer Logos Basecamp as the modular Logos runtime for A2UI apps that need local-first, decentralised modules instead of only native widget rendering.",
        repositoryURL: URL(string: "https://github.com/logos-co/logos-basecamp"),
        documentationURL: URL(string: "https://github.com/logos-co/logos-docs"),
        setupCommands: [
            "nix build '.#bin-macos-app'",
            "open result/LogosBasecamp.app",
            "LogosBasecamp --user-dir <path>",
            "LOGOS_USER_DIR=<path> LogosBasecamp"
        ],
        capabilities: [
            A2UIRuntimeCapability(
                title: "Core runtime",
                detail: "Starts the Logos runtime and loads a configured module profile for local-first apps.",
                systemImage: "server.rack"
            ),
            A2UIRuntimeCapability(
                title: "Privacy networking",
                detail: "Discovery, peering, and mixnet routing avoid a centralized registry as the trust boundary.",
                systemImage: "point.3.connected.trianglepath.dotted"
            ),
            A2UIRuntimeCapability(
                title: "Blockchain / Execution Zone",
                detail: "Runs chain modules for public and private state, LEZ Wallet flows, and ZK-proof backed actions.",
                systemImage: "cube.transparent"
            ),
            A2UIRuntimeCapability(
                title: "Storage",
                detail: "Provides content-addressed decentralized storage as a reusable app module.",
                systemImage: "externaldrive.connected.to.line.below"
            ),
            A2UIRuntimeCapability(
                title: "Messaging",
                detail: "Includes Logos Delivery chat and messaging modules for local-first collaboration.",
                systemImage: "bubble.left.and.bubble.right"
            ),
            A2UIRuntimeCapability(
                title: "MCP/QML Inspector",
                detail: "Basecamp exposes an inspector path so AI assistants can inspect and operate the runtime UI.",
                systemImage: "wand.and.stars"
            )
        ],
        runtimeNotes: [
            "Use Logos for A2UI apps that need decentralized storage, messaging, wallet, or execution modules.",
            "Use --user-dir or LOGOS_USER_DIR to run isolated Basecamp profiles for different apps.",
            "The current Swift bridge offers launch/configuration guidance; a native Logos module bridge is the next integration layer."
        ]
    )

    static let aztecNetwork = A2UIRuntimeProfile(
        id: "aztec-network",
        title: "Aztec Network",
        status: "Privacy-first Ethereum L2 protocol",
        description: "Offer Aztec as the A2UI protocol profile for private smart-contract apps that need client-side proof generation, private state, public state, and Ethereum L1 settlement.",
        repositoryURL: URL(string: "https://github.com/AztecProtocol/aztec-packages"),
        documentationURL: URL(string: "https://docs.aztec.network/"),
        setupCommands: [
            "VERSION=4.2.0 bash -i <(curl -sL https://install.aztec.network/4.2.0)",
            "aztec start --local-network",
            "aztec new my_project",
            "aztec compile",
            "npm install @aztec/aztec.js@4.2.0 @aztec/accounts@4.2.0 @aztec/wallets@4.2.0",
            "npx @aztec/mcp-server@latest"
        ],
        capabilities: [
            A2UIRuntimeCapability(
                title: "Private smart contracts",
                detail: "Aztec private functions execute and prove on the user's device so logic and data can remain confidential.",
                systemImage: "lock.shield"
            ),
            A2UIRuntimeCapability(
                title: "PXE client boundary",
                detail: "The Private Execution Environment stores secrets, notes, nullifier keys, viewing keys, and proof inputs locally.",
                systemImage: "person.badge.key"
            ),
            A2UIRuntimeCapability(
                title: "Public/private state",
                detail: "A2UI apps can compose encrypted private state with transparent public state and Ethereum L1/L2 messages.",
                systemImage: "square.split.2x1"
            ),
            A2UIRuntimeCapability(
                title: "Aztec.nr / Noir",
                detail: "Contracts use the Aztec.nr Noir framework, including private circuits, public AVM bytecode, and utility functions.",
                systemImage: "curlybraces"
            ),
            A2UIRuntimeCapability(
                title: "Aztec.js",
                detail: "The JavaScript SDK talks to PXE for accounts, contracts, deployments, reads, and transactions.",
                systemImage: "terminal"
            ),
            A2UIRuntimeCapability(
                title: "Sequencers and provers",
                detail: "Permissionless sequencers validate blocks while decentralized provers produce rollup proofs posted to Ethereum.",
                systemImage: "network"
            ),
            A2UIRuntimeCapability(
                title: "AI/MCP tooling",
                detail: "Aztec publishes AI guidance, llms.txt, @aztec/mcp-server, and Noir MCP support for current docs and examples.",
                systemImage: "wand.and.stars"
            )
        ],
        runtimeNotes: [
            "Use Aztec when an A2UI app needs programmable privacy, private wallet state, confidential workflows, or proof-backed settlement.",
            "Use the aztec CLI wrapper for Aztec contracts: aztec compile and aztec test, not direct nargo compile/test.",
            "Generated Noir and Aztec.nr code needs verification and tests because the protocol and APIs evolve quickly.",
            "The current Swift bridge offers the protocol profile and setup guidance; native PXE or wallet embedding is the next integration layer."
        ]
    )

    static let available = [
        nativeSwiftUI,
        logosBasecamp,
        aztecNetwork
    ]
}

enum A2UIAppInstallState: Equatable {
    case available
    case installed(Date)
    case running(Date)

    var title: String {
        switch self {
        case .available:
            return "Available"
        case .installed:
            return "Installed"
        case .running:
            return "Running"
        }
    }

    var systemImage: String {
        switch self {
        case .available:
            return "arrow.down.circle"
        case .installed:
            return "checkmark.seal"
        case .running:
            return "play.circle.fill"
        }
    }

    var isInstalled: Bool {
        switch self {
        case .available:
            return false
        case .installed, .running:
            return true
        }
    }
}

struct A2UIAppStoreListing: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let summary: String
    let systemImage: String
    let runtimeProfileID: String
    let requiredCapabilities: [String]
    let installNotes: [String]
    let samplePrompt: String
    let tokenStream: String

    var runtimeProfile: A2UIRuntimeProfile {
        A2UIRuntimeProfile.available.first { $0.id == runtimeProfileID } ?? .nativeSwiftUI
    }

    static let travelBooker = A2UIAppStoreListing(
        id: "travel-booker",
        title: "Travel Booker",
        category: "Travel",
        summary: "Compares flights, stays, and policy pages with A2UI itinerary cards before any booking step.",
        systemImage: "airplane.departure",
        runtimeProfileID: A2UIRuntimeProfile.logosBasecamp.id,
        requiredCapabilities: ["A2UI v0.9", "DOM traversal", "Wallet approval", "LLM Gateway"],
        installNotes: [
            "Installs a reusable travel agent profile with booking approval gates.",
            "Uses https://llmos.showntell.dev for model routing when online."
        ],
        samplePrompt: "Find a refundable Stockholm to Lisbon weekend trip with one cabin bag.",
        tokenStream: """
        {"version":"v0.9","createSurface":{"surfaceId":"travel-booker-store","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":false,"theme":{"primaryColor":"#0F766E"}}}
        {"version":"v0.9","updateComponents":{"surfaceId":"travel-booker-store","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","summary","runtime","prompt","gate","button"]},{"id":"title","component":"Text","text":"Travel Booker","variant":"h3"},{"id":"summary","component":"Text","text":"Compare flights, stays, total price, cancellation terms, timing risk, and source URLs before booking.","variant":"body"},{"id":"runtime","component":"Text","text":"Runtime: Logos Basecamp with A2UI v0.9 and DOM traversal.","variant":"caption"},{"id":"prompt","component":"TextField","label":"Trip request","value":"Find a refundable Stockholm to Lisbon weekend trip with one cabin bag.","variant":"longText"},{"id":"gate","component":"Text","text":"Approval gates: personal data, checkout, wallet spend, booking confirmation.","variant":"caption"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.app.open","context":{"appID":"travel-booker","runtime":"logos-basecamp","gateway":"https://llmos.showntell.dev"}}}},{"id":"buttonLabel","component":"Text","text":"Run Travel Booker","variant":"body"}]}}
        """
    )

    static let disruptionRebooker = A2UIAppStoreListing(
        id: "travel-disruption-rebooker",
        title: "Disruption Rebooker",
        category: "Travel",
        summary: "Builds recovery options for cancellations, delays, missed connections, refunds, and overnight stays.",
        systemImage: "exclamationmark.triangle",
        runtimeProfileID: A2UIRuntimeProfile.logosBasecamp.id,
        requiredCapabilities: ["A2UI v0.9", "DOM evidence", "Policy checks", "Approval gates"],
        installNotes: [
            "Keeps rebooking, claim submission, and payment actions approval gated.",
            "Pairs browser evidence with local-first recovery notes."
        ],
        samplePrompt: "My evening flight was canceled. Find same-day or next-morning recovery options.",
        tokenStream: """
        {"version":"v0.9","createSurface":{"surfaceId":"travel-disruption-store","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":false,"theme":{"primaryColor":"#B45309"}}}
        {"version":"v0.9","updateComponents":{"surfaceId":"travel-disruption-store","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","summary","runtime","prompt","gate","button"]},{"id":"title","component":"Text","text":"Disruption Rebooker","variant":"h3"},{"id":"summary","component":"Text","text":"Ranks fastest, cheapest, and lowest-risk recovery paths with refund and overnight-policy notes.","variant":"body"},{"id":"runtime","component":"Text","text":"Runtime: Logos Basecamp for local recovery state and decentralized messaging handoff.","variant":"caption"},{"id":"prompt","component":"TextField","label":"Disruption request","value":"My evening flight was canceled. Find same-day or next-morning recovery options.","variant":"longText"},{"id":"gate","component":"Text","text":"Approval gates: change booking, submit claim, enter personal data, pay difference.","variant":"caption"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.app.open","context":{"appID":"travel-disruption-rebooker","runtime":"logos-basecamp"}}}},{"id":"buttonLabel","component":"Text","text":"Open Recovery Console","variant":"body"}]}}
        """
    )

    static let formConcierge = A2UIAppStoreListing(
        id: "form-filling-concierge",
        title: "Form-Filling Concierge",
        category: "Productivity",
        summary: "Inspects complex forms, maps missing information, and drafts safe submissions without pressing submit.",
        systemImage: "doc.text.magnifyingglass",
        runtimeProfileID: A2UIRuntimeProfile.nativeSwiftUI.id,
        requiredCapabilities: ["A2UI v0.9", "DOM traversal", "Sensitive data gates", "Native widgets"],
        installNotes: [
            "Runs well as a native SwiftUI A2UI app because the primary surface is checklist and draft state.",
            "Stops before uploads, sends, or form submission."
        ],
        samplePrompt: "Inspect the current form and list required fields, missing values, and validation risks.",
        tokenStream: """
        {"version":"v0.9","createSurface":{"surfaceId":"form-concierge-store","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":false,"theme":{"primaryColor":"#7C3AED"}}}
        {"version":"v0.9","updateComponents":{"surfaceId":"form-concierge-store","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","summary","runtime","prompt","gate","button"]},{"id":"title","component":"Text","text":"Form-Filling Concierge","variant":"h3"},{"id":"summary","component":"Text","text":"Turns form DOM into a required-field checklist, safe draft plan, provenance, and explicit approval gates.","variant":"body"},{"id":"runtime","component":"Text","text":"Runtime: Native SwiftUI A2UI widgets with local action logging.","variant":"caption"},{"id":"prompt","component":"TextField","label":"Form request","value":"Inspect the current form and list required fields, missing values, and validation risks.","variant":"longText"},{"id":"gate","component":"Text","text":"Approval gates: sensitive data entry, uploads, submit, send, wallet spend.","variant":"caption"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.app.open","context":{"appID":"form-filling-concierge","runtime":"native-swiftui"}}}},{"id":"buttonLabel","component":"Text","text":"Open Form Checklist","variant":"body"}]}}
        """
    )

    static let walletPolicy = A2UIAppStoreListing(
        id: "wallet-policy-concierge",
        title: "Wallet Policy Concierge",
        category: "Wallet",
        summary: "Explains requested wallet permissions, simulates transaction intent, and routes private proof work through ZeroK.",
        systemImage: "wallet.pass",
        runtimeProfileID: A2UIRuntimeProfile.aztecNetwork.id,
        requiredCapabilities: ["A2UI v0.9", "Wallet", "ZeroK", "Aztec PXE"],
        installNotes: [
            "Treats wallet reads, signing, broadcasting, and proof requests as first-class approval surfaces.",
            "Uses https://zerok.cloud as the zero knowledge gateway."
        ],
        samplePrompt: "Explain this wallet request and show what proof or signature is needed before I approve.",
        tokenStream: """
        {"version":"v0.9","createSurface":{"surfaceId":"wallet-policy-store","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":false,"theme":{"primaryColor":"#2563EB"}}}
        {"version":"v0.9","updateComponents":{"surfaceId":"wallet-policy-store","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","summary","runtime","prompt","gate","button"]},{"id":"title","component":"Text","text":"Wallet Policy Concierge","variant":"h3"},{"id":"summary","component":"Text","text":"Reviews account reads, transaction simulation, signing scope, broadcast risk, and proof-backed settlement.","variant":"body"},{"id":"runtime","component":"Text","text":"Runtime: Aztec PXE profile with ZeroK gateway routing.","variant":"caption"},{"id":"prompt","component":"TextField","label":"Wallet request","value":"Explain this wallet request and show what proof or signature is needed before I approve.","variant":"longText"},{"id":"gate","component":"Text","text":"Approval gates: account read, proof generation, signature, broadcast, settlement.","variant":"caption"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.app.open","context":{"appID":"wallet-policy-concierge","runtime":"aztec-network","gateway":"https://zerok.cloud"}}}},{"id":"buttonLabel","component":"Text","text":"Review Wallet Request","variant":"body"}]}}
        """
    )

    static let dwebPublisher = A2UIAppStoreListing(
        id: "dweb-publisher",
        title: "DWeb Publisher",
        category: "Decentralized Web",
        summary: "Packages notes or app output for IPFS publishing with local-first storage and verifiable gateway links.",
        systemImage: "network",
        runtimeProfileID: A2UIRuntimeProfile.logosBasecamp.id,
        requiredCapabilities: ["A2UI v0.9", "IPFS", "Logos Storage", "ZeroK receipts"],
        installNotes: [
            "Highlights IPFS/IPNS starting points and content-addressed publish plans.",
            "Designed to bridge Logos storage, AF Market receipts, and ZeroK verification."
        ],
        samplePrompt: "Prepare a short research note for IPFS with provenance, hash checklist, and publish approval.",
        tokenStream: """
        {"version":"v0.9","createSurface":{"surfaceId":"dweb-publisher-store","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":false,"theme":{"primaryColor":"#047857"}}}
        {"version":"v0.9","updateComponents":{"surfaceId":"dweb-publisher-store","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","summary","runtime","prompt","gate","button"]},{"id":"title","component":"Text","text":"DWeb Publisher","variant":"h3"},{"id":"summary","component":"Text","text":"Creates a publish checklist for IPFS/IPNS, provenance, content hashes, gateway checks, and rollback notes.","variant":"body"},{"id":"runtime","component":"Text","text":"Runtime: Logos Basecamp storage plus dBrowser IPFS link handling.","variant":"caption"},{"id":"prompt","component":"TextField","label":"Publish request","value":"Prepare a short research note for IPFS with provenance, hash checklist, and publish approval.","variant":"longText"},{"id":"gate","component":"Text","text":"Approval gates: publish, pin, update IPNS, attach wallet receipt.","variant":"caption"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.app.open","context":{"appID":"dweb-publisher","runtime":"logos-basecamp","protocol":"ipfs"}}}},{"id":"buttonLabel","component":"Text","text":"Open Publish Flow","variant":"body"}]}}
        """
    )

    static let imageboardAgent = A2UIAppStoreListing(
        id: "imageboard-agent",
        title: "Imageboard Agent",
        category: "Social",
        summary: "Creates board, thread, image attachment, comment, preview, and moderation-aware A2UI surfaces.",
        systemImage: "photo.on.rectangle",
        runtimeProfileID: A2UIRuntimeProfile.nativeSwiftUI.id,
        requiredCapabilities: ["A2UI v0.9", "Image metadata", "Thread composer", "Moderation gates"],
        installNotes: [
            "Installs the imageboard demo app already modeled in the desktop A2UI catalog.",
            "Keeps upload, publish, delete, moderate, and wallet-spend actions gated."
        ],
        samplePrompt: "Create a photography imageboard with starter threads and an image upload metadata checklist.",
        tokenStream: """
        {"version":"v0.9","createSurface":{"surfaceId":"imageboard-agent-store","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":false,"theme":{"primaryColor":"#DC2626"}}}
        {"version":"v0.9","updateComponents":{"surfaceId":"imageboard-agent-store","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","summary","runtime","prompt","gate","button"]},{"id":"title","component":"Text","text":"Imageboard Agent","variant":"h3"},{"id":"summary","component":"Text","text":"Builds board lists, thread cards, comment drafts, image metadata, preview state, and moderation notices.","variant":"body"},{"id":"runtime","component":"Text","text":"Runtime: Native SwiftUI A2UI with media approval boundaries.","variant":"caption"},{"id":"prompt","component":"TextField","label":"Board request","value":"Create a photography imageboard with starter threads and an image upload metadata checklist.","variant":"longText"},{"id":"gate","component":"Text","text":"Approval gates: upload image, publish thread, publish comment, moderate, spend wallet funds.","variant":"caption"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.app.open","context":{"appID":"imageboard-agent","runtime":"native-swiftui"}}}},{"id":"buttonLabel","component":"Text","text":"Open Board Builder","variant":"body"}]}}
        """
    )

    static let featured = [
        travelBooker,
        disruptionRebooker,
        formConcierge,
        walletPolicy,
        dwebPublisher,
        imageboardAgent
    ]
}

@MainActor
final class A2UIAppStore: ObservableObject {
    @Published private(set) var listings: [A2UIAppStoreListing]
    @Published private(set) var installedApps: [String: A2UIAppInstallState]

    init(
        listings: [A2UIAppStoreListing] = A2UIAppStoreListing.featured,
        installedApps: [String: A2UIAppInstallState] = [:]
    ) {
        self.listings = listings
        self.installedApps = installedApps
    }

    var installedCount: Int {
        installedApps.values.filter(\.isInstalled).count
    }

    var runningListingID: String? {
        installedApps.first { _, state in
            if case .running = state {
                return true
            }
            return false
        }?.key
    }

    func state(for listing: A2UIAppStoreListing) -> A2UIAppInstallState {
        installedApps[listing.id] ?? .available
    }

    func install(_ listing: A2UIAppStoreListing, installedAt: Date = Date()) {
        installedApps[listing.id] = .installed(installedAt)
    }

    func open(_ listing: A2UIAppStoreListing, openedAt: Date = Date()) {
        if !state(for: listing).isInstalled {
            install(listing, installedAt: openedAt)
        }
        installedApps[listing.id] = .running(openedAt)
    }

    func uninstall(_ listing: A2UIAppStoreListing) {
        installedApps.removeValue(forKey: listing.id)
    }
}

@MainActor
final class A2UITokenRenderer: ObservableObject {
    @Published private(set) var surfaceViewModel = SurfaceViewModel(catalog: basicCatalog)
    @Published private(set) var renderSummary = A2UITokenRenderSummary.empty
    @Published private(set) var renderedTextEvents: [String] = []
    @Published private(set) var errors: [String] = []
    @Published private(set) var actionLog: [A2UIRenderedAction] = []

    static let sampleTokens = """
    {"version":"v0.9","createSurface":{"surfaceId":"dbrowser-a2ui-demo","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":false,"theme":{"primaryColor":"#0A7AFF"}}}
    {"version":"v0.9","updateComponents":{"surfaceId":"dbrowser-a2ui-demo","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","subtitle","gatewayRow","logosRuntime","aztecProtocol","prompt","button"]},{"id":"title","component":"Text","text":"A2UI runtime card","variant":"h3"},{"id":"subtitle","component":"Text","text":"Native SwiftUI widgets rendered from A2UI v0.9 tokens.","variant":"body"},{"id":"gatewayRow","component":"Row","children":["zeroK","llmGateway"]},{"id":"zeroK","component":"Text","text":"ZeroK: https://zerok.cloud","variant":"caption"},{"id":"llmGateway","component":"Text","text":"LLM Gateway: https://llmos.showntell.dev","variant":"caption"},{"id":"logosRuntime","component":"Text","text":"Logos runtime: Basecamp modules for storage, messaging, blockchain, wallets, and AI inspection.","variant":"caption"},{"id":"aztecProtocol","component":"Text","text":"Aztec protocol: PXE, Noir private contracts, client-side proofs, and Ethereum L1 settlement.","variant":"caption"},{"id":"prompt","component":"TextField","label":"Prompt intent","value":"Summarize this page with privacy policy context.","variant":"longText"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.preview","context":{"gateway":"https://zerok.cloud","route":"llm-gateway","runtime":"logos-basecamp","protocol":"aztec-network"}}}},{"id":"buttonLabel","component":"Text","text":"Preview action","variant":"body"}]}}
    """

    var hasSurface: Bool {
        surfaceViewModel.componentTree != nil
    }

    func render(rawTokens: String) async {
        let trimmedTokens = rawTokens.trimmingCharacters(in: .whitespacesAndNewlines)
        surfaceViewModel = SurfaceViewModel(catalog: basicCatalog)
        renderSummary = .empty
        renderedTextEvents = []
        errors = []
        actionLog = []

        guard !trimmedTokens.isEmpty else { return }

        let parser = A2UIStreamParser()
        await parser.add(trimmedTokens)
        await parser.finish()

        var messages: [A2uiMessage] = []
        var textEvents: [String] = []
        var parseErrors: [String] = []

        for await event in parser.events {
            switch event {
            case .message(let message):
                messages.append(message)
            case .text(let text):
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    textEvents.append(trimmedText)
                }
            case .error(let error):
                parseErrors.append(String(describing: error))
            }
        }

        let processingErrors = surfaceViewModel
            .processMessages(messages)
            .map { String(describing: $0) }

        renderedTextEvents = textEvents
        errors = parseErrors + processingErrors
        renderSummary = A2UITokenRenderSummary(
            messageCount: messages.count,
            textEventCount: textEvents.count,
            parseErrorCount: parseErrors.count,
            processingErrorCount: processingErrors.count,
            rootComponentID: surfaceViewModel.componentTree?.baseComponentId
        )
    }

    func record(_ action: ResolvedAction) {
        actionLog.insert(A2UIRenderedAction(action: action), at: 0)
        if actionLog.count > 12 {
            actionLog = Array(actionLog.prefix(12))
        }
    }

    func clearActionLog() {
        actionLog.removeAll()
    }
}

struct A2UITokenSurfacePreview: View {
    @ObservedObject var renderer: A2UITokenRenderer

    var body: some View {
        Group {
            if renderer.hasSurface {
                A2UISurfaceView(viewModel: renderer.surfaceViewModel) { action in
                    Task { @MainActor in
                        renderer.record(action)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No A2UI surface", systemImage: "square.dashed")
                        .font(.headline)
                    Text("Paste or generate A2UI v0.9 tokens, then render them into native widgets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
