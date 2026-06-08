import Foundation

enum LocalCapabilityPrincipalKind: String, Codable, Equatable {
    case a2uiApp
    case mcpServer

    var title: String {
        switch self {
        case .a2uiApp: "A2UI app"
        case .mcpServer: "MCP server"
        }
    }
}

struct LocalCapabilityPrincipal: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kind: LocalCapabilityPrincipalKind

    init(id: String, name: String, kind: LocalCapabilityPrincipalKind) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
    }
}

enum WalletAccountScope: String, Codable, Equatable, Hashable, CaseIterable {
    case selectedAccount
    case allAccounts

    var title: String {
        switch self {
        case .selectedAccount: "Selected account"
        case .allAccounts: "All accounts"
        }
    }
}

enum BlockchainCapabilityOperation: String, Codable, Equatable, CaseIterable {
    case readChainData
    case readWalletState
    case prepareTransactions
    case simulateTransactions
    case requestSigning
    case requestBroadcast

    var hostToolName: String {
        switch self {
        case .readChainData: "dbrowser.chain.get_status"
        case .readWalletState: "dbrowser.wallet.get_portfolio"
        case .prepareTransactions: "dbrowser.tx.prepare"
        case .simulateTransactions: "dbrowser.tx.simulate"
        case .requestSigning: "dbrowser.tx.request_signature"
        case .requestBroadcast: "dbrowser.tx.request_broadcast"
        }
    }

    var title: String {
        switch self {
        case .readChainData: "Read chain data"
        case .readWalletState: "Read wallet state"
        case .prepareTransactions: "Prepare transactions"
        case .simulateTransactions: "Simulate transactions"
        case .requestSigning: "Request signing"
        case .requestBroadcast: "Request broadcast"
        }
    }
}

struct BlockchainCapabilityGrant: Codable, Equatable {
    var readChainData: Bool
    var readWalletState: Bool
    var prepareTransactions: Bool
    var simulateTransactions: Bool
    var requestSigning: Bool
    var requestBroadcast: Bool
    var accountScope: WalletAccountScope
    var allowedChainRefs: [String]
    var spendLimit: Decimal?
    var expiresAt: Date?
    var approvalGates: [String]

    init(
        readChainData: Bool = true,
        readWalletState: Bool = true,
        prepareTransactions: Bool = true,
        simulateTransactions: Bool = true,
        requestSigning: Bool = false,
        requestBroadcast: Bool = false,
        accountScope: WalletAccountScope = .selectedAccount,
        allowedChainRefs: [String] = Self.defaultChainRefs,
        spendLimit: Decimal? = Decimal(25),
        expiresAt: Date? = nil,
        approvalGates: [String] = Self.defaultApprovalGates
    ) {
        self.readChainData = readChainData
        self.readWalletState = readWalletState
        self.prepareTransactions = prepareTransactions
        self.simulateTransactions = simulateTransactions
        self.requestSigning = requestSigning
        self.requestBroadcast = requestBroadcast
        self.accountScope = accountScope
        self.allowedChainRefs = Self.normalizedChainRefs(allowedChainRefs)
        self.spendLimit = spendLimit
        self.expiresAt = expiresAt
        self.approvalGates = approvalGates
    }

    static func defaultForA2UIApp() -> BlockchainCapabilityGrant {
        BlockchainCapabilityGrant(
            requestSigning: true,
            requestBroadcast: true,
            approvalGates: [
                "wallet account read",
                "transaction signing request",
                "transaction broadcast request",
                "payment or wallet spend"
            ]
        )
    }

    static func defaultForMCPServer() -> BlockchainCapabilityGrant {
        BlockchainCapabilityGrant(
            requestSigning: false,
            requestBroadcast: false,
            approvalGates: [
                "wallet account read",
                "transaction signing request",
                "transaction broadcast request"
            ]
        )
    }

    static let none = BlockchainCapabilityGrant(
        readChainData: false,
        readWalletState: false,
        prepareTransactions: false,
        simulateTransactions: false,
        requestSigning: false,
        requestBroadcast: false,
        allowedChainRefs: [],
        spendLimit: nil,
        approvalGates: []
    )

    var enabledOperations: [BlockchainCapabilityOperation] {
        BlockchainCapabilityOperation.allCases.filter { allowsOperationFlag($0) }
    }

    var hostTools: [String] {
        var tools = enabledOperations.map(\.hostToolName)
        if readWalletState {
            tools.append("dbrowser.wallet.list_accounts")
        }
        if prepareTransactions {
            tools.append("dbrowser.chain.get_balance")
        }
        return Array(Set(tools)).sorted()
    }

    var installSummary: String {
        let operationSummary = enabledOperations.map(\.title).joined(separator: ", ")
        let chainSummary = allowedChainRefs.isEmpty ? "no chains" : "\(allowedChainRefs.count) chain\(allowedChainRefs.count == 1 ? "" : "s")"
        let limitSummary = spendLimit.map { "spend limit \(NSDecimalNumber(decimal: $0).stringValue)" } ?? "no spend limit"
        return "\(operationSummary.isEmpty ? "No blockchain access" : operationSummary); \(accountScope.title); \(chainSummary); \(limitSummary)."
    }

    func sanitized() -> BlockchainCapabilityGrant {
        var copy = self
        copy.allowedChainRefs = Self.normalizedChainRefs(allowedChainRefs)
        copy.approvalGates = approvalGates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return copy
    }

