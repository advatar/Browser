import SwiftUI
import A2UISwiftCore
import A2UISwiftUI
import UniversalInteractionKit

/// Renders the Hyperactive Web surface for the entered service and routes A2UI
/// actions into the coordinator (follow / pay / confirm), so navigating the
/// capability web feels like browsing. Slice 5 of #149.
struct HyperactiveWebPanel: View {
    @ObservedObject var coordinator: HyperactiveWebCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if coordinator.renderer.hasSurface {
                A2UISurfaceView(viewModel: coordinator.renderer.surfaceViewModel) { action in
                    Task { @MainActor in
                        coordinator.renderer.record(action)
                        await coordinator.handle(action)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No capability surface",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Navigate to a site that publishes a Hyperactive Web service card.")
                )
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if let service = coordinator.activeService {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(service.name).font(.headline)
                    Text(service.provider).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if coordinator.awaitingPayment {
                    Label("Payment required", systemImage: "creditcard")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(12)
        }
    }
}
