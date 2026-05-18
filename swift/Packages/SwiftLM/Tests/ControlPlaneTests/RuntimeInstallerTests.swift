@testable import ControlPlane
@testable import RuntimeAdapters
import Contracts
import Foundation
import Storage
import Testing

@Test
func pythonRuntimeLocatorPrefersHighestCompatibleVersion() async throws {
    let sandbox = try TestExecutableSandbox()
    defer { sandbox.cleanup() }

    let python39 = try sandbox.makeExecutable(named: "python3.9")
    let python311 = try sandbox.makeExecutable(named: "python3.11")

    let runtime = await PythonRuntimeLocator.locateCompatibleRuntime(
        requirement: .minimum(PythonVersion(major: 3, minor: 8)),
        candidates: [python39.path, python311.path],
        runner: { executablePath, _ in
            executablePath == python311.path ? "3.11.9\n" : "3.9.6\n"
        }
    )

    #expect(runtime?.executablePath == python311.path)
    #expect(runtime?.version == PythonVersion("3.11.9"))
}

@Test
func pythonRuntimeLocatorHonorsExactMajorMinorRequirement() async throws {
    let sandbox = try TestExecutableSandbox()
    defer { sandbox.cleanup() }

    let python312 = try sandbox.makeExecutable(named: "python3.12")
    let python313 = try sandbox.makeExecutable(named: "python3.13")

    let runtime = await PythonRuntimeLocator.locateCompatibleRuntime(
        requirement: .exactMajorMinor(PythonVersion(major: 3, minor: 12)),
        candidates: [python313.path, python312.path],
        runner: { executablePath, _ in
            executablePath == python312.path ? "3.12.8\n" : "3.13.0\n"
        }
    )

    #expect(runtime?.executablePath == python312.path)
    #expect(runtime?.version == PythonVersion("3.12.8"))
}

@Test
func pythonRuntimeLocatorReturnsNilWhenNoCandidateMatches() async throws {
    let sandbox = try TestExecutableSandbox()
    defer { sandbox.cleanup() }

    let python311 = try sandbox.makeExecutable(named: "python3.11")

    let runtime = await PythonRuntimeLocator.locateCompatibleRuntime(
        requirement: .exactMajorMinor(PythonVersion(major: 3, minor: 12)),
        candidates: [python311.path],
        runner: { _, _ in "3.11.12\n" }
    )

    #expect(runtime == nil)
}

@Test
func mlxNativeDetectsManifestManagedInstallation() async throws {
    let sandbox = try TestExecutableSandbox()
    defer { sandbox.cleanup() }

    let runtimeRoot = sandbox.root.appending(path: "mlx-native")
    try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
    let sitePackages = runtimeRoot.appending(path: "site-packages/python3.9")
    try FileManager.default.createDirectory(
        at: sitePackages.appending(path: "mlx_lm"),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: sitePackages.appending(path: "mlx"),
        withIntermediateDirectories: true
    )
    try Data().write(to: sitePackages.appending(path: "mlx_lm/server.py"))
    try Data().write(to: sitePackages.appending(path: "mlx/core.cpython-311-darwin.so"))
    let python = try sandbox.makeExecutable(named: "python3-managed")
    let manifest = RuntimeManifest(
        backendId: BackendKind.mlxNative.rawValue,
        packageName: "mlx-lm",
        version: "0.31.1",
        pythonVersion: "3.9.6",
        installedAt: "2026-04-03T10:00:00.000Z",
        runtimeRootPath: runtimeRoot.path,
        executablePath: python.path,
        pythonPath: python.path,
        metadata: ["sitePackagesPath": sitePackages.path]
    )
    let manifestData = try JSONEncoder().encode(manifest)
    try manifestData.write(to: runtimeRoot.appending(path: "manifest.json"))

    let installation = MLXNativeAdapter.runtimeInstallation(
        candidate: runtimeRoot.appending(path: "venv"),
        backendId: BackendKind.mlxNative.rawValue,
        sitePackagesValidator: { _, _ in true }
    )

    #expect(installation?.rootPath == runtimeRoot.path)
    #expect(installation?.pythonPath == python.path)
    #expect(installation?.version == "0.31.1")
}

@Test
func finalizedManifestKeepsExternalPythonAndRewritesManagedSitePackages() async throws {
    let originalRoot = URL(fileURLWithPath: "/tmp/swiftlm-runtime-staging/runtime")
    let finalRoot = URL(fileURLWithPath: "/tmp/swiftlm-runtime-final/mlx-native")
    let externalPython = "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"
    let manifest = RuntimeManifest(
        backendId: BackendKind.mlxNative.rawValue,
        packageName: "mlx-lm",
        version: "0.29.1",
        pythonVersion: "3.12.8",
        installedAt: "2026-04-11T22:00:00.000Z",
        runtimeRootPath: originalRoot.path,
        executablePath: externalPython,
        pythonPath: externalPython,
        metadata: [
            "entrypoint": "python -m mlx_lm.server",
            "sitePackagesPath": originalRoot.appending(path: "site-packages/python3.12").path
        ]
    )

    let finalized = RuntimeInstaller.finalizedManifest(
        manifest: manifest,
        finalRuntimeRoot: finalRoot,
        originalRuntimeRoot: originalRoot
    )

    #expect(finalized.runtimeRootPath == finalRoot.path)
    #expect(finalized.executablePath == externalPython)
    #expect(finalized.pythonPath == externalPython)
    #expect(finalized.metadata["sitePackagesPath"] == finalRoot.appending(path: "site-packages/python3.12").path)
}

