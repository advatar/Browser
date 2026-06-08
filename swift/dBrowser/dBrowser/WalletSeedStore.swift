//
//  WalletSeedStore.swift
//  dBrowser
//
//  Secure persistence for the embedded wallet seed. Replaces holding the seed as an in-memory
//  UUID string with cryptographically-secure entropy stored in the system Keychain.
//

import Foundation
import Security
import CryptoKit

/// Generates a fresh embedded wallet seed. This is 256 bits of cryptographically-secure
/// entropy rendered as hex, replacing the previous `UUID().uuidString`. BIP-39 mnemonic
/// encoding and Secure Enclave key-wrapping of the seed remain follow-ups.
enum WalletSeedFactory {
    static func generateSeedHex() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Persists the embedded wallet seed in the system Keychain, scoped to this device and only
/// readable after first unlock. If the Keychain is unavailable (for example an unentitled test
/// host), it transparently falls back to a process-lifetime in-memory cache so behavior degrades
/// gracefully instead of trapping. In a normally-entitled app build the seed is Keychain-backed.
final class KeychainWalletSeedStore {
    private let service: String
    private var inMemoryFallback: [String: String] = [:]

    init(service: String = "com.advatarsystems.dBrowser.walletSeed") {
        self.service = service
    }

    func loadSeed(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            if let data = item as? Data, let seed = String(data: data, encoding: .utf8) {
                return seed
            }
            return nil
        case errSecItemNotFound:
            return inMemoryFallback[account]
        default:
            // Keychain unavailable (e.g. missing entitlement): use the process-lifetime cache.
            return inMemoryFallback[account]
        }
    }

    /// Persists the seed. Returns true when it was written to the Keychain, false when it could
    /// only be cached in memory because the Keychain was unavailable.
    @discardableResult
    func saveSeed(_ seed: String, account: String) -> Bool {
        guard let data = seed.data(using: .utf8) else { return false }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(identity as CFDictionary)
        var attributes = identity
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess {
            inMemoryFallback.removeValue(forKey: account)
            return true
        }
        inMemoryFallback[account] = seed
        return false
    }

    @discardableResult
    func deleteSeed(account: String) -> Bool {
        inMemoryFallback.removeValue(forKey: account)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(identity as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Loads the seed for `account`, generating and persisting a fresh secure seed on first use.
    func loadOrCreateSeed(account: String) -> String {
        if let existing = loadSeed(account: account) {
            return existing
        }
        let generated = WalletSeedFactory.generateSeedHex()
        saveSeed(generated, account: account)
        return generated
    }
}
