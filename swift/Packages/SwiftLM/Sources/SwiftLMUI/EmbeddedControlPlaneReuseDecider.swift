import ControlPlane
import Foundation
import Network

enum ControlPlaneBootstrapMode: Equatable {
    case embedded
    case existing
}

struct EmbeddedControlPlaneReuseDecider {
    var probeExistingControlPlane: @Sendable () async -> Bool
    var isAddressInUseError: @Sendable (Error) -> Bool

    init(
        probeExistingControlPlane: @escaping @Sendable () async -> Bool = {
            await EmbeddedControlPlaneReuseDecider.defaultProbeExistingControlPlane()
        },
        isAddressInUseError: @escaping @Sendable (Error) -> Bool = EmbeddedControlPlaneReuseDecider.isAddressInUseError(_:)
    ) {
        self.probeExistingControlPlane = probeExistingControlPlane
        self.isAddressInUseError = isAddressInUseError
    }

    func initialMode() async -> ControlPlaneBootstrapMode {
        await probeExistingControlPlane() ? .existing : .embedded
    }

    func recoveryMode(afterStartError error: Error) async -> ControlPlaneBootstrapMode? {
        guard isAddressInUseError(error) else {
            return nil
        }
        return await probeExistingControlPlane() ? .existing : nil
    }

    static func defaultProbeExistingControlPlane(
        client: ControlPlaneClient = ControlPlaneClient(),
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                do {
                    _ = try await client.fetchOverview()
                    return true
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    static func isAddressInUseError(_ error: Error) -> Bool {
        if let nwError = error as? NWError,
           case .posix(let posixError) = nwError,
           posixError == .EADDRINUSE {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EADDRINUSE) {
            return true
        }
        if nsError.domain == "Network.NWError" && nsError.code == Int(EADDRINUSE) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isAddressInUseError(underlying)
        }
        return false
    }
}
