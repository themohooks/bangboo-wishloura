import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/tunnel_config.dart';
import '../storage/config_storage.dart';
import '../storage/secure_storage.dart';
import '../utils/validators.dart';

class ConfigValidationResult {
  const ConfigValidationResult({required this.errors, required this.config});

  final List<String> errors;
  final TunnelConfig? config;

  bool get isValid => errors.isEmpty;
}

class ConfigService {
  ConfigService(this._storage, this._secureStorage);

  final ConfigStorage _storage;
  final SecureStorage _secureStorage;
  static const _uuid = Uuid();

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<List<TunnelConfig>> loadAll() => _storage.loadAll();

  Future<TunnelConfig> save(TunnelConfig config) async {
    final isNew = config.id.isEmpty;
    final now = DateTime.now();
    final saved = config.copyWith(
      id: isNew ? _uuid.v4() : config.id,
      updatedAt: now,
      createdAt: isNew ? now : config.createdAt,
    );

    // Persist auth token separately
    if (saved.authToken != null && saved.authToken!.isNotEmpty) {
      await _secureStorage.saveAuthToken(saved.id, saved.authToken!);
    }

    await _storage.saveOne(saved.copyWith(clearAuthToken: true));
    return saved;
  }

  Future<void> delete(String id) async {
    await _secureStorage.deleteAuthToken(id);
    await _storage.delete(id);
  }

  Future<TunnelConfig?> loadWithSecret(String id) async {
    final all = await _storage.loadAll();
    final config = all.cast<TunnelConfig?>().firstWhere(
      (c) => c?.id == id,
      orElse: () => null,
    );
    if (config == null) return null;
    final token = await _secureStorage.loadAuthToken(id);
    return config.copyWith(authToken: token);
  }

  // ── Import ────────────────────────────────────────────────────────────────

  /// Parses and validates a JSON string, returns validation result.
  /// Does NOT persist — call save() explicitly.
  ConfigValidationResult parseImport(String jsonString) {
    Map<String, dynamic> map;
    try {
      map = json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return ConfigValidationResult(errors: ['Invalid JSON: $e'], config: null);
    }

    final errors = <String>[];

    // Required fields
    final host = map['serverHost'] as String?;
    if (host == null || host.trim().isEmpty) errors.add('serverHost is required');

    final portRaw = map['serverPort'];
    final port = portRaw is int ? portRaw : int.tryParse(portRaw?.toString() ?? '');
    if (port == null || port < 1 || port > 65535) errors.add('serverPort must be 1–65535');

    final mtuRaw = map['mtu'];
    final mtu = mtuRaw is int ? mtuRaw : int.tryParse(mtuRaw?.toString() ?? '');
    if (mtu != null && (mtu < 576 || mtu > 1500)) errors.add('mtu must be 576–1500');

    final workersRaw = map['workers'];
    final workers = workersRaw is int ? workersRaw : int.tryParse(workersRaw?.toString() ?? '');
    if (workers != null && (workers < 1 || workers > 32)) errors.add('workers must be 1–32');

    final keepAliveRaw = map['keepAliveSeconds'];
    final keepAlive = keepAliveRaw is int ? keepAliveRaw : int.tryParse(keepAliveRaw?.toString() ?? '');
    if (keepAlive != null && (keepAlive < 5 || keepAlive > 300)) {
      errors.add('keepAliveSeconds must be 5–300');
    }

    // DNS
    final dnsRaw = map['dnsServers'];
    if (dnsRaw is List) {
      for (final d in dnsRaw) {
        final err = Validators.dnsServer(d?.toString());
        if (err != null) errors.add(err);
      }
    }

    // Routes
    final allowedRaw = map['allowedIPv4Routes'];
    if (allowedRaw is List) {
      for (final r in allowedRaw) {
        final err = Validators.cidr(r?.toString());
        if (err != null) errors.add('allowedIPv4Routes: $err');
      }
    }

    final excludedRaw = map['excludedIPv4Routes'];
    if (excludedRaw is List) {
      for (final r in excludedRaw) {
        final err = Validators.cidr(r?.toString());
        if (err != null) errors.add('excludedIPv4Routes: $err');
      }
    }

    if (errors.isNotEmpty) {
      return ConfigValidationResult(errors: errors, config: null);
    }

    try {
      final config = TunnelConfig.fromJson(map);
      return ConfigValidationResult(errors: [], config: config);
    } catch (e) {
      return ConfigValidationResult(errors: ['Parse error: $e'], config: null);
    }
  }
}
