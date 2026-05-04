// Package client provides the VPN client core.
//
// TWO build modes:
//
// 1. Android — ELF executable (placed in jniLibs as libclient.so):
//
//	cd go_client
//	./build_android_so.sh
//	# Communicates via stdin/stdout text protocol (same as original wdtt project)
//
// 2. iOS — gomobile XCFramework:
//
//	cd go_client
//	./build_ios.sh
//	# Communicates via direct function calls (gomobile JNI bridge)
//
// STDIN protocol (Android process mode):
//
//	"PAUSE\n"              → pause transport (network lost)
//	"RESUME\n"             → resume transport (network restored)
//	"STOP\n"               → graceful shutdown
//
// STDOUT protocol (Android process mode):
//
//	"[СТАТИСТИКА] Активных: N, Bytes↑ X, Bytes↓ Y\n"
//	"╔══ WireGuard Конфиг ══╗\n║ <config line>\n╚══╝\n"
//
// gomobile public API constraints:
//   - No generics in exported types/functions.
//   - Config passed as JSON string to avoid gomobile slice limitations.
package client

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const version = "1.0.0-mock"

// Version returns the Go client version string.
func Version() string { return version }

// ─────────────────────────────────────────────────────────────────────────────
// Status constants — match Flutter TunnelStatus enum
// ─────────────────────────────────────────────────────────────────────────────

const (
	StatusDisconnected  = "disconnected"
	StatusPreparing     = "preparing"
	StatusConnecting    = "connecting"
	StatusConnected     = "connected"
	StatusReconnecting  = "reconnecting"
	StatusDisconnecting = "disconnecting"
	StatusFailed        = "failed"
)

// ─────────────────────────────────────────────────────────────────────────────
// Client — gomobile-compatible API (used on iOS via XCFramework)
// ─────────────────────────────────────────────────────────────────────────────

// Client is the main gomobile-exported VPN client (iOS path).
// On Android the process-based Main() function is used instead.
type Client struct {
	mu        sync.Mutex
	transport Transport
	log       *internalLogger
	status    string
	cfg       Config
	cancel    context.CancelFunc
	wg        sync.WaitGroup

	reconnectAttempt int
}

// NewClient creates a new Client instance with noop logger.
func NewClient() *Client {
	return &Client{
		status: StatusDisconnected,
		log:    newInternalLogger(nil),
	}
}

// SetLogger sets the logger callback. Call before Start().
func (c *Client) SetLogger(logger Logger) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.log = newInternalLogger(logger)
}

// Start initialises the transport and begins the VPN session.
// configJSON is the full TunnelConfig JSON produced by Flutter.
func (c *Client) Start(configJSON string) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.cancel != nil {
		return fmt.Errorf("client already running; call Stop() first")
	}

	cfg, err := ParseConfig(configJSON)
	if err != nil {
		c.log.error("Client", "invalid config: %v", err)
		c.status = StatusFailed
		return err
	}
	c.cfg = cfg

	transport, err := newTransport(cfg.TransportType)
	if err != nil {
		c.log.error("Client", "failed to create transport: %v", err)
		c.status = StatusFailed
		return err
	}
	c.transport = transport
	c.reconnectAttempt = 0

	ctx, cancel := context.WithCancel(context.Background())
	c.cancel = cancel
	c.status = StatusConnecting

	c.wg.Add(1)
	go c.runSession(ctx)
	return nil
}

// Stop tears down the active VPN session.
func (c *Client) Stop() error {
	c.mu.Lock()
	cancel := c.cancel
	c.cancel = nil
	c.status = StatusDisconnecting
	c.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	c.wg.Wait()

	c.mu.Lock()
	c.status = StatusDisconnected
	c.transport = nil
	c.mu.Unlock()

	c.log.info("Client", "stopped")
	return nil
}

