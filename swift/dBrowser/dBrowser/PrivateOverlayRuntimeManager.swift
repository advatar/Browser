import Foundation

enum PrivateOverlayManagedRuntimeKind: String, CaseIterable, Codable, Equatable, Sendable {
    case unmanaged
    case i2pRouter
    case torArti

    nonisolated var title: String {
        switch self {
        case .unmanaged: "Managed runtime"
        case .i2pRouter: "I2P router"
        case .torArti: "Tor/Arti"
        }
    }
}

enum PrivateOverlayManagedRuntimeLifecycle: String, CaseIterable, Codable, Equatable, Sendable {
    case disabled
    case notInstalled
    case launchReady
    case starting
    case running
    case stopping
    case stopped
    case misconfigured
    case blocked
    case failed

    nonisolated var readiness: PrivateOverlayRuntimeReadiness {
        switch self {
        case .disabled, .notInstalled, .stopped:
            return .notInstalled
        case .launchReady:
            return .installed
        case .starting, .running, .stopping:
            return .running
        case .misconfigured, .failed:
            return .misconfigured
        case .blocked:
            return .blocked
        }
    }

    nonisolated var statusText: String {
        switch self {
        case .disabled: "disabled"
        case .notInstalled: "not installed"
        case .launchReady: "launch ready"
        case .starting: "starting"
        case .running: "running"
        case .stopping: "stopping"
        case .stopped: "stopped"
        case .misconfigured: "misconfigured"
        case .blocked: "blocked"
        case .failed: "failed"
        }
    }
}

struct PrivateOverlayRuntimePortSet: Equatable, Sendable {
    var adapterPort: Int
    var socksPort: Int
    var controlPort: Int

    nonisolated var adapterEndpoint: String { "127.0.0.1:\(adapterPort)" }
    nonisolated var socksEndpoint: String { "127.0.0.1:\(socksPort)" }
    nonisolated var controlEndpoint: String { "127.0.0.1:\(controlPort)" }

    nonisolated init(adapterPort: Int, socksPort: Int, controlPort: Int) {
        self.adapterPort = adapterPort
        self.socksPort = socksPort
        self.controlPort = controlPort
    }
}

struct PrivateOverlayRuntimeLaunchPolicy: Equatable, Sendable {
    var bindsOnlyLoopback: Bool
    var allowsSystemDNSForPrivateNames: Bool
    var allowsClearnetFallback: Bool

    nonisolated static let noClearnetFallback = PrivateOverlayRuntimeLaunchPolicy(
        bindsOnlyLoopback: true,
        allowsSystemDNSForPrivateNames: false,
        allowsClearnetFallback: false
    )

    nonisolated var isSafeForPrivateOverlay: Bool {
        bindsOnlyLoopback && !allowsSystemDNSForPrivateNames && !allowsClearnetFallback
    }
}

enum PrivateOverlayRuntimeStopStrategy: Equatable, Sendable {
    case terminateProcess
    case command(arguments: [String])
}

struct PrivateOverlayManagedRuntimeProfile: Equatable, Identifiable, Sendable {
    var id: String
    var network: PrivateOverlayNetwork
    var kind: PrivateOverlayManagedRuntimeKind
    var executableName: String
    var bundledExecutableRelativePath: String?
    var defaultExecutablePaths: [String]
    var ports: PrivateOverlayRuntimePortSet
    var dataDirectoryName: String
    var configurationFileName: String
    var launchPolicy: PrivateOverlayRuntimeLaunchPolicy

    nonisolated static let torArti = PrivateOverlayManagedRuntimeProfile(
        id: "tor-arti",
        network: .tor,
        kind: .torArti,
        executableName: "arti",
        bundledExecutableRelativePath: "PrivateOverlayRuntimes/arti",
        defaultExecutablePaths: [
            "/opt/homebrew/bin/arti",
            "/usr/local/bin/arti",
            "/usr/bin/arti"
        ],
        ports: PrivateOverlayRuntimePortSet(adapterPort: 4893, socksPort: 4898, controlPort: 4899),
        dataDirectoryName: "TorArti",
        configurationFileName: "arti.toml",
        launchPolicy: .noClearnetFallback
    )

