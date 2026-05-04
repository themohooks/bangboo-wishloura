package client

import (
	"context"
	"errors"
	"time"
)

// SocksKcpSmuxTransport is a clean adapter stub for a SOCKS5+KCP+SMUX transport.
//
// # Architecture (production)
//
// This transport connects to a user-owned server that speaks:
//   - KCP (reliable UDP) as the underlying reliable layer
//   - SMUX (stream multiplexer) on top of KCP
//   - SOCKS5 (or a custom framing protocol) for application-layer routing
//
// # How to complete this transport
//
// TODO(production):
//  1. Import a KCP library (e.g. github.com/xtaci/kcp-go) and a SMUX library
//     (e.g. github.com/xtaci/smux) — ensure their licenses are compatible.
//  2. In Start(), dial cfg.ServerHost:cfg.ServerPort over UDP/KCP.
//  3. Wrap the KCP connection with SMUX.
//  4. Open worker streams (cfg.Workers) for multiplexed packet channels.
//  5. Authenticate with cfg.AuthToken.
//  6. In WritePacket(), write an IP packet frame to a SMUX stream.
//  7. In ReadPacket(), read from the SMUX read loop.
//  8. Implement keepalive (cfg.KeepAliveSeconds), reconnect, and backoff.
//  9. Report stats via t.stats.
//
// IMPORTANT:
//   - Do NOT hard-code any relay/TURN/third-party server addresses.
//   - The server address comes exclusively from cfg.ServerHost / cfg.ServerPort.
//   - Never phone home, never download or execute remote code.
//   - All traffic goes to the user's own server.
type SocksKcpSmuxTransport struct {
	stats  Stats
	log    *internalLogger
	cancel context.CancelFunc
}

func (t *SocksKcpSmuxTransport) Start(ctx context.Context, cfg Config, log *internalLogger) error {
	t.log = log
	t.stats.reset()
	_, cancel := context.WithCancel(ctx)
	t.cancel = cancel

	log.info("SocksKcpSmux", "transport stub started — connect to %s:%d", cfg.ServerHost, cfg.ServerPort)
	log.warning("SocksKcpSmux",
		"TODO: implement production KCP+SMUX dial in socks_kcp_smux_transport.go")

	// TODO(production): replace with real dial logic
	return errors.New("SocksKcpSmuxTransport: not yet implemented — see TODO in socks_kcp_smux_transport.go")
}

func (t *SocksKcpSmuxTransport) Stop() error {
	if t.cancel != nil {
		t.cancel()
		t.cancel = nil
	}
	if t.log != nil {
		t.log.info("SocksKcpSmux", "transport stopped")
	}
	return nil
}

func (t *SocksKcpSmuxTransport) WritePacket(packet []byte, proto int) error {
	// TODO(production): write framed IP packet to a SMUX stream
	return errors.New("SocksKcpSmuxTransport: not implemented")
}

func (t *SocksKcpSmuxTransport) ReadPacket() ([]byte, int, error) {
	// TODO(production): read framed IP packet from the SMUX read loop
	// Block until available; return (pkt, proto, nil) on success.
	time.Sleep(time.Second) // prevent busy-loop in stub
	return nil, 0, errors.New("SocksKcpSmuxTransport: not implemented")
}

func (t *SocksKcpSmuxTransport) Stats() *Stats {
	return &t.stats
}

// ─────────────────────────────────────────────────────────────────────────────
// Production implementation checklist:
//
//  [ ] Dial UDP/KCP to cfg.ServerHost:cfg.ServerPort
//  [ ] TLS / DTLS wrapping (optional, use cfg.SNI for SNI)
//  [ ] SMUX session over KCP conn
//  [ ] Auth handshake with cfg.AuthToken (HMAC or similar)
//  [ ] cfg.Workers parallel SMUX streams for packet forwarding
//  [ ] cfg.EnableUDP / cfg.EnableTCP routing flags
//  [ ] Keepalive goroutine (cfg.KeepAliveSeconds)
//  [ ] Reconnect loop with exponential backoff (cfg.AutoReconnect, cfg.MaxReconnectAttempts)
//  [ ] Stats: AddBytesIn/Out, AddPacketsIn/Out, SetActiveStreams
//  [ ] Route IPv4 packets based on cfg.AllowedIPv4Routes / cfg.ExcludedIPv4Routes
// ─────────────────────────────────────────────────────────────────────────────