// WritePacket sends an outbound IP packet to the transport.
// proto: 4 = IPv4, 6 = IPv6.
func (c *Client) WritePacket(packet []byte, proto int) error {
	c.mu.Lock()
	t := c.transport
	c.mu.Unlock()
	if t == nil {
		return fmt.Errorf("no active transport")
	}
	return t.WritePacket(packet, proto)
}

// ReadPacket blocks and returns the next inbound IP packet from the transport.
func (c *Client) ReadPacket() ([]byte, error) {
	c.mu.Lock()
	t := c.transport
	c.mu.Unlock()
	if t == nil {
		return nil, fmt.Errorf("no active transport")
	}
	pkt, _, err := t.ReadPacket()
	return pkt, err
}

// StatsJSON returns current traffic statistics as a JSON string.
func (c *Client) StatsJSON() string {
	c.mu.Lock()
	t := c.transport
	c.mu.Unlock()
	if t == nil {
		return `{"bytesIn":0,"bytesOut":0,"packetsIn":0,"packetsOut":0,"activeStreams":0}`
	}
	return t.Stats().toJSON()
}

// Status returns the current status string.
func (c *Client) Status() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.status
}

// ConfigSummaryJSON returns a diagnostics-safe config summary (no secrets).
func (c *Client) ConfigSummaryJSON() string {
	c.mu.Lock()
	cfg := c.cfg
	c.mu.Unlock()
	masked := map[string]interface{}{
		"serverHost":    cfg.ServerHost,
		"serverPort":    cfg.ServerPort,
		"transportType": cfg.TransportType,
		"mtu":           cfg.MTU,
		"workers":       cfg.Workers,
		"authToken":     maskSecret(cfg.AuthToken),
	}
	b, _ := json.Marshal(masked)
	return string(b)
}

