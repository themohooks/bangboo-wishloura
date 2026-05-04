import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/transport_type.dart';
import '../../core/models/tunnel_config.dart';
import '../../core/services/providers.dart';

class SettingsController {
  SettingsController(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<TunnelConfig?> loadFirst() async {
    final all = await _ref.read(configServiceProvider).loadAll();
    return all.isEmpty ? null : all.first;
  }

  Future<TunnelConfig?> loadWithSecret(String id) =>
      _ref.read(configServiceProvider).loadWithSecret(id);

  Future<void> save(TunnelConfig config) async {
    final saved = await _ref.read(configServiceProvider).save(config);
    _ref.invalidate(tunnelConfigListProvider);
  }

  Future<void> delete(String id) async {
    await _ref.read(configServiceProvider).delete(id);
    _ref.invalidate(tunnelConfigListProvider);
  }

  TunnelConfig blank() => TunnelConfig.defaults.copyWith(
        id: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}

final settingsControllerProvider = Provider((ref) => SettingsController(ref));