@Test
func finalizedManifestRewritesPathsInsideManagedRuntimeRoot() async throws {
    let originalRoot = URL(fileURLWithPath: "/tmp/swiftlm-runtime-staging/runtime")
    let finalRoot = URL(fileURLWithPath: "/tmp/swiftlm-runtime-final/vllm-metal")
    let manifest = RuntimeManifest(
        backendId: BackendKind.vllmMetal.rawValue,
        packageName: "vllm-metal",
        version: "0.17.1",
        pythonVersion: "3.12.8",
        installedAt: "2026-04-11T22:00:00.000Z",
        runtimeRootPath: originalRoot.path,
        executablePath: originalRoot.appending(path: "venv/bin/vllm").path,
        pythonPath: originalRoot.appending(path: "venv/bin/python").path,
        metadata: ["entrypoint": "vllm serve"]
    )

    let finalized = RuntimeInstaller.finalizedManifest(
        manifest: manifest,
        finalRuntimeRoot: finalRoot,
        originalRuntimeRoot: originalRoot
    )

    #expect(finalized.executablePath == finalRoot.appending(path: "venv/bin/vllm").path)
    #expect(finalized.pythonPath == finalRoot.appending(path: "venv/bin/python").path)
}

@Test
func managedPythonLocatorPrefersManagedRuntimeWhenVersionTiesSystem() async throws {
    let sandbox = try TestExecutableSandbox()
    defer { sandbox.cleanup() }

    let paths = ApplicationPaths(root: sandbox.root.appending(path: "swiftlm-app"))
    try paths.createIfNeeded()

    let managedPython = try sandbox.makeExecutable(
        named: "swiftlm-app/python/cpython-3.12.9/python/install/bin/python3.12"
    )
    let systemPython = try sandbox.makeExecutable(named: "python3.12-system")

    let runtime = try await ManagedPythonLocator.locateCompatibleRuntime(
        requirement: .exactMajorMinor(PythonVersion(major: 3, minor: 12)),
        paths: paths,
        systemCandidates: [systemPython.path],
        runner: { _, _ in "3.12.9\n" },
        installer: { _ in
            Issue.record("Managed Python should not be installed when a compatible managed runtime already exists.")
        }
    )

    #expect(
        runtime.map { URL(fileURLWithPath: $0.executablePath).standardizedFileURL.path } ==
        managedPython.standardizedFileURL.path
    )
}

@Test
func managedPythonLocatorInstallsManagedRuntimeWhenNoCompatiblePythonExists() async throws {
    let sandbox = try TestExecutableSandbox()
    defer { sandbox.cleanup() }

    let paths = ApplicationPaths(root: sandbox.root.appending(path: "swiftlm-app"))
    try paths.createIfNeeded()

    let runtime = try await ManagedPythonLocator.locateCompatibleRuntime(
        requirement: .minimum(PythonVersion(major: 3, minor: 8)),
        paths: paths,
        systemCandidates: [],
        runner: { executablePath, _ in
            executablePath.contains("python3.12") ? "3.12.10\n" : "3.11.0\n"
        },
        installer: { version in
            #expect(version == PythonVersion(major: 3, minor: 12))
            _ = try sandbox.makeExecutable(
                named: "swiftlm-app/python/cpython-3.12.10/python/install/bin/python3.12"
            )
        }
    )

    #expect(runtime?.version == PythonVersion("3.12.10"))
    #expect(runtime?.executablePath.contains("/python/cpython-3.12.10/") == true)
}

@Test
func managedPythonReleaseAssetSelectionMatchesRequestedVersionAndArchitecture() async throws {
    let payload = """
    {
      "assets": [
        {
          "name": "cpython-3.11.11+20260410-aarch64-apple-darwin-install_only.tar.gz",
          "browser_download_url": "https://example.com/python311.tar.gz"
        },
        {
          "name": "cpython-3.12.10+20260410-aarch64-apple-darwin-install_only.tar.gz",
          "browser_download_url": "https://example.com/python312.tar.gz"
        }
      ]
    }
    """.data(using: .utf8)!

    let asset = ManagedPythonLocator.selectReleaseAsset(
        from: payload,
        version: PythonVersion(major: 3, minor: 12),
        architecture: .aarch64AppleDarwin
    )

    #expect(asset?.name == "cpython-3.12.10+20260410-aarch64-apple-darwin-install_only.tar.gz")
    #expect(asset?.downloadURL.absoluteString == "https://example.com/python312.tar.gz")
}

private struct TestExecutableSandbox {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "swiftlm-python-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeExecutable(named name: String) throws -> URL {
        let url = root.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
