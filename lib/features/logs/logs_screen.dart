import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/log_entry.dart';
import '../../core/services/providers.dart';
import 'logs_controller.dart';

class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  static const _levels = ['debug', 'info', 'warning', 'error'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(filteredLogEntriesProvider);
    final filter = ref.watch(logLevelFilterProvider);
    final ctrl = ref.read(logsControllerProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy diagnostics',
            onPressed: () async {
              final text = entries.map((e) {
                final ts = e.timestamp.toIso8601String();
                final rep = e.repeatCount > 1 ? ' (×${e.repeatCount})' : '';
                return '[$ts] [${e.level.toUpperCase()}] [${e.category}] ${e.message}$rep';
              }).join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs copied to clipboard')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: () {
              ctrl.clearLogs();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Level filter chips ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _levels.map((level) {
                  final selected = filter == level;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        level.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.black : _levelColor(level, cs),
                        ),
                      ),
                      selected: selected,
                      onSelected: (_) => ctrl.setFilter(level),
                      backgroundColor: const Color(0xFF1A1A1A),
                      selectedColor: _levelColor(level, cs),
                      checkmarkColor: Colors.black,
                      side: BorderSide(color: _levelColor(level, cs).withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // ── Log list ─────────────────────────────────────────────────
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'No logs',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final entry = entries[entries.length - 1 - i];
                      return _LogTile(entry: entry, cs: cs);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static Color _levelColor(String level, ColorScheme cs) {
    switch (level) {
      case 'error':
        return cs.error;
      case 'warning':
        return Colors.amber;
      case 'info':
        return cs.primary;
      default:
        return Colors.white38;
    }
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry, required this.cs});

  final LogEntry entry;
  final ColorScheme cs;

  static Color _levelColor(String level, ColorScheme cs) {
    switch (level) {
      case 'error':
        return cs.error;
      case 'warning':
        return Colors.amber;
      case 'info':
        return cs.primary;
      default:
        return Colors.white24;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(entry.level, cs);
    final time = '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        border: Border(left: BorderSide(color: color, width: 2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            time,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white24,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          // Level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.level.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Category
          Text(
            '[${entry.category}]',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white38,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          // Message
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: 12,
                color: color == Colors.white24 ? Colors.white54 : Colors.white70,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Repeat count
          if (entry.repeatCount > 1)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '×${entry.repeatCount}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white38,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