func maskSecret(s string) string {
	if len(s) <= 8 {
		return "****"
	}
	return s[:4] + "********" + s[len(s)-4:]
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal session runner (iOS gomobile path)
// ─────────────────────────────────────────────────────────────────────────────

func (c *Client) runSession(ctx context.Context) {
	defer c.wg.Done()

	c.log.info("Client", "session starting — transport=%s server=%s:%d",
		c.cfg.TransportType, c.cfg.ServerHost, c.cfg.ServerPort)

	if err := c.transport.Start(ctx, c.cfg, c.log); err != nil {
		c.log.error("Client", "transport start failed: %v", err)
		c.handleTransportError(ctx, err)
		return
	}

	c.mu.Lock()
	c.status = StatusConnected
	c.reconnectAttempt = 0
	c.mu.Unlock()

	c.log.info("Client", "connected")
	<-ctx.Done()

	c.mu.Lock()
	t := c.transport
	c.mu.Unlock()
	if t != nil {
		_ = t.Stop()
	}
	c.log.info("Client", "session ended")
}

func (c *Client) handleTransportError(ctx context.Context, _ error) {
	c.mu.Lock()
	cfg := c.cfg
	c.mu.Unlock()

	if !cfg.AutoReconnect {
		c.mu.Lock()
		c.status = StatusFailed
		c.mu.Unlock()
		return
	}

	for {
		c.mu.Lock()
		attempt := c.reconnectAttempt
		c.reconnectAttempt++
		c.mu.Unlock()

		if attempt >= cfg.MaxReconnectAttempts {
			c.mu.Lock()
			c.status = StatusFailed
			c.mu.Unlock()
			c.log.error("Client", "max reconnect attempts (%d) reached", cfg.MaxReconnectAttempts)
			return
		}

		delay := time.Duration(1<<uint(attempt)) * time.Second
		c.mu.Lock()
		c.status = StatusReconnecting
		c.mu.Unlock()
		c.log.warning("Client", "reconnect attempt %d/%d in %v", attempt+1, cfg.MaxReconnectAttempts, delay)

		select {
		case <-ctx.Done():
			return
		case <-time.After(delay):
		}

		newT, err := newTransport(cfg.TransportType)
		if err != nil {
			continue
		}
		c.mu.Lock()
		c.transport = newT
		c.status = StatusConnecting
		c.mu.Unlock()

		if startErr := newT.Start(ctx, cfg, c.log); startErr != nil {
			c.log.error("Client", "reconnect attempt %d failed: %v", attempt+1, startErr)
			continue
		}

		c.mu.Lock()
		c.status = StatusConnected
		c.reconnectAttempt = 0
		c.mu.Unlock()
		c.log.info("Client", "reconnected on attempt %d", attempt+1)
		<-ctx.Done()
		_ = newT.Stop()
		return
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Main — Android process mode (libclient.so ELF entry point)
//
// Called when Android launches libclient.so via ProcessBuilder.
// Communicates with Kotlin via stdin/stdout text protocol.
// ─────────────────────────────────────────────────────────────────────────────

// processFlags holds parsed CLI flags for the Android process mode.
type processFlags struct {
	peer              string
	listenAddr        string
	workers           int
	transportType     string
	authToken         string
	deviceID          string
	sni               string
	enableUDP         bool
	enableTCP         bool
	autoReconnect     bool
	maxReconnects     int
	keepAlive         int
	mtu               int
	ipv4Address       string
	ipv4Mask          string
	allowedRoutes     []string
	excludedRoutes    []string
	dns               []string
	mock              bool
}

// androidMain is the entry point for the Android process-based execution.
// It is NOT called by gomobile on iOS — only by Main() below.
func androidMain(flags processFlags) {
	log := newInternalLogger(stdoutLogger{})

	// Resolve transport type
	ttype := flags.transportType
	if flags.mock || ttype == "" {
		ttype = "mock"
	}

	log.info("Main", "starting — transport=%s peer=%s workers=%d",
		ttype, flags.peer, flags.workers)

	// Build config from flags
	cfg := Config{
		ServerHost:           flags.peer,
		ServerPort:           0, // port embedded in peer string, parsed by transport
		TransportType:        ttype,
		AuthToken:            flags.authToken,
		DeviceID:             flags.deviceID,
		MTU:                  flags.mtu,
		DNSServers:           flags.dns,
		IPv4Address:          flags.ipv4Address,
		IPv4SubnetMask:       flags.ipv4Mask,
		AllowedIPv4Routes:    flags.allowedRoutes,
		ExcludedIPv4Routes:   flags.excludedRoutes,
		KeepAliveSeconds:     flags.keepAlive,
		Workers:              flags.workers,
		SNI:                  flags.sni,
		EnableUDP:            flags.enableUDP,
		EnableTCP:            flags.enableTCP,
		AutoReconnect:        flags.autoReconnect,
		MaxReconnectAttempts: flags.maxReconnects,
	}
	if err := cfg.validate(); err != nil {
		log.error("Main", "config validation: %v", err)
		os.Exit(1)
	}

	// Pause/resume atomic flag — set by stdin PAUSE/RESUME commands
	var pausedFlag atomic.Int32

	ctx, cancelMain := context.WithCancel(context.Background())
	defer cancelMain()

	// ── stdin command reader ─────────────────────────────────────────────────
	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			cmd := strings.TrimSpace(scanner.Text())
			switch cmd {
			case "PAUSE":
				pausedFlag.Store(1)
				log.info("Main", "PAUSED (network lost)")
			case "RESUME":
				pausedFlag.Store(0)
				log.info("Main", "RESUMED (network restored)")
			case "STOP":
				log.info("Main", "STOP received — exiting")
				cancelMain()
				return
			}
		}
		// stdin closed → stop
		cancelMain()
	}()

	// ── transport + session ──────────────────────────────────────────────────
	var activeWorkers atomic.Int32
	var reconnectAttempt int

	for {
		select {
		case <-ctx.Done():
			log.info("Main", "shutdown complete")
			return
		default:
		}

		// Wait while paused
		for pausedFlag.Load() != 0 {
			select {
			case <-ctx.Done():
				return
			case <-time.After(500 * time.Millisecond):
			}
		}

		transport, err := newTransport(cfg.TransportType)
		if err != nil {
			log.error("Main", "create transport: %v", err)
			time.Sleep(2 * time.Second)
			continue
		}

		log.info("Main", "connecting attempt %d", reconnectAttempt+1)
		activeWorkers.Store(int32(cfg.Workers))
		printStats(transport, int(activeWorkers.Load()))

		startErr := transport.Start(ctx, cfg, log)
		if startErr != nil {
			log.error("Main", "transport start error: %v", startErr)
			activeWorkers.Store(0)
			printStats(transport, 0)

			if !cfg.AutoReconnect || reconnectAttempt >= cfg.MaxReconnectAttempts {
				log.error("Main", "giving up after %d reconnects", reconnectAttempt)
				return
			}

			delay := time.Duration(1<<uint(reconnectAttempt)) * time.Second
			if delay > 30*time.Second {
				delay = 30 * time.Second
			}
			log.warning("Main", "reconnect in %v (attempt %d/%d)",
				delay, reconnectAttempt+1, cfg.MaxReconnectAttempts)
			reconnectAttempt++

			select {
			case <-ctx.Done():
				return
			case <-time.After(delay):
			}
			continue
		}

		reconnectAttempt = 0
		log.info("Main", "transport connected")

		// ── WireGuard config delivery (via stdout framed block) ─────────────
		// MockTransport does not produce a real WireGuard config.
		// Production transports should call printWireGuardConfig(configStr)
		// after receiving the config from the server via GETCONF protocol.
		if cfg.TransportType == "mock" {
			// Print a placeholder config so Kotlin can parse and bring up WG tunnel.
			printMockWireGuardConfig(cfg, log)
		}

		// ── Stats ticker ─────────────────────────────────────────────────────
		statsTicker := time.NewTicker(3 * time.Second)
		statsDone := make(chan struct{})
		go func() {
			defer close(statsDone)
			for {
				select {
				case <-ctx.Done():
					return
				case <-statsTicker.C:
					if pausedFlag.Load() == 0 {
						printStats(transport, int(activeWorkers.Load()))
					}
				}
			}
		}()

		<-ctx.Done()
		statsTicker.Stop()
		<-statsDone
		_ = transport.Stop()
		log.info("Main", "transport stopped")
		return
	}
}

// Main is called when the Go binary is executed as a process (Android path).
// Flag parsing is done here so gomobile does not see any `flag` package init.
//
// Usage (from ProcessBuilder in Kotlin):
//
//	libclient.so -peer host:port -n 12 -listen 127.0.0.1:9000
//	             [-password token] [-device-id id] [-sni host]
//	             [-udp|-tcp] [-mock] [-mtu 1280] ...
func Main() {
	flags := parseOSArgs()
	androidMain(flags)
}

// parseOSArgs parses os.Args manually (no flag package — avoids init() conflicts with gomobile).
func parseOSArgs() processFlags {
	f := processFlags{
		workers:       12,
		listenAddr:    "127.0.0.1:9000",
		mtu:           1280,
		keepAlive:     25,
		maxReconnects: 5,
		autoReconnect: true,
		enableUDP:     true,
		dns:           []string{"1.1.1.1", "8.8.8.8"},
		ipv4Address:   "10.7.0.2",
		ipv4Mask:      "255.255.255.0",
		allowedRoutes: []string{"0.0.0.0/0"},
	}
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		arg := args[i]
		val := func() string {
			if i+1 < len(args) {
				i++
				return args[i]
			}
			return ""
		}
		switch arg {
		case "-peer":
			f.peer = val()
		case "-listen":
			f.listenAddr = val()
		case "-n":
			if v := val(); v != "" {
				fmt.Sscanf(v, "%d", &f.workers)
			}
		case "-transport":
			f.transportType = val()
		case "-password":
			f.authToken = val()
		case "-device-id":
			f.deviceID = val()
		case "-sni":
			f.sni = val()
		case "-mtu":
			if v := val(); v != "" {
				fmt.Sscanf(v, "%d", &f.mtu)
			}
		case "-keepalive":
			if v := val(); v != "" {
				fmt.Sscanf(v, "%d", &f.keepAlive)
			}
		case "-reconnects":
			if v := val(); v != "" {
				fmt.Sscanf(v, "%d", &f.maxReconnects)
			}
		case "-dns":
			if v := val(); v != "" {
				f.dns = strings.Split(v, ",")
			}
		case "-ipv4":
			f.ipv4Address = val()
		case "-mask":
			f.ipv4Mask = val()
		case "-allow":
			if v := val(); v != "" {
				f.allowedRoutes = strings.Split(v, ",")
			}
		case "-exclude":
			if v := val(); v != "" {
				f.excludedRoutes = strings.Split(v, ",")
			}
		case "-udp":
			f.enableUDP = true
			f.enableTCP = false
		case "-tcp":
			f.enableTCP = true
			f.enableUDP = false
		case "-mock":
			f.mock = true
			f.transportType = "mock"
		case "-no-reconnect":
			f.autoReconnect = false
		}
	}
	return f
}

