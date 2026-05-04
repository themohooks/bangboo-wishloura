import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';

/// In-memory log buffer with deduplication and level filtering.
/// Max 1000 entries; repeating messages are grouped.
class LogService extends ChangeNotifier {
  static const _maxEntries = 1000;
  final _entries = <LogEntry>[];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(LogEntry entry) {
    // Group consecutive repeated messages
    if (_entries.isNotEmpty) {
      final last = _entries.last;
      if (last.level == entry.level &&
          last.category == entry.category &&
          last.message == entry.message) {
        _entries[_entries.length - 1] = last.copyWith(repeatCount: last.repeatCount + 1);
        notifyListeners();
        return;
      }
    }

    if (_entries.length >= _maxEntries) {
      _entries.removeAt(0);
    }
    _entries.add(entry);
    notifyListeners();
  }

  void addRaw({
    required String level,
    required String category,
    required String message,
  }) {
    add(LogEntry(
      id: _id(),
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
    ));
  }

  void debug(String category, String message) => addRaw(level: 'debug', category: category, message: message);
  void info(String category, String message) => addRaw(level: 'info', category: category, message: message);
  void warning(String category, String message) => addRaw(level: 'warning', category: category, message: message);
  void error(String category, String message) => addRaw(level: 'error', category: category, message: message);

  void addAll(List<LogEntry> entries) {
    for (final e in entries) {
      add(e);
    }
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  List<LogEntry> filtered(String minLevel) {
    final minOrder = minLevel.levelOrder;
    return _entries.where((e) => e.level.levelOrder >= minOrder).toList();
  }

  static final _rng = Random();
  static String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_rng.nextInt(9999)}';
}
