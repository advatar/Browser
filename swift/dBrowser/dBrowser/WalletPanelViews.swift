//
//  WalletPanelViews.swift
//  dBrowser
//
//  Extracted from ContentView.swift to reduce the ContentView god file.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct WalletPanelView: View {
    @ObservedObject var browser: BrowserViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeaderView(
                    title: "Wallet",
                    systemImage: BrowserPanel.wallet.systemImage,
                    subtitle: "Human wallet roots, delegated agent wallets, chain trust, explorers, and approval-gated receipts."
                )

                WalletExplorerPanelView(browser: browser)
                ChainTrustPanelView(registry: browser.chainTrustSnapshot)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(platformBackgroundColor)
        .accessibilityIdentifier("panel-content-wallet")
    }
}

struct ChainTrustPanelView: View {
    let registry: ChainTrustRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Chain Trust", systemImage: "checkmark.shield")
                .font(.headline)
            Text(registry.runtimeStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(registry.fallbackWarning)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(registry.statuses.prefix(6)) { status in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(status.displaySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(status.proofTypeSummary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(status.state.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.state.isProductionEvidence ? Color.green : Color.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("runtime-chain-trust")
    }
}

struct WalletExplorerPanelView: View {
    @ObservedObject var browser: BrowserViewModel
    @State private var destinationText = ""
    @State private var amountText = "1"
    @State private var preview: WalletTransferPreview?
    @State private var receipt: WalletTransferReceipt?
    @State private var errorMessage: String?

    private var portfolio: WalletPortfolioSnapshot {
        browser.walletPortfolio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Wallet & Explorers", systemImage: "wallet.pass")
                    .font(.headline)
                Spacer()
                Button {
                    Task {
                        if portfolio.isConnected {
                            await browser.disconnectWallet()
                            preview = nil
                            receipt = nil
                        } else {
                            await browser.createEmbeddedWallet()
                        }
                    }
                } label: {
                    Label(portfolio.isConnected ? "Disconnect" : "Create Embedded Wallet", systemImage: portfolio.isConnected ? "xmark.circle" : "plus.circle")
                }
                .buttonStyle(.bordered)
            }

            Text(portfolio.policySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(portfolio.productionSigningStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            AgenticPaymentsStatusView()
            WalletControlPlaneView(snapshot: portfolio.controlPlane)

            if portfolio.isConnected, let activeNetwork = portfolio.activeNetwork, let activeAccount = portfolio.activeAccount {
                if let embeddedWallet = portfolio.embeddedWallet {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(embeddedWallet.displayName, systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                        Text(embeddedWallet.custodyLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Fingerprint \(embeddedWallet.seedFingerprint)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeNetwork.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(activeAccount.address)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(activeAccount.balance.amountText + " " + activeAccount.balance.asset)
                            .font(.caption)
                            .foregroundStyle(activeAccount.balance.isVerified ? Color.green : Color.secondary)
                    }
                    Spacer()
                    if let url = activeAccount.explorerURL() {
                        Button {
                            browser.navigate(url.absoluteString)
                        } label: {
                            Label("Explorer", systemImage: "arrow.up.forward")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    ForEach(portfolio.networks) { network in
                        Button {
                            Task {
                                await browser.switchWalletNetwork(network.chainRef)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: network.chainRef == portfolio.activeChainRef ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(network.chainRef == portfolio.activeChainRef ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(network.displayName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(network.nativeAsset + " / " + (network.trustStatus(in: browser.chainTrustSnapshot)?.state.title ?? "Unregistered"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(network.chainRef == portfolio.activeChainRef ? 0.16 : 0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Transfer Preview")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("Destination", text: $destinationText)
                            .textFieldStyle(.roundedBorder)
                        TextField("Amount", text: $amountText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                    HStack {
                        Button {
                            Task { await runPreview() }
                        } label: {
                            Label("Preview", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await runSign() }
                        } label: {
                            Label("Policy Receipt", systemImage: "signature")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let preview {
                    WalletPreviewSummaryView(preview: preview)
                }
                if let receipt {
                    WalletReceiptSummaryView(receipt: receipt)
                }
            } else {
                Text("No embedded wallet has been created yet. Create one to give local A2UI apps and MCP servers brokered access to accounts, chain trust, transaction previews, and approval-gated signing requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !portfolio.recentReceipts.isEmpty {
                Divider()
                Text("Recent Receipts")
                    .font(.subheadline.weight(.semibold))
                ForEach(portfolio.recentReceipts.prefix(4)) { receipt in
                    WalletReceiptSummaryView(receipt: receipt)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("runtime-wallet-explorer")
    }

    private func transferRequest() -> WalletTransferRequest? {
        guard let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines)),
              amount > Decimal.zero else {
            errorMessage = "Enter a positive amount."
            return nil
        }
        let destination = destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDestination = portfolio.activeAccount?.address ?? ""
        errorMessage = nil
        return WalletTransferRequest(
            chainRef: portfolio.activeChainRef,
            amount: amount,
            asset: portfolio.activeNetwork?.nativeAsset,
            destination: destination.isEmpty ? fallbackDestination : destination,
            reason: "Runtime panel transfer preview"
        )
    }

    private func runPreview() async {
        guard let request = transferRequest() else { return }
        preview = await browser.previewWalletTransfer(request)
    }

    private func runSign() async {
        guard let request = transferRequest() else { return }
        let signed = await browser.signWalletTransfer(request)
        receipt = signed
        preview = await browser.previewWalletTransfer(request)
    }
}

struct AgenticPaymentsStatusView: View {
    private let eudiProfile = EUDIWalletProfile.dbrowserReference
    private let protocolStates = [
        ("Verified email", "cliwallet EmailAddressCredential import"),
        ("Visa TAP", "Trusted-agent verification"),
        ("ACP", "Checkout and token references"),
        ("AP2", "Intent/cart/payment mandates"),
        ("x402", "HTTP payment requirements"),
        ("Notabene TAP", "Transfer authorization")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Identity & Agentic Payments", systemImage: "person.text.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(eudiProfile.mode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(eudiProfile.canUseForProductionWalletProviderClaim ? Color.green : Color.secondary)
            }
            Text(eudiProfile.certificationNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                ForEach(protocolStates, id: \.0) { state in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.0)
                            .font(.caption.weight(.semibold))
                        Text(state.1)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("agentic-payments-status")
    }
}

struct WalletControlPlaneView: View {
    let snapshot: WalletControlPlaneSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Wallet Control Plane", systemImage: "person.2.badge.key")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(snapshot.policySummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], spacing: 8) {
                ForEach(snapshot.principals) { principal in
                    WalletPrincipalCard(principal: principal, snapshot: snapshot)
                }
            }

            if !snapshot.humanIdentityCredentials.isEmpty {
                Text("Human Identity Credentials")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(snapshot.humanIdentityCredentials) { credential in
                        WalletIdentityCredentialCard(document: credential)
                    }
                }
            }

            if !snapshot.agentIdentityCredentials.isEmpty {
                Text("Agent Identity Credentials")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(snapshot.agentIdentityCredentials) { credential in
                        WalletAgentIdentityCredentialCard(credential: credential, snapshot: snapshot)
                    }
                }
            }

            if !snapshot.grants.isEmpty {
                Text("Capability Grants")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(snapshot.grants) { grant in
                        WalletCapabilityGrantCard(grant: grant, snapshot: snapshot)
                    }
                }
            }

            if !snapshot.receipts.isEmpty {
                Text("Control-Plane Receipts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(snapshot.receipts.prefix(3)) { receipt in
                    WalletControlPlaneReceiptRow(receipt: receipt, snapshot: snapshot)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("wallet-control-plane")
    }
}

struct WalletPrincipalCard: View {
    let principal: WalletPrincipal
    let snapshot: WalletControlPlaneSnapshot

    private var tint: Color {
        principal.kind == .human ? .blue : .purple
    }

    private var parentName: String? {
        principal.parentPrincipalID.flatMap { snapshot.principal(id: $0)?.displayName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(principal.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(principal.kind.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(parentName.map { "Delegated by \($0)" } ?? principal.delegationSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            FlowPillRow(items: principal.vaults.map(\.title), tint: tint)
            if let profile = principal.agentProfile {
                Text("\(profile.trustStatus.title) / \(profile.allowedProtocols.map(\.title).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WalletIdentityCredentialCard: View {
    let document: EUDICredentialDocument

    private var claimLabels: [String] {
        let preferred = ["email", "email_verified", "signature_trust", "email_normalized"]
        let preferredLabels = preferred.compactMap { key in
            document.claims[key].map { "\(key):\($0)" }
        }
        let remaining = document.claims.keys
            .filter { !preferred.contains($0) }
            .sorted()
            .prefix(2)
            .map { "claim:\($0)" }
        return preferredLabels + remaining
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(document.kind.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(document.isUsable ? "Usable" : "Blocked")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(document.isUsable ? Color.green : Color.secondary)
            }
            Text(document.subjectHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(document.issuer)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            FlowPillRow(items: claimLabels, tint: .blue)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WalletAgentIdentityCredentialCard: View {
    let credential: EUDIAgentIdentityCredential
    let snapshot: WalletControlPlaneSnapshot

    private var agentName: String {
        snapshot.principal(id: credential.agentPrincipalID)?.displayName ?? credential.agentPrincipalID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Delegated identity")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(credential.isUsable ? "Issued" : "Blocked")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(credential.isUsable ? Color.green : Color.secondary)
            }
            Text(agentName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("Source \(credential.sourceCredentialID)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            FlowPillRow(items: credential.claimNames, tint: .purple)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WalletCapabilityGrantCard: View {
    let grant: CapabilityGrant
    let snapshot: WalletControlPlaneSnapshot

    private var principalName: String {
        snapshot.principal(id: grant.principalID)?.displayName ?? grant.principalID
    }

    private var scopeLabels: [String] {
        let merchants = grant.merchantAllowlist
        let protocols = grant.protocolAllowlist.map(\.title)
        let chains = grant.chainAllowlist
        let claims = grant.identityClaimAllowlist.map { "claim:\($0)" }
        let labels = merchants + protocols + chains + claims
        return labels.isEmpty ? ["No scope labels"] : labels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(grant.capability.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(grant.statusTitle())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(grant.isActive() ? Color.green : Color.secondary)
            }
            Text("\(grant.capability.vault.title) / \(principalName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(grant.budgetSummary())
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            FlowPillRow(items: scopeLabels, tint: .green)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WalletControlPlaneReceiptRow: View {
    let receipt: WalletReceipt
    let snapshot: WalletControlPlaneSnapshot

    private var principalName: String {
        snapshot.principal(id: receipt.principalID)?.displayName ?? receipt.principalID
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: receipt.exposesRootCredential ? "exclamationmark.triangle" : "checkmark.seal")
                .foregroundStyle(receipt.exposesRootCredential ? Color.red : Color.green)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(receipt.kind.title)
                        .font(.caption.weight(.semibold))
                    Text(receipt.status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("\(principalName): \(receipt.summary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(receipt.receiptHash)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WalletPreviewSummaryView: View {
    let preview: WalletTransferPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(preview.status.rawValue, systemImage: preview.status == .rejected ? "xmark.circle" : "checkmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(preview.status == .rejected ? Color.red : Color.secondary)
            Text(preview.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(preview.chainTrustSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(preview.broadcastMode.title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WalletReceiptSummaryView: View {
    let receipt: WalletTransferReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(receipt.status.rawValue)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(receipt.amountText + " " + receipt.asset)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(receipt.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(receipt.destination)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let signatureDigest = receipt.signatureDigest {
                Text(signatureDigest)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AFMServicesPanelView: View {
    let snapshot: AFMServiceSnapshot
    let trainingJobs: [AFMExpertTrainingJob]
    let latestA2ACall: AFMA2ACallResult?
    let onCreateTrainingJob: () -> Void
    let onPublishTrainingJob: (AFMExpertTrainingJob) -> Void
    let onPrepareA2ACall: (AFMA2APeerExpert) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AFM Services", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Text(snapshot.serviceStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(
                snapshot.nodeAvailable ? "Node install, dispatch, attestation, proof, and settlement online" : "Node install, dispatch, attestation, proof, and settlement offline",
                systemImage: snapshot.nodeAvailable ? "checkmark.seal" : "xmark.seal"
            )
            .font(.caption)
            .foregroundStyle(snapshot.nodeAvailable ? Color.green : Color.secondary)
            Text("Registry v1: \(snapshot.registryExperts.count) expert\(snapshot.registryExperts.count == 1 ? "" : "s"), \(snapshot.registryBundles.count) bundle\(snapshot.registryBundles.count == 1 ? "" : "s").")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let marketplaceAvailable = snapshot.marketplaceAvailable {
                Label(
                    "Marketplace \(marketplaceAvailable ? "online" : "offline") with \(snapshot.marketplacePacks.count) runner pack\(snapshot.marketplacePacks.count == 1 ? "" : "s") and \(snapshot.marketplaceExperts.count) expert\(snapshot.marketplaceExperts.count == 1 ? "" : "s")",
                    systemImage: marketplaceAvailable ? "shippingbox.circle" : "shippingbox"
                )
                .font(.caption)
                .foregroundStyle(marketplaceAvailable ? Color.green : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("A2A Peer Experts", systemImage: "person.2.wave.2")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(peerExperts.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if peerExperts.isEmpty {
                    Text("No peer-installed Foundation Model experts reported by AFMarket registry or local training jobs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(peerExperts.prefix(4)) { expert in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expert.displayName)
                                    .font(.caption.weight(.semibold))
                                Text(expert.availabilitySummary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Preview") {
                                onPrepareA2ACall(expert)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
                if let latestA2ACall {
                    Text(latestA2ACall.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Embedded Expert Training", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        onCreateTrainingJob()
                    } label: {
                        Label("Create Demo Expert", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                Text("Local training jobs produce deterministic adapter artifacts and can publish marketplace runner packs when the AFM marketplace service is configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if trainingJobs.isEmpty {
                    Text("No embedded expert training jobs yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trainingJobs.prefix(4)) { job in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.request.displayName)
                                    .font(.caption.weight(.semibold))
                                Text(job.displaySummary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text([job.outputRunnerID, job.manifestHash, job.request.policy.safetySummary].compactMap { $0 }.joined(separator: " / "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if job.isPublishedToMarketplace {
                                Label("Published", systemImage: "checkmark.seal")
                                    .font(.caption2)
                                    .foregroundStyle(Color.green)
                            } else if job.request.policy.publishToAFMarket {
                                Button("Publish") {
                                    onPublishTrainingJob(job)
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if snapshot.availablePacks.isEmpty {
                Text("No runner packs reported by router, registry, or marketplace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.availablePacks.prefix(6)) { pack in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text([pack.id, pack.version, pack.modelID, pack.status].compactMap { $0 }.joined(separator: " / "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let marketplaceDetails = marketplacePackDetails(for: pack)
                            if !marketplaceDetails.isEmpty {
                                Text(marketplaceDetails.joined(separator: " / "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let maintainer = pack.maintainer {
                            Text(maintainer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("runtime-afm-services")
    }

    private var peerExperts: [AFMA2APeerExpert] {
        uniquePeerExperts(snapshot.peerExperts + trainingJobs.map(\.peerExpert))
            .sorted { $0.displayName < $1.displayName }
    }

    private func uniquePeerExperts(_ experts: [AFMA2APeerExpert]) -> [AFMA2APeerExpert] {
        var seen = Set<String>()
        return experts.filter { seen.insert($0.id).inserted }
    }

    private func marketplacePackDetails(for pack: AFMPackSummary) -> [String] {
        var details: [String] = []
        if let allowedDomains = pack.allowedDomains, !allowedDomains.isEmpty {
            details.append("Domains \(allowedDomains.joined(separator: ", "))")
        }
        if let maxContext = pack.maxContext {
            details.append("Context \(maxContext)")
        }
        if let creatorRoyaltyBPS = pack.creatorRoyaltyBPS {
            details.append("Creator \(creatorRoyaltyBPS) bps")
        }
        if let dataRoyaltyBPS = pack.dataRoyaltyBPS {
            details.append("Data \(dataRoyaltyBPS) bps")
        }
        return details
    }
}