    func allows(
        _ operation: BlockchainCapabilityOperation,
        chainRef: String,
        amount: Decimal? = nil,
        now: Date = Date()
    ) -> Bool {
        guard allowsOperationFlag(operation) else { return false }
        if let expiresAt, expiresAt <= now { return false }

        let normalized = ChainTrustStatus.normalized(chainRef)
        guard allowedChainRefs.isEmpty || allowedChainRefs.contains(normalized) else { return false }

        if let amount, let spendLimit, amount > spendLimit {
            return false
        }

        return true
    }

    func denialReason(
        for operation: BlockchainCapabilityOperation,
        chainRef: String,
        amount: Decimal? = nil,
        now: Date = Date()
    ) -> String? {
        if !allowsOperationFlag(operation) {
            return "\(operation.title) is not granted."
        }
        if let expiresAt, expiresAt <= now {
            return "Blockchain grant expired."
        }
        let normalized = ChainTrustStatus.normalized(chainRef)
        if !allowedChainRefs.isEmpty, !allowedChainRefs.contains(normalized) {
            return "\(normalized) is outside the allowed chain set."
        }
        if let amount, let spendLimit, amount > spendLimit {
            return "Amount exceeds the grant spend limit."
        }
        return nil
    }

    private func allowsOperationFlag(_ operation: BlockchainCapabilityOperation) -> Bool {
        switch operation {
        case .readChainData: readChainData
        case .readWalletState: readWalletState
        case .prepareTransactions: prepareTransactions
        case .simulateTransactions: simulateTransactions
        case .requestSigning: requestSigning
        case .requestBroadcast: requestBroadcast
        }
    }

    static let defaultChainRefs: [String] = [
        "bitcoin-mainnet",
        "ethereum-mainnet",
        "base-mainnet",
        "base-sepolia",
        "arbitrum-one",
        "optimism-mainnet",
        "polygon-mainnet",
        "bnb-smart-chain",
        "avalanche-c",
        "solana-mainnet",
        "cosmos-hub",
        "polkadot",
        "tron-mainnet",
        "xrp-ledger",
        "sui-mainnet",
        "aptos-mainnet"
    ]

    static let defaultApprovalGates: [String] = [
        "wallet account read",
        "transaction signing request",
        "transaction broadcast request"
    ]

    private static func normalizedChainRefs(_ chainRefs: [String]) -> [String] {
        var seen = Set<String>()
        return chainRefs.compactMap { chainRef in
            let normalized = ChainTrustStatus.normalized(chainRef)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}

struct BlockchainChainAccessDescriptor: Codable, Equatable, Identifiable {
    var id: String { chainRef }

    var chainRef: String
    var displayName: String
    var family: ChainTrustFamily
    var state: ChainTrustState
    var trustSource: ChainTrustSource
    var supportedProofTypes: [String]
    var summary: String

    nonisolated init(status: ChainTrustStatus) {
        self.chainRef = status.chainRef
        self.displayName = status.displayName
        self.family = status.family
        self.state = status.state
        self.trustSource = status.trustSource
        self.supportedProofTypes = status.supportedProofTypes
        self.summary = status.displaySummary
    }
}

struct BlockchainHostContract: Codable, Equatable {
    var principal: LocalCapabilityPrincipal
    var grant: BlockchainCapabilityGrant
    var hostTools: [String]
    var chains: [BlockchainChainAccessDescriptor]
    var walletPolicySummary: String
    var productionSigningStatus: String

    init(
        principal: LocalCapabilityPrincipal,
        grant: BlockchainCapabilityGrant,
        chainTrust: ChainTrustRegistry,
        walletPortfolio: WalletPortfolioSnapshot
    ) {
        let sanitizedGrant = grant.sanitized()
        self.principal = principal
        self.grant = sanitizedGrant
        self.hostTools = sanitizedGrant.hostTools
        self.chains = chainTrust.statuses
            .filter { sanitizedGrant.allowedChainRefs.isEmpty || sanitizedGrant.allowedChainRefs.contains($0.chainRef) }
            .map(BlockchainChainAccessDescriptor.init(status:))
        self.walletPolicySummary = walletPortfolio.policySummary
        self.productionSigningStatus = walletPortfolio.productionSigningStatus
    }
}

struct WalletPreparedTransaction: Codable, Equatable, Identifiable {
    enum Status: String, Codable, Equatable {
        case ready
        case needsApproval
        case rejected
    }

    var id: UUID
    var principal: LocalCapabilityPrincipal
    var request: WalletTransferRequest
    var preview: WalletTransferPreview
    var status: Status
    var message: String

    init(
        id: UUID = UUID(),
        principal: LocalCapabilityPrincipal,
        request: WalletTransferRequest,
        preview: WalletTransferPreview,
        status: Status,
        message: String
    ) {
        self.id = id
        self.principal = principal
        self.request = request
        self.preview = preview
        self.status = status
        self.message = message
    }
}

struct WalletTransactionSimulation: Codable, Equatable, Identifiable {
    enum Status: String, Codable, Equatable {
        case success
        case needsApproval
        case rejected
    }

    var id: UUID
    var preparedTransactionID: UUID
    var status: Status
    var message: String
    var feeEstimate: String?
    var chainTrustSummary: String
}

struct WalletBroadcastResult: Codable, Equatable, Identifiable {
    enum Status: String, Codable, Equatable {
        case unavailable
        case denied
        case needsApproval
        case broadcasted
    }

    var id: UUID
    var principal: LocalCapabilityPrincipal
    var receiptID: UUID
    var chainRef: String
    var status: Status
    var transactionHash: String?
    var explorerURL: URL?
    var message: String
}
