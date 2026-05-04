import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/models/log_entry.dart';

void main() {
  group('LogEntry', () {
    const entry = LogEntry(
      id: 'abc-123',
      timestamp: _ts,
      level: 'info',
      category: 'VpnService',
      message: 'Connected successfully',
    );

    test('defaults repeatCount to 1', () {
      expect(entry.repeatCount, 1);
    });

    test('copyWith updates repeatCount', () {
      final repeated = entry.copyWith(repeatCount: 5);
      expect(repeated.repeatCount, 5);
      expect(repeated.message, entry.message);
    });

    test('toJson / fromJson round-trip', () {
      final json = entry.toJson();
      final restored = LogEntry.fromJson(json);
      expect(restored.id, entry.id);
      expect(restored.level, entry.level);
      expect(restored.category, entry.category);
      expect(restored.message, entry.message);
      expect(restored.repeatCount, 1);
    });

    test('equality based on id', () {
      const same = LogEntry(
        id: 'abc-123',
        timestamp: _ts,
        level: 'error',
        category: 'other',
        message: 'different message',
      );
      expect(entry, equals(same));
    });
  });

  group('LogLevelExt ordering', () {
    test('debug < info < warning < error', () {
      expect('debug'.levelOrder, lessThan('info'.levelOrder));
      expect('info'.levelOrder, lessThan('warning'.levelOrder));
      expect('warning'.levelOrder, lessThan('error'.levelOrder));
    });

    test('unknown level has order 0', () {
      expect('unknown'.levelOrder, 0);
    });
  });
}

const _ts = DateTime(2024, 1, 1, 12, 0, 0);
