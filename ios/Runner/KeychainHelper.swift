import Foundation
import Security

/// Thin wrapper around SecItem for storing VPN secrets.
/// Secrets are stored with `kSecAttrAccessGroup` set to the shared Keychain
/// access group so the Packet Tunnel extension can read them.
class KeychainHelper {

    static let shared = KeychainHelper()

    private let accessGroup = VpnConstants.keychainAccessGroup
    private let service = "com.example.flutterVpnGo"

    // ── Write ──────────────────────────────────────────────────────────────

    @discardableResult
    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(key: key) // delete existing before re-adding

        var query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            // kSecAttrAccess is set at the query level, not item level on iOS
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Uncomment when Keychain Sharing capability is configured in Xcode:
        // query[kSecAttrAccessGroup as String] = accessGroup

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // ── Read ───────────────────────────────────────────────────────────────

    func read(key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        // query[kSecAttrAccessGroup as String] = accessGroup

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    // ── Delete ─────────────────────────────────────────────────────────────

    @discardableResult
    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
