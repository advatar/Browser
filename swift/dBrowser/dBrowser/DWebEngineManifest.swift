import Foundation

enum DWebEnginePlatform: String, Codable, Equatable, CaseIterable {
    case macOS = "macos"
    case iOS = "ios"

    nonisolated static var current: DWebEnginePlatform {
        #if os(macOS)
        return .macOS
        #else
        return .iOS
        #endif
    }
}

enum DWebEngineRuntimeKind: String, Codable, Equatable, CaseIterable {
    case inProcessSwift = "in-process-swift"
    case managedHelper = "managed-helper"
    case configuredRemote = "configured-remote"
    case platformLimited = "platform-limited"
}

enum DWebEngineReadiness: String, Codable, Equatable, CaseIterable {
    case appManaged = "app-managed"
    case builtInGateway = "built-in-gateway"
    case requiresConfiguredBackend = "requires-configured-backend"
    case requiresCredential = "requires-credential"
    case unsupportedOnPlatform = "unsupported-on-platform"
}

enum DWebEngineRequirementKind: String, Codable, Equatable, CaseIterable {
    case credential
    case funding
    case permission
    case backend
    case platform
    case contentPolicy = "content-policy"
}

struct DWebEngineRequirement: Codable, Equatable, Identifiable {
    var id: String { "\(kind.rawValue):\(name)" }

    var kind: DWebEngineRequirementKind
    var name: String
    var reason: String

    nonisolated init(kind: DWebEngineRequirementKind, name: String, reason: String) {
        self.kind = kind
        self.name = name
        self.reason = reason
    }
}

struct DWebEnginePlatformSupport: Codable, Equatable {
    var runtimeKind: DWebEngineRuntimeKind
    var readiness: DWebEngineReadiness
    var adapterEnabled: Bool
    var launchPolicy: String
    var artifacts: [String]
    var status: String

    nonisolated init(
        runtimeKind: DWebEngineRuntimeKind,
        readiness: DWebEngineReadiness,
        adapterEnabled: Bool,
        launchPolicy: String,
        artifacts: [String],
        status: String
    ) {
        self.runtimeKind = runtimeKind
        self.readiness = readiness
        self.adapterEnabled = adapterEnabled
        self.launchPolicy = launchPolicy
        self.artifacts = artifacts
        self.status = status
    }
}

struct DWebEngineDescriptor: Codable, Equatable, Identifiable {
    var id: String { networkID }

    var networkID: String
    var title: String
    var handlerID: String
    var routePath: String
    var port: Int
    var schemes: [String]
    var trackingIssue: Int
    var protocolIssue: Int?
    var upstream: String
    var license: String
    var macOS: DWebEnginePlatformSupport
    var iOS: DWebEnginePlatformSupport
    var requirements: [DWebEngineRequirement]

    nonisolated init(
        networkID: String,
        title: String,
        handlerID: String,
        routePath: String,
        port: Int,
        schemes: [String],
        trackingIssue: Int,
        protocolIssue: Int?,
        upstream: String,
        license: String,
        macOS: DWebEnginePlatformSupport,
        iOS: DWebEnginePlatformSupport,
        requirements: [DWebEngineRequirement]
    ) {
        self.networkID = networkID
        self.title = title
        self.handlerID = handlerID
        self.routePath = routePath
        self.port = port
        self.schemes = schemes
        self.trackingIssue = trackingIssue
        self.protocolIssue = protocolIssue
        self.upstream = upstream
        self.license = license
        self.macOS = macOS
        self.iOS = iOS
        self.requirements = requirements
    }

    nonisolated func support(on platform: DWebEnginePlatform = .current) -> DWebEnginePlatformSupport {
        platform == .macOS ? macOS : iOS
    }

    nonisolated var credentialRequirements: [DWebEngineRequirement] {
        requirements.filter { $0.kind == .credential || $0.kind == .funding }
    }
}

struct DWebEngineManifest: Codable, Equatable {
    var version: String
    var engines: [DWebEngineDescriptor]

    nonisolated init(version: String, engines: [DWebEngineDescriptor]) {
        self.version = version
        self.engines = engines
    }

    nonisolated var networkIDs: Set<String> {
        Set(engines.map(\.networkID))
    }

    nonisolated func engine(for networkID: String) -> DWebEngineDescriptor? {
        engines.first { $0.networkID == networkID }
    }

