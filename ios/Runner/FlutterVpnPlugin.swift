import Flutter
import Foundation
import NetworkExtension
import UIKit

/// Flutter plugin for iOS.
/// Implements VpnHostApiProtocol (Pigeon) and bridges to VpnManager.
/// EventChannels emit push events for status, stats, and logs.
class FlutterVpnPlugin: NSObject, FlutterPlugin, VpnHostApiProtocol {

    private var statusChannel: FlutterEventChannel?
    private var statsChannel:  FlutterEventChannel?
    private var logChannel:    FlutterEventChannel?

    private var statusSink: FlutterEventSink?
    private var statsSink:  FlutterEventSink?
    private var logSink:    FlutterEventSink?

    private var statusTimer: Timer?
    private var statsTimer:  Timer?

    // ── Registration ──────────────────────────────────────────────────────

    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = FlutterVpnPlugin()
        VpnHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: plugin)

        plugin.statusChannel = FlutterEventChannel(
            name: "com.example.fluttervpngo/vpn_status_events",
            binaryMessenger: registrar.messenger())
        plugin.statsChannel = FlutterEventChannel(
            name: "com.example.fluttervpngo/vpn_stats_events",
            binaryMessenger: registrar.messenger())
        plugin.logChannel = FlutterEventChannel(
            name: "com.example.fluttervpngo/vpn_log_events",
            binaryMessenger: registrar.messenger())

        plugin.statusChannel?.setStreamHandler(
            EventStreamHandler { sink in plugin.statusSink = sink }
                               cancel: { plugin.statusSink = nil })
        plugin.statsChannel?.setStreamHandler(
            EventStreamHandler { sink in plugin.statsTimer = plugin.startStatsTimer(sink: sink) }
                               cancel: { plugin.statsTimer?.invalidate(); plugin.statsSink = nil })
        plugin.logChannel?.setStreamHandler(
            EventStreamHandler { sink in plugin.logSink = sink }
                               cancel: { plugin.logSink = nil })

        // Observe NE status changes
        VpnManager.shared.statusChangeHandler = { [weak plugin] status in
            plugin?.pushStatus(status)
        }
    }

    // ── prepareVpn ────────────────────────────────────────────────────────

    func prepareVpn(completion: @escaping (Result<Bool, Error>) -> Void) {
        Task { @MainActor in
            do {
                let ok = try await VpnManager.shared.prepare()
                completion(.success(ok))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // ── installOrUpdateProfile ────────────────────────────────────────────

    func installOrUpdateProfile(config: TunnelConfigDto, completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            do {
                // Build config JSON (authToken comes from Keychain in extension)
                let configDict: [String: Any] = [
                    "id": config.id, "name": config.name,
                    "serverHost": config.serverHost, "serverPort": config.serverPort,
                    "transportType": config.transportType,
                    "deviceId": config.deviceId, "mtu": config.mtu,
                    "dnsServers": config.dnsServers.compactMap { $0 },
                    "ipv4Address": config.ipv4Address, "ipv4SubnetMask": config.ipv4SubnetMask,
                    "allowedIPv4Routes": config.allowedIPv4Routes.compactMap { $0 },
                    "excludedIPv4Routes": config.excludedIPv4Routes.compactMap { $0 },
                    "keepAliveSeconds": config.keepAliveSeconds, "workers": config.workers,
                    "sni": config.sni ?? "",
                    "enableUdp": config.enableUdp, "enableTcp": config.enableTcp,
                    "autoReconnect": config.autoReconnect,
                    "maxReconnectAttempts": config.maxReconnectAttempts,
                ]
                let data = try JSONSerialization.data(withJSONObject: configDict)
                let json = String(data: data, encoding: .utf8) ?? "{}"

                // Save authToken to Keychain if present
                if let token = config.authToken, !token.isEmpty {
                    KeychainHelper.shared.save(key: "authToken_\(config.id)", value: token)
                }

                try await VpnManager.shared.installOrUpdateProfile(
                    configJSON: json,
                    serverAddress: config.serverHost,
                    name: config.name
                )
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // ── startTunnel ───────────────────────────────────────────────────────

    func startTunnel(completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            do {
                try VpnManager.shared.startTunnel()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // ── stopTunnel ────────────────────────────────────────────────────────

    func stopTunnel(completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            VpnManager.shared.stopTunnel()
            completion(.success(()))
        }
    }

    // ── getStatus ─────────────────────────────────────────────────────────

    func getStatus(completion: @escaping (Result<TunnelStatusDto, Error>) -> Void) {
        Task { @MainActor in
            let status = VpnManager.shared.currentStatus
            let uptime = VpnManager.shared.uptimeSeconds.map { Int64($0) }

            // Read server/transport from shared container
            let configDict = readConfigDict()
            let host = configDict?["serverHost"] as? String
            let transport = configDict?["transportType"] as? String

            completion(.success(TunnelStatusDto(
                status: status.tunnelStatusString,
                lastError: nil,
                serverHost: host,
                transportType: transport,
                uptimeSeconds: uptime
            )))
        }
    }

    // ── getStats ──────────────────────────────────────────────────────────

    func getStats(completion: @escaping (Result<TrafficStatsDto, Error>) -> Void) {
        Task {
            if let data = try? VpnManager.shared.readSharedFile(VpnConstants.statsKey),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                completion(.success(TrafficStatsDto(
                    bytesIn:      Int64(dict["bytesIn"] as? Int ?? 0),
                    bytesOut:     Int64(dict["bytesOut"] as? Int ?? 0),
                    packetsIn:    Int64(dict["packetsIn"] as? Int ?? 0),
                    packetsOut:   Int64(dict["packetsOut"] as? Int ?? 0),
                    activeStreams: Int64(dict["activeStreams"] as? Int ?? 0),
                    updatedAtMs:  Int64(Date().timeIntervalSince1970 * 1000)
                )))
            } else {
                completion(.success(TrafficStatsDto(
                    bytesIn: 0, bytesOut: 0, packetsIn: 0, packetsOut: 0,
                    activeStreams: 0,
                    updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000))))
            }
        }
    }

    // ── getLogs ───────────────────────────────────────────────────────────

    func getLogs(completion: @escaping (Result<[LogEntryDto?], Error>) -> Void) {
        Task {
            guard let data = try? VpnManager.shared.readSharedFile(VpnConstants.logsKey) else {
                completion(.success([])); return
            }
            let lines = String(data: data, encoding: .utf8)?
                .split(separator: "\n", omittingEmptySubsequences: true) ?? []
            var entries: [LogEntryDto?] = []
            for line in lines {
                if let dict = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                    entries.append(LogEntryDto(
                        id:          dict["id"] as? String ?? UUID().uuidString,
                        timestampMs: Int64(dict["timestampMs"] as? Int ?? 0),
                        level:       dict["level"] as? String ?? "info",
                        category:    dict["category"] as? String ?? "extension",
                        message:     dict["message"] as? String ?? "",
                        repeatCount: Int64(dict["repeatCount"] as? Int ?? 1)
                    ))
                }
            }
            completion(.success(entries))
        }
    }

    // ── clearLogs ─────────────────────────────────────────────────────────

    func clearLogs(completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            try? VpnManager.shared.writeSharedFile(VpnConstants.logsKey, data: Data())
            completion(.success(()))
        }
    }

    // ── getDiagnostics ────────────────────────────────────────────────────

    func getDiagnostics(completion: @escaping (Result<DiagnosticsDto, Error>) -> Void) {
        Task { @MainActor in
            let bundle = Bundle.main
            let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build   = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            let bundleId = bundle.bundleIdentifier ?? "unknown"
            let device   = UIDevice.current
            let osVersion = "\(device.systemName) \(device.systemVersion)"
            let model     = device.model

            let vpnStatus  = VpnManager.shared.currentStatus
            let neStatus: String
            switch vpnStatus {
            case .invalid:       neStatus = "notInstalled"
            case .disconnected:  neStatus = "installed"
            case .connecting, .connected, .reasserting, .disconnecting: neStatus = "enabled"
            @unknown default:    neStatus = "unknown"
            }

            // Try to get Go client version from shared container
            let goVersion: String
            if let data = try? VpnManager.shared.readSharedFile("go_version.txt"),
               let v = String(data: data, encoding: .utf8) {
                goVersion = v.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                goVersion = "unavailable (build extension first)"
            }

            completion(.success(DiagnosticsDto(
                platform:                "ios",
                appVersion:              version,
                buildNumber:             build,
                osVersion:               osVersion,
                deviceModel:             model,
                vpnPermissionGranted:    vpnStatus != .invalid,
                networkExtensionStatus:  neStatus,
                runnerBundleId:          bundleId,
                extensionBundleId:       VpnConstants.extensionBundleId,
                appGroupId:              VpnConstants.appGroupId,
                goClientVersion:         goVersion,
                keychainAccessGroup:     VpnConstants.keychainAccessGroup
            )))
        }
    }

    // ── sendProviderMessage ───────────────────────────────────────────────

    func sendProviderMessage(type: String, payload: [String: Any?], completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            do {
                var msg: [String: Any] = ["type": type]
                for (k, v) in payload { if let v = v { msg[k] = v } }
                let data = try JSONSerialization.data(withJSONObject: msg)
                _ = try await VpnManager.shared.sendProviderMessage(data)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // ── Push helpers ──────────────────────────────────────────────────────

    @MainActor
    private func pushStatus(_ status: NEVPNStatus) {
        let configDict = readConfigDict()
        let map: [String: Any?] = [
            "status": status.tunnelStatusString,
            "lastError": nil,
            "serverHost": configDict?["serverHost"] as? String,
            "transportType": configDict?["transportType"] as? String,
            "uptimeSeconds": VpnManager.shared.uptimeSeconds,
        ]
        statusSink?(map)
    }

    private func startStatsTimer(sink: @escaping FlutterEventSink) -> Timer {
        statsSink = sink
        return Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                if let data = try? VpnManager.shared.readSharedFile(VpnConstants.statsKey),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let map: [String: Any] = [
                        "bytesIn":      dict["bytesIn"] ?? 0,
                        "bytesOut":     dict["bytesOut"] ?? 0,
                        "packetsIn":    dict["packetsIn"] ?? 0,
                        "packetsOut":   dict["packetsOut"] ?? 0,
                        "activeStreams": dict["activeStreams"] ?? 0,
                        "updatedAtMs":  Int(Date().timeIntervalSince1970 * 1000),
                    ]
                    DispatchQueue.main.async { self.statsSink?(map) }
                }
            }
        }
    }

    private func readConfigDict() -> [String: Any]? {
        guard let data = try? VpnManager.shared.readSharedFile(VpnConstants.configKey) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// ── EventStreamHandler helper ─────────────────────────────────────────────

private class EventStreamHandler: NSObject, FlutterStreamHandler {
    let onListen: (FlutterEventSink?) -> Void
    let onCancelAction: () -> Void

    init(onListen: @escaping (FlutterEventSink?) -> Void, cancel: @escaping () -> Void) {
        self.onListen = onListen
        self.onCancelAction = cancel
    }

    func onListen(withArguments args: Any?, eventSink sink: @escaping FlutterEventSink) -> FlutterError? {
        onListen(sink); return nil
    }
    func onCancel(withArguments args: Any?) -> FlutterError? {
        onCancelAction(); return nil
    }
}
