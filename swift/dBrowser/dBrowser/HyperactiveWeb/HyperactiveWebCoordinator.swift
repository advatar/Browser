import Foundation
import Combine
import A2UISwiftCore
import UniversalInteractionKit

/// Wires the Hyperactive Web navigation fabric into dBrowser: it builds a
/// `CapabilityResolver` from dBrowser-backed policy, identity, payments, and
/// adapters; renders capability surfaces through the existing A2UI renderer
/// (UIK emits A2UI v0.9 tokens — dBrowser never renders UIK's own UI); and
/// routes resolved A2UI actions back into the resolver. Slice 5 of #149.
@MainActor
final class HyperactiveWebCoordinator: ObservableObject {
    @Published private(set) var awaitingPayment = false

    let renderer: A2UITokenRenderer

    private let registry: InMemoryCapabilityRegistry
    private let resolver: CapabilityResolver
    private let context: AdapterInvocationContext
    private var affordances: [String: Affordance] = [:]
    private var pendingPayment: (affordance: Affordance, requirements: PaymentRequirements)?

    init(
        renderer: A2UITokenRenderer = A2UITokenRenderer(),
        mcpServers: [MCPServerConfiguration] = [],
        rootDirectory: URL,
        userID: String = "dbrowser.local",
        sessionID: String = UUID().uuidString
    ) throws {
        self.renderer = renderer
        let registry = InMemoryCapabilityRegistry()
        self.registry = registry
        let workspace = InteractionWorkspace(store: try DBrowserArtifactStore(rootDirectory: rootDirectory))
        self.resolver = CapabilityResolver(
            registry: registry,
            adapters: HyperactiveAdapters.make(from: mcpServers),
            policy: DBrowserPolicyKernel(),
            workspace: workspace,
            cache: InMemoryResultCache(),
            authorizer: DBrowserPaymentAuthorizer(),
            identityVerifier: DBrowserIdentityVerifier()
        )
        self.context = AdapterInvocationContext(userID: userID, sessionID: sessionID)
    }

    /// Register a discovered service card (e.g. decoded from an agent card at
    /// `/.well-known/agent-card.json`) and index its affordances for routing.
    func register(_ card: ServiceCard) async {
        await registry.register(card)
        for link in card.capabilities {
            affordances[link.id] = Affordance(link: link)
        }
    }

    /// Enter a service and render its zoomable surface.
    func enter(serviceID: String, zoom: SurfaceZoom = .summary) async throws {
        let surface = try await resolver.enter(serviceID: serviceID, zoom: zoom)
        await present(surface)
    }

    /// Render a resolved surface through the existing A2UI renderer.
    func present(_ surface: ResolvedSurface) async {
        awaitingPayment = surface.awaitingPayment
        let tokens = A2UISurfaceEncoder.tokenStream(for: surface.document)
        await renderer.render(rawTokens: tokens)
    }

    /// Route a resolved A2UI action (from the renderer) back into the resolver.
    func handle(_ action: ResolvedAction) async {
        switch action.name {
        case A2UIEventName.followAffordance:
            guard let id = string(action.context["affordanceID"]), let affordance = affordances[id] else { return }
            guard let next = try? await resolver.follow(affordance, arguments: .object([:]), context: context) else { return }
            pendingPayment = (next.awaitingPayment ? next.paymentRequirements.map { (affordance, $0) } : nil)
            await present(next)

        case A2UIEventName.pay:
            // The wallet UI authorizes payment, then resolver.pay(...) delivers
            // and retains the receipt. Authorization is deferred to slice 6 (#149).
            break

        default:
            break
        }
    }

    private func string(_ value: AnyCodable?) -> String? {
        guard let value else { return nil }
        return value.description.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
