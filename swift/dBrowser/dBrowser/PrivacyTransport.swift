import Foundation

enum BuiltInVPNProtocol: String, CaseIterable, Identifiable, Equatable {
    case wireGuard
    case ikev2IPSec
    case openVPN
    case customPacketTunnel

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .wireGuard: "WireGuard"
        case .ikev2IPSec: "IKEv2/IPSec"
        case .openVPN: "OpenVPN"
        case .customPacketTunnel: "Custom packet tunnel"
        }
    }

    nonisolated var providerKind: String {
        switch self {
        case .wireGuard: "NetworkExtension packet tunnel with WireGuard engine"
        case .ikev2IPSec: "NetworkExtension NEVPNManager"
        case .openVPN: "NetworkExtension packet tunnel with OpenVPN engine"
        case .customPacketTunnel: "NetworkExtension packet tunnel provider"
        }
    }

    nonisolated var privacyBoundary: String {
        switch self {
        case .wireGuard:
            "WireGuard keys and peer endpoints stay inside the VPN profile; browser tabs see only the runtime tunnel state."
        case .ikev2IPSec:
            "IKEv2 credentials stay in the OS VPN profile or keychain-backed identity, not in page context or prompts."
        case .openVPN:
            "OpenVPN credentials and inline certificates stay in the VPN profile boundary and require explicit import."
        case .customPacketTunnel:
            "Custom packet tunnel providers must expose an auditable local controller and explicit user-approved routing policy."
        }
    }

    nonisolated var requiresPacketTunnelProvider: Bool {
        switch self {
        case .wireGuard, .openVPN, .customPacketTunnel: true
        case .ikev2IPSec: false
        }
    }
}

struct BuiltInVPNProfile: Equatable, Identifiable {
    let id: String
    let title: String
    let protocolKind: BuiltInVPNProtocol
    let endpointDescription: String
    var isEnabled: Bool

    nonisolated static let localProfiles: [BuiltInVPNProfile] = [
        BuiltInVPNProfile(
            id: "wireguard-local",
            title: "WireGuard tunnel",
            protocolKind: .wireGuard,
            endpointDescription: "User-imported wg config or local packet-tunnel profile",
            isEnabled: false
        ),
        BuiltInVPNProfile(
            id: "ikev2-system",
            title: "IKEv2/IPSec tunnel",
            protocolKind: .ikev2IPSec,
            endpointDescription: "System NetworkExtension VPN profile",
            isEnabled: false
        ),
        BuiltInVPNProfile(
            id: "openvpn-local",
            title: "OpenVPN tunnel",
            protocolKind: .openVPN,
            endpointDescription: "User-imported ovpn config or local packet-tunnel profile",
            isEnabled: false
        ),
        BuiltInVPNProfile(
            id: "packet-tunnel-custom",
            title: "Custom packet tunnel",
            protocolKind: .customPacketTunnel,
            endpointDescription: "Local packet tunnel provider controlled by dBrowser policy",
            isEnabled: false
        )
    ]
}

enum BuiltInVPNClientAvailability: Equatable {
    case available
    case entitlementRequired
    case noProfiles
    case disabled

    nonisolated var title: String {
        switch self {
        case .available: "Available"
        case .entitlementRequired: "NetworkExtension entitlement required"
        case .noProfiles: "No VPN profiles configured"
        case .disabled: "Disabled"
        }
    }
}

struct BuiltInVPNClientConfiguration: Equatable {
    var supportedProtocols: [BuiltInVPNProtocol]
    var profiles: [BuiltInVPNProfile]
    var networkExtensionEntitled: Bool
    var localControllerBaseURL: URL?
    var isEnabled: Bool

    nonisolated static let disabled = BuiltInVPNClientConfiguration(
        supportedProtocols: [],
        profiles: [],
        networkExtensionEntitled: false,
        localControllerBaseURL: nil,
        isEnabled: false
    )

    nonisolated static let localDefaults = BuiltInVPNClientConfiguration(
        supportedProtocols: BuiltInVPNProtocol.allCases,
        profiles: BuiltInVPNProfile.localProfiles,
        networkExtensionEntitled: false,
        localControllerBaseURL: URL(string: "http://127.0.0.1:4898/vpn/client"),
        isEnabled: true
    )

    nonisolated var availability: BuiltInVPNClientAvailability {
        guard isEnabled else { return .disabled }
        guard !profiles.isEmpty, !supportedProtocols.isEmpty else { return .noProfiles }
        guard networkExtensionEntitled else { return .entitlementRequired }
        return .available
    }

    nonisolated var isRuntimeAvailable: Bool {
        switch availability {
        case .available: true
        case .entitlementRequired, .noProfiles, .disabled: false
        }
    }

    nonisolated var supportedProtocolTitles: [String] {
        supportedProtocols.map(\.title)
    }

    nonisolated var statusText: String {
        let protocolList = supportedProtocolTitles.joined(separator: ", ")
        switch availability {
        case .available:
            return "Built-in VPN ready: \(protocolList)"
        case .entitlementRequired:
            return "VPN profiles registered for \(protocolList); NetworkExtension entitlement required before tunnels can start"
        case .noProfiles:
            return "VPN client enabled but no protocol profiles are configured"
        case .disabled:
            return "Built-in VPN client disabled"
        }
    }

    nonisolated func profile(for protocolKind: BuiltInVPNProtocol) -> BuiltInVPNProfile? {
        profiles.first { $0.protocolKind.rawValue == protocolKind.rawValue }
    }
}

enum TraceMinimizedNetworkActivity: Equatable {
    case privateOverlay(PrivateOverlayNetwork)
    case torrentTransfer(DecentralizedStorageNetwork)

    nonisolated var title: String {
        switch self {
        case .privateOverlay(let network): network.title
        case .torrentTransfer(let network): network.title
        }
    }

    nonisolated var tabDescription: String {
        switch self {
        case .privateOverlay: "a private-overlay tab"
        case .torrentTransfer: "a torrent transfer tab"
        }
    }
}
