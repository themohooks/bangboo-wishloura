import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/log_entry.dart';
import '../models/traffic_stats.dart';
import '../models/tunnel_config.dart';
import '../models/tunnel_status.dart';
import '../services/config_service.dart';
import '../services/diagnostics_service.dart';
import '../services/log_service.dart';
import '../services/vpn_service.dart';
import '../storage/config_storage.dart';
import '../storage/secure_storage.dart';
import '../../platform/vpn_platform_service.dart';

// ── Infrastructure ────────────────────────────────────────────────────────

final secureStorageProvider = Provider<SecureStorage>((_) => SecureStorage());

final configStorageProvider = Provider<ConfigStorage>((_) => ConfigStorage());

final vpnPlatformServiceProvider = Provider<VpnPlatformService>((ref) {
  final svc = VpnPlatformService();
  ref.onDispose(svc.dispose);
  return svc;
});

final logServiceProvider = ChangeNotifierProvider<LogService>((ref) {
  return LogService();
});

// ── Services ──────────────────────────────────────────────────────────────

final configServiceProvider = Provider<ConfigService>((ref) {
  return ConfigService(
    ref.watch(configStorageProvider),
    ref.watch(secureStorageProvider),
  );
});

final vpnServiceProvider = ChangeNotifierProvider<VpnService>((ref) {
  final svc = VpnService(
    platform: ref.watch(vpnPlatformServiceProvider),
    logService: ref.watch(logServiceProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

final diagnosticsServiceProvider = Provider<DiagnosticsService>((ref) {
  return DiagnosticsService(ref.watch(vpnPlatformServiceProvider));
});

// ── Derived state ─────────────────────────────────────────────────────────

/// Current tunnel status from VpnService
final tunnelStatusProvider = Provider<TunnelStatusState>((ref) {
  return ref.watch(vpnServiceProvider.select((s) => s.status));
});

/// Current traffic stats from VpnService
final trafficStatsProvider = Provider<TrafficStats>((ref) {
  return ref.watch(vpnServiceProvider.select((s) => s.stats));
});

/// All log entries (from LogService, reactive)
final logEntriesProvider = Provider<List<LogEntry>>((ref) {
  return ref.watch(logServiceProvider).entries;
});

/// Configs list (async, loaded from disk)
final tunnelConfigListProvider = FutureProvider<List<TunnelConfig>>((ref) async {
  return ref.watch(configServiceProvider).loadAll();
});

/// Active config from VpnService
final activeConfigProvider = Provider<TunnelConfig?>((ref) {
  return ref.watch(vpnServiceProvider.select((s) => s.activeConfig));
});

// ── Log filter state ──────────────────────────────────────────────────────

final logLevelFilterProvider = StateProvider<String>((ref) => 'debug');

final filteredLogEntriesProvider = Provider<List<LogEntry>>((ref) {
  final entries = ref.watch(logEntriesProvider);
  final minLevel = ref.watch(logLevelFilterProvider);
  final minOrder = minLevel.levelOrder;
  return entries.where((e) => e.level.levelOrder >= minOrder).toList();
});