    nonisolated func validationErrors(adapterConfiguration: DecentralizedStorageNativeAdapterConfiguration = .localDefaults) -> [String] {
        var errors: [String] = []
        let duplicateIDs = Dictionary(grouping: engines, by: \.networkID)
            .filter { $0.value.count > 1 }
            .keys
        for duplicateID in duplicateIDs.sorted() {
            errors.append("Duplicate engine descriptor for \(duplicateID).")
        }

        for engine in engines {
            guard let endpoint = adapterConfiguration.endpoint(for: engine.networkID) else {
                errors.append("Missing native adapter endpoint for \(engine.networkID).")
                continue
            }
            if endpoint.routePath != engine.routePath {
                errors.append("\(engine.networkID) route mismatch: \(endpoint.routePath) != \(engine.routePath).")
            }
            if endpoint.baseURL.port != engine.port {
                errors.append("\(engine.networkID) port mismatch: \(endpoint.baseURL.port?.description ?? "nil") != \(engine.port).")
            }
            if engine.schemes.isEmpty {
                errors.append("\(engine.networkID) has no schemes.")
            }
            if engine.macOS.adapterEnabled && engine.macOS.artifacts.isEmpty {
                errors.append("\(engine.networkID) macOS helper has no declared artifact.")
            }
            if engine.macOS.adapterEnabled && engine.macOS.launchPolicy.isEmpty {
                errors.append("\(engine.networkID) macOS helper has no launch policy.")
            }
        }
        return errors
    }

