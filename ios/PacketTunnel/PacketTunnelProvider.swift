import Foundation
import NetworkExtension

/// NEPacketTunnelProvider — runs in the Packet Tunnel Extension process.
///
/// This is entirely separate from the Flutter app process.
/// Communication with the Runner happens via:
///   - Shared App Group container (config.json, stats.json, logs.jsonl)
///   - Keychain Sharing (auth token)
///   - NEVPNStatus notifications (system-level)
///   - NETunnelProviderSession.sendProviderMessage (IPC)
///
/// The Go client (GoClientBridge) is loaded directly inside this extension.
class PacketTunnelProvider: NEPacketTunnelProvider {

    // ── Dependencies ──────────────────────────────────────────────────────

    private lazy var logger = TunnelLogger(appGroupId: appGroupId)
    private lazy var configLoader = TunnelConfigLoader(appGroupId: appGroupId)
    private var goBridge: GoClientBridge?
    private var packetBridge: PacketFlowBridge?
    private var statsTimer: Timer?

    private var appGroupId: String {
        // Read from Info.plist of the extension target (set in build settings)
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
            ?? "group.com.example.flutterVpnGo"
    }

    // ── startTunnel ────────────────────────────────────────────────────────

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        logger.info("PacketTunnel", "startTunnel called")

        do {
            // 1. Load config from shared container
            var configJSON = try configLoader.loadConfigJSON()
            let configDict = try configLoader.loadConfigDict()

            // 2. Merge auth token from Keychain
            let configId = configDict["id"] as? String ?? ""
            if let token = configLoader.loadAuthToken(configId: configId), !token.isEmpty {
                if var dict = try? JSONSerialization.jsonObject(with: Data(configJSON.utf8)) as? [String: Any] {
                    dict["authToken"] = token
                    if let merged = try? JSONSerialization.data(withJSONObject: dict),
                       let mergedStr = String(data: merged, encoding: .utf8) {
                        configJSON = mergedStr
                    }
                }
            }

            // 3. Build NEPacketTunnelNetworkSettings
            let settings = try buildNetworkSettings(config: configDict)

            // 4. Apply settings (async, then start Go client)
            setTunnelNetworkSettings(settings) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.logger.error("PacketTunnel", "setTunnelNetworkSettings failed: \(error.localizedDescription)")
                    completionHandler(error)
                    return
                }

                do {
                    // 5. Start Go client
                    let bridge = GoClientBridge()
                    let loggerBridge = GoLoggerBridge(tunnelLogger: self.logger)
                    bridge.setLogger(loggerBridge)
                    try bridge.start(configJSON: configJSON)
                    self.goBridge = bridge

                    // 6. Start packet flow bridge
                    let pb = PacketFlowBridge(
                        packetFlow: self.packetFlow,
                        goBridge: bridge,
                        logger: self.logger
                    )
                    pb.start()
                    self.packetBridge = pb

                    // 7. Write Go version for diagnostics
                    let versionData = Data(bridge.version().utf8)
                    try? self.configLoader.writeStats([:])  // init stats file
                    if let containerURL = FileManager.default
                        .containerURL(forSecurityApplicationGroupIdentifier: self.appGroupId) {
                        try? versionData.write(
                            to: containerURL.appendingPathComponent("go_version.txt"))
                    }

                    // 8. Start stats flush timer
                    self.startStatsTimer()

                    self.logger.info("PacketTunnel", "tunnel started successfully")
                    completionHandler(nil)

                } catch {
                    self.logger.error("PacketTunnel", "Go client start failed: \(error.localizedDescription)")
                    completionHandler(error)
                }
            }

        } catch {
            logger.error("PacketTunnel", "startTunnel error: \(error.localizedDescription)")
            completionHandler(error)
        }
    }

    // ── stopTunnel ─────────────────────────────────────────────────────────

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("PacketTunnel", "stopTunnel called — reason: \(reason.rawValue)")

        statsTimer?.invalidate()
        statsTimer = nil

        packetBridge?.stop()
        packetBridge = nil

        goBridge?.stop()
        goBridge = nil

        configLoader.writeStatus(["status": "disconnected"])
        completionHandler()
    }

    // ── handleAppMessage (IPC) ─────────────────────────────────────────────

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let dict = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let type = dict["type"] as? String else {
            completionHandler?(nil); return
        }
        logger.debug("PacketTunnel", "handleAppMessage: type=\(type)")

        switch type {
        case "getStats":
            let statsJSON = goBridge?.statsJSON() ?? "{}"
            completionHandler?(Data(statsJSON.utf8))
        case "getStatus":
            let status = goBridge?.status() ?? "disconnected"
            let resp = try? JSONSerialization.data(withJSONObject: ["status": status])
            completionHandler?(resp)
        default:
            completionHandler?(nil)
        }
    }

    // ── sleep / wake ───────────────────────────────────────────────────────

    override func sleep(completionHandler: @escaping () -> Void) {
        logger.debug("PacketTunnel", "sleep")
        completionHandler()
    }

    override func wake() {
        logger.debug("PacketTunnel", "wake")
    }

    // ── Network settings builder ───────────────────────────────────────────

    private func buildNetworkSettings(config: [String: Any]) throws -> NEPacketTunnelNetworkSettings {
        guard let serverAddress = config["serverHost"] as? String else {
            throw TunnelConfigError.parseError("serverHost missing")
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverAddress)

        // IPv4
        let ipv4Address   = config["ipv4Address"]    as? String ?? "10.7.0.2"
        let subnetMask    = config["ipv4SubnetMask"] as? String ?? "255.255.255.0"

        let ipv4Settings = NEIPv4Settings(addresses: [ipv4Address], subnetMasks: [subnetMask])

        // Routes
        var includedRoutes: [NEIPv4Route] = []
        if let allowed = config["allowedIPv4Routes"] as? [String] {
            for cidr in allowed {
                if let route = parseRoute(cidr) { includedRoutes.append(route) }
            }
        }
        if includedRoutes.isEmpty {
            includedRoutes = [NEIPv4Route.default()]
        }
        ipv4Settings.includedRoutes = includedRoutes

        if let excluded = config["excludedIPv4Routes"] as? [String] {
            ipv4Settings.excludedRoutes = excluded.compactMap { parseRoute($0) }
        }
        settings.ipv4Settings = ipv4Settings

        // DNS
        let dnsServers = (config["dnsServers"] as? [String]) ?? ["1.1.1.1", "8.8.8.8"]
        settings.dnsSettings = NEDNSSettings(servers: dnsServers)

        // MTU
        let mtu = config["mtu"] as? Int ?? 1280
        settings.mtu = NSNumber(value: mtu)

        return settings
    }

    private func parseRoute(_ cidr: String) -> NEIPv4Route? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32 else { return nil }
        let mask = prefixToMask(prefix)
        return NEIPv4Route(destinationAddress: String(parts[0]), subnetMask: mask)
    }

    private func prefixToMask(_ prefix: Int) -> String {
        var mask: UInt32 = prefix == 0 ? 0 : (~UInt32(0)) << (32 - prefix)
        let bytes = [
            UInt8((mask >> 24) & 0xFF),
            UInt8((mask >> 16) & 0xFF),
            UInt8((mask >>  8) & 0xFF),
            UInt8( mask        & 0xFF),
        ]
        return bytes.map { "\($0)" }.joined(separator: ".")
    }

    // ── Stats timer ────────────────────────────────────────────────────────

    private func startStatsTimer() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, let goBridge = self.goBridge else { return }
            let statsJSON = goBridge.statsJSON()
            if let data = statsJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.configLoader.writeStats(dict)
            }
        }
    }
}
