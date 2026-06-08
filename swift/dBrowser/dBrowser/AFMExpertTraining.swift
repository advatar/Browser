import Foundation

enum AFMExpertTrainingPrivacyMode: String, Codable, Equatable, CaseIterable {
    case localOnly
    case redactedA2A
    case publishable

    var title: String {
        switch self {
        case .localOnly: "Local only"
        case .redactedA2A: "Redacted A2A"
        case .publishable: "Publishable"
        }
    }
}

enum AFMExpertTrainingMethod: String, Codable, Equatable, CaseIterable {
    case profileAdapter
    case loraAdapter
    case fullFineTune

    var title: String {
        switch self {
        case .profileAdapter: "Profile adapter"
        case .loraAdapter: "LoRA adapter"
        case .fullFineTune: "Full fine-tune"
        }
    }
}

enum AFMExpertTrainingStatus: String, Codable, Equatable {
    case datasetPrepared
    case readyForLocalUse
    case publishBlocked
    case publishReady

    var title: String {
        switch self {
        case .datasetPrepared: "Dataset prepared"
        case .readyForLocalUse: "Ready for local use"
        case .publishBlocked: "Publish blocked"
        case .publishReady: "Publish ready"
        }
    }
}

enum AFMExpertPublishReadiness: String, Codable, Equatable {
    case localOnly
    case needsEvaluation
    case needsAttestation
    case readyForAFMarket

    var title: String {
        switch self {
        case .localOnly: "Local only"
        case .needsEvaluation: "Needs evaluation"
        case .needsAttestation: "Needs attestation"
        case .readyForAFMarket: "Ready for AFMarket"
        }
    }
}

struct AFMExpertTrainingPolicy: Codable, Equatable {
    var baseModelID: String
    var method: AFMExpertTrainingMethod
    var privacyMode: AFMExpertTrainingPrivacyMode
    var allowA2A: Bool
    var publishToAFMarket: Bool
    var maxTrainingExamples: Int
    var domainTags: [String]

    init(
        baseModelID: String = "apple.foundation-model.local",
        method: AFMExpertTrainingMethod = .profileAdapter,
        privacyMode: AFMExpertTrainingPrivacyMode = .localOnly,
        allowA2A: Bool = false,
        publishToAFMarket: Bool = false,
        maxTrainingExamples: Int = 500,
        domainTags: [String] = []
    ) {
        self.baseModelID = baseModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "apple.foundation-model.local"
            : baseModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.method = method
        self.privacyMode = privacyMode
        self.allowA2A = allowA2A
        self.publishToAFMarket = publishToAFMarket
        self.maxTrainingExamples = max(1, maxTrainingExamples)
        self.domainTags = Self.normalizedTags(domainTags)
    }

    var safetySummary: String {
        let publishSummary = publishToAFMarket ? "publish requested" : "local draft"
        let a2aSummary = allowA2A ? "A2A callable" : "A2A disabled"
        return "\(privacyMode.title), \(method.title), \(a2aSummary), \(publishSummary)."
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}

struct AFMExpertTrainingRequest: Codable, Equatable {
    var displayName: String
    var objective: String
    var datasetSummary: String
    var sampleCount: Int
    var policy: AFMExpertTrainingPolicy

    init(
        displayName: String,
        objective: String,
        datasetSummary: String,
        sampleCount: Int,
        policy: AFMExpertTrainingPolicy = AFMExpertTrainingPolicy()
    ) {
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled AFM Expert"
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.objective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        self.datasetSummary = datasetSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sampleCount = max(0, sampleCount)
        self.policy = policy
    }

    static let demo = AFMExpertTrainingRequest(
        displayName: "Local Travel Policy Expert",
        objective: "Answer travel-policy questions from local examples and browser-approved context.",
        datasetSummary: "Redacted examples from travel policy pages, booking rules, and user-approved notes.",
        sampleCount: 42,
        policy: AFMExpertTrainingPolicy(
            baseModelID: "apple.foundation-model.local",
            method: .profileAdapter,
            privacyMode: .redactedA2A,
            allowA2A: true,
            publishToAFMarket: true,
            maxTrainingExamples: 500,
            domainTags: ["travel", "policy", "support"]
        )
    )
}

struct AFMExpertTrainingJob: Codable, Equatable, Identifiable {
    var id: UUID
    var request: AFMExpertTrainingRequest
    var status: AFMExpertTrainingStatus
    var publishReadiness: AFMExpertPublishReadiness
    var progress: Double
    var localAdapterID: String
    var outputRunnerID: String
    var marketplaceJobID: String?
    var marketplacePublishStatus: String
    var artifactBundleURLString: String?
    var manifestHash: String?
    var createdAt: Date
    var updatedAt: Date
    var trainingSummary: String
    var adapterStatus: String

    init(
        id: UUID = UUID(),
        request: AFMExpertTrainingRequest,
        createdAt: Date = Date()
    ) {
        let stable = Self.stableID(for: request)
        let publishReadiness: AFMExpertPublishReadiness = {
            guard request.policy.publishToAFMarket else { return .localOnly }
            guard request.policy.allowA2A, request.policy.privacyMode != .localOnly else { return .needsEvaluation }
            return .needsAttestation
        }()
        self.id = id
        self.request = request
        self.status = request.policy.publishToAFMarket && publishReadiness == .localOnly ? .publishBlocked : .readyForLocalUse
        self.publishReadiness = publishReadiness
        self.progress = 1.0
        self.localAdapterID = "afm-local-\(stable)"
        self.outputRunnerID = "afm-local-\(stable)@draft"
        self.marketplaceJobID = nil
        self.marketplacePublishStatus = request.policy.publishToAFMarket ? "local-draft" : "local-only"
        self.artifactBundleURLString = nil
        self.manifestHash = nil
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.trainingSummary = "Prepared \(request.policy.method.title.lowercased()) from \(request.sampleCount) approved example\(request.sampleCount == 1 ? "" : "s") for \(request.policy.baseModelID)."
        self.adapterStatus = "Local profile adapter is ready. Production Apple Foundation Model fine-tune and weight-export adapters are not configured."
    }