    nonisolated static let current = DWebEngineManifest(
        version: "dweb-engine-manifest-v1",
        engines: [
            helper(
                networkID: "filecoin",
                title: "Filecoin",
                handlerID: "filecoin.piece-car",
                routePath: "/dweb/filecoin/native",
                port: 4881,
                schemes: ["filecoin", "piececid", "fil"],
                protocolIssue: 119,
                upstream: "Lassie-compatible Filecoin retrieval bridge plus CAR/CID verifier",
                license: "Apache-2.0 or upstream-compatible",
                iOSStatus: "Public IPFS-compatible CIDs use the built-in gateway bridge; Filecoin piece/deal retrieval requires a configured resolver endpoint on iOS.",
                requirements: []
            ),
            helper(
                networkID: "walrus",
                title: "Walrus",
                handlerID: "walrus.blob",
                routePath: "/dweb/walrus/native",
                port: 4882,
                schemes: ["walrus"],
                protocolIssue: 120,
                upstream: "Walrus HTTP aggregator, Sites, and quilt-aware adapter",
                license: "Apache-2.0 or upstream-compatible",
                iOSRuntime: .inProcessSwift,
                iOSReadiness: .builtInGateway,
                iOSStatus: "Single blob reads use the bundled Swift HTTP aggregator path; path-bearing Sites and quilt locators use the configured resolver contract.",
                requirements: [
                    DWebEngineRequirement(kind: .funding, name: "Walrus write payment", reason: "Publishing and writes need user-approved wallet funds; public reads do not.")
                ]
            ),
            helper(
                networkID: "iroh",
                title: "Iroh blobs",
                handlerID: "iroh.blake3-blob",
                routePath: "/dweb/iroh/native",
                port: 4883,
                schemes: ["iroh", "iroh-blob"],
                protocolIssue: 121,
                upstream: "Rust iroh-blobs helper or UniFFI library",
                license: "Apache-2.0 or MIT",
                iOSStatus: "Requires an embedded Rust library or configured Iroh resolver endpoint on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .permission, name: "peer networking", reason: "Iroh tickets can require peer dialing, relay use, and local blob-store persistence.")
                ]
            ),
            helper(
                networkID: "hypercore",
                title: "Hypercore / Hyperdrive",
                handlerID: "hypercore.feed",
                routePath: "/dweb/hypercore/native",
                port: 4884,
                schemes: ["hyper", "hypercore", "hyperdrive", "pear", "dat"],
                protocolIssue: 122,
                upstream: "Node/Pear Hypercore helper with app-private storage",
                license: "MIT-compatible",
                iOSStatus: "Requires a configured resolver endpoint on iOS because the daemon-oriented Node/Pear stack is not shipped as executable code there.",
                requirements: [
                    DWebEngineRequirement(kind: .credential, name: "feed write key", reason: "Private or writable feeds need user-held keys that the app cannot bundle.")
                ]
            ),
            helper(
                networkID: "sia",
                title: "Sia",
                handlerID: "sia.renterd-object",
                routePath: "/dweb/sia/native",
                port: 4885,
                schemes: ["sia"],
                protocolIssue: 123,
                upstream: "renterd helper with Swift adapter bridge",
                license: "MIT-compatible",
                iOSStatus: "Requires a configured renterd endpoint on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .credential, name: "renterd auth", reason: "Sia object reads need a renterd password, token, or auth header."),
                    DWebEngineRequirement(kind: .funding, name: "Siacoin funding", reason: "Storage contracts and paid retrieval need user-controlled funds.")
                ]
            ),
            helper(
                networkID: "storj",
                title: "Storj",
                handlerID: "storj.uplink-object",
                routePath: "/dweb/storj/native",
                port: 4886,
                schemes: ["storj"],
                protocolIssue: 124,
                upstream: "libuplink or linksharing bridge",
                license: "AGPL-3.0 or commercial-compatible, depending on selected upstream artifact",
                iOSStatus: "Requires libuplink as a signed framework or a configured linksharing endpoint on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .credential, name: "access grant", reason: "Storj buckets are scoped by access grants and passphrases.")
                ]
            ),
            helper(
                networkID: "tahoe-lafs",
                title: "Tahoe-LAFS",
                handlerID: "tahoe.capability",
                routePath: "/dweb/tahoe-lafs/native",
                port: 4887,
                schemes: ["tahoe", "lafs"],
                protocolIssue: 125,
                upstream: "Tahoe-LAFS WebAPI helper",
                license: "GPL-2.0-or-later",
                iOSStatus: "Requires a configured Tahoe gateway on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .credential, name: "Tahoe capability", reason: "Read and write caps are least-authority secrets and stay outside prompts and logs."),
                    DWebEngineRequirement(kind: .backend, name: "grid introducer", reason: "A Tahoe grid configuration selects the storage grid boundary.")
                ]
            ),
            helper(
                networkID: "autonomi",
                title: "Autonomi",
                handlerID: "autonomi.address",
                routePath: "/dweb/autonomi/native",
                port: 4888,
                schemes: ["autonomi", "safe"],
                protocolIssue: 126,
                upstream: "Rust Autonomi client helper or UniFFI library",
                license: "GPL-3.0 or upstream-compatible",
                iOSStatus: "Requires an embedded Rust library or configured Autonomi resolver endpoint on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .credential, name: "Autonomi keys", reason: "Private data maps and chunks require user-held keys."),
                    DWebEngineRequirement(kind: .funding, name: "network payment", reason: "Writes and paid operations need user-approved funds.")
                ]
            ),
            helper(
                networkID: "bittorrent",
                title: "BitTorrent / WebTorrent",
                handlerID: "bittorrent.infohash",
                routePath: "/dweb/bittorrent/native",
                port: 4889,
                schemes: ["magnet", "bittorrent", "webtorrent"],
                protocolIssue: 127,
                upstream: "libtorrent helper plus WebTorrent bridge when WebRTC mode is selected",
                license: "BSD-3-Clause and MIT-compatible",
                iOSStatus: "HTTP web seeds are loadable in-process; tracker, DHT, or WebRTC peer retrieval requires a signed library or configured resolver endpoint on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .contentPolicy, name: "user consent", reason: "Torrent retrieval can contact untrusted peers and must remain user-approved.")
                ]
            ),
            helper(
                networkID: "ceramic",
                title: "Ceramic",
                handlerID: "ceramic.stream",
                routePath: "/dweb/ceramic/native",
                port: 4890,
                schemes: ["ceramic", "ceramic-stream"],
                protocolIssue: 128,
                upstream: "ceramic-one helper with Swift HTTP client",
                license: "Apache-2.0",
                iOSStatus: "Requires a configured Ceramic node on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .credential, name: "DID key", reason: "Stream writes need a controller DID key and explicit write authorization.")
                ]
            ),
            helper(
                networkID: "orbitdb",
                title: "OrbitDB",
                handlerID: "orbitdb.address",
                routePath: "/dweb/orbitdb/native",
                port: 4891,
                schemes: ["orbitdb"],
                protocolIssue: 129,
                upstream: "OrbitDB/IPFS JavaScript helper",
                license: "MIT-compatible",
                iOSStatus: "Requires a configured OrbitDB/IPFS resolver endpoint on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .credential, name: "database identity", reason: "Private or writable databases need user-held identity keys.")
                ]
            ),
            helper(
                networkID: "radicle",
                title: "Radicle",
                handlerID: "radicle.repository",
                routePath: "/dweb/radicle/native",
                port: 4892,
                schemes: ["rad", "radicle"],
                protocolIssue: 130,
                upstream: "radicle-node and radicle-httpd helper",
                license: "GPL-3.0",
                iOSStatus: "Requires a configured Radicle seed or signed Rust library on iOS.",
                requirements: [
                    DWebEngineRequirement(kind: .credential, name: "node identity", reason: "Seeding and writes need a user-owned Radicle identity.")
                ]
            )
        ]
    )

    nonisolated private static func helper(
        networkID: String,
        title: String,
        handlerID: String,
        routePath: String,
        port: Int,
        schemes: [String],
        protocolIssue: Int,
        upstream: String,
        license: String,
        iOSRuntime: DWebEngineRuntimeKind = .configuredRemote,
        iOSReadiness: DWebEngineReadiness = .requiresConfiguredBackend,
        iOSStatus: String,
        requirements: [DWebEngineRequirement]
    ) -> DWebEngineDescriptor {
        DWebEngineDescriptor(
            networkID: networkID,
            title: title,
            handlerID: handlerID,
            routePath: routePath,
            port: port,
            schemes: schemes,
            trackingIssue: 133,
            protocolIssue: protocolIssue,
            upstream: upstream,
            license: license,
            macOS: DWebEnginePlatformSupport(
                runtimeKind: .managedHelper,
                readiness: .appManaged,
                adapterEnabled: true,
                launchPolicy: "The signed dweb-storage-adapters helper is started by the app, binds 127.0.0.1:\(port), and proxies only this protocol route.",
                artifacts: [
                    "Contents/Library/DWebEngines/bin/dweb-storage-adapters",
                    "Contents/Resources/DWebEngines/manifest.json"
                ],
                status: "\(title) uses the app-managed macOS storage-adapters helper; users do not install protocol daemons."
            ),
            iOS: DWebEnginePlatformSupport(
                runtimeKind: iOSRuntime,
                readiness: iOSReadiness,
                adapterEnabled: false,
                launchPolicy: "No downloaded executable code is used on iOS; only signed in-app code or configured endpoints are allowed.",
                artifacts: iOSRuntime == .inProcessSwift ? ["Swift HTTP resolver"] : [],
                status: iOSStatus
            ),
            requirements: requirements
        )
    }
}

