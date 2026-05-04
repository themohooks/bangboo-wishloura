package client

import (
	"context"
	"errors"
	"time"
)

// WireGuardTransport is a clean adapter stub for WireGuard integration.
//
// # Architecture (production)
//
// There are two recommended approaches:
//
//  1. Pure Go via wireguard-go (golang.zx2c4.com/wireguard):
//     - Embed the wireguard-go device/tun package directly in this Go module.
//     - Create a wireguard-go Device with a virtual TUN interface.
//     - Feed packets from the OS TUN fd to the Device.
//     - Feed packets from the Device to the OS TUN fd.
//     - Configure peers, allowed IPs, private key, public key from cfg fields.
//
//  2. Platform-native WireGuard (recommended for iOS):
//     - On iOS:  use WireGuardKit (Apple Network Extension framework).
//                The Go client is NOT responsible for the WireGuard data plane.
//                Configure the WireGuard tunnel via NEPacketTunnelNetworkSettings.
//     - On Android: use the WireGuard Android library or wireguard-go GoBackend.
//
// # How to complete this transport
//
// TODO(production):
//  1. Decide on approach: embedded wireguard-go or platform-native.
//  2. For embedded wireguard-go:
//     a. Import golang.zx2c4.com/wireguard (Apache-2.0 licensed).
//     b. Add WireGuard-specific fields to Config (privateKey, peerPublicKey,
//        presharedKey, endpoint, allowedIPs, persistentKeepalive).
//     c. Create a wireguard.Device from a virtual TUN.
//     d. Route packets through WritePacket / ReadPacket.
//  3. For platform-native:
//     a. Leave this stub returning ErrUseNativePlatform.
//     b. Handle in Kotlin (GoClientBridge.kt) and Swift (GoClientBridge.swift).
//
// IMPORTANT:
//   - Do NOT use any hardcoded WireGuard endpoints or peers.
//   - All server details come from cfg.ServerHost / cfg.ServerPort and user config.
//   - The WireGuard private key MUST be generated locally and NEVER logged.
type WireGuardTransport struct {
	stats  Stats
	log    *internalLogger
	cancel context.CancelFunc
}

var ErrUseNativePlatform = errors.New(
	"WireGuardTransport: use platform-native WireGuard — " +
		"see ios/PacketTunnel/GoClientBridge.swift and " +
		"android/vpnplugin/.../GoClientBridge.kt",
)

func (t *WireGuardTransport) Start(ctx context.Context, cfg Config, log *internalLogger) error {
	t.log = log
	t.stats.reset()
	_, cancel := context.WithCancel(ctx)
	t.cancel = cancel

	log.info("WireGuard", "transport stub started")
	log.warning("WireGuard",
		"TODO: implement production WireGuard in wireguard_transport.go")

	// TODO(production): replace with wireguard-go or return ErrUseNativePlatform
	return errors.New("WireGuardTransport: not yet implemented — see TODO in wireguard_transport.go")
}

func (t *WireGuardTransport) Stop() error {
	if t.cancel != nil {
		t.cancel()
		t.cancel = nil
	}
	if t.log != nil {
		t.log.info("WireGuard", "transport stopped")
	}
	return nil
}

func (t *WireGuardTransport) WritePacket(packet []byte, proto int) error {
	// TODO(production): inject into wireguard-go Device.InboundChannel
	return errors.New("WireGuardTransport: not implemented")
}

func (t *WireGuardTransport) ReadPacket() ([]byte, int, error) {
	// TODO(production): read from wireguard-go Device.OutboundChannel
	time.Sleep(time.Second)
	return nil, 0, errors.New("WireGuardTransport: not implemented")
}

func (t *WireGuardTransport) Stats() *Stats {
	return &t.stats
}

// ─────────────────────────────────────────────────────────────────────────────
// Production implementation checklist (wireguard-go approach):
//
//  [ ] Add to go.mod: golang.zx2c4.com/wireguard
//  [ ] Extend Config with WireGuard-specific fields:
//        PrivateKey       string (base64)
//        PeerPublicKey    string (base64)
//        PresharedKey     string (base64, optional)
//        PersistentKeepalive int
//  [ ] Create tun.CreateTUN or use a virtual TUN pipe
//  [ ] Create wireguard.NewDevice(tun, conn.NewDefaultBind(), logger)
//  [ ] device.IpcSet(wgQuickConf) to configure peer
//  [ ] device.Up()
//  [ ] WritePacket -> write to tun inbound
//  [ ] ReadPacket  <- read from tun outbound
//  [ ] device.Down() in Stop()
//  [ ] Stats via tun read/write counters
//  [ ] NEVER log private keys or preshared keys
// ─────────────────────────────────────────────────────────────────────────────
