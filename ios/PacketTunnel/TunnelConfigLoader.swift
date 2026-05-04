import Foundation
import NetworkExtension

/// Loads the tunnel configuration from the App Group shared container.
/// Called by PacketTunnelProvider.startTunnel().
struct TunnelConfigLoader {

    let appGroupId: String

    // ── Load config ────────────────────────────────────────────────────────

    func loadConfigJSON() throws -> String {
        guard let container = containerURL() else {
            throw TunnelConfigError.appGroupUnavailable
        }
        let url = container.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TunnelConfigError.configNotFound
        }
        let data = try Data(contentsOf: url)
        guard let json = String(data: data, encoding: .utf8), !json.isEmpty else {
            throw TunnelConfigError.emptyConfig
        }
        return json
    }

    func loadConfigDict() throws -> [String: Any] {
        let json = try loadConfigJSON()
        guard let data = json.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TunnelConfigError.parseError("Cannot deserialise config JSON")
        }
        return dict
    }

    // ── Stats / status write ───────────────────────────────────────────────

    func writeStats(_ dict: [String: Any]) {
        guard let container = containerURL(),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let url = container.appendingPathComponent("stats.json")
        try? data.write(to: url, options: .atomic)
    }

    func writeStatus(_ dict: [String: Any]) {
        guard let container = containerURL(),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let url = container.appendingPathComponent("status.json")
        try? data.write(to: url, options: .atomic)
    }

    // ── Auth token (Keychain) ─────────────────────────────────────────────

    /// Reads the authToken for the given configId from the shared Keychain.
    /// The token was written by FlutterVpnPlugin (Runner side).
    func loadAuthToken(configId: String) -> String? {
        let key = "authToken_\(configId)"
        let service = "com.example.flutterVpnGo"
        // Access group shared with Runner (requires Keychain Sharing capability)
        // let accessGroup = "$(AppIdentifierPrefix)com.example.flutterVpnGo"

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

    // ── Helpers ────────────────────────────────────────────────────────────

    private func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
}

// ── Errors ────────────────────────────────────────────────────────────────

enum TunnelConfigError: LocalizedError {
    case appGroupUnavailable
    case configNotFound
    case emptyConfig
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: return "App Group container unavailable. Check entitlements."
        case .configNotFound:      return "config.json not found in App Group container."
        case .emptyConfig:         return "config.json is empty."
        case .parseError(let m):   return "Config parse error: \(m)"
        }
    }
}
