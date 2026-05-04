// Package client provides the gomobile-compatible VPN client API.
// Build with:
//   gomobile bind -target=android -androidapi 26 -o ../android/vpnplugin/libs/goclient.aar ./client
//   gomobile bind -target=ios     -o ../ios/Frameworks/GoClient.xcframework          ./client
package client

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Config holds the tunnel configuration passed from Flutter via JSON string.
// All fields are exported for gomobile compatibility (no generics in public API).
type Config struct {
	ID                   string   `json:"id"`
	Name                 string   `json:"name"`
	ServerHost           string   `json:"serverHost"`
	ServerPort           int      `json:"serverPort"`
	TransportType        string   `json:"transportType"`
	AuthToken            string   `json:"authToken"`
	DeviceID             string   `json:"deviceId"`
	MTU                  int      `json:"mtu"`
	DNSServers           []string `json:"dnsServers"`
	IPv4Address          string   `json:"ipv4Address"`
	IPv4SubnetMask       string   `json:"ipv4SubnetMask"`
	AllowedIPv4Routes    []string `json:"allowedIPv4Routes"`
	ExcludedIPv4Routes   []string `json:"excludedIPv4Routes"`
	KeepAliveSeconds     int      `json:"keepAliveSeconds"`
	Workers              int      `json:"workers"`
	SNI                  string   `json:"sni"`
	EnableUDP            bool     `json:"enableUdp"`
	EnableTCP            bool     `json:"enableTcp"`
	AutoReconnect        bool     `json:"autoReconnect"`
	MaxReconnectAttempts int      `json:"maxReconnectAttempts"`
}

// ParseConfig deserializes a JSON string into a Config struct.
func ParseConfig(jsonStr string) (Config, error) {
	var c Config
	if err := json.Unmarshal([]byte(jsonStr), &c); err != nil {
		return c, fmt.Errorf("config parse error: %w", err)
	}
	if err := c.validate(); err != nil {
		return c, err
	}
	return c, nil
}

func (c *Config) validate() error {
	var errs []string
	if strings.TrimSpace(c.ServerHost) == "" {
		errs = append(errs, "serverHost is required")
	}
	if c.ServerPort < 1 || c.ServerPort > 65535 {
		errs = append(errs, "serverPort must be 1–65535")
	}
	if c.MTU != 0 && (c.MTU < 576 || c.MTU > 1500) {
		errs = append(errs, "mtu must be 576–1500")
	}
	if c.Workers != 0 && (c.Workers < 1 || c.Workers > 32) {
		errs = append(errs, "workers must be 1–32")
	}
	if c.KeepAliveSeconds != 0 && (c.KeepAliveSeconds < 5 || c.KeepAliveSeconds > 300) {
		errs = append(errs, "keepAliveSeconds must be 5–300")
	}
	// Apply sane defaults
	if c.MTU == 0 {
		c.MTU = 1280
	}
	if c.Workers == 0 {
		c.Workers = 4
	}
	if c.KeepAliveSeconds == 0 {
		c.KeepAliveSeconds = 25
	}
	if c.MaxReconnectAttempts == 0 {
		c.MaxReconnectAttempts = 3
	}
	if c.DeviceID == "" {
		c.DeviceID = "auto"
	}
	if len(errs) > 0 {
		return fmt.Errorf("config validation: %s", strings.Join(errs, "; "))
	}
	return nil
}

// ToJSON serializes the config to JSON (authToken is included for IPC to extension).
func (c *Config) ToJSON() string {
	b, _ := json.Marshal(c)
	return string(b)
}
