package client

import "context"

// Transport is the internal interface each transport implementation must satisfy.
// NOT exported via gomobile directly — the public API is on Client.
type Transport interface {
	// Start initialises the transport and begins processing.
	Start(ctx context.Context, cfg Config, log *internalLogger) error

	// Stop tears down the transport gracefully.
	Stop() error

	// WritePacket sends an outbound IP packet to the remote server.
	// proto: 4 = IPv4, 6 = IPv6
	WritePacket(packet []byte, proto int) error

	// ReadPacket returns the next inbound IP packet from the remote server.
	// Blocks until a packet is available or the context is cancelled.
	// Returns (data, proto, error).
	ReadPacket() ([]byte, int, error)

	// Stats returns current traffic statistics.
	Stats() *Stats
}

// newTransport creates the appropriate Transport for the given type string.
func newTransport(transportType string) (Transport, error) {
	switch transportType {
	case "mock", "":
		return &MockTransport{}, nil
	case "socksKcpSmux":
		return &SocksKcpSmuxTransport{}, nil
	case "wireguard":
		return &WireGuardTransport{}, nil
	case "custom":
		// TODO: plug in your custom transport here
		return &MockTransport{}, nil
	default:
		// Fallback to mock to keep the app usable
		return &MockTransport{}, nil
	}
}
