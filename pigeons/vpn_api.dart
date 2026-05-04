// Pigeon definition file.
// Run: dart run pigeon --input pigeons/vpn_api.dart
// to regenerate lib/platform/vpn_api.g.dart

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/vpn_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/vpnplugin/src/main/kotlin/com/example/fluttervpngo/vpnplugin/VpnApi.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.example.fluttervpngo.vpnplugin',
    ),
    swiftOut: 'ios/Runner/VpnApi.swift',
    swiftOptions: SwiftOptions(),
  ),
)

// ─────────────────────────────────────────────
// DTOs
// ─────────────────────────────────────────────

class TunnelConfigDto {
  TunnelConfigDto({
    required this.id,
    required this.name,
    required this.serverHost,
    required this.serverPort,
    required this.transportType,
    this.authToken,
    required this.deviceId,
    required this.mtu,
    required this.dnsServers,
    required this.ipv4Address,
    required this.ipv4SubnetMask,
    required this.allowedIPv4Routes,
    required this.excludedIPv4Routes,
    required this.keepAliveSeconds,
    required this.workers,
    this.sni,
    required this.enableUdp,
    required this.enableTcp,
    required this.autoReconnect,
    required this.maxReconnectAttempts,
  });

  final String id;
  final String name;
  final String serverHost;
  final int serverPort;

  /// "mock" | "socksKcpSmux" | "wireguard" | "custom"
  final String transportType;
  final String? authToken;
  final String deviceId;
  final int mtu;
  final List<String?> dnsServers;
  final String ipv4Address;
  final String ipv4SubnetMask;
  final List<String?> allowedIPv4Routes;
  final List<String?> excludedIPv4Routes;
  final int keepAliveSeconds;
  final int workers;
  final String? sni;
  final bool enableUdp;
  final bool enableTcp;
  final bool autoReconnect;
  final int maxReconnectAttempts;
}

class TunnelStatusDto {
  TunnelStatusDto({
    required this.status,
    this.lastError,
    this.serverHost,
    this.transportType,
    this.uptimeSeconds,
  });

  /// "disconnected"|"preparing"|"connecting"|"connected"|
  /// "reconnecting"|"disconnecting"|"failed"
  final String status;
  final String? lastError;
  final String? serverHost;
  final String? transportType;
  final int? uptimeSeconds;
}

class TrafficStatsDto {
  TrafficStatsDto({
    required this.bytesIn,
    required this.bytesOut,
    required this.packetsIn,
    required this.packetsOut,
    required this.activeStreams,
    required this.updatedAtMs,
  });

  final int bytesIn;
  final int bytesOut;
  final int packetsIn;
  final int packetsOut;
  final int activeStreams;
  final int updatedAtMs;
}

class LogEntryDto {
  LogEntryDto({
    required this.id,
    required this.timestampMs,
    required this.level,
    required this.category,
    required this.message,
    required this.repeatCount,
  });

  final String id;
  final int timestampMs;
  final String level;
  final String category;
  final String message;
  final int repeatCount;
}

class DiagnosticsDto {
  DiagnosticsDto({
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    required this.osVersion,
    required this.deviceModel,
    required this.vpnPermissionGranted,
    required this.networkExtensionStatus,
    required this.runnerBundleId,
    required this.extensionBundleId,
    required this.appGroupId,
    required this.goClientVersion,
    required this.keychainAccessGroup,
  });

  final String platform;
  final String appVersion;
  final String buildNumber;
  final String osVersion;
  final String deviceModel;
  final bool vpnPermissionGranted;

  /// iOS only; "notInstalled"|"installed"|"enabled"|"unknown"
  final String networkExtensionStatus;
  final String runnerBundleId;
  final String extensionBundleId;
  final String appGroupId;
  final String goClientVersion;
  final String keychainAccessGroup;
}

// ─────────────────────────────────────────────
// Flutter → Native host API
// ─────────────────────────────────────────────

@HostApi()
abstract class VpnHostApi {
  /// Requests VPN permission (Android) or loads NE profile (iOS).
  /// Returns true if permission/profile is ready.
  @async
  bool prepareVpn();

  /// Pushes config to native layer (persists to shared container on iOS).
  @async
  void installOrUpdateProfile(TunnelConfigDto config);

  /// Starts the tunnel.
  @async
  void startTunnel();

  /// Stops the tunnel.
  @async
  void stopTunnel();

  /// Returns current tunnel status snapshot.
  @async
  TunnelStatusDto getStatus();

  /// Returns traffic statistics snapshot.
  @async
  TrafficStatsDto getStats();

  /// Returns buffered log entries from native side.
  @async
  List<LogEntryDto> getLogs();

  /// Clears native log buffer.
  @async
  void clearLogs();

  /// Returns platform diagnostics.
  @async
  DiagnosticsDto getDiagnostics();

  /// Sends an arbitrary message to the PacketTunnel extension (iOS IPC).
  @async
  void sendProviderMessage(String type, Map<String, Object?> payload);
}

// ─────────────────────────────────────────────
// Native → Flutter callback API
// ─────────────────────────────────────────────

@FlutterApi()
abstract class VpnFlutterApi {
  void onStatusChanged(TunnelStatusDto status);
  void onStatsChanged(TrafficStatsDto stats);
  void onLogReceived(LogEntryDto entry);
}