// ─────────────────────────────────────────────────────────────────────────────
// Stdout protocol helpers
// ─────────────────────────────────────────────────────────────────────────────

// printStats writes a [СТАТИСТИКА] line to stdout for Kotlin to parse.
func printStats(t Transport, activeWorkers int) {
	snap := t.Stats().snapshot()
	fmt.Printf("[СТАТИСТИКА] Активных: %d, Bytes↑ %d, Bytes↓ %d, Pkts↑ %d, Pkts↓ %d\n",
		activeWorkers,
		snap.BytesOut, snap.BytesIn,
		snap.PacketsOut, snap.PacketsIn,
	)
}

// PrintWireGuardConfig prints the WireGuard config in the framed format
// that Kotlin's log reader recognises.
//
// Called by production transports after receiving GETCONF response from server.
func PrintWireGuardConfig(configStr string) {
	fmt.Println("╔══ WireGuard Конфиг ══╗")
	for _, line := range strings.Split(configStr, "\n") {
		if line != "" {
			fmt.Printf("║ %s\n", line)
		}
	}
	fmt.Println("╚══════════════════════╝")
}

// printMockWireGuardConfig outputs a stub WireGuard config for MockTransport.
// On real devices this will bring up a VPN tunnel with loopback routing.
func printMockWireGuardConfig(cfg Config, log *internalLogger) {
	// Generate a deterministic private key stub (not cryptographically valid —
	// GoBackend will replace with real keys if the config is invalid).
	// In production this comes from the server GETCONF response.
	stub := fmt.Sprintf(`[Interface]
PrivateKey = %s
Address = %s/24
DNS = %s
MTU = %d

[Peer]
PublicKey = %s
AllowedIPs = 0.0.0.0/0
Endpoint = 127.0.0.1:51820
PersistentKeepalive = %d`,
		"mock-private-key-replace-in-production-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=",
		cfg.IPv4Address,
		strings.Join(cfg.DNSServers, ", "),
		cfg.MTU,
		"mock-public-key--replace-in-production-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=",
		cfg.KeepAliveSeconds,
	)

	log.info("Main", "delivering mock WireGuard config (replace with real GETCONF in production)")
	PrintWireGuardConfig(stub)
}

// ─────────────────────────────────────────────────────────────────────────────
// stdoutLogger — Android process mode: routes Go logs to stdout
// ─────────────────────────────────────────────────────────────────────────────

type stdoutLogger struct{}

func (stdoutLogger) Log(level, category, message string) {
	// Prefix that Kotlin's log parser expects (Go date prefix will be added by log package)
	fmt.Printf("[%s] [%s] %s\n", strings.ToUpper(level), category, message)
}
