import ControlPlane
import Foundation

@main
struct SwiftLMControlPlaneMain {
    static func main() async {
        do {
            let host = try await ControlPlaneHost.bootstrap()
            try await host.start()
            print("SwiftLM control plane listening on http://127.0.0.1:8400")
            if let plaintextKey = host.secrets.plaintextKey {
                print("Bootstrap API key: \(plaintextKey)")
            } else {
                print("Developer API key preview: \(host.secrets.preview)")
            }
            while true {
                try await Task.sleep(for: .seconds(3_600))
            }
        } catch {
            fputs("Failed to start SwiftLM control plane: \(error)\n", stderr)
            exit(1)
        }
    }
}
