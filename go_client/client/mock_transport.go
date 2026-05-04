package client

import (
	"context"
	"errors"
	"sync"
	"time"
)

// MockTransport is a no-op transport for MVP / testing.
// It accepts packets, counts statistics, and echoes them back after a
// small simulated delay. No real network traffic is generated.
type MockTransport struct {
	mu      sync.Mutex
	stats   Stats
	log     *internalLogger
	cancel  context.CancelFunc
	packets chan []byte // inbound echo queue
}

func (t *MockTransport) Start(ctx context.Context, cfg Config, log *internalLogger) error {
	t.log = log
	t.packets = make(chan []byte, 256)
	t.stats.reset()

	cctx, cancel := context.WithCancel(ctx)
	t.cancel = cancel

	log.info("MockTransport", "started (host=%s port=%d mtu=%d)",
		cfg.ServerHost, cfg.ServerPort, cfg.MTU)

	// Simulate keepalive pings and dummy traffic
	go t.simulateTraffic(cctx, cfg)

	return nil
}

func (t *MockTransport) Stop() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.cancel != nil {
		t.cancel()
		t.cancel = nil
	}
	if t.log != nil {
		t.log.info("MockTransport", "stopped")
	}
	return nil
}

func (t *MockTransport) WritePacket(packet []byte, proto int) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.cancel == nil {
		return errors.New("mock transport not running")
	}
	size := int64(len(packet))
	t.stats.AddPacketsOut(1)
	t.stats.AddBytesOut(size)

	// Echo the packet back (simulates a loopback tunnel)
	select {
	case t.packets <- append([]byte(nil), packet...):
	default:
		// Drop if queue full
	}
	return nil
}

func (t *MockTransport) ReadPacket() ([]byte, int, error) {
	pkt, ok := <-t.packets
	if !ok {
		return nil, 0, errors.New("mock transport closed")
	}
	t.stats.AddPacketsIn(1)
	t.stats.AddBytesIn(int64(len(pkt)))
	return pkt, 4, nil
}

func (t *MockTransport) Stats() *Stats {
	return &t.stats
}

// simulateTraffic generates periodic dummy stat increments to give the
// dashboard some activity without real network I/O.
func (t *MockTransport) simulateTraffic(ctx context.Context, cfg Config) {
	ticker := time.NewTicker(time.Duration(cfg.KeepAliveSeconds) * time.Second)
	defer ticker.Stop()
	t.stats.SetActiveStreams(1)

	for {
		select {
		case <-ctx.Done():
			t.stats.SetActiveStreams(0)
			close(t.packets)
			return
		case <-ticker.C:
			// Simulate keepalive packet exchange
			dummy := make([]byte, 40) // small ICMP-like packet size
			t.stats.AddBytesOut(int64(len(dummy)))
			t.stats.AddPacketsOut(1)
			t.stats.AddBytesIn(int64(len(dummy)))
			t.stats.AddPacketsIn(1)
			if t.log != nil {
				t.log.debug("MockTransport", "keepalive ping (%d bytes)", len(dummy))
			}
		}
	}
}
