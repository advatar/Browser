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

@MainActor
final class A2UITokenRenderer: ObservableObject {
    @Published private(set) var surfaceViewModel = SurfaceViewModel(catalog: basicCatalog)
    @Published private(set) var renderSummary = A2UITokenRenderSummary.empty
    @Published private(set) var renderedTextEvents: [String] = []
    @Published private(set) var errors: [String] = []
    @Published private(set) var actionLog: [A2UIRenderedAction] = []

    static let sampleTokens = """
    {"version":"v0.9","createSurface":{"surfaceId":"dbrowser-a2ui-demo","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":false,"theme":{"primaryColor":"#0A7AFF"}}}
    {"version":"v0.9","updateComponents":{"surfaceId":"dbrowser-a2ui-demo","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["title","subtitle","gatewayRow","prompt","button"]},{"id":"title","component":"Text","text":"A2UI runtime card","variant":"h3"},{"id":"subtitle","component":"Text","text":"Native SwiftUI widgets rendered from A2UI v0.9 tokens.","variant":"body"},{"id":"gatewayRow","component":"Row","children":["zeroK","llmGateway"]},{"id":"zeroK","component":"Text","text":"ZeroK: https://zerok.cloud","variant":"caption"},{"id":"llmGateway","component":"Text","text":"LLM Gateway: https://llmos.showntell.dev","variant":"caption"},{"id":"prompt","component":"TextField","label":"Prompt intent","value":"Summarize this page with privacy policy context.","variant":"longText"},{"id":"button","component":"Button","child":"buttonLabel","variant":"primary","action":{"event":{"name":"a2ui.preview","context":{"gateway":"https://zerok.cloud","route":"llm-gateway"}}}},{"id":"buttonLabel","component":"Text","text":"Preview action","variant":"body"}]}}
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
