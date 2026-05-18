import Contracts
import Darwin
import Foundation
import LoggingKit
import RuntimeAdapters

final class ManagedEngine: @unchecked Sendable {
    let process: Process
    let plan: EngineLaunchPlan
    let launchSpec: LaunchSpec
    let internalAPIKey: String?
    private(set) var instance: EngineInstanceRef

    init(
        process: Process,
        plan: EngineLaunchPlan,
        launchSpec: LaunchSpec,
        internalAPIKey: String?,
        instance: EngineInstanceRef
    ) {
        self.process = process
        self.plan = plan
        self.launchSpec = launchSpec
        self.internalAPIKey = internalAPIKey
        self.instance = instance
    }

    var baseURL: URL {
        URL(string: "http://\(instance.host):\(instance.port)")!
    }

    var isRunning: Bool {
        process.isRunning
    }

    func updateStatus(_ status: EngineStatus) {
        instance = EngineInstanceRef(
            id: instance.id,
            backendId: instance.backendId,
            modelId: instance.modelId,
            host: instance.host,
            port: instance.port,
            status: status,
            warnings: instance.warnings,
            pid: instance.pid,
            launchedAt: instance.launchedAt,
            profileId: instance.profileId,
            engineModelName: instance.engineModelName
        )
    }
}

enum PortAllocator {
    static func nextAvailablePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw APIErrorEnvelope(code: "LOCALHOST_BIND_FAILED", message: "Unable to allocate a localhost port.")
        }
        defer { close(descriptor) }

        var value: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw APIErrorEnvelope(code: "LOCALHOST_BIND_FAILED", message: "Failed to bind a temporary localhost socket.")
        }

        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw APIErrorEnvelope(code: "LOCALHOST_BIND_FAILED", message: "Failed to resolve a free localhost port.")
        }

        return Int(UInt16(bigEndian: resolved.sin_port))
    }
}

enum ProcessSupervisor {
    static func launch(
        plan: EngineLaunchPlan,
        spec: LaunchSpec,
        host: String,
        port: Int,
        modelId: String,
        profileId: String?,
        internalAPIKey: String?,
        logger: AppLogger
    ) throws -> ManagedEngine {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = plan.arguments
        process.environment = plan.environment
        if let workingDirectory = plan.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let instanceID = Identifiers.prefixed("inst")
        let metadata = [
            "instanceId": instanceID,
            "backendId": plan.backendId,
            "modelId": modelId
        ]
        attach(pipe: stdoutPipe, logger: logger, level: "info", category: "engine.stdout", metadata: metadata)
        attach(pipe: stderrPipe, logger: logger, level: "error", category: "engine.stderr", metadata: metadata)

        process.terminationHandler = { process in
            Task {
                await logger.log(level: "info", category: "engine.lifecycle", message: "Engine terminated.", metadata: metadata.merging([
                    "terminationStatus": "\(process.terminationStatus)"
                ], uniquingKeysWith: { _, new in new }))
            }
        }

        do {
            try process.run()
        } catch {
            throw APIErrorEnvelope(
                code: "ENGINE_LAUNCH_TIMEOUT",
                message: "Failed to launch backend executable \(plan.executablePath): \(error.localizedDescription)",
                details: metadata
            )
        }

        let instance = EngineInstanceRef(
            id: instanceID,
            backendId: plan.backendId,
            modelId: modelId,
            host: host,
            port: port,
            status: .launching,
            warnings: [],
            pid: Int(process.processIdentifier),
            launchedAt: Time.nowISO8601(),
            profileId: profileId,
            engineModelName: plan.engineModelName
        )
        return ManagedEngine(process: process, plan: plan, launchSpec: spec, internalAPIKey: internalAPIKey, instance: instance)
    }

    static func waitUntilReady(_ engine: ManagedEngine, timeoutSeconds: TimeInterval = 60) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if engine.isRunning == false {
                throw APIErrorEnvelope(
                    code: "ENGINE_CRASHED",
                    message: "Engine exited during startup.",
                    details: [
                        "instanceId": engine.instance.id,
                        "backendId": engine.instance.backendId,
                        "modelId": engine.instance.modelId
                    ]
                )
            }

            do {
                let (_, response) = try await EngineHTTPClient.request(
                    engine: engine,
                    path: engine.plan.readinessPath,
                    method: "GET",
                    body: nil
                )
                if 200 ..< 300 ~= response.statusCode {
                    engine.updateStatus(.ready)
                    return
                }
            } catch {
                // Retry until timeout.
            }

            try await Task.sleep(for: .milliseconds(400))
        }

        throw APIErrorEnvelope(
            code: "ENGINE_LAUNCH_TIMEOUT",
            message: "Engine failed readiness checks before timeout.",
            details: [
                "instanceId": engine.instance.id,
                "backendId": engine.instance.backendId,
                "modelId": engine.instance.modelId
            ]
        )
    }

    static func stop(_ engine: ManagedEngine) async {
        guard engine.isRunning else {
            engine.updateStatus(.stopped)
            return
        }

        engine.process.terminate()
        for _ in 0 ..< 20 where engine.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if engine.isRunning, let pid = engine.instance.pid {
            kill(pid_t(pid), SIGKILL)
        }
        engine.updateStatus(.stopped)
    }

    private static func attach(
        pipe: Pipe,
        logger: AppLogger,
        level: String,
        category: String,
        metadata: [String: String]
    ) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else {
                handle.readabilityHandler = nil
                return
            }

            let text = String(decoding: data, as: UTF8.self)
            let lines = text.split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { $0.isEmpty == false }
            guard lines.isEmpty == false else { return }

            Task {
                for line in lines {
                    await logger.log(level: level, category: category, message: line, metadata: metadata)
                }
            }
        }
    }
}

enum EngineHTTPClient {
    static func request(
        engine: ManagedEngine,
        path: String,
        method: String,
        body: Data?,
        additionalHeaders: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: engine.baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let internalAPIKey = engine.internalAPIKey, internalAPIKey.isEmpty == false {
            request.setValue("Bearer \(internalAPIKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIErrorEnvelope(code: "ENGINE_PROXY_FAILED", message: "Engine returned a non-HTTP response.")
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw envelope
            }
            let message = String(data: data, encoding: .utf8) ?? "Engine request failed."
            throw APIErrorEnvelope(
                code: "ENGINE_PROXY_FAILED",
                message: message,
                details: [
                    "instanceId": engine.instance.id,
                    "backendId": engine.instance.backendId,
                    "statusCode": "\(httpResponse.statusCode)",
                    "path": path
                ]
            )
        }
        return (data, httpResponse)
    }

    static func text(engine: ManagedEngine, path: String) async throws -> String {
        let (data, _) = try await request(engine: engine, path: path, method: "GET", body: nil)
        return String(decoding: data, as: UTF8.self)
    }
}
