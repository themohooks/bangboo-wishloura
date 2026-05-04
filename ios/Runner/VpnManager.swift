import Foundation
import NetworkExtension

/// Constants shared between Runner and PacketTunnel extension.
enum VpnConstants {
    /// App Group ID for shared container (config, logs, stats).
    /// Replace "TEAMID" with your actual Apple Developer Team ID.
    static let appGroupId            = "group.com.example.flutterVpnGo"

    /// Bundle ID of the Packet Tunnel extension target.
    static let extensionBundleId     = "com.example.flutterVpnGo.PacketTunnel"

    /// Keychain access group for sharing secrets between Runner and extension.
    static let keychainAccessGroup   = "$(AppIdentifierPrefix)com.example.flutterVpnGo"

    /// Keys in the shared App Group container
    static let configKey   = "config.json"
    static let statusKey   = "status.json"
    static let statsKey    = "stats.json"
    static let logsKey     = "logs.jsonl"
}

/// Manages the NETunnelProviderManager lifecycle from the Flutter app side.
///
/// Responsibilities:
///  - Load / create the VPN profile in System Preferences.
///  - Push config JSON to the shared App Group container.
///  - Start / stop the Packet Tunnel extension.
///  - Observe NEVPNStatus and push updates to [statusChangeHandler].
///  - Send IPC messages to the extension via sendProviderMessage.
@MainActor
class VpnManager: NSObject {

    static let shared = VpnManager()

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    var statusChangeHandler: ((NEVPNStatus) -> Void)?

    // ── Load / Setup ──────────────────────────────────────────────────────

    /// Loads the first existing profile or creates a new one.
    func prepare() async throws -> Bool {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let existing = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == VpnConstants.extensionBundleId
        })
        if let m = existing {
            manager = m
        } else {
            manager = NETunnelProviderManager()
        }
        observeStatus()
        return true
    }

    /// Writes the config to the shared App Group container and updates
    /// the NETunnelProviderManager profile in System Preferences.
    func installOrUpdateProfile(configJSON: String, serverAddress: String, name: String) async throws {
        guard let m = manager else { throw VpnError.notPrepared }

        // 1. Write config to shared App Group container
        try writeSharedFile(VpnConstants.configKey, data: Data(configJSON.utf8))

        // 2. Build / update the provider protocol
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = VpnConstants.extensionBundleId
        proto.serverAddress = serverAddress.isEmpty ? "vpn-server" : serverAddress
        proto.providerConfiguration = [
            "configKey": VpnConstants.configKey,
            "appGroupId": VpnConstants.appGroupId,
        ]
        // Do NOT put authToken into providerConfiguration — it's in Keychain.

        m.protocolConfiguration = proto
        m.localizedDescription = "VPN Go — \(name)"
        m.isEnabled = true

        try await m.saveToPreferences()
        try await m.loadFromPreferences()
    }

    // ── Connect / Disconnect ──────────────────────────────────────────────

    func startTunnel() throws {
        guard let m = manager else { throw VpnError.notPrepared }
        try m.connection.startVPNTunnel()
    }

    func stopTunnel() {
        manager?.connection.stopVPNTunnel()
    }

    // ── Status ────────────────────────────────────────────────────────────

    var currentStatus: NEVPNStatus {
        manager?.connection.status ?? .disconnected
    }

    var uptimeSeconds: Int? {
        guard let connectedDate = manager?.connection.connectedDate else { return nil }
        return Int(-connectedDate.timeIntervalSinceNow)
    }

    // ── IPC: sendProviderMessage ──────────────────────────────────────────

    func sendProviderMessage(_ data: Data) async throws -> Data? {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            throw VpnError.notConnected
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { responseData in
                    continuation.resume(returning: responseData)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // ── Shared container ──────────────────────────────────────────────────

    func readSharedFile(_ key: String) throws -> Data {
        guard let url = containerURL(for: key) else { throw VpnError.appGroupUnavailable }
        return try Data(contentsOf: url)
    }

    func writeSharedFile(_ key: String, data: Data) throws {
        guard let url = containerURL(for: key) else { throw VpnError.appGroupUnavailable }
        try data.write(to: url, options: .atomic)
    }

    private func containerURL(for key: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: VpnConstants.appGroupId)?
            .appendingPathComponent(key)
    }

    // ── Status observation ────────────────────────────────────────────────

    private func observeStatus() {
        guard let conn = manager?.connection else { return }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: conn,
            queue: .main
        ) { [weak self] _ in
            self?.statusChangeHandler?(conn.status)
        }
    }

    deinit {
        if let obs = statusObserver { NotificationCenter.default.removeObserver(obs) }
    }
}

// ── Errors ────────────────────────────────────────────────────────────────

enum VpnError: LocalizedError {
    case notPrepared
    case notConnected
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .notPrepared:         return "VPN manager not prepared. Call prepareVpn() first."
        case .notConnected:        return "VPN is not connected."
        case .appGroupUnavailable: return "App Group container unavailable. Check entitlements."
        }
    }
}

// ── NEVPNStatus → string ──────────────────────────────────────────────────

extension NEVPNStatus {
    var tunnelStatusString: String {
        switch self {
        case .disconnected:  return "disconnected"
        case .connecting:    return "connecting"
        case .connected:     return "connected"
        case .reasserting:   return "reconnecting"
        case .disconnecting: return "disconnecting"
        case .invalid:       return "failed"
        @unknown default:    return "disconnected"
        }
    }
}