    var displaySummary: String {
        "\(request.displayName): \(status.title), \(publishReadiness.title), \(marketplacePublishStatus). \(adapterStatus)"
    }

    var peerExpert: AFMA2APeerExpert {
        AFMA2APeerExpert(trainingJob: self)
    }

    var isPublishedToMarketplace: Bool {
        marketplacePublishStatus == "published"
    }

    func applyingMarketplaceJob(_ marketplaceJob: AFMMarketplaceTrainingJob, updatedAt: Date = Date()) -> AFMExpertTrainingJob {
        var job = self
        job.marketplaceJobID = marketplaceJob.id
        job.marketplacePublishStatus = marketplaceJob.publishStatus
        job.status = marketplaceJob.status ?? status
        job.publishReadiness = marketplaceJob.publishReadiness ?? publishReadiness
        job.progress = marketplaceJob.progress
        job.localAdapterID = marketplaceJob.localAdapterID
        job.outputRunnerID = marketplaceJob.outputRunnerID
        job.artifactBundleURLString = marketplaceJob.artifactBundleURL
        job.manifestHash = marketplaceJob.manifestHash
        job.trainingSummary = marketplaceJob.trainingSummary ?? trainingSummary
        job.adapterStatus = marketplaceJob.adapterStatus ?? adapterStatus
        job.updatedAt = updatedAt
        return job
    }

    private static func stableID(for request: AFMExpertTrainingRequest) -> String {
        let input = [
            request.displayName,
            request.objective,
            request.datasetSummary,
            request.policy.baseModelID,
            request.policy.domainTags.joined(separator: ",")
        ].joined(separator: "|")
        return fnv1a64Hex(input)
    }

    private static func fnv1a64Hex(_ input: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

enum AFMA2APeerTransport: String, Codable, Equatable {
    case registryIngest
    case localEmbedded
    case unavailable

    var title: String {
        switch self {
        case .registryIngest: "Registry A2A ingest"
        case .localEmbedded: "Local embedded"
        case .unavailable: "Unavailable"
        }
    }
}

struct AFMA2APeerExpert: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var baseModelID: String?
    var tags: [String]
    var transport: AFMA2APeerTransport
    var endpointURLString: String?
    var pricePer1K: Double?
    var reputation: Double?
    var attestationSummary: String
    var publishReadiness: AFMExpertPublishReadiness?

    nonisolated init(record: AFMExpertRecord) {
        self.id = record.id
        self.displayName = record.name
        self.baseModelID = record.baseModel
        self.tags = record.tags
        self.transport = record.ingestURLString == nil ? .unavailable : .registryIngest
        self.endpointURLString = record.ingestURLString
        self.pricePer1K = record.pricePer1K
        self.reputation = record.reputation
        self.attestationSummary = record.attestation == nil
            ? "No peer attestation metadata reported."
            : "Peer reports attestation metadata for A2A calls."
        self.publishReadiness = nil
    }

    init(trainingJob: AFMExpertTrainingJob) {
        self.id = trainingJob.outputRunnerID
        self.displayName = trainingJob.request.displayName
        self.baseModelID = trainingJob.request.policy.baseModelID
        self.tags = trainingJob.request.policy.domainTags
        self.transport = .localEmbedded
        self.endpointURLString = nil
        self.pricePer1K = nil
        self.reputation = nil
        self.attestationSummary = trainingJob.adapterStatus
        self.publishReadiness = trainingJob.publishReadiness
    }

    var availabilitySummary: String {
        let tagsSummary = tags.isEmpty ? "no tags" : tags.joined(separator: ", ")
        return "\(transport.title); \(baseModelID ?? "unknown model"); \(tagsSummary). \(attestationSummary)"
    }
}

struct AFMA2ACallRequest: Codable, Equatable {
    var expertID: String
    var prompt: String
    var contextCommitment: String?
    var maxTokens: Int
    var userApproved: Bool

    init(
        expertID: String,
        prompt: String,
        contextCommitment: String? = nil,
        maxTokens: Int = 700,
        userApproved: Bool = false
    ) {
        self.expertID = expertID
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.contextCommitment = contextCommitment?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maxTokens = max(1, maxTokens)
        self.userApproved = userApproved
    }
}

struct AFMA2ACallResult: Codable, Equatable, Identifiable {
    enum Status: String, Codable, Equatable {
        case requiresApproval
        case prepared
        case localPreview
        case unavailable
    }

    var id: UUID
    var request: AFMA2ACallRequest
    var expert: AFMA2APeerExpert?
    var status: Status
    var summary: String
    var transportSummary: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        request: AFMA2ACallRequest,
        expert: AFMA2APeerExpert?,
        status: Status,
        summary: String,
        transportSummary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.expert = expert
        self.status = status
        self.summary = summary
        self.transportSummary = transportSummary
        self.createdAt = createdAt
    }
}

extension AFMServiceSnapshot {
    var peerExperts: [AFMA2APeerExpert] {
        (registryExperts + marketplaceExperts)
            .map(AFMA2APeerExpert.init(record:))
            .sorted { $0.displayName < $1.displayName }
    }
}
