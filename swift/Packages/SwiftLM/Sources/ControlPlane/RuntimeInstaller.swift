import Contracts
import Foundation
import LoggingKit
import RuntimeAdapters
import Storage

public protocol BackendRuntimeInstalling: Sendable {
    func install(backendID: String) async throws -> RuntimeManifest
}

struct RuntimeInstaller: BackendRuntimeInstalling, Sendable {
    let paths: ApplicationPaths
    let logger: AppLogger

    func install(backendID: String) async throws -> RuntimeManifest {
        switch backendID {
        case BackendKind.vllmMetal.rawValue:
            return try await installVLLMMetal()
        case BackendKind.mlxNative.rawValue:
            return try await installMLXNative()
        default:
            throw APIErrorEnvelope(
                code: "BACKEND_NOT_SUPPORTED",
                message: "SwiftLM does not manage installation for this backend.",
                details: ["backendId": backendID]
            )
        }
    }

    private func installVLLMMetal() async throws -> RuntimeManifest {
        let session = try stagingSession(prefix: "vllm-metal")
        defer { cleanup(session.stagingRoot) }

        let python = try await resolvePythonRuntime(
            requirement: .exactMajorMinor(PythonVersion(major: 3, minor: 12)),
            backendID: BackendKind.vllmMetal.rawValue,
            backendName: "vLLM Metal",
            category: "runtime.install.vllm-metal"
        )
        await logger.log(level: "info", category: "runtime.install.vllm-metal", message: "Using local Python runtime for backend installation.", metadata: [
            "pythonPath": python.executablePath,
            "pythonVersion": python.version.description
        ])

        let runtimeVenv = session.runtimeRoot.appending(path: "venv").path
        let archiveURL = URL(string: "https://github.com/vllm-project/vllm/releases/download/v0.17.1/vllm-0.17.1.tar.gz")!
        let archiveURLOnDisk = session.workDirectory.appending(path: "vllm-0.17.1.tar.gz")
        let wheelURL = try await latestVLLMMetalWheelURL()
        let wheelURLOnDisk = session.workDirectory.appending(path: "vllm-metal.whl")

        try await download(from: archiveURL, to: archiveURLOnDisk, category: "runtime.install.vllm-metal")
        try await download(from: wheelURL, to: wheelURLOnDisk, category: "runtime.install.vllm-metal")

        _ = try await ShellCommandRunner.run(
            executablePath: python.executablePath,
            arguments: ["-m", "venv", runtimeVenv, "--clear"],
            workingDirectory: session.workDirectory.path,
            logger: logger,
            category: "runtime.install.vllm-metal"
        )

        let pythonPath = session.runtimeRoot.appending(path: "venv/bin/python").path
        let executablePath = session.runtimeRoot.appending(path: "venv/bin/vllm").path

        _ = try await ShellCommandRunner.run(
            executablePath: pythonPath,
            arguments: ["-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
            workingDirectory: session.workDirectory.path,
            logger: logger,
            category: "runtime.install.vllm-metal"
        )
        _ = try await ShellCommandRunner.run(
            executablePath: "/usr/bin/tar",
            arguments: ["xf", archiveURLOnDisk.lastPathComponent],
            workingDirectory: session.workDirectory.path,
            logger: logger,
            category: "runtime.install.vllm-metal"
        )

        let sourceDirectory = session.workDirectory.appending(path: "vllm-0.17.1")
        _ = try await ShellCommandRunner.run(
            executablePath: pythonPath,
            arguments: ["-m", "pip", "install", "-r", "requirements/cpu.txt"],
            workingDirectory: sourceDirectory.path,
            logger: logger,
            category: "runtime.install.vllm-metal"
        )
        _ = try await ShellCommandRunner.run(
            executablePath: pythonPath,
            arguments: ["-m", "pip", "install", "."],
            workingDirectory: sourceDirectory.path,
            logger: logger,
            category: "runtime.install.vllm-metal"
        )
        _ = try await ShellCommandRunner.run(
            executablePath: pythonPath,
            arguments: ["-m", "pip", "install", "transformers>=5.0.0"],
            workingDirectory: session.workDirectory.path,
            logger: logger,
            category: "runtime.install.vllm-metal"
        )
        _ = try await ShellCommandRunner.run(
            executablePath: pythonPath,
            arguments: ["-m", "pip", "install", wheelURLOnDisk.path],
            workingDirectory: session.workDirectory.path,
            logger: logger,
            category: "runtime.install.vllm-metal"
        )

        let version = try await pythonMetadataValue(pythonPath: pythonPath, packageName: "vllm-metal")
        let pythonVersion = try await pythonVersion(pythonPath: pythonPath)
        let manifest = RuntimeManifest(
            backendId: BackendKind.vllmMetal.rawValue,
            packageName: "vllm-metal",
            version: version,
            pythonVersion: pythonVersion,
            installedAt: Time.nowISO8601(),
            runtimeRootPath: session.runtimeRoot.path,
            executablePath: executablePath,
            pythonPath: pythonPath,
            metadata: [
                "entrypoint": "vllm serve",
                "source": "system-python-managed"
            ]
        )
        try finalizeInstallation(manifest: manifest, backendID: BackendKind.vllmMetal.rawValue, runtimeRoot: session.runtimeRoot)
        return manifest
    }

    private func installMLXNative() async throws -> RuntimeManifest {
        let session = try stagingSession(prefix: "mlx-native")
        defer { cleanup(session.stagingRoot) }

        let python = try await resolvePythonRuntime(
            requirement: .minimum(PythonVersion(major: 3, minor: 11)),
            backendID: BackendKind.mlxNative.rawValue,
            backendName: "MLX Native",
            category: "runtime.install.mlx-native"
        )
        await logger.log(level: "info", category: "runtime.install.mlx-native", message: "Using local Python runtime for backend installation.", metadata: [
            "pythonPath": python.executablePath,
            "pythonVersion": python.version.description
        ])

        let pythonPath = python.executablePath
        let sitePackagesPath = try createManagedSitePackagesDirectory(
            root: session.runtimeRoot,
            version: python.version
        ).path
        _ = try await ShellCommandRunner.run(
            executablePath: pythonPath,
            arguments: ["-m", "pip", "install", "--upgrade", "--target", sitePackagesPath, "mlx-lm"],
            workingDirectory: session.workDirectory.path,
            logger: logger,
            category: "runtime.install.mlx-native"
        )
        guard ManagedMLXSitePackagesValidator.isValid(at: sitePackagesPath, pythonPath: pythonPath) else {
            throw APIErrorEnvelope(
                code: "BACKEND_INSTALL_FAILED",
                message: "MLX Native installation did not produce a loadable runtime.",
                details: ["backendId": BackendKind.mlxNative.rawValue]
            )
        }

        let version = try await pythonMetadataValue(
            pythonPath: pythonPath,
            packageName: "mlx-lm",
            pythonPathEntries: [sitePackagesPath]
        )
        let pythonVersion = python.version.description
        let manifest = RuntimeManifest(
            backendId: BackendKind.mlxNative.rawValue,
            packageName: "mlx-lm",
            version: version,
            pythonVersion: pythonVersion,
            installedAt: Time.nowISO8601(),
            runtimeRootPath: session.runtimeRoot.path,
            executablePath: pythonPath,
            pythonPath: pythonPath,
            metadata: [
                "entrypoint": "python -m mlx_lm.server",
                "source": "system-python-managed",
                "sitePackagesPath": sitePackagesPath
            ]
        )
        try finalizeInstallation(manifest: manifest, backendID: BackendKind.mlxNative.rawValue, runtimeRoot: session.runtimeRoot)
        return manifest
    }

    private func resolvePythonRuntime(
        requirement: PythonRequirement,
        backendID: String,
        backendName: String,
        category: String
    ) async throws -> PythonRuntime {
        if let runtime = try await ManagedPythonLocator.locateCompatibleRuntime(
            requirement: requirement,
            paths: paths,
            systemCandidates: PythonRuntimeLocator.defaultCandidates(),
            installer: { version in
                try await installManagedPython(version: version, category: category)
            }
        ) {
            return runtime
        }

        let requestedVersion = requirement.description
        await logger.log(level: "error", category: category, message: "Missing Python prerequisite for backend installation.", metadata: [
            "backendId": backendID,
            "requiredPython": requestedVersion
        ])
        throw APIErrorEnvelope(
            code: "BACKEND_INSTALL_PREREQUISITE_MISSING",
            message: "\(backendName) requires a local Python \(requestedVersion) interpreter. Install it and retry.",
            details: ["backendId": backendID, "requiredPython": requestedVersion]
        )
    }

    private func installManagedPython(version: PythonVersion, category: String) async throws {
        let session = try managedPythonStagingSession(version: version)
        defer { cleanup(session.stagingRoot) }

        let asset = try await latestManagedPythonReleaseAsset(for: version)
        let archiveURL = session.stagingRoot.appending(path: asset.name)
        await logger.log(level: "info", category: category, message: "Installing managed Python runtime.", metadata: [
            "pythonVersion": "\(version.major).\(version.minor)",
            "asset": asset.name
        ])

        try await download(from: asset.downloadURL, to: archiveURL, category: category)
        _ = try await ShellCommandRunner.run(
            executablePath: "/usr/bin/tar",
            arguments: ["xzf", archiveURL.path, "-C", session.extractedRoot.path],
            workingDirectory: nil,
            logger: logger,
            category: category
        )

        let fileManager = FileManager.default
        let finalRoot = paths.pythonDirectory.appending(path: asset.installationDirectoryName)
        if fileManager.fileExists(atPath: finalRoot.path) {
            try fileManager.removeItem(at: finalRoot)
        }
        try fileManager.moveItem(at: session.extractedRoot, to: finalRoot)

        let candidates = ManagedPythonLocator.candidateExecutables(root: finalRoot)
        if let runtime = await PythonRuntimeLocator.locateCompatibleRuntime(
            requirement: .exactMajorMinor(version),
            candidates: candidates
        ) {
            await logger.log(level: "info", category: category, message: "Managed Python runtime installed.", metadata: [
                "pythonPath": runtime.executablePath,
                "pythonVersion": runtime.version.description
            ])
            return
        }

        throw APIErrorEnvelope(
            code: "BACKEND_INSTALL_FAILED",
            message: "Managed Python \(version.major).\(version.minor) installed, but no compatible executable was found.",
            details: ["pythonVersion": "\(version.major).\(version.minor)"]
        )
    }

    private func latestManagedPythonReleaseAsset(for version: PythonVersion) async throws -> ManagedPythonReleaseAsset {
        let requestURL = URL(string: "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest")!
        var request = URLRequest(url: requestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SwiftLM", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw APIErrorEnvelope(
                code: "BACKEND_INSTALL_FAILED",
                message: "Failed to fetch managed Python release metadata.",
                details: ["pythonVersion": "\(version.major).\(version.minor)"]
            )
        }

        guard let asset = ManagedPythonLocator.selectReleaseAsset(
            from: data,
            version: version,
            architecture: ManagedPythonLocator.hostArchitecture
        ) else {
            throw APIErrorEnvelope(
                code: "BACKEND_INSTALL_FAILED",
                message: "No managed Python \(version.major).\(version.minor) distribution is available for this Mac.",
                details: [
                    "pythonVersion": "\(version.major).\(version.minor)",
                    "architecture": ManagedPythonLocator.hostArchitecture.releaseToken
                ]
            )
        }

        return asset
    }