struct DWebEngineReadinessReport: Equatable, Identifiable {
    var id: String { descriptor.networkID }

    var descriptor: DWebEngineDescriptor
    var platform: DWebEnginePlatform
    var support: DWebEnginePlatformSupport
    var endpoint: DecentralizedStorageNativeAdapterEndpoint?

    nonisolated var isRoutableThroughLocalAdapter: Bool {
        support.adapterEnabled && endpoint != nil
    }

    nonisolated var summary: String {
        if isRoutableThroughLocalAdapter {
            return "\(descriptor.title): \(support.status) Route \(descriptor.routePath) on 127.0.0.1:\(descriptor.port)."
        }
        return "\(descriptor.title): \(support.status)"
    }
}

struct DWebEngineManager: Equatable {
    var manifest: DWebEngineManifest
    var adapterDefaults: DecentralizedStorageNativeAdapterConfiguration
    var platform: DWebEnginePlatform

    nonisolated init(
        manifest: DWebEngineManifest = .current,
        adapterDefaults: DecentralizedStorageNativeAdapterConfiguration = .localDefaults,
        platform: DWebEnginePlatform = .current
    ) {
        self.manifest = manifest
        self.adapterDefaults = adapterDefaults
        self.platform = platform
    }

    nonisolated static let production = DWebEngineManager()

    nonisolated var adapterConfiguration: DecentralizedStorageNativeAdapterConfiguration {
        var endpoints: [String: DecentralizedStorageNativeAdapterEndpoint] = [:]
        for engine in manifest.engines {
            let support = engine.support(on: platform)
            guard support.adapterEnabled,
                  let endpoint = adapterDefaults.endpoint(for: engine.networkID) else {
                continue
            }
            endpoints[engine.networkID] = endpoint
        }
        return DecentralizedStorageNativeAdapterConfiguration(endpoints: endpoints)
    }

    nonisolated func report(for networkID: String) -> DWebEngineReadinessReport? {
        guard let descriptor = manifest.engine(for: networkID) else {
            return nil
        }
        return DWebEngineReadinessReport(
            descriptor: descriptor,
            platform: platform,
            support: descriptor.support(on: platform),
            endpoint: adapterConfiguration.endpoint(for: networkID)
        )
    }

    nonisolated var reports: [DWebEngineReadinessReport] {
        manifest.engines.compactMap { report(for: $0.networkID) }
    }
}
