import Foundation
import Combine
import A2UISwiftCore
import UniversalInteractionKit

/// Wires the Hyperactive Web navigation fabric into dBrowser: it builds a
/// `CapabilityResolver` from dBrowser-backed policy, identity, payments, and
/// adapters; discovers service cards from `/.well-known/agent-card.json` as the
/// user navigates; renders capability surfaces through the existing A2UI
/// renderer (UIK emits A2UI v0.9 tokens — dBrowser never renders UIK's own UI);
/// and routes resolved A2UI actions back into the resolver. Slice 5 of #149.
@MainActor
final class HyperactiveWebCoordinator: ObservableObject {
    /// True while a surface is blocked on a 402 payment the user must authorize.
    @Published private(set) var awaitingPayment = false
    /// The service card currently entered, if any (drives the panel header).
    @Published private(set) var activeService: ServiceCard?

    let renderer: A2UITokenRenderer

    /// Authorizes a 402 challenge through dBrowser's wallet / AgenticPayments
    /// flow, returning a signed X402 payload. Injected by the host so the
    /// coordinator stays free of wallet internals; `nil` means no wallet wired
    /// (the payment surface is shown but cannot be fulfilled).
    var walletAuthorize: ((X402PaymentRequirement) async -> X402PaymentPayload?)?

    private let registry: InMemoryCapabilityRegistry
    private let resolver: CapabilityResolver
    private let context: AdapterInvocationContext
    private var affordances: [String: Affordance] = [:]
    private var pendingPayment: (affordance: Affordance, requirements: PaymentRequirements)?

    init(
        renderer: A2UITokenRenderer = A2UITokenRenderer(),
        mcpServers: [MCPServerConfiguration] = [],
        rootDirectory: URL,
        openMind: OpenMindMemoryClient = OpenMindMemoryClient(),
        userID: String = "dbrowser.local",
        sessionID: String = UUID().uuidString
    ) throws {
        self.renderer = renderer
        let registry = InMemoryCapabilityRegistry()
        self.registry = registry
        let store = try DBrowserArtifactStore(rootDirectory: rootDirectory, openMind: openMind)
        let workspace = InteractionWorkspace(store: store)
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

    // MARK: - Navigation

    /// Probe a navigated URL for a Hyperactive Web service: fetch its
    /// `/.well-known/agent-card.json`, register the card, and render its surface.
    /// Accepts either a native UIK `ServiceCard` document or a plain A2A agent
    /// card (wrapped via `A2AAdapter`). Returns `true` if a service was entered.
    @discardableResult
    func discover(urlString: String) async -> Bool {
        guard let origin = Self.origin(of: urlString) else { return false }
        let cardURL = origin.appendingPathComponent(".well-known/agent-card.json")
        guard
            let (data, response) = try? await URLSession.shared.data(from: cardURL),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return false }

        // Native Hyperactive Web discovery document.
        if let card = try? JSONDecoder().decode(ServiceCard.self, from: data), !card.capabilities.isEmpty {
            await register(card)
            try? await enter(serviceID: card.id)
            return true
        }

        // Plain A2A agent card: build an adapter + card from discovered skills.
        let adapter = A2AAdapter(id: origin.host ?? urlString, agentBaseURL: origin)
        guard let capabilities = try? await adapter.discover(), !capabilities.isEmpty else { return false }
        await resolver.registerAdapter(adapter)
        let links = capabilities.map {
            CapabilityLink(capability: $0, adapterID: adapter.id, href: cardURL.absoluteString, method: .delegate)
        }
        let card = ServiceCard(
            id: adapter.id,
            name: origin.host ?? "Agent",
            provider: origin.host ?? "",
            serviceURI: "a2a+\(cardURL.absoluteString)",
            adapterID: adapter.id,
            supportedProtocols: ["a2a"],
            capabilities: links
        )
        await register(card)
        try? await enter(serviceID: card.id)
        return true
    }

    /// Register a discovered service card and index its affordances for routing.
    func register(_ card: ServiceCard) async {
        await registry.register(card)
        for link in card.capabilities {
            affordances[link.id] = Affordance(link: link)
        }
    }

    /// Enter a service and render its zoomable surface.
    func enter(serviceID: String, zoom: SurfaceZoom = .summary) async throws {
        let surface = try await resolver.enter(serviceID: serviceID, zoom: zoom)
        activeService = await registry.card(id: serviceID)
        await present(surface)
    }

    /// Render a resolved surface through the existing A2UI renderer.
    func present(_ surface: ResolvedSurface) async {
        awaitingPayment = surface.awaitingPayment
        pendingPayment = surface.awaitingPayment
            ? surface.paymentRequirements.flatMap { req in pendingPayment.map { ($0.affordance, req) } }
            : nil
        let tokens = A2UISurfaceEncoder.tokenStream(for: surface.document)
        await renderer.render(rawTokens: tokens)
    }

    // MARK: - Action routing

    /// Route a resolved A2UI action (from the renderer) back into the resolver.
    func handle(_ action: ResolvedAction) async {
        switch action.name {
        case A2UIEventName.followAffordance:
            guard let id = string(action.context["affordanceID"]), let affordance = affordances[id] else { return }
            guard let next = try? await resolver.follow(affordance, arguments: .object([:]), context: context) else { return }
            pendingPayment = next.awaitingPayment ? next.paymentRequirements.map { (affordance, $0) } : nil
            await present(next)

        case A2UIEventName.pay:
            await payPending()

        default:
            break
        }
    }

    /// Fulfill the pending 402 by routing through the host wallet (X402), then
    /// retrying the capability with the authorization and retaining the receipt.
    private func payPending() async {
        guard let pending = pendingPayment, let walletAuthorize else { return }
        let requirement = X402Bridge.requirement(
            from: pending.requirements,
            resourceURLString: pending.affordance.link.href
        )
        guard let payload = await walletAuthorize(requirement), payload.isSigned else { return }
        let authorization = X402Bridge.authorization(from: payload, price: pending.requirements.price)
        guard let delivered = try? await resolver.pay(
            pending.affordance,
            requirements: pending.requirements,
            authorization: authorization,
            context: context
        ) else { return }
        pendingPayment = nil
        await present(delivered)
    }

    // MARK: - Helpers

    private func string(_ value: AnyCodable?) -> String? {
        guard let value else { return nil }
        return value.description.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// The scheme://host[:port] origin of a navigated URL.
    private static func origin(of urlString: String) -> URL? {
        guard
            let url = URL(string: urlString),
            let scheme = url.scheme, scheme.hasPrefix("http"),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
