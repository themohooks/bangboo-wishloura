# flutter_vpn_go

A cross-platform VPN/proxy client built with **Flutter 3**, **Go** (gomobile), and native VPN layers for Android and iOS.

> **Status:** MVP scaffold with MockTransport.  
> Production transports are clean stubs with TODO checklists — see below.

---

## 1. Architecture

```
Flutter App (Dart/Flutter 3)
 ├─ Material 3 dark UI
 ├─ Riverpod state management
 ├─ Pigeon type-safe platform channels (+ EventChannel fallback)
 ├─ config / secrets / log management
 │
 ├─── Android (Kotlin)
 │     ├─ FlutterVpnPlugin  — Pigeon host API, EventChannels
 │     ├─ AndroidVpnService — VpnService, TUN interface, foreground notification
 │     ├─ GoClientBridge    — wraps gomobile AAR
 │     ├─ TunDeviceBridge   — TUN fd ↔ Go client packet loop
 │     └─ AndroidLogBridge  — Go Logger → Logcat + in-memory buffer
 │
 └─── iOS (Swift)
       ├─ Runner
       │   ├─ FlutterVpnPlugin — Pigeon host API, EventChannels
       │   ├─ VpnManager       — NETunnelProviderManager lifecycle
       │   └─ KeychainHelper   — auth token storage
       └─ PacketTunnel Extension (separate process)
           ├─ PacketTunnelProvider — NEPacketTunnelProvider
           ├─ GoClientBridge       — wraps gomobile XCFramework
           ├─ PacketFlowBridge     — NEPacketTunnelFlow ↔ Go client
           ├─ TunnelConfigLoader   — reads config from App Group
           └─ TunnelLogger         — writes logs to App Group

Go Module (go_client/)
 ├─ client.go          — public gomobile API
 ├─ config.go          — JSON config parsing & validation
 ├─ transport.go       — Transport interface + factory
 ├─ mock_transport.go  — MVP loopback transport (stats, no real traffic)
 ├─ socks_kcp_smux_transport.go  — production stub (TODO)
 └─ wireguard_transport.go       — production stub (TODO)
```

---

## 2. Why Flutter for UI only?

Flutter runs in its own Dart VM. VPN packet processing must happen in a
**persistent native process** that the OS can keep alive when the app is
backgrounded or killed. On both platforms the OS enforces this separation:

- **Android** — `VpnService` runs as a foreground service in the app process but
  with its own lifecycle independent of the Flutter engine.
- **iOS** — `NEPacketTunnelProvider` runs in a **separate extension process**
  that the OS manages. The Flutter engine is never involved in packet I/O.

Flutter is used exclusively for the **control plane**: UI, config management,
status display, logs, diagnostics.

---

## 3. Why Android uses VpnService?

`android.net.VpnService` is the only public Android API that allows an app to:
- Create a TUN (layer-3 virtual network) interface.
- Route all device traffic through it.
- Run as a foreground service with a persistent notification.

No private APIs or root are required.

---

## 4. Why iOS uses NetworkExtension + Packet Tunnel Extension?

Apple's **NetworkExtension** framework is the only approved way to implement a
VPN on iOS without jailbreak. Key points:

- `NETunnelProviderManager` (Runner) configures the VPN profile.
- `NEPacketTunnelProvider` (Extension) processes packets in a sandboxed process.
- The extension has its **own entitlements** and runs independently of the app.
- Shared data (config, logs, stats) flows through an **App Group** container.
- Secrets (auth token) flow through a **shared Keychain** access group.

---

## 5. Building the Go Client

### Prerequisites
```bash
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init          # run once
```

### Android AAR
```bash
cd flutter_vpn_go/go_client
chmod +x build_android.sh
./build_android.sh
# Output: android/vpnplugin/libs/goclient.aar
```

### iOS XCFramework
```bash
cd flutter_vpn_go/go_client
chmod +x build_ios.sh
./build_ios.sh
# Output: ios/Frameworks/GoClient.xcframework
```

See `go_client/README.md` for detailed setup instructions.

---

## 6. Android Permissions & Setup

Add to your **host app** `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
```

