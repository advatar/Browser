import Foundation
import Network
import SwiftUI
import Testing
@testable import SwiftLMUI

struct SwiftLMUIModuleTests {

    @MainActor
    @Test
    func applicationSceneCanBeInstantiatedByHostApps() {
        let scene = SwiftLMApplicationScene(
            title: "SwiftLM Harness",
            mainWindowID: "harness-main",
            minimumWindowSize: CGSize(width: 640, height: 480)
        )

        _ = scene.body
    }

    @Test
    func embeddedControlPlaneReuseDeciderPrefersExistingControlPlaneWhenProbeSucceeds() async {
        let decider = EmbeddedControlPlaneReuseDecider(probeExistingControlPlane: { true })

        let mode = await decider.initialMode()

        #expect(mode == .existing)
    }

    @Test
    func embeddedControlPlaneReuseDeciderRecoversFromAddressInUseRace() async {
        let probeResults = LockedProbeResults([false, true])
        let decider = EmbeddedControlPlaneReuseDecider(
            probeExistingControlPlane: { await probeResults.next() },
            isAddressInUseError: { _ in true }
        )

        let initialMode = await decider.initialMode()
        let recoveryMode = await decider.recoveryMode(afterStartError: NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE)))

        #expect(initialMode == .embedded)
        #expect(recoveryMode == .existing)
    }

    @Test
    func embeddedControlPlaneReuseDeciderDoesNotMaskNonBindErrors() async {
        let decider = EmbeddedControlPlaneReuseDecider(
            probeExistingControlPlane: { true },
            isAddressInUseError: { _ in false }
        )

        let recoveryMode = await decider.recoveryMode(afterStartError: URLError(.cannotConnectToHost))

        #expect(recoveryMode == nil)
    }

    @Test
    func embeddedControlPlaneReuseDeciderRecognizesAddressInUseErrors() {
        #expect(EmbeddedControlPlaneReuseDecider.isAddressInUseError(NWError.posix(.EADDRINUSE)))
        #expect(EmbeddedControlPlaneReuseDecider.isAddressInUseError(NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE))))
        #expect(EmbeddedControlPlaneReuseDecider.isAddressInUseError(NSError(domain: "Network.NWError", code: Int(EADDRINUSE))))
        #expect(EmbeddedControlPlaneReuseDecider.isAddressInUseError(URLError(.cannotConnectToHost)) == false)
    }

}

actor LockedProbeResults {
    private var values: [Bool]

    init(_ values: [Bool]) {
        self.values = values
    }

    func next() -> Bool {
        guard values.isEmpty == false else {
            return false
        }
        return values.removeFirst()
    }
}
