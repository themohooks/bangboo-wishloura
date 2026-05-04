import 'dart:async';

import 'package:flutter/services.dart';

import '../core/models/log_entry.dart';
import '../core/models/traffic_stats.dart';
import '../core/models/tunnel_config.dart';
import '../core/models/tunnel_status.dart';
import 'vpn_api.g.dart';

/// High-level platform bridge.
///
/// Uses Pigeon [VpnHostApi] for command/response calls, and falls back to
/// [EventChannel] streams for push notifications from the native side
/// (status, stats, logs).
///
/// If Pigeon callbacks fail (e.g. simulator / unsupported platform) the
/// EventChannel approach serves as the primary event delivery mechanism.
class VpnPlatformService {
  VpnPlatformService() : _host = VpnHostApi() {
    _bindFlutterApi();
    _bindEventChannels();
  }

  final VpnHostApi _host;

  // ── Pigeon Flutter-side callbacks ────────────────────────────────────────

  final _statusController = StreamController<TunnelStatusState>.broadcast();
  final _statsController = StreamController<TrafficStats>.broadcast();
  final _logController = StreamController<LogEntry>.broadcast();

  Stream<TunnelStatusState> get statusStream => _statusController.stream;
  Stream<TrafficStats> get statsStream => _statsController.stream;
  Stream<LogEntry> get logStream => _logController.stream;

  // ── EventChannel fallback ────────────────────────────────────────────────

  static const _statusChannel = EventChannel('com.example.fluttervpngo/vpn_status_events');
  static const _statsChannel = EventChannel('com.example.fluttervpngo/vpn_stats_events');
  static const _logChannel = EventChannel('com.example.fluttervpngo/vpn_log_events');

  StreamSubscription<dynamic>? _statusSub;
  StreamSubscription<dynamic>? _statsSub;
  StreamSubscription<dynamic>? _logSub;

  void _bindFlutterApi() {
    VpnFlutterApi.setUp(_VpnFlutterApiImpl(
      onStatus: (dto) => _statusController.add(_dtoToStatus(dto)),
      onStats: (dto) => _statsController.add(_dtoToStats(dto)),
      onLog: (dto) => _logController.add(_dtoToLog(dto)),
    ));
  }

  void _bindEventChannels() {
    _statusSub = _statusChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          try {
            final map = Map<String, dynamic>.from(event);
            final status = TunnelStatusState(
              status: TunnelStatus.fromString(map['status'] as String? ?? 'disconnected'),
              lastError: map['lastError'] as String?,
              serverHost: map['serverHost'] as String?,
              transportType: map['transportType'] as String?,
              uptimeSeconds: map['uptimeSeconds'] as int?,
            );
            _statusController.add(status);
          } catch (_) {}
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );

