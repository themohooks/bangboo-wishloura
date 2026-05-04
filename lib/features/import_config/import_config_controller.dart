import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/config_service.dart';
import '../../core/services/providers.dart';

class ImportConfigController {
  const ImportConfigController(this._ref);

  final Ref _ref;

  ConfigValidationResult validate(String json) =>
      _ref.read(configServiceProvider).parseImport(json);

  Future<void> importConfig(String json) async {
    final result = _ref.read(configServiceProvider).parseImport(json);
    if (!result.isValid || result.config == null) {
      throw Exception(result.errors.join('\n'));
    }
    await _ref.read(configServiceProvider).save(result.config!);
    _ref.invalidate(tunnelConfigListProvider);
  }
}

final importConfigControllerProvider =
    Provider((ref) => ImportConfigController(ref));