    private func latestVLLMMetalWheelURL() async throws -> URL {
        let requestURL = URL(string: "https://api.github.com/repos/vllm-project/vllm-metal/releases/latest")!
        var request = URLRequest(url: requestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SwiftLM", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw APIErrorEnvelope(
                code: "BACKEND_INSTALL_FAILED",
                message: "Failed to fetch the latest vLLM Metal release metadata.",
                details: ["backendId": BackendKind.vllmMetal.rawValue]
            )
        }

        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let assets = payload?["assets"] as? [[String: Any]] ?? []
        for asset in assets {
            guard
                let name = asset["name"] as? String,
                name.contains("cp312"),
                name.hasSuffix(".whl"),
                let value = asset["browser_download_url"] as? String,
                let url = URL(string: value)
            else {
                continue
            }
            return url
        }

        throw APIErrorEnvelope(
            code: "BACKEND_INSTALL_FAILED",
            message: "The latest vLLM Metal release does not expose a Python 3.12 wheel.",
            details: ["backendId": BackendKind.vllmMetal.rawValue]
        )
    }

    private func download(from remoteURL: URL, to destinationURL: URL, category: String) async throws {
        await logger.log(level: "info", category: category, message: "Downloading runtime artifact.", metadata: [
            "url": remoteURL.absoluteString,
            "destination": destinationURL.lastPathComponent
        ])
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw APIErrorEnvelope(
                code: "BACKEND_INSTALL_FAILED",
                message: "Failed to download \(remoteURL.lastPathComponent).",
                details: ["category": category, "url": remoteURL.absoluteString]
            )
        }
        try data.write(to: destinationURL)
    }

    private func createManagedSitePackagesDirectory(root: URL, version: PythonVersion) throws -> URL {
        let directory = root
            .appending(path: "site-packages")
            .appending(path: "python\(version.major).\(version.minor)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func stagingSession(prefix: String) throws -> RuntimeStagingSession {
        let identifier = UUID().uuidString.lowercased()
        let stagingRoot = paths.runtimesDirectory.appending(path: ".install-\(prefix)-\(identifier)")
        let workDirectory = stagingRoot.appending(path: "work")
        let runtimeRoot = stagingRoot.appending(path: "runtime")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        return RuntimeStagingSession(stagingRoot: stagingRoot, workDirectory: workDirectory, runtimeRoot: runtimeRoot)
    }

    private func managedPythonStagingSession(version: PythonVersion) throws -> ManagedPythonStagingSession {
        let identifier = UUID().uuidString.lowercased()
        let stagingRoot = paths.pythonDirectory.appending(path: ".install-python-\(version.major).\(version.minor)-\(identifier)")
        let extractedRoot = stagingRoot.appending(path: "payload")
        try FileManager.default.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
        return ManagedPythonStagingSession(stagingRoot: stagingRoot, extractedRoot: extractedRoot)
    }

    private func finalizeInstallation(manifest: RuntimeManifest, backendID: String, runtimeRoot: URL) throws {
        let fileManager = FileManager.default
        let versionDirectoryName = "\(backendID)-\(sanitize(manifest.version))-py\(manifest.pythonVersion.replacingOccurrences(of: ".", with: ""))"
        let finalRuntimeRoot = paths.runtimesDirectory.appending(path: versionDirectoryName)
        if fileManager.fileExists(atPath: finalRuntimeRoot.path) {
            try fileManager.removeItem(at: finalRuntimeRoot)
        }
        try fileManager.moveItem(at: runtimeRoot, to: finalRuntimeRoot)

        let finalizedManifest = Self.finalizedManifest(
            manifest: manifest,
            finalRuntimeRoot: finalRuntimeRoot,
            originalRuntimeRoot: runtimeRoot
        )
        let manifestData = try JSONEncoder().encode(finalizedManifest)
        try manifestData.write(to: finalRuntimeRoot.appending(path: "manifest.json"))
        try switchCurrentSymlink(backendID: backendID, target: finalRuntimeRoot)
    }

    static func finalizedManifest(
        manifest: RuntimeManifest,
        finalRuntimeRoot: URL,
        originalRuntimeRoot: URL
    ) -> RuntimeManifest {
        RuntimeManifest(
            backendId: manifest.backendId,
            packageName: manifest.packageName,
            version: manifest.version,
            pythonVersion: manifest.pythonVersion,
            installedAt: manifest.installedAt,
            runtimeRootPath: finalRuntimeRoot.path,
            executablePath: relocatedPath(
                manifest.executablePath,
                originalRoot: originalRuntimeRoot,
                finalRoot: finalRuntimeRoot
            ),
            pythonPath: manifest.pythonPath.map {
                relocatedPath($0, originalRoot: originalRuntimeRoot, finalRoot: finalRuntimeRoot)
            },
            metadata: manifest.metadata.mapValues {
                relocatedPath($0, originalRoot: originalRuntimeRoot, finalRoot: finalRuntimeRoot)
            }
        )
    }

    private func switchCurrentSymlink(backendID: String, target: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.currentDirectory, withIntermediateDirectories: true)
        let symlinkURL = paths.currentDirectory.appending(path: backendID)
        if fileManager.fileExists(atPath: symlinkURL.path) || (try? symlinkURL.checkResourceIsReachable()) == true {
            try fileManager.removeItem(at: symlinkURL)
        }
        let relativeTarget = "../runtimes/\(target.lastPathComponent)"
        try fileManager.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: relativeTarget)
    }

    private func pythonMetadataValue(
        pythonPath: String,
        packageName: String,
        pythonPathEntries: [String] = []
    ) async throws -> String {
        let script = "import importlib.metadata as m; print(m.version('\(packageName)'))"
        let environment = pythonPathEntries.isEmpty ? nil : mergedEnvironment(with: [
            "PYTHONPATH": pythonPathEntries.joined(separator: ":")
        ])
        let output = try await ShellCommandRunner.run(
            executablePath: pythonPath,
            arguments: ["-c", script],
            workingDirectory: nil,
            environment: environment,
            logger: logger,
            category: "runtime.metadata"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pythonVersion(pythonPath: String) async throws -> String {
        let script = "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
        let output = try await ShellCommandRunner.run(
            executablePath: pythonPath,
            arguments: ["-c", script],
            workingDirectory: nil,
            environment: nil,
            logger: logger,
            category: "runtime.metadata"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergedEnvironment(with overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }

    private static func relocatedPath(
        _ path: String,
        originalRoot: URL,
        finalRoot: URL
    ) -> String {
        let originalRootPath = originalRoot.path
        guard path.hasPrefix(originalRootPath + "/") else {
            return path
        }
        let suffix = String(path.dropFirst(originalRootPath.count + 1))
        return finalRoot.appending(path: suffix).path
    }

    private func sanitize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

struct PythonRuntime: Equatable, Sendable {
    let executablePath: String
    let version: PythonVersion
}

struct PythonVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int?

    init(major: Int, minor: Int, patch: Int? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ value: String) {
        let components = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
        guard components.count >= 2,
              let major = Int(components[0]),
              let minor = Int(components[1])
        else {
            return nil
        }
        let patch = components.count > 2 ? Int(components[2]) : nil
        self.init(major: major, minor: minor, patch: patch)
    }

    var description: String {
        if let patch {
            return "\(major).\(minor).\(patch)"
        }
        return "\(major).\(minor)"
    }

    static func < (lhs: PythonVersion, rhs: PythonVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return (lhs.patch ?? 0) < (rhs.patch ?? 0)
    }
}

enum PythonRequirement: Equatable, Sendable, CustomStringConvertible {
    case minimum(PythonVersion)
    case exactMajorMinor(PythonVersion)

    func accepts(_ version: PythonVersion) -> Bool {
        switch self {
        case let .minimum(required):
            return version >= required
        case let .exactMajorMinor(required):
            return version.major == required.major && version.minor == required.minor
        }
    }

    var description: String {
        switch self {
        case let .minimum(required):
            return "\(required.major).\(required.minor)+"
        case let .exactMajorMinor(required):
            return "\(required.major).\(required.minor)"
        }
    }
}

enum PythonRuntimeLocator {
    typealias Runner = @Sendable (String, [String]) async throws -> String

    static func defaultCandidates(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        let names = [
            "python3.13",
            "python3.12",
            "python3.11",
            "python3.10",
            "python3.9",
            "python3",
            "python"
        ]
        let seedPaths = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/python3",
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.10",
            "/opt/homebrew/bin/python3.9",
            "/usr/local/bin/python3.13",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3.11",
            "/usr/local/bin/python3.10",
            "/usr/local/bin/python3.9"
        ]
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        var candidates: [String] = seedPaths
        for directory in pathDirectories {
            for name in names {
                candidates.append(URL(fileURLWithPath: directory).appendingPathComponent(name).path)
            }
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate).inserted
        }
    }

    static func locateCompatibleRuntime(
        requirement: PythonRequirement,
        candidates: [String],
        runner: Runner = defaultRunner
    ) async -> PythonRuntime? {
        var compatible: [(runtime: PythonRuntime, order: Int)] = []
        for (index, candidate) in candidates.enumerated() where FileManager.default.isExecutableFile(atPath: candidate) {
            guard let version = await version(for: candidate, runner: runner) else {
                continue
            }
            guard requirement.accepts(version) else {
                continue
            }
            compatible.append((PythonRuntime(executablePath: candidate, version: version), index))
        }

        return compatible.sorted { lhs, rhs in
            if lhs.runtime.version == rhs.runtime.version {
                return lhs.order < rhs.order
            }
            return lhs.runtime.version > rhs.runtime.version
        }.first?.runtime
    }

    private static func version(
        for executablePath: String,
        runner: Runner
    ) async -> PythonVersion? {
        let script = "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')"
        guard let output = try? await runner(executablePath, ["-c", script]) else {
            return nil
        }
        return PythonVersion(output)
    }

    static func defaultRunner(executablePath: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(decoding: stdoutData, as: UTF8.self)
                let stderr = String(decoding: stderrData, as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(throwing: APIErrorEnvelope(
                        code: "BACKEND_INSTALL_PREREQUISITE_MISSING",
                        message: stderr.isEmpty == false ? stderr.trimmingCharacters(in: .whitespacesAndNewlines) : stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct ManagedPythonReleaseAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL

    var installationDirectoryName: String {
        if name.hasSuffix(".tar.gz") {
            return String(name.dropLast(".tar.gz".count))
        }
        return name
    }
}

enum ManagedPythonLocator {
    enum Architecture: String, Sendable {
        case aarch64AppleDarwin = "aarch64-apple-darwin"
        case x8664AppleDarwin = "x86_64-apple-darwin"

        var releaseToken: String { rawValue }
    }

    typealias Installer = @Sendable (PythonVersion) async throws -> Void

    static var hostArchitecture: Architecture {
        #if arch(arm64)
        .aarch64AppleDarwin
        #else
        .x8664AppleDarwin
        #endif
    }

    static func candidateExecutables(root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [String] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard name == "python" || name == "python3" || name.hasPrefix("python3.") else {
                continue
            }
            guard fileURL.path.contains("/bin/") else {
                continue
            }
            let path = fileURL.path
            guard FileManager.default.isExecutableFile(atPath: path) else {
                continue
            }
            candidates.append(path)
        }

        return candidates.sorted()
    }

    static func preferredVersion(for requirement: PythonRequirement) -> PythonVersion {
        switch requirement {
        case let .exactMajorMinor(required):
            return PythonVersion(major: required.major, minor: required.minor)
        case let .minimum(required):
            let requested = PythonVersion(major: required.major, minor: required.minor)
            let baseline = PythonVersion(major: 3, minor: 12)
            return max(requested, baseline)
        }
    }

    static func locateCompatibleRuntime(
        requirement: PythonRequirement,
        paths: ApplicationPaths,
        systemCandidates: [String],
        runner: PythonRuntimeLocator.Runner = PythonRuntimeLocator.defaultRunner,
        installer: Installer
    ) async throws -> PythonRuntime? {
        let managedCandidates = candidateExecutables(root: paths.pythonDirectory)
        if let runtime = await PythonRuntimeLocator.locateCompatibleRuntime(
            requirement: requirement,
            candidates: managedCandidates + systemCandidates,
            runner: runner
        ) {
            return runtime
        }

        try await installer(preferredVersion(for: requirement))

        let refreshedManagedCandidates = candidateExecutables(root: paths.pythonDirectory)
        return await PythonRuntimeLocator.locateCompatibleRuntime(
            requirement: requirement,
            candidates: refreshedManagedCandidates + systemCandidates,
            runner: runner
        )
    }

    static func selectReleaseAsset(
        from data: Data,
        version: PythonVersion,
        architecture: Architecture
    ) -> ManagedPythonReleaseAsset? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let assets = payload["assets"] as? [[String: Any]] ?? []
        let prefix = "cpython-\(version.major).\(version.minor)."
        let suffix = "-\(architecture.releaseToken)-install_only.tar.gz"
        for asset in assets {
            guard
                let name = asset["name"] as? String,
                name.hasPrefix(prefix),
                name.hasSuffix(suffix),
                let value = asset["browser_download_url"] as? String,
                let url = URL(string: value)
            else {
                continue
            }
            return ManagedPythonReleaseAsset(name: name, downloadURL: url)
        }
        return nil
    }
}

private struct RuntimeStagingSession {
    let stagingRoot: URL
    let workDirectory: URL
    let runtimeRoot: URL
}

private struct ManagedPythonStagingSession {
    let stagingRoot: URL
    let extractedRoot: URL
}

private enum ShellCommandRunner {
    static func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]? = nil,
        logger: AppLogger,
        category: String
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let collector = OutputCollector()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        attach(pipe: stdoutPipe, collector: collector, logger: logger, level: "info", category: category)
        attach(pipe: stderrPipe, collector: collector, logger: logger, level: "error", category: category)

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                Task {
                    let stdout = await collector.stdout()
                    let stderr = await collector.stderr()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: stdout)
                    } else {
                        let message = stderr.isEmpty == false ? stderr : stdout
                        continuation.resume(throwing: APIErrorEnvelope(
                            code: "BACKEND_INSTALL_FAILED",
                            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                            details: ["category": category, "status": "\(process.terminationStatus)"]
                        ))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: APIErrorEnvelope(
                    code: "BACKEND_INSTALL_FAILED",
                    message: "Failed to launch install process \(executablePath): \(error.localizedDescription)",
                    details: ["category": category]
                ))
            }
        }
    }

    private static func attach(
        pipe: Pipe,
        collector: OutputCollector,
        logger: AppLogger,
        level: String,
        category: String
    ) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else {
                handle.readabilityHandler = nil
                return
            }

            let text = String(decoding: data, as: UTF8.self)
            Task {
                await collector.append(text, to: level == "error" ? .stderr : .stdout)
                for line in text.split(whereSeparator: \.isNewline) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.isEmpty == false else { continue }
                    await logger.log(level: level, category: category, message: trimmed, metadata: [:])
                }
            }
        }
    }
}

private actor OutputCollector {
    enum Stream {
        case stdout
        case stderr
    }

    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    func append(_ value: String, to stream: Stream) {
        switch stream {
        case .stdout:
            stdoutBuffer += value
        case .stderr:
            stderrBuffer += value
        }
    }

    func stdout() -> String {
        stdoutBuffer
    }

    func stderr() -> String {
        stderrBuffer
    }
}
