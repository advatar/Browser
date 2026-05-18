import Contracts
import Foundation
import Testing
@testable import RuntimeAdapters

struct MLXRuntimeValidationTests {
    @Test
    func managedMLXSitePackagesValidatorRejectsMissingServerEntryPoint() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sitePackagesPath = try createManagedSitePackages(at: root, includeServerEntryPoint: false)

        #expect(ManagedMLXSitePackagesValidator.isValid(at: sitePackagesPath) == false)
    }

    @Test
    func mlxNativeRuntimeInstallationRejectsIncompleteManagedSitePackages() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sitePackagesPath = try createManagedSitePackages(at: root)
        let runtimeRoot = root.appending(path: "runtime")
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        try writeManifest(at: runtimeRoot, sitePackagesPath: sitePackagesPath)

        let installation = MLXNativeAdapter.runtimeInstallation(
            candidate: runtimeRoot,
            backendId: BackendKind.mlxNative.rawValue,
            sitePackagesValidator: { _, _ in false }
        )

        #expect(installation == nil)
    }

    @Test
    func managedMLXSitePackagesValidatorRejectsFailedImportProbe() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sitePackagesPath = try createManagedSitePackages(at: root)
        let isValid = ManagedMLXSitePackagesValidator.isValid(
            at: sitePackagesPath,
            pythonPath: "/bin/sh",
            importProbe: { _, _ in false }
        )

        #expect(isValid == false)
    }

    @Test
    func mlxNativeRuntimeInstallationAcceptsValidatedManagedSitePackages() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sitePackagesPath = try createManagedSitePackages(at: root)
        let runtimeRoot = root.appending(path: "runtime")
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        try writeManifest(at: runtimeRoot, sitePackagesPath: sitePackagesPath)

        let installation = MLXNativeAdapter.runtimeInstallation(
            candidate: runtimeRoot,
            backendId: BackendKind.mlxNative.rawValue,
            sitePackagesValidator: { _, _ in true }
        )

        #expect(installation?.rootPath == runtimeRoot.path)
        #expect(installation?.pythonPath == "/bin/sh")
    }

    @Test
    func mlxNativeLaunchPlanUsesSourcePathAsEngineModelName() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let runtimeRoot = root.appending(path: "runtime")
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        let adapter = MLXNativeAdapter()
        let modelSource = root.appending(path: "models/Qwen2.5-1.5B-Instruct-4bit").path
        let plan = try adapter.launchPlan(
            model: ModelRecord(
                ref: ModelRef(
                    id: "public-model-id",
                    displayName: "Qwen",
                    sourceKind: .local,
                    sourceRef: modelSource,
                    modality: .text
                ),
                primaryArtifactPath: modelSource
            ),
            spec: LaunchSpec(contextWindow: 4096, maxOutputTokens: 256, gpuOnly: true),
            profile: nil,
            installation: RuntimeInstallation(
                backendId: BackendKind.mlxNative.rawValue,
                rootPath: runtimeRoot.path,
                executablePath: "/bin/sh",
                pythonPath: "/bin/sh",
                version: "0.31.2",
                pythonVersion: "3.11.15"
            ),
            port: 8801,
            publicModelName: "public-model-id",
            apiKey: nil
        )

        #expect(plan.engineModelName == modelSource)
    }

    private func temporaryRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "swiftlm-runtime-tests-\(UUID().uuidString.lowercased())")
    }

    private func createManagedSitePackages(at root: URL, includeServerEntryPoint: Bool = true) throws -> String {
        let sitePackages = root.appending(path: "site-packages/python3.11")
        let mlxLM = sitePackages.appending(path: "mlx_lm")
        let mlx = sitePackages.appending(path: "mlx")

        try FileManager.default.createDirectory(at: mlxLM, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mlx, withIntermediateDirectories: true)
        if includeServerEntryPoint {
            try Data().write(to: mlxLM.appending(path: "server.py"))
        }
        return sitePackages.path
    }

    private func writeManifest(at runtimeRoot: URL, sitePackagesPath: String) throws {
        let manifest = RuntimeManifest(
            backendId: BackendKind.mlxNative.rawValue,
            packageName: "mlx-lm",
            version: "0.31.2",
            pythonVersion: "3.11.15",
            installedAt: Time.nowISO8601(),
            runtimeRootPath: runtimeRoot.path,
            executablePath: "/bin/sh",
            pythonPath: "/bin/sh",
            metadata: ["sitePackagesPath": sitePackagesPath]
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: runtimeRoot.appending(path: "manifest.json"))
    }
}
