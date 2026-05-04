import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';

class LogsController {
  const LogsController(this._ref);

  final Ref _ref;

  void clearLogs() {
    _ref.read(logServiceProvider).clear();
  }

  void setFilter(String level) {
    _ref.read(logLevelFilterProvider.notifier).state = level;
  }
}

final logsControllerProvider = Provider((ref) => LogsController(ref));
