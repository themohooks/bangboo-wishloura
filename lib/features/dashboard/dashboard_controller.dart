import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/config_service.dart';
import '../../core/services/providers.dart';
import '../../core/services/vpn_service.dart';

class DashboardController {
  const DashboardController(this._ref);

  final Ref _ref;

  VpnService get _vpn => _ref.read(vpnServiceProvider);
  ConfigService get _cfg => _ref.read(configServiceProvider);

  Future<void> toggleConnection() async {
    final status = _ref.read(tunnelStatusProvider);
    if (status.canConnect) {
      await _connect();
    } else if (status.canDisconnect) {
      await _vpn.disconnect();
    }
  }

  Future<void> _connect() async {
    final configs = await _cfg.loadAll();
    if (configs.isEmpty) {
      throw Exception('No config found. Please import or create a config in Settings.');
    }
    final config = configs.first;
    final prepared = await _vpn.prepareVpn();
    if (!prepared) {
      throw Exception('VPN permission denied');
    }
    await _vpn.connect(config);
  }
}

final dashboardControllerProvider = Provider((ref) => DashboardController(ref));