The plugin module's `AndroidManifest.xml` already declares `AndroidVpnService`
with the required `android.permission.BIND_VPN_SERVICE` and intent-filter.

Register the plugin in your `MainActivity.kt`:
```kotlin
import com.example.fluttervpngo.vpnplugin.FlutterVpnPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(FlutterVpnPlugin())
    }
}
```

---

## 7. iOS Capabilities (Xcode Setup)

### 7.1 Create Packet Tunnel Extension target
1. Xcode → File → New → Target → **Network Extension**
2. Name: `PacketTunnel`
3. Bundle ID: `com.example.flutterVpnGo.PacketTunnel`
4. Set **Deployment Target** to iOS 15.0

### 7.2 Network Extension entitlement
Both **Runner** and **PacketTunnel** targets need:
- Capability: `Network Extensions` → check `Packet Tunnel`

### 7.3 App Groups
Both **Runner** and **PacketTunnel** targets need:
- Capability: `App Groups`
- Group ID: `group.com.example.flutterVpnGo`

Update `VpnConstants.appGroupId` in `VpnManager.swift` to match.

### 7.4 Keychain Sharing
Both targets need:
- Capability: `Keychain Sharing`
- Access Group: `$(AppIdentifierPrefix)com.example.flutterVpnGo`

Uncomment the `kSecAttrAccessGroup` lines in `KeychainHelper.swift` and
`TunnelConfigLoader.swift` once this capability is configured.

### 7.5 Add GoClient.xcframework
- **Runner** target → General → Frameworks, Libraries: Add → **Embed & Sign**
- **PacketTunnel** target → General → Frameworks: Add → **Do Not Embed**

### 7.6 PacketTunnel Info.plist
Add the `AppGroupID` key:
```xml
<key>AppGroupID</key>
<string>group.com.example.flutterVpnGo</string>
```

### 7.7 Register plugin in AppDelegate
```swift
// ios/Runner/AppDelegate.swift — already done in this project
FlutterVpnPlugin.register(with: registrar)
```

---

## 8. Running on a Real Android Device

```bash
flutter run --release    # or --debug
```

1. When you tap **Connect**, Android shows a VPN permission dialog.
2. Accept → `AndroidVpnService` starts as a foreground service.
3. The TUN interface is built with `VpnService.Builder`.
4. MockTransport counts packets and echoes them back.
5. Dashboard shows live stats.

> ⚠️ You need a physical device or an emulator with Google Play Services for
> the VPN permission dialog to work.

---

## 9. Running on a Real iPhone

```bash
flutter run --release -d <device-udid>
```

1. Must be signed with a **paid Apple Developer account** (free accounts cannot
   create Network Extension entitlements).
2. Profile is installed in iOS Settings → General → VPN & Device Management.
3. Tap **Connect** → system installs the NE profile → PacketTunnel extension starts.
4. MockTransport runs inside the extension; stats are written to App Group.

---

## 10. Why iOS Simulator Doesn't Work for VPN

The iOS Simulator does **not** support `NetworkExtension`. Specifically:
- `NETunnelProviderManager.loadAllFromPreferences` may hang or fail silently.
- The Packet Tunnel extension cannot be launched by the simulator.
- There is no virtual TUN interface available.

Always test VPN functionality on a **physical iPhone** with the correct
entitlements and provisioning profile.

---

## 11. Where to Plug In Real Transports

### SOCKS+KCP+SMUX
Edit: `go_client/client/socks_kcp_smux_transport.go`

Key TODOs at the bottom of that file:
1. Import `github.com/xtaci/kcp-go` and `github.com/xtaci/smux`.
2. Dial `cfg.ServerHost:cfg.ServerPort` over KCP/UDP.
3. Wrap with SMUX, open `cfg.Workers` streams.
4. Authenticate with `cfg.AuthToken`.
5. Implement `WritePacket`, `ReadPacket`, keepalive, reconnect.

### WireGuard
Edit: `go_client/client/wireguard_transport.go`

Two approaches (see file for details):
- **Embedded** — import `golang.zx2c4.com/wireguard` and create a wireguard-go Device.
- **Platform-native** — return `ErrUseNativePlatform` and handle in Swift/Kotlin.

