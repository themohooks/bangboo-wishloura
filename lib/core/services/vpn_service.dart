import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/traffic_stats.dart';
import '../models/tunnel_config.dart';
import '../models/tunnel_status.dart';
import '../models/log_entry.dart';
import '../services/log_service.dart';
import '../storage/secure_storage.dart';
import '../../platform/vpn_platform_service.dart';

/// High-level VPN service; orchestrates native platform calls,
/// feeds LogService, and exposes ValueNotifiers for reactive UI.
class VpnService extends ChangeNotifier {
  VpnService({
    required VpnPlatformService platform,
    required LogService logService,
    required SecureStorage secureStorage,
  })  : _platform = platform,
        _log = logService,
        _secure = secureStorage {
    _bindStreams();
    _startPolling();
  }

  final VpnPlatformService _platform;
  final LogService _log;
  final SecureStorage _secure;

  // ── Public state ──────────────────────────────────────────────────────────

  TunnelStatusState get status => _status;
  TrafficStats get stats => _stats;
  TunnelConfig? get activeConfig => _activeConfig;

  var _status = TunnelStatusState.initial;
  var _stats = TrafficStats.zero;
  TunnelConfig? _activeConfig;

  StreamSubscription<TunnelStatusState>? _statusSub;
  StreamSubscription<TrafficStats>? _statsSub;
  StreamSubscription<LogEntry>? _logSub;
  Timer? _pollTimer;

  // ── Bindings ──────────────────────────────────────────────────────────────

  void _bindStreams() {
    _statusSub = _platform.statusStream.listen(_onStatus);
    _statsSub = _platform.statsStream.listen(_onStats);
    _logSub = _platform.logStream.listen(_onLog);
  }

  void _onStatus(TunnelStatusState s) {
    _status = s;
    notifyListeners();
  }

  void _onStats(TrafficStats s) {
    _stats = s;
    notifyListeners();
  }

  void _onLog(LogEntry e) {
    _log.add(e);
  }

  /// Poll native side every 2 s as fallback when event channels are silent.
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final s = await _platform.getStatus();
        _onStatus(s);
        if (s.status.isActive) {
          final stats = await _platform.getStats();
          _onStats(stats);
        }
        final logs = await _platform.getLogs();
        if (logs.isNotEmpty) {
          _log.addAll(logs);
          await _platform.clearLogs();
        }
      } catch (_) {
        // Ignore polling errors silently
      }
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<bool> prepareVpn() async {
    _log.info('VpnService', 'Requesting VPN permission');
    try {
      final ok = await _platform.prepareVpn();
      _log.info('VpnService', ok ? 'VPN permission granted' : 'VPN permission denied');
      return ok;
    } on PlatformException catch (e) {
      _log.error('VpnService', 'prepareVpn error: ${e.message}');
      return false;
    }
  }

  Future<void> connect(TunnelConfig config) async {
    if (!_status.canConnect) {
      _log.warning('VpnService', 'Cannot connect in status: ${_status.status.name}');
      return;
    }
    _activeConfig = config;
    _setStatus(TunnelStatus.preparing, clearError: true);
    _log.info('VpnService', 'Connecting to ${config.serverHost}:${config.serverPort} via ${config.transportType.displayName}');

    try {
      final token = await _secure.loadAuthToken(config.id);
      await _platform.installOrUpdateProfile(config, authToken: token);
      _setStatus(TunnelStatus.connecting);
      await _platform.startTunnel();
      // Status update will come from native via stream/event
    } on PlatformException catch (e) {
      final msg = _mapPlatformError(e);
      _log.error('VpnService', 'Connect failed: $msg');
      _setStatus(TunnelStatus.failed, error: msg);
    } catch (e) {
      _log.error('VpnService', 'Connect error: $e');
      _setStatus(TunnelStatus.failed, error: e.toString());
    }
  }

  Future<void> disconnect() async {
    if (!_status.canDisconnect) return;
    _log.info('VpnService', 'Disconnecting…');
    _setStatus(TunnelStatus.disconnecting);
    try {
      await _platform.stopTunnel();
    } on PlatformException catch (e) {
      _log.error('VpnService', 'Disconnect error: ${e.message}');
      _setStatus(TunnelStatus.failed, error: e.message);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setStatus(TunnelStatus status, {String? error, bool clearError = false}) {
    _status = _status.copyWith(
      status: status,
      lastError: error,
      clearError: clearError,
    );
    notifyListeners();
  }

  static String _mapPlatformError(PlatformException e) {
    switch (e.code) {
      case 'VPN_PERMISSION_DENIED':
        return 'VPN permission denied';
      case 'INVALID_CONFIG':
        return 'Invalid config';
      case 'NATIVE_BRIDGE_UNAVAILABLE':
        return 'Native bridge unavailable';
      case 'PACKET_TUNNEL_FAILED':
        return 'Packet tunnel failed';
      case 'GO_CLIENT_FAILED':
        return 'Go client failed';
      case 'TRANSPORT_DISCONNECTED':
        return 'Transport disconnected';
      default:
        return e.message ?? e.code;
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _statsSub?.cancel();
    _logSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}