    _statsSub = _statsChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          try {
            final map = Map<String, dynamic>.from(event);
            _statsController.add(TrafficStats(
              bytesIn: map['bytesIn'] as int? ?? 0,
              bytesOut: map['bytesOut'] as int? ?? 0,
              packetsIn: map['packetsIn'] as int? ?? 0,
              packetsOut: map['packetsOut'] as int? ?? 0,
              activeStreams: map['activeStreams'] as int? ?? 0,
              updatedAt: DateTime.now(),
            ));
          } catch (_) {}
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );

    _logSub = _logChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          try {
            final map = Map<String, dynamic>.from(event);
            _logController.add(LogEntry(
              id: map['id'] as String? ?? _genId(),
              timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestampMs'] as int? ?? 0),
              level: map['level'] as String? ?? 'info',
              category: map['category'] as String? ?? 'native',
              message: map['message'] as String? ?? '',
              repeatCount: map['repeatCount'] as int? ?? 1,
            ));
          } catch (_) {}
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  // ── Commands ─────────────────────────────────────────────────────────────

  Future<bool> prepareVpn() => _host.prepareVpn();

  Future<void> installOrUpdateProfile(TunnelConfig config, {String? authToken}) async {
    final dto = TunnelConfigDto(
      id: config.id,
      name: config.name,
      serverHost: config.serverHost,
      serverPort: config.serverPort,
      transportType: config.transportType.toJson(),
      authToken: authToken,
      deviceId: config.deviceId,
      mtu: config.mtu,
      dnsServers: config.dnsServers,
      ipv4Address: config.ipv4Address,
      ipv4SubnetMask: config.ipv4SubnetMask,
      allowedIPv4Routes: config.allowedIPv4Routes,
      excludedIPv4Routes: config.excludedIPv4Routes,
      keepAliveSeconds: config.keepAliveSeconds,
      workers: config.workers,
      sni: config.sni,
      enableUdp: config.enableUdp,
      enableTcp: config.enableTcp,
      autoReconnect: config.autoReconnect,
      maxReconnectAttempts: config.maxReconnectAttempts,
    );
    await _host.installOrUpdateProfile(dto);
  }

  Future<void> startTunnel() => _host.startTunnel();
  Future<void> stopTunnel() => _host.stopTunnel();

  Future<TunnelStatusState> getStatus() async {
    final dto = await _host.getStatus();
    return _dtoToStatus(dto);
  }

  Future<TrafficStats> getStats() async {
    final dto = await _host.getStats();
    return _dtoToStats(dto);
  }

  Future<List<LogEntry>> getLogs() async {
    final list = await _host.getLogs();
    return list.whereType<LogEntryDto>().map(_dtoToLog).toList();
  }

  Future<void> clearLogs() => _host.clearLogs();

  Future<DiagnosticsDto> getDiagnostics() => _host.getDiagnostics();

  Future<void> sendProviderMessage(String type, Map<String, Object?> payload) =>
      _host.sendProviderMessage(type, payload);

  // ── Converters ───────────────────────────────────────────────────────────

  static TunnelStatusState _dtoToStatus(TunnelStatusDto dto) => TunnelStatusState(
        status: TunnelStatus.fromString(dto.status),
        lastError: dto.lastError,
        serverHost: dto.serverHost,
        transportType: dto.transportType,
        uptimeSeconds: dto.uptimeSeconds,
      );

  static TrafficStats _dtoToStats(TrafficStatsDto dto) => TrafficStats(
        bytesIn: dto.bytesIn,
        bytesOut: dto.bytesOut,
        packetsIn: dto.packetsIn,
        packetsOut: dto.packetsOut,
        activeStreams: dto.activeStreams,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(dto.updatedAtMs),
      );

  static LogEntry _dtoToLog(LogEntryDto dto) => LogEntry(
        id: dto.id,
        timestamp: DateTime.fromMillisecondsSinceEpoch(dto.timestampMs),
        level: dto.level,
        category: dto.category,
        message: dto.message,
        repeatCount: dto.repeatCount,
      );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _statusSub?.cancel();
    await _statsSub?.cancel();
    await _logSub?.cancel();
    await _statusController.close();
    await _statsController.close();
    await _logController.close();
    VpnFlutterApi.setUp(null);
  }
}

// ── VpnFlutterApi implementation ──────────────────────────────────────────

class _VpnFlutterApiImpl extends VpnFlutterApi {
  _VpnFlutterApiImpl({
    required this.onStatus,
    required this.onStats,
    required this.onLog,
  });

  final void Function(TunnelStatusDto) onStatus;
  final void Function(TrafficStatsDto) onStats;
  final void Function(LogEntryDto) onLog;

  @override
  void onStatusChanged(TunnelStatusDto status) => onStatus(status);

  @override
  void onStatsChanged(TrafficStatsDto stats) => onStats(stats);

  @override
  void onLogReceived(LogEntryDto entry) => onLog(entry);
}

String _genId() => '${DateTime.now().microsecondsSinceEpoch}-${Object().hashCode}';
