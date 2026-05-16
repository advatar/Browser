import CryptoKit
import Foundation

enum BlockchainExplorerTargetKind: String, Codable, Equatable, CaseIterable {
    case account
    case transaction
    case block

    var title: String {
        switch self {
        case .account: "Account"
        case .transaction: "Transaction"
        case .block: "Block"
        }
    }
}

struct BlockchainExplorerTarget: Codable, Equatable {
    var chainRef: String
    var kind: BlockchainExplorerTargetKind
    var value: String

    init(chainRef: String, kind: BlockchainExplorerTargetKind, value: String) {
        self.chainRef = ChainTrustStatus.normalized(chainRef)
        self.kind = kind
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BlockchainExplorerEndpoint: Codable, Equatable, Identifiable {
    var id: String { chainRef }

    var chainRef: String
    var displayName: String
    var baseURLString: String
    var accountPath: [String]
    var transactionPath: [String]
    var blockPath: [String]
    var trustLabel: String

    init(
        chainRef: String,
        displayName: String,
        baseURLString: String,
        accountPath: [String] = ["address"],
        transactionPath: [String] = ["tx"],
        blockPath: [String] = ["block"],
        trustLabel: String = "Third-party explorer; not a local light-client trust root."
    ) {
        self.chainRef = ChainTrustStatus.normalized(chainRef)
        self.displayName = displayName
        self.baseURLString = baseURLString
        self.accountPath = accountPath
        self.transactionPath = transactionPath
        self.blockPath = blockPath
        self.trustLabel = trustLabel
    }

    func url(for target: BlockchainExplorerTarget) -> URL? {
        guard matches(chainRef: target.chainRef), !target.value.isEmpty else { return nil }
        guard var url = URL(string: baseURLString) else { return nil }

        let path: [String]
        switch target.kind {
        case .account:
            path = accountPath
        case .transaction:
            path = transactionPath
        case .block:
            path = blockPath
        }

        for component in path where !component.isEmpty {
            url.appendPathComponent(component)
        }
        url.appendPathComponent(target.value)
        return url
    }

    func matches(chainRef candidate: String) -> Bool {
        ChainTrustStatus.normalized(candidate) == ChainTrustStatus.normalized(chainRef)
    }
}

struct BlockchainExplorerCatalog: Codable, Equatable {
    var explorers: [BlockchainExplorerEndpoint]

    init(explorers: [BlockchainExplorerEndpoint] = Self.defaultExplorers) {
        self.explorers = explorers
    }

    static var `default`: BlockchainExplorerCatalog {
        BlockchainExplorerCatalog()
    }

    func explorer(forChainRef chainRef: String) -> BlockchainExplorerEndpoint? {
        explorers.first { $0.matches(chainRef: chainRef) }
    }

    func url(for target: BlockchainExplorerTarget) -> URL? {
        explorer(forChainRef: target.chainRef)?.url(for: target)
    }

    static let defaultExplorers: [BlockchainExplorerEndpoint] = [
        BlockchainExplorerEndpoint(chainRef: "bitcoin-mainnet", displayName: "Mempool", baseURLString: "https://mempool.space"),
        BlockchainExplorerEndpoint(chainRef: "ethereum-mainnet", displayName: "Etherscan", baseURLString: "https://etherscan.io"),
        BlockchainExplorerEndpoint(chainRef: "base-mainnet", displayName: "BaseScan", baseURLString: "https://basescan.org"),
        BlockchainExplorerEndpoint(chainRef: "base-sepolia", displayName: "BaseScan Sepolia", baseURLString: "https://sepolia.basescan.org"),
        BlockchainExplorerEndpoint(chainRef: "arbitrum-one", displayName: "Arbiscan", baseURLString: "https://arbiscan.io"),
        BlockchainExplorerEndpoint(chainRef: "optimism-mainnet", displayName: "Optimistic Etherscan", baseURLString: "https://optimistic.etherscan.io"),
        BlockchainExplorerEndpoint(chainRef: "polygon-mainnet", displayName: "PolygonScan", baseURLString: "https://polygonscan.com"),
        BlockchainExplorerEndpoint(chainRef: "bnb-smart-chain", displayName: "BscScan", baseURLString: "https://bscscan.com"),
        BlockchainExplorerEndpoint(chainRef: "avalanche-c", displayName: "Avascan", baseURLString: "https://avascan.info/blockchain/c"),
        BlockchainExplorerEndpoint(chainRef: "solana-mainnet", displayName: "Solscan", baseURLString: "https://solscan.io", accountPath: ["account"]),
        BlockchainExplorerEndpoint(chainRef: "solana-devnet", displayName: "Solscan Devnet", baseURLString: "https://solscan.io", accountPath: ["account"]),
        BlockchainExplorerEndpoint(chainRef: "cosmos-hub", displayName: "Mintscan", baseURLString: "https://www.mintscan.io/cosmos"),
        BlockchainExplorerEndpoint(chainRef: "osmosis", displayName: "Mintscan Osmosis", baseURLString: "https://www.mintscan.io/osmosis"),
        BlockchainExplorerEndpoint(chainRef: "polkadot", displayName: "Subscan Polkadot", baseURLString: "https://polkadot.subscan.io"),
        BlockchainExplorerEndpoint(chainRef: "asset-hub-polkadot", displayName: "Subscan Asset Hub", baseURLString: "https://assethub-polkadot.subscan.io"),
        BlockchainExplorerEndpoint(chainRef: "tron-mainnet", displayName: "Tronscan", baseURLString: "https://tronscan.org/#", accountPath: ["address"], transactionPath: ["transaction"]),
        BlockchainExplorerEndpoint(chainRef: "xrp-ledger", displayName: "XRPSCAN", baseURLString: "https://xrpscan.com", accountPath: ["account"], transactionPath: ["tx"]),
        BlockchainExplorerEndpoint(chainRef: "sui-mainnet", displayName: "SuiVision", baseURLString: "https://suivision.xyz", accountPath: ["account"], transactionPath: ["txblock"], blockPath: ["checkpoint"]),
        BlockchainExplorerEndpoint(chainRef: "aptos-mainnet", displayName: "Aptos Explorer", baseURLString: "https://explorer.aptoslabs.com", accountPath: ["account"], transactionPath: ["txn"])
    ]
}

enum WalletSignerKind: String, Codable, Equatable {
    case localPolicyReceipt
    case secureEnclavePlanned
    case walletConnectPlanned
    case externalSignerPlanned

    var title: String {
        switch self {
        case .localPolicyReceipt: "Local policy receipt"
        case .secureEnclavePlanned: "Secure Enclave planned"
        case .walletConnectPlanned: "WalletConnect planned"
        case .externalSignerPlanned: "External signer planned"
        }
    }
}

enum WalletBroadcastMode: String, Codable, Equatable {
    case unavailable
    case rpcFallbackPlanned
    case servicePlanned

    var title: String {
        switch self {
        case .unavailable: "Broadcast unavailable"
        case .rpcFallbackPlanned: "RPC broadcast planned"
        case .servicePlanned: "Service broadcast planned"
        }
    }
}

struct WalletNetwork: Codable, Equatable, Identifiable {
    var id: String { chainRef }

    var chainRef: String
    var displayName: String
    var family: ChainTrustFamily
    var nativeAsset: String
    var chainID: String?
    var signerKind: WalletSignerKind
    var broadcastMode: WalletBroadcastMode
    var explorer: BlockchainExplorerEndpoint?

    init(
        chainRef: String,
        displayName: String,
        family: ChainTrustFamily,
        nativeAsset: String,
        chainID: String? = nil,
        signerKind: WalletSignerKind = .localPolicyReceipt,
        broadcastMode: WalletBroadcastMode = .unavailable,
        explorer: BlockchainExplorerEndpoint? = nil
    ) {
        self.chainRef = ChainTrustStatus.normalized(chainRef)
        self.displayName = displayName
        self.family = family
        self.nativeAsset = nativeAsset
        self.chainID = chainID
        self.signerKind = signerKind
        self.broadcastMode = broadcastMode
        self.explorer = explorer ?? BlockchainExplorerCatalog.default.explorer(forChainRef: chainRef)
    }

    func trustStatus(in registry: ChainTrustRegistry) -> ChainTrustStatus? {
        registry.status(forChainRef: chainRef)
    }

    func explorerURL(kind: BlockchainExplorerTargetKind, value: String) -> URL? {
        explorer?.url(for: BlockchainExplorerTarget(chainRef: chainRef, kind: kind, value: value))
    }
}

struct WalletBalance: Codable, Equatable {
    var asset: String
    var amountText: String
    var source: ChainTrustSource
    var isVerified: Bool

    static func placeholder(asset: String) -> WalletBalance {
        WalletBalance(
            asset: asset,
            amountText: "0",
            source: .gatewayRPCFallback,
            isVerified: false
        )
    }
}

struct WalletAccount: Codable, Equatable, Identifiable {
    var id: String { "\(chainRef):\(address)" }

    var chainRef: String
    var displayName: String
    var address: String
    var signerKind: WalletSignerKind
    var balance: WalletBalance

    func explorerURL(in catalog: BlockchainExplorerCatalog = .default) -> URL? {
        catalog.url(for: BlockchainExplorerTarget(chainRef: chainRef, kind: .account, value: address))
    }
}

struct WalletTransferRequest: Codable, Equatable {
    var chainRef: String?
    var amount: Decimal
    var asset: String?
    var destination: String
    var memo: String?
    var reason: String

    init(
        chainRef: String? = nil,
        amount: Decimal,
        asset: String? = nil,
        destination: String,
        memo: String? = nil,
        reason: String
    ) {
        self.chainRef = chainRef.map(ChainTrustStatus.normalized)
        self.amount = amount
        self.asset = asset
        self.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        self.memo = memo
        self.reason = reason
    }
}

struct WalletTransferPreview: Codable, Equatable, Identifiable {
    enum Status: String, Codable, Equatable {
        case ready
        case needsApproval
        case rejected
    }

    var id: UUID
    var request: WalletTransferRequest
    var network: WalletNetwork?
    var account: WalletAccount?
    var status: Status
    var reason: String
    var feeEstimate: String?
    var requiresApproval: Bool
    var chainTrustState: ChainTrustState?
    var chainTrustSummary: String
    var explorerURL: URL?
    var broadcastMode: WalletBroadcastMode

    init(
        id: UUID = UUID(),
        request: WalletTransferRequest,
        network: WalletNetwork?,
        account: WalletAccount?,
        status: Status,
        reason: String,
        feeEstimate: String? = nil,
        requiresApproval: Bool = false,
        chainTrustState: ChainTrustState? = nil,
        chainTrustSummary: String,
        explorerURL: URL? = nil,
        broadcastMode: WalletBroadcastMode = .unavailable
    ) {
        self.id = id
        self.request = request
        self.network = network
        self.account = account
        self.status = status
        self.reason = reason
        self.feeEstimate = feeEstimate
        self.requiresApproval = requiresApproval
        self.chainTrustState = chainTrustState
        self.chainTrustSummary = chainTrustSummary
        self.explorerURL = explorerURL
        self.broadcastMode = broadcastMode
    }
}

struct WalletTransferReceipt: Codable, Equatable, Identifiable {
    enum Status: String, Codable, Equatable {
        case policySigned
        case needsApproval
        case rejected
    }

    var id: UUID
    var request: WalletTransferRequest
    var chainRef: String
    var fromAddress: String
    var destination: String
    var amountText: String
    var asset: String
    var status: Status
    var signatureDigest: String?
    var transactionHash: String?
    var explorerURL: URL?
    var broadcastMode: WalletBroadcastMode
    var chainTrustSummary: String
    var message: String
    var createdAt: Date
}

struct WalletPortfolioSnapshot: Codable, Equatable {
    var isConnected: Bool
    var activeChainRef: String
    var networks: [WalletNetwork]
    var accounts: [WalletAccount]
    var recentReceipts: [WalletTransferReceipt]
    var policySummary: String
    var productionSigningStatus: String

    static var disconnected: WalletPortfolioSnapshot {
        WalletPortfolioSnapshot(
            isConnected: false,
            activeChainRef: "ethereum-mainnet",
            networks: WalletNetwork.defaultNetworks(),
            accounts: [],
            recentReceipts: [],
            policySummary: "Connect a wallet before signing or spending.",
            productionSigningStatus: "Production signing adapters are not configured."
        )
    }

    var activeNetwork: WalletNetwork? {
        networks.first { $0.chainRef == activeChainRef }
    }

    var activeAccount: WalletAccount? {
        account(forChainRef: activeChainRef)
    }

    func account(forChainRef chainRef: String) -> WalletAccount? {
        let normalized = ChainTrustStatus.normalized(chainRef)
        return accounts.first { $0.chainRef == normalized }
    }

    func network(forChainRef chainRef: String) -> WalletNetwork? {
        let normalized = ChainTrustStatus.normalized(chainRef)
        return networks.first { $0.chainRef == normalized }
    }

    func withChainTrust(_ registry: ChainTrustRegistry) -> WalletPortfolioSnapshot {
        var copy = self
        copy.networks = networks.map { network in
            var updated = network
            updated.explorer = network.explorer ?? BlockchainExplorerCatalog.default.explorer(forChainRef: network.chainRef)
            return updated
        }
        copy.accounts = accounts.map { account in
            var updated = account
            if let status = registry.status(forChainRef: account.chainRef) {
                updated.balance.source = status.trustSource
                updated.balance.isVerified = status.state.isProductionEvidence
            }
            return updated
        }
        return copy
    }
}

extension WalletNetwork {
    static func defaultNetworks(catalog: BlockchainExplorerCatalog = .default) -> [WalletNetwork] {
        [
            WalletNetwork(chainRef: "bitcoin-mainnet", displayName: "Bitcoin", family: .bitcoin, nativeAsset: "BTC", explorer: catalog.explorer(forChainRef: "bitcoin-mainnet")),
            WalletNetwork(chainRef: "ethereum-mainnet", displayName: "Ethereum Mainnet", family: .ethereum, nativeAsset: "ETH", chainID: "1", explorer: catalog.explorer(forChainRef: "ethereum-mainnet")),
            WalletNetwork(chainRef: "base-mainnet", displayName: "Base", family: .evmLayer2, nativeAsset: "ETH", chainID: "8453", explorer: catalog.explorer(forChainRef: "base-mainnet")),
            WalletNetwork(chainRef: "base-sepolia", displayName: "Base Sepolia", family: .evmLayer2, nativeAsset: "ETH", chainID: "84532", explorer: catalog.explorer(forChainRef: "base-sepolia")),
            WalletNetwork(chainRef: "arbitrum-one", displayName: "Arbitrum One", family: .evmLayer2, nativeAsset: "ETH", chainID: "42161", explorer: catalog.explorer(forChainRef: "arbitrum-one")),
            WalletNetwork(chainRef: "optimism-mainnet", displayName: "Optimism", family: .evmLayer2, nativeAsset: "ETH", chainID: "10", explorer: catalog.explorer(forChainRef: "optimism-mainnet")),
            WalletNetwork(chainRef: "polygon-mainnet", displayName: "Polygon", family: .evmLayer2, nativeAsset: "MATIC", chainID: "137", explorer: catalog.explorer(forChainRef: "polygon-mainnet")),
            WalletNetwork(chainRef: "bnb-smart-chain", displayName: "BNB Smart Chain", family: .evmLayer2, nativeAsset: "BNB", chainID: "56", explorer: catalog.explorer(forChainRef: "bnb-smart-chain")),
            WalletNetwork(chainRef: "avalanche-c", displayName: "Avalanche C-Chain", family: .avalanche, nativeAsset: "AVAX", chainID: "43114", explorer: catalog.explorer(forChainRef: "avalanche-c")),
            WalletNetwork(chainRef: "solana-mainnet", displayName: "Solana", family: .solana, nativeAsset: "SOL", explorer: catalog.explorer(forChainRef: "solana-mainnet")),
            WalletNetwork(chainRef: "cosmos-hub", displayName: "Cosmos Hub", family: .cosmosTendermint, nativeAsset: "ATOM", chainID: "cosmoshub-4", explorer: catalog.explorer(forChainRef: "cosmos-hub")),
            WalletNetwork(chainRef: "polkadot", displayName: "Polkadot", family: .polkadotSubstrate, nativeAsset: "DOT", explorer: catalog.explorer(forChainRef: "polkadot")),
            WalletNetwork(chainRef: "tron-mainnet", displayName: "TRON", family: .tron, nativeAsset: "TRX", explorer: catalog.explorer(forChainRef: "tron-mainnet")),
            WalletNetwork(chainRef: "xrp-ledger", displayName: "XRP Ledger", family: .xrpLedger, nativeAsset: "XRP", explorer: catalog.explorer(forChainRef: "xrp-ledger")),
            WalletNetwork(chainRef: "sui-mainnet", displayName: "Sui", family: .sui, nativeAsset: "SUI", explorer: catalog.explorer(forChainRef: "sui-mainnet")),
            WalletNetwork(chainRef: "aptos-mainnet", displayName: "Aptos", family: .aptos, nativeAsset: "APT", explorer: catalog.explorer(forChainRef: "aptos-mainnet"))
        ]
    }
}

enum WalletPolicyEngine {
    static let localPolicyLimit = Decimal(25)

    static func preview(
        request: WalletTransferRequest,
        portfolio: WalletPortfolioSnapshot,
        chainTrust: ChainTrustRegistry
    ) -> WalletTransferPreview {
        let chainRef = request.chainRef ?? portfolio.activeChainRef
        let network = portfolio.network(forChainRef: chainRef)
        let account = portfolio.account(forChainRef: chainRef)
        let status = network.flatMap { chainTrust.status(forChainRef: $0.chainRef) }
        let chainSummary = status?.displaySummary ?? "No chain trust state is registered for \(chainRef)."
        let explorerURL = network?.explorerURL(kind: .account, value: request.destination)

        guard portfolio.isConnected else {
            return WalletTransferPreview(
                request: request,
                network: network,
                account: account,
                status: .rejected,
                reason: "Connect a wallet before creating transfer previews.",
                chainTrustState: status?.state,
                chainTrustSummary: chainSummary,
                explorerURL: explorerURL
            )
        }
        guard let network else {
            return WalletTransferPreview(
                request: request,
                network: nil,
                account: nil,
                status: .rejected,
                reason: "Unsupported wallet network \(chainRef).",
                chainTrustState: status?.state,
                chainTrustSummary: chainSummary,
                explorerURL: nil
            )
        }
        guard let account else {
            return WalletTransferPreview(
                request: request,
                network: network,
                account: nil,
                status: .rejected,
                reason: "No local policy account is available for \(network.displayName).",
                chainTrustState: status?.state,
                chainTrustSummary: chainSummary,
                explorerURL: explorerURL,
                broadcastMode: network.broadcastMode
            )
        }
        guard request.amount > Decimal.zero else {
            return WalletTransferPreview(
                request: request,
                network: network,
                account: account,
                status: .rejected,
                reason: "Transfer amount must be greater than zero.",
                chainTrustState: status?.state,
                chainTrustSummary: chainSummary,
                explorerURL: explorerURL,
                broadcastMode: network.broadcastMode
            )
        }
        guard isPlausibleDestination(request.destination, family: network.family) else {
            return WalletTransferPreview(
                request: request,
                network: network,
                account: account,
                status: .rejected,
                reason: "Destination does not match the expected \(network.displayName) address shape.",
                chainTrustState: status?.state,
                chainTrustSummary: chainSummary,
                explorerURL: explorerURL,
                broadcastMode: network.broadcastMode
            )
        }

        let needsApproval = request.amount > localPolicyLimit
        let previewStatus: WalletTransferPreview.Status = needsApproval ? .needsApproval : .ready
        let reason = needsApproval
            ? "Amount exceeds the local policy limit and needs explicit approval before signing."
            : "Amount is within the local policy limit; production signing remains unavailable."

        return WalletTransferPreview(
            request: request,
            network: network,
            account: account,
            status: previewStatus,
            reason: reason,
            feeEstimate: "Requires \(network.nativeAsset) fee quote from \(network.displayName) adapter.",
            requiresApproval: needsApproval,
            chainTrustState: status?.state,
            chainTrustSummary: chainSummary,
            explorerURL: explorerURL,
            broadcastMode: network.broadcastMode
        )
    }

    static func receipt(
        request: WalletTransferRequest,
        preview: WalletTransferPreview
    ) -> WalletTransferReceipt {
        let network = preview.network
        let account = preview.account
        let asset = request.asset?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? request.asset!
            : network?.nativeAsset ?? "asset"
        let amountText = NSDecimalNumber(decimal: request.amount).stringValue

        switch preview.status {
        case .rejected:
            return WalletTransferReceipt(
                id: UUID(),
                request: request,
                chainRef: network?.chainRef ?? request.chainRef ?? "unknown",
                fromAddress: account?.address ?? "",
                destination: request.destination,
                amountText: amountText,
                asset: asset,
                status: .rejected,
                signatureDigest: nil,
                transactionHash: nil,
                explorerURL: nil,
                broadcastMode: network?.broadcastMode ?? .unavailable,
                chainTrustSummary: preview.chainTrustSummary,
                message: preview.reason,
                createdAt: Date()
            )
        case .needsApproval:
            return WalletTransferReceipt(
                id: UUID(),
                request: request,
                chainRef: network?.chainRef ?? request.chainRef ?? "unknown",
                fromAddress: account?.address ?? "",
                destination: request.destination,
                amountText: amountText,
                asset: asset,
                status: .needsApproval,
                signatureDigest: nil,
                transactionHash: nil,
                explorerURL: preview.explorerURL,
                broadcastMode: network?.broadcastMode ?? .unavailable,
                chainTrustSummary: preview.chainTrustSummary,
                message: preview.reason,
                createdAt: Date()
            )
        case .ready:
            let preimage = [
                network?.chainRef ?? request.chainRef ?? "unknown",
                account?.address ?? "",
                request.destination,
                amountText,
                asset,
                request.reason
            ].joined(separator: "|")
            let digest = sha256Hex(preimage)
            return WalletTransferReceipt(
                id: UUID(),
                request: request,
                chainRef: network?.chainRef ?? request.chainRef ?? "unknown",
                fromAddress: account?.address ?? "",
                destination: request.destination,
                amountText: amountText,
                asset: asset,
                status: .policySigned,
                signatureDigest: digest,
                transactionHash: nil,
                explorerURL: preview.explorerURL,
                broadcastMode: network?.broadcastMode ?? .unavailable,
                chainTrustSummary: preview.chainTrustSummary,
                message: "Created a local policy receipt. No production transaction was signed or broadcast.",
                createdAt: Date()
            )
        }
    }

    static func isPlausibleDestination(_ value: String, family: ChainTrustFamily) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch family {
        case .ethereum, .evmLayer2, .avalanche, .sui, .aptos:
            return trimmed.lowercased().hasPrefix("0x") && trimmed.count >= 4
        case .bitcoin:
            guard trimmed.count >= 8 else { return false }
            return trimmed.lowercased().hasPrefix("bc1")
                || trimmed.hasPrefix("1")
                || trimmed.hasPrefix("3")
        case .solana:
            guard trimmed.count >= 8 else { return false }
            return trimmed.allSatisfy { base58Alphabet.contains($0) }
        case .cosmosTendermint:
            guard trimmed.count >= 8 else { return false }
            return trimmed.lowercased().hasPrefix("cosmos1")
                || trimmed.lowercased().hasPrefix("osmo1")
        case .polkadotSubstrate:
            guard trimmed.count >= 8 else { return false }
            return trimmed.allSatisfy { base58Alphabet.contains($0) }
        case .tron:
            return trimmed.hasPrefix("T") && trimmed.count >= 8
        case .xrpLedger:
            return trimmed.hasPrefix("r") && trimmed.count >= 8
        case .unknown:
            return false
        }
    }

    static func makeAccounts(seed: String, networks: [WalletNetwork]) -> [WalletAccount] {
        networks.map { network in
            WalletAccount(
                chainRef: network.chainRef,
                displayName: "\(network.displayName) policy account",
                address: makeAddress(seed: seed, network: network),
                signerKind: network.signerKind,
                balance: .placeholder(asset: network.nativeAsset)
            )
        }
    }

    static func makeAddress(seed: String, network: WalletNetwork) -> String {
        let digest = sha256Hex("\(seed)|\(network.chainRef)")
        switch network.family {
        case .bitcoin:
            return "bc1q\(base58(fromHex: digest, length: 38).lowercased())"
        case .ethereum, .evmLayer2, .avalanche:
            return "0x\(digest.prefix(40))"
        case .solana:
            return base58(fromHex: digest, length: 44)
        case .cosmosTendermint:
            let prefix = network.chainRef == "osmosis" ? "osmo" : "cosmos"
            return "\(prefix)1\(base58(fromHex: digest, length: 38).lowercased())"
        case .polkadotSubstrate:
            return base58(fromHex: digest, length: 48)
        case .tron:
            return "T\(base58(fromHex: digest, length: 33))"
        case .xrpLedger:
            return "r\(base58(fromHex: digest, length: 33))"
        case .sui, .aptos:
            return "0x\(digest)"
        case .unknown:
            return digest
        }
    }

    static func sha256Hex(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).map { String(format: "%02x", $0) }.joined()
    }

    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    private static func base58(fromHex hex: String, length: Int) -> String {
        let scalars = Array(hex.unicodeScalars)
        guard !scalars.isEmpty else { return String(repeating: "1", count: length) }
        var output = ""
        for index in 0..<length {
            let scalar = scalars[index % scalars.count]
            let value = Int(scalar.value) + index
            output.append(base58Alphabet[value % base58Alphabet.count])
        }
        return output
    }
}
