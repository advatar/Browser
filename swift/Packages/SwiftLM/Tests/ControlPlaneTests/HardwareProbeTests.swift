import Foundation
import Testing
@testable import ControlPlane

@Test
func hardwareProbeUsesInjectedGPUAndMetalDetectors() {
    let snapshot = HardwareProbe(
        gpuCoreCountProvider: { 40 },
        metalAvailabilityProvider: { false }
    ).collect()

    #expect(snapshot.gpuCores == 40)
    #expect(snapshot.metalAvailable == false)
    #expect(snapshot.notes["gpuCoreCountSource"] == "IOKit gpu-core-count")
}

@Test
func hardwareProbeDoesNotInventGPUCoreCount() {
    let snapshot = HardwareProbe(
        gpuCoreCountProvider: { nil },
        metalAvailabilityProvider: { true }
    ).collect()

    #expect(snapshot.gpuCores == 0)
    #expect(snapshot.metalAvailable)
    #expect(snapshot.notes["gpuCoreCountSource"] == "unavailable")
}

@Test
func hardwareProbeParsesPositiveIORegistryNumber() {
    #expect(HardwareProbe.gpuCoreCount(from: NSNumber(value: 32)) == 32)
    #expect(HardwareProbe.gpuCoreCount(from: NSNumber(value: 0)) == nil)
    #expect(HardwareProbe.gpuCoreCount(from: "32") == nil)
}
