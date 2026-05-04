import Foundation
import NetworkExtension

/// Bridges NEPacketTunnelFlow ↔ GoClientBridge.
///
/// Two async loops:
///   1. flowToGo  — reads packets from NEPacketTunnelFlow → GoClientBridge.writePacket
///   2. goToFlow  — GoClientBridge.readPacket → writes to NEPacketTunnelFlow
///
/// Both loops run on dedicated DispatchQueues and stop when stop() is called.
class PacketFlowBridge {

    private let packetFlow: NEPacketTunnelFlow
    private let goBridge: GoClientBridge
    private let logger: TunnelLogger

    private let writeQueue = DispatchQueue(
        label: "com.example.flutterVpnGo.PacketFlow.write", qos: .userInitiated)
    private let readQueue = DispatchQueue(
        label: "com.example.flutterVpnGo.PacketFlow.read",  qos: .userInitiated)

    private var running = false

    init(packetFlow: NEPacketTunnelFlow, goBridge: GoClientBridge, logger: TunnelLogger) {
        self.packetFlow = packetFlow
        self.goBridge = goBridge
        self.logger = logger
    }

    // ── Start ──────────────────────────────────────────────────────────────

    func start() {
        running = true
        writeQueue.async { self.flowToGoLoop() }
        readQueue.async  { self.goToFlowLoop()  }
        logger.info("PacketFlow", "bridge started")
    }

    // ── Stop ───────────────────────────────────────────────────────────────

    func stop() {
        running = false
        logger.info("PacketFlow", "bridge stopped")
    }

    // ── Flow → Go ──────────────────────────────────────────────────────────

    private func flowToGoLoop() {
        logger.debug("PacketFlow", "flowToGoLoop started")
        while running {
            // readPackets is callback-based; we use a semaphore to serialize.
            let sem = DispatchSemaphore(value: 0)
            packetFlow.readPackets { [weak self] packets, protocols in
                guard let self = self, self.running else { sem.signal(); return }
                for (i, packet) in packets.enumerated() {
                    let af = protocols[i].int32Value  // AF_INET=2, AF_INET6=30
                    let proto = (af == 30) ? 6 : 4
                    do {
                        try self.goBridge.writePacket(packet, proto: proto)
                    } catch {
                        self.logger.error("PacketFlow", "writePacket error: \(error.localizedDescription)")
                    }
                }
                sem.signal()
            }
            sem.wait()
        }
        logger.debug("PacketFlow", "flowToGoLoop ended")
    }

    // ── Go → Flow ──────────────────────────────────────────────────────────

    private func goToFlowLoop() {
        logger.debug("PacketFlow", "goToFlowLoop started")
        while running {
            do {
                let packet = try goBridge.readPacket()
                guard !packet.isEmpty else { continue }

                // Determine IP version from first nibble to set the AF number
                let version = (packet[0] & 0xF0) >> 4
                let af = NSNumber(value: version == 6 ? AF_INET6 : AF_INET)

                packetFlow.writePackets([packet], withProtocols: [af])
            } catch {
                if running {
                    logger.error("PacketFlow", "readPacket error: \(error.localizedDescription)")
                    // Small back-off to avoid busy-loop on persistent errors
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
        logger.debug("PacketFlow", "goToFlowLoop ended")
    }
}