    nonisolated static let i2pRouter = PrivateOverlayManagedRuntimeProfile(
        id: "i2p-router",
        network: .i2p,
        kind: .i2pRouter,
        executableName: "i2prouter",
        bundledExecutableRelativePath: "PrivateOverlayRuntimes/i2p/i2prouter",
        defaultExecutablePaths: [
            "/Applications/i2p/i2prouter",
            "/Applications/I2P/i2prouter",
            "/opt/homebrew/bin/i2prouter",
            "/opt/homebrew/opt/i2p/bin/i2prouter",
            "/usr/local/bin/i2prouter",
            "/usr/bin/i2prouter"
        ],
        ports: PrivateOverlayRuntimePortSet(adapterPort: 4894, socksPort: 4444, controlPort: 7657),
        dataDirectoryName: "I2PRouter",
        configurationFileName: "dbrowser-i2p-runtime.md",
        launchPolicy: .noClearnetFallback
    )

    nonisolated static func unmanaged(network: PrivateOverlayNetwork) -> PrivateOverlayManagedRuntimeProfile {
        PrivateOverlayManagedRuntimeProfile(
            id: "\(network.id)-unmanaged",
            network: network,
            kind: .unmanaged,
            executableName: "",
            bundledExecutableRelativePath: nil,
            defaultExecutablePaths: [],
            ports: PrivateOverlayRuntimePortSet(adapterPort: 0, socksPort: 0, controlPort: 0),
            dataDirectoryName: "",
            configurationFileName: "",
            launchPolicy: .noClearnetFallback
        )
    }

    nonisolated func launchPlan(
        executableURL: URL,
        rootDirectory: URL
    ) -> PrivateOverlayRuntimeLaunchPlan {
        let runtimeDirectory = rootDirectory.appendingPathComponent(dataDirectoryName, isDirectory: true)
        let configurationFileURL = runtimeDirectory.appendingPathComponent(configurationFileName)
        return PrivateOverlayRuntimeLaunchPlan(
            profileID: id,
            network: network,
            kind: kind,
            executableURL: executableURL,
            arguments: launchArguments(configurationFileURL: configurationFileURL),
            environment: [
                "DBROWSER_PRIVATE_OVERLAY": network.id,
                "DBROWSER_PRIVATE_OVERLAY_RUNTIME": kind.rawValue,
                "DBROWSER_NO_CLEARNET_FALLBACK": "1"
            ].merging(launchEnvironment(runtimeDirectory: runtimeDirectory)) { _, managed in managed },
            workingDirectory: runtimeDirectory,
            configurationFileURL: configurationFileURL,
            configurationText: configurationText(runtimeDirectory: runtimeDirectory),
            ports: ports,
            launchPolicy: launchPolicy,
            stopStrategy: stopStrategy()
        )
    }

    nonisolated private func launchArguments(configurationFileURL: URL) -> [String] {
        switch kind {
        case .torArti:
            ["--config", configurationFileURL.path, "proxy"]
        case .i2pRouter:
            ["start"]
        case .unmanaged:
            []
        }
    }

    nonisolated private func launchEnvironment(runtimeDirectory: URL) -> [String: String] {
        switch kind {
        case .i2pRouter:
            [
                "I2P_CONFIG_DIR": runtimeDirectory.path,
                "DBROWSER_I2P_HTTP_PROXY": ports.socksEndpoint,
                "DBROWSER_I2P_ROUTER_CONSOLE": ports.controlEndpoint
            ]
        case .torArti, .unmanaged:
            [:]
        }
    }

    nonisolated private func configurationText(runtimeDirectory: URL) -> String {
        switch kind {
        case .torArti:
            artiConfigurationText(runtimeDirectory: runtimeDirectory)
        case .i2pRouter:
            i2pRuntimeBoundaryText(runtimeDirectory: runtimeDirectory)
        case .unmanaged:
            ""
        }
    }

    nonisolated private func stopStrategy() -> PrivateOverlayRuntimeStopStrategy {
        switch kind {
        case .i2pRouter:
            .command(arguments: ["stop"])
        case .torArti, .unmanaged:
            .terminateProcess
        }
    }