---

## 12. Known Limitations

| Area | Limitation |
|---|---|
| MockTransport | No real network I/O; just counters and echo |
| iOS Simulator | NetworkExtension not supported |
| Android < 26 | minSdk set to 26; older devices not supported |
| gomobile AAR | Must be built before first Android build |
| gomobile XCFramework | Must be built before first iOS build |
| Pigeon callbacks | Use EventChannel as primary push mechanism |
| WireGuard | Stub only; see wireguard_transport.go TODOs |
| SOCKS+KCP+SMUX | Stub only; see socks_kcp_smux_transport.go TODOs |
| IPv6 | Only IPv4 is configured in TUN settings (extend as needed) |
| Multiple configs | UI shows first config; extend to support profile list |

---

## 13. Security Notes

| Concern | Mitigation |
|---|---|
| Auth token storage | Android: EncryptedSharedPreferences via flutter_secure_storage |
| Auth token storage | iOS: Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Auth token in logs | Masked: `abcd********3456` |
| Auth token in config JSON | Stripped before writing to plain storage |
| Auth token in diagnostics | Masked before display/export |
| Plain-text config | Stored in app documents dir (not sensitive fields) |
| Remote code execution | Not implemented; no dynamic loading of any kind |
| Third-party relay servers | Not used; server address from user config only |
| Private APIs | Not used; only public Android/iOS VPN APIs |
| WireGuard private keys | Never logged (TODO: enforce in production transport) |
| Network security | `cleartextTrafficPermitted="false"` in network_security_config.xml |

---

## 14. Project Structure

```
flutter_vpn_go/
├── pubspec.yaml
├── README.md
├── pigeons/
│   └── vpn_api.dart                  ← Pigeon definition (run to regenerate)
├── lib/
│   ├── main.dart
│   ├── app.dart                      ← Theme + shell navigation
│   ├── core/
│   │   ├── models/                   ← TunnelConfig, TunnelStatus, TrafficStats…
│   │   ├── services/                 ← VpnService, ConfigService, LogService…
│   │   ├── storage/                  ← SecureStorage, ConfigStorage
│   │   └── utils/                    ← ByteFormatter, Validators
│   ├── features/
│   │   ├── dashboard/                ← Connect/Disconnect UI
│   │   ├── settings/                 ← Config editor
│   │   ├── logs/                     ← Live log viewer
│   │   ├── import_config/            ← JSON import + validation
│   │   └── diagnostics/              ← Platform diagnostics
│   └── platform/
│       ├── vpn_api.g.dart            ← Generated Pigeon client
│       └── vpn_platform_service.dart ← High-level bridge
├── go_client/
│   ├── go.mod
│   ├── build_android.sh
│   ├── build_ios.sh
│   ├── README.md
│   └── client/
│       ├── client.go                 ← gomobile public API
│       ├── config.go
│       ├── stats.go
│       ├── logger.go
│       ├── transport.go              ← Transport interface
│       ├── mock_transport.go         ← MVP loopback
│       ├── socks_kcp_smux_transport.go  ← Production stub
│       └── wireguard_transport.go       ← Production stub
├── android/
│   └── vpnplugin/
│       ├── build.gradle
│       ├── libs/                     ← goclient.aar goes here
│       └── src/main/kotlin/…/vpnplugin/
│           ├── VpnApi.kt             ← Pigeon generated
│           ├── FlutterVpnPlugin.kt
│           ├── AndroidVpnService.kt
│           ├── GoClientBridge.kt
│           ├── TunDeviceBridge.kt
│           └── AndroidLogBridge.kt
└── ios/
    ├── Frameworks/                   ← GoClient.xcframework goes here
    ├── Runner/
    │   ├── AppDelegate.swift
    │   ├── VpnApi.swift              ← Pigeon generated
    │   ├── FlutterVpnPlugin.swift
    │   ├── VpnManager.swift
    │   └── KeychainHelper.swift
    └── PacketTunnel/
        ├── PacketTunnelProvider.swift
        ├── GoClientBridge.swift
        ├── PacketFlowBridge.swift
        ├── TunnelConfigLoader.swift
        └── TunnelLogger.swift
```
