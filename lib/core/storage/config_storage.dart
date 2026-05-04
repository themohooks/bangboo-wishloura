import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/tunnel_config.dart';

/// Persists TunnelConfig list to a local JSON file.
/// authToken is NEVER written here — use SecureStorage for that.
class ConfigStorage {
  static const _fileName = 'tunnel_configs.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<TunnelConfig>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      final list = json.decode(raw) as List<dynamic>;
      return list
          .map((e) => TunnelConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ConfigStorage] loadAll error: $e');
      return [];
    }
  }

  Future<void> saveAll(List<TunnelConfig> configs) async {
    try {
      final file = await _file();
      // Strip authToken before writing
      final list = configs.map((c) => c.copyWith(clearAuthToken: true).toJson()).toList();
      await file.writeAsString(json.encode(list));
    } catch (e) {
      debugPrint('[ConfigStorage] saveAll error: $e');
    }
  }

  Future<void> saveOne(TunnelConfig config) async {
    final all = await loadAll();
    final idx = all.indexWhere((c) => c.id == config.id);
    if (idx >= 0) {
      all[idx] = config;
    } else {
      all.add(config);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((c) => c.id == id);
    await saveAll(all);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