    nonisolated private func artiConfigurationText(runtimeDirectory: URL) -> String {
        let cacheDirectory = runtimeDirectory.appendingPathComponent("cache", isDirectory: true).path
        let stateDirectory = runtimeDirectory.appendingPathComponent("state", isDirectory: true).path
        return """
        [proxy]
        socks_listen = "\(ports.socksEndpoint)"
        dns_listen = 0

        [address_filter]
        allow_onion_addrs = true
        allow_local_addrs = false

        [storage]
        cache_dir = "\(cacheDirectory)"
        state_dir = "\(stateDirectory)"

        [logging]
        console = "warn"
        log_sensitive_information = false
        """
    }

    nonisolated private func i2pRuntimeBoundaryText(runtimeDirectory: URL) -> String {
        let stateDirectory = runtimeDirectory.appendingPathComponent("state", isDirectory: true).path
        return """
        # dBrowser managed I2P runtime boundary

        network = i2p
        adapter_endpoint = \(ports.adapterEndpoint)
        http_proxy = \(ports.socksEndpoint)
        router_console = \(ports.controlEndpoint)
        state_directory = \(stateDirectory)

        allow_system_dns_for_i2p = false
        allow_clearnet_fallback = false
        adapter_health_required_before_navigation = true
        """
    }
}

struct PrivateOverlayRuntimeLaunchPlan: Equatable, Sendable {
    var profileID: String
    var network: PrivateOverlayNetwork
    var kind: PrivateOverlayManagedRuntimeKind
    var executableURL: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL
    var configurationFileURL: URL
    var configurationText: String
    var ports: PrivateOverlayRuntimePortSet
    var launchPolicy: PrivateOverlayRuntimeLaunchPolicy
    var stopStrategy: PrivateOverlayRuntimeStopStrategy

    nonisolated var isSafeForPrivateOverlay: Bool {
        executableURL.isFileURL
            && workingDirectory.isFileURL
            && configurationFileURL.isFileURL
            && launchPolicy.isSafeForPrivateOverlay
            && ports.adapterEndpoint.hasPrefix("127.0.0.1:")
            && ports.socksEndpoint.hasPrefix("127.0.0.1:")
            && ports.controlEndpoint.hasPrefix("127.0.0.1:")
    }
}

struct PrivateOverlayRuntimeProcessHandle: Equatable, Sendable {
    var profileID: String
    var processIdentifier: Int32
    var startedAt: Date
    var executableURL: URL
    var environment: [String: String]
    var workingDirectory: URL
    var stopStrategy: PrivateOverlayRuntimeStopStrategy
}

struct PrivateOverlayManagedRuntimeStatus: Equatable, Identifiable, Sendable {
    var profile: PrivateOverlayManagedRuntimeProfile
    var lifecycle: PrivateOverlayManagedRuntimeLifecycle
    var executableURL: URL?
    var processIdentifier: Int32?
    var launchPlan: PrivateOverlayRuntimeLaunchPlan?
    var message: String

    nonisolated var id: String { profile.id }
    nonisolated var network: PrivateOverlayNetwork { profile.network }
    nonisolated var readiness: PrivateOverlayRuntimeReadiness { lifecycle.readiness }

    nonisolated var summary: String {
        "\(profile.kind.title) \(lifecycle.statusText)"
    }
}

struct PrivateOverlayManagedRuntimeSnapshot: Equatable, Sendable {
    var statuses: [PrivateOverlayManagedRuntimeStatus]

    nonisolated static let empty = PrivateOverlayManagedRuntimeSnapshot(statuses: [])

    nonisolated func status(for network: PrivateOverlayNetwork) -> PrivateOverlayManagedRuntimeStatus? {
        statuses.first { $0.network == network }
    }

    nonisolated var launchReadyStatuses: [PrivateOverlayManagedRuntimeStatus] {
        statuses.filter { $0.lifecycle == .launchReady }
    }

    nonisolated var runningStatuses: [PrivateOverlayManagedRuntimeStatus] {
        statuses.filter { $0.lifecycle == .running || $0.lifecycle == .starting || $0.lifecycle == .stopping }
    }

