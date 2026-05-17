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

    static let available = [
        nativeSwiftUI,
        logosBasecamp
    ]
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
    {"version":"v0.9","updateComponents":{"surfaceId":"dbrowser-a2ui-demo","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","subtitle","gatewayRow","logosRuntime","prompt","button"]},{"id":"title","component":"Text","text":"A2UI runtime card","variant":"h3"},{"id":"subtitle","component":"Text","text":"Native SwiftUI widgets rendered from A2UI v0.9 tokens.","variant":"body"},{"id":"gatewayRow","component":"Row","children":["zeroK","llmGateway"]},{"id":"zeroK","component":"Text","text":"ZeroK: https://zerok.cloud","variant":"caption"},{"id":"llmGateway","component":"Text","text":"LLM Gateway: https://llmos.showntell.dev","variant":"caption"},{"id":"logosRuntime","component":"Text","text":"Logos runtime: Basecamp modules for storage, messaging, blockchain, wallets, and AI inspection.","variant":"caption"},{"id":"prompt","component":"TextField","label":"Prompt intent","value":"Summarize this page with privacy policy context.","variant":"longText"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.preview","context":{"gateway":"https://zerok.cloud","route":"llm-gateway","runtime":"logos-basecamp"}}}},{"id":"buttonLabel","component":"Text","text":"Preview action","variant":"body"}]}}
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