    nonisolated var summary: String {
        guard !statuses.isEmpty else {
            return "No managed private-overlay runtimes"
        }
        let runningCount = runningStatuses.count
        let launchReadyCount = launchReadyStatuses.count
        if runningCount > 0 {
            return "\(runningCount) managed private-overlay runtime\(runningCount == 1 ? "" : "s") running"
        }
        if launchReadyCount > 0 {
            return "\(launchReadyCount) managed private-overlay runtime\(launchReadyCount == 1 ? "" : "s") launch ready"
        }
        let missingCount = statuses.filter { $0.lifecycle == .notInstalled }.count
        if missingCount > 0 {
            return "\(missingCount) managed private-overlay runtime\(missingCount == 1 ? "" : "s") missing"
        }
        return statuses.map(\.summary).joined(separator: ", ")
    }
}

protocol PrivateOverlayRuntimeExecutableResolving: Sendable {
    nonisolated func executableURL(for profile: PrivateOverlayManagedRuntimeProfile) -> URL?
}

struct DefaultPrivateOverlayRuntimeExecutableResolver: PrivateOverlayRuntimeExecutableResolving, Sendable {
    var environment: [String: String]
    var additionalSearchPaths: [String]

    nonisolated init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchPaths: [String] = []
    ) {
        self.environment = environment
        self.additionalSearchPaths = additionalSearchPaths
    }

    nonisolated func executableURL(for profile: PrivateOverlayManagedRuntimeProfile) -> URL? {
        if let bundledExecutableRelativePath = profile.bundledExecutableRelativePath,
           let bundledURL = Bundle.main.resourceURL?.appendingPathComponent(bundledExecutableRelativePath),
           FileManager.default.isExecutableFile(atPath: bundledURL.path) {
            return bundledURL
        }

        for path in profile.defaultExecutablePaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for directory in additionalSearchPaths + pathDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(profile.executableName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

protocol PrivateOverlayRuntimeProcessControlling: Sendable {
    func launch(_ plan: PrivateOverlayRuntimeLaunchPlan) async throws -> PrivateOverlayRuntimeProcessHandle
    func stop(_ handle: PrivateOverlayRuntimeProcessHandle) async
}

actor LocalPrivateOverlayRuntimeProcessController: PrivateOverlayRuntimeProcessControlling {
    private var processes: [String: Process] = [:]

    func launch(_ plan: PrivateOverlayRuntimeLaunchPlan) async throws -> PrivateOverlayRuntimeProcessHandle {
        let process = Process()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments
        let environment = ProcessInfo.processInfo.environment.merging(plan.environment) { _, managed in managed }
        process.environment = environment
        process.currentDirectoryURL = plan.workingDirectory
        try process.run()
        processes[plan.profileID] = process
        return PrivateOverlayRuntimeProcessHandle(
            profileID: plan.profileID,
            processIdentifier: process.processIdentifier,
            startedAt: Date(),
            executableURL: plan.executableURL,
            environment: environment,
            workingDirectory: plan.workingDirectory,
            stopStrategy: plan.stopStrategy
        )
    }

    func stop(_ handle: PrivateOverlayRuntimeProcessHandle) async {
        let process = processes[handle.profileID]
        switch handle.stopStrategy {
        case .terminateProcess:
            if process?.isRunning == true {
                process?.terminate()
            }
        case .command(let arguments):
            let stopProcess = Process()
            stopProcess.executableURL = handle.executableURL
            stopProcess.arguments = arguments
            stopProcess.environment = handle.environment
            stopProcess.currentDirectoryURL = handle.workingDirectory
            do {
                try stopProcess.run()
                stopProcess.waitUntilExit()
            } catch {}
        }
        if process?.isRunning == true {
            process?.terminate()
        }
        processes.removeValue(forKey: handle.profileID)
    }
}

protocol PrivateOverlayRuntimeManaging: Sendable {
    func snapshot(configuration: PrivateOverlayAdapterConfiguration) async -> PrivateOverlayManagedRuntimeSnapshot
    func launchPlan(
        for network: PrivateOverlayNetwork,
        configuration: PrivateOverlayAdapterConfiguration
    ) async -> PrivateOverlayRuntimeLaunchPlan?
    func start(
        network: PrivateOverlayNetwork,
        configuration: PrivateOverlayAdapterConfiguration
    ) async -> PrivateOverlayManagedRuntimeStatus
    func stop(
        network: PrivateOverlayNetwork,
        configuration: PrivateOverlayAdapterConfiguration
    ) async -> PrivateOverlayManagedRuntimeStatus
}

actor LocalPrivateOverlayRuntimeManager: PrivateOverlayRuntimeManaging {
    private let profiles: [PrivateOverlayManagedRuntimeProfile]
    private let resolver: any PrivateOverlayRuntimeExecutableResolving
    private let processController: any PrivateOverlayRuntimeProcessControlling
    private let rootDirectory: URL
    private var runningHandles: [String: PrivateOverlayRuntimeProcessHandle] = [:]

    init(
        profiles: [PrivateOverlayManagedRuntimeProfile] = [.torArti, .i2pRouter],
        resolver: any PrivateOverlayRuntimeExecutableResolving = DefaultPrivateOverlayRuntimeExecutableResolver(),
        processController: any PrivateOverlayRuntimeProcessControlling = LocalPrivateOverlayRuntimeProcessController(),
        rootDirectory: URL? = nil
    ) {
        self.profiles = profiles
        self.resolver = resolver
        self.processController = processController
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory()
    }

    func snapshot(configuration: PrivateOverlayAdapterConfiguration) async -> PrivateOverlayManagedRuntimeSnapshot {
        PrivateOverlayManagedRuntimeSnapshot(
            statuses: profiles.map { status(for: $0, configuration: configuration) }
        )
    }

    func launchPlan(
        for network: PrivateOverlayNetwork,
        configuration: PrivateOverlayAdapterConfiguration
    ) async -> PrivateOverlayRuntimeLaunchPlan? {
        guard let profile = profiles.first(where: { $0.network == network }),
              configuration.endpoint(for: network.id) != nil,
              let executableURL = resolver.executableURL(for: profile) else {
            return nil
        }
        return profile.launchPlan(executableURL: executableURL, rootDirectory: rootDirectory)
    }

    func start(
        network: PrivateOverlayNetwork,
        configuration: PrivateOverlayAdapterConfiguration
    ) async -> PrivateOverlayManagedRuntimeStatus {
        guard let profile = profiles.first(where: { $0.network == network }) else {
            return disabledStatus(network: network)
        }
        guard configuration.endpoint(for: network.id) != nil else {
            return PrivateOverlayManagedRuntimeStatus(
                profile: profile,
                lifecycle: .disabled,
                executableURL: nil,
                processIdentifier: nil,
                launchPlan: nil,
                message: "\(profile.kind.title) is not configured as a local private-overlay adapter."
            )
        }
        guard let executableURL = resolver.executableURL(for: profile) else {
            return notInstalledStatus(for: profile)
        }
        let plan = profile.launchPlan(executableURL: executableURL, rootDirectory: rootDirectory)
        guard plan.isSafeForPrivateOverlay else {
            return PrivateOverlayManagedRuntimeStatus(
                profile: profile,
                lifecycle: .blocked,
                executableURL: executableURL,
                processIdentifier: nil,
                launchPlan: plan,
                message: "\(profile.kind.title) launch plan is blocked because it does not satisfy loopback/no-clearnet policy."
            )
        }

        do {
            try writeConfiguration(for: plan)
            let handle = try await processController.launch(plan)
            runningHandles[profile.id] = handle
            return PrivateOverlayManagedRuntimeStatus(
                profile: profile,
                lifecycle: .running,
                executableURL: executableURL,
                processIdentifier: handle.processIdentifier,
                launchPlan: plan,
                message: "\(profile.kind.title) started on \(plan.ports.socksEndpoint) with local-only private-overlay policy."
            )
        } catch {
            return PrivateOverlayManagedRuntimeStatus(
                profile: profile,
                lifecycle: .failed,
                executableURL: executableURL,
                processIdentifier: nil,
                launchPlan: plan,
                message: "\(profile.kind.title) failed to start: \(error.localizedDescription)"
            )
        }
    }

    func stop(
        network: PrivateOverlayNetwork,
        configuration: PrivateOverlayAdapterConfiguration
    ) async -> PrivateOverlayManagedRuntimeStatus {
        guard let profile = profiles.first(where: { $0.network == network }) else {
            return disabledStatus(network: network)
        }
        guard let handle = runningHandles[profile.id] else {
            return status(for: profile, configuration: configuration)
        }
        await processController.stop(handle)
        runningHandles.removeValue(forKey: profile.id)
        return PrivateOverlayManagedRuntimeStatus(
            profile: profile,
            lifecycle: .stopped,
            executableURL: resolver.executableURL(for: profile),
            processIdentifier: nil,
            launchPlan: await launchPlan(for: network, configuration: configuration),
            message: "\(profile.kind.title) stopped."
        )
    }

    private func status(
        for profile: PrivateOverlayManagedRuntimeProfile,
        configuration: PrivateOverlayAdapterConfiguration
    ) -> PrivateOverlayManagedRuntimeStatus {
        if let handle = runningHandles[profile.id] {
            let executableURL = resolver.executableURL(for: profile)
            return PrivateOverlayManagedRuntimeStatus(
                profile: profile,
                lifecycle: .running,
                executableURL: executableURL,
                processIdentifier: handle.processIdentifier,
                launchPlan: executableURL.map { profile.launchPlan(executableURL: $0, rootDirectory: rootDirectory) },
                message: "\(profile.kind.title) is running with managed local-only policy."
            )
        }
        guard configuration.endpoint(for: profile.network.id) != nil else {
            return PrivateOverlayManagedRuntimeStatus(
                profile: profile,
                lifecycle: .disabled,
                executableURL: nil,
                processIdentifier: nil,
                launchPlan: nil,
                message: "\(profile.kind.title) is disabled because \(profile.network.title) has no configured local adapter endpoint."
            )
        }
        guard let executableURL = resolver.executableURL(for: profile) else {
            return notInstalledStatus(for: profile)
        }
        let plan = profile.launchPlan(executableURL: executableURL, rootDirectory: rootDirectory)
        guard plan.isSafeForPrivateOverlay else {
            return PrivateOverlayManagedRuntimeStatus(
                profile: profile,
                lifecycle: .blocked,
                executableURL: executableURL,
                processIdentifier: nil,
                launchPlan: plan,
                message: "\(profile.kind.title) launch plan is blocked because it does not satisfy loopback/no-clearnet policy."
            )
        }
        return PrivateOverlayManagedRuntimeStatus(
            profile: profile,
            lifecycle: .launchReady,
            executableURL: executableURL,
            processIdentifier: nil,
            launchPlan: plan,
            message: "\(profile.kind.title) is installed and ready to launch on \(plan.ports.socksEndpoint); adapter health must verify before navigation."
        )
    }

    private func notInstalledStatus(
        for profile: PrivateOverlayManagedRuntimeProfile
    ) -> PrivateOverlayManagedRuntimeStatus {
        PrivateOverlayManagedRuntimeStatus(
            profile: profile,
            lifecycle: .notInstalled,
            executableURL: nil,
            processIdentifier: nil,
            launchPlan: nil,
            message: "\(profile.kind.title) executable '\(profile.executableName)' was not found in the app bundle, default install paths, or PATH."
        )
    }

    private func disabledStatus(network: PrivateOverlayNetwork) -> PrivateOverlayManagedRuntimeStatus {
        let profile = PrivateOverlayManagedRuntimeProfile.unmanaged(network: network)
        return PrivateOverlayManagedRuntimeStatus(
            profile: profile,
            lifecycle: .disabled,
            executableURL: nil,
            processIdentifier: nil,
            launchPlan: nil,
            message: "No managed runtime profile is registered for \(network.title)."
        )
    }

    private func writeConfiguration(for plan: PrivateOverlayRuntimeLaunchPlan) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: plan.workingDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: plan.workingDirectory.appendingPathComponent("cache", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: plan.workingDirectory.appendingPathComponent("state", isDirectory: true),
            withIntermediateDirectories: true
        )
        try plan.configurationText.write(
            to: plan.configurationFileURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private nonisolated static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("dBrowser", isDirectory: true)
            .appendingPathComponent("PrivateOverlayRuntimes", isDirectory: true)
    }
}
