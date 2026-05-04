import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/models/log_entry.dart';
import 'package:flutter_vpn_go/core/services/log_service.dart';

void main() {
  late LogService service;

  setUp(() => service = LogService());
  tearDown(() => service.dispose());

  group('LogService.add', () {
    test('adds a new entry', () {
      service.info('Test', 'hello');
      expect(service.entries, hasLength(1));
      expect(service.entries.first.message, 'hello');
      expect(service.entries.first.level, 'info');
    });

    test('groups consecutive identical messages', () {
      service.info('Cat', 'same message');
      service.info('Cat', 'same message');
      service.info('Cat', 'same message');
      expect(service.entries, hasLength(1));
      expect(service.entries.first.repeatCount, 3);
    });

    test('does not group messages with different level', () {
      service.info('Cat', 'msg');
      service.error('Cat', 'msg');
      expect(service.entries, hasLength(2));
    });

    test('does not group messages with different category', () {
      service.info('CatA', 'msg');
      service.info('CatB', 'msg');
      expect(service.entries, hasLength(2));
    });

    test('does not group non-consecutive same messages', () {
      service.info('Cat', 'msg A');
      service.info('Cat', 'msg B');
      service.info('Cat', 'msg A'); // same as first but not consecutive
      expect(service.entries, hasLength(3));
    });

    test('caps buffer at 1000 entries', () {
      for (var i = 0; i < 1100; i++) {
        service.info('Cat', 'message $i'); // all different → no grouping
      }
      expect(service.entries.length, lessThanOrEqualTo(1000));
    });
  });

  group('LogService.filtered', () {
    setUp(() {
      service.debug('Cat', 'debug msg');
      service.info('Cat', 'info msg');
      service.warning('Cat', 'warn msg');
      service.error('Cat', 'error msg');
    });

    test('debug shows all', () {
      expect(service.filtered('debug'), hasLength(4));
    });

    test('info filters out debug', () {
      final result = service.filtered('info');
      expect(result.any((e) => e.level == 'debug'), isFalse);
      expect(result, hasLength(3));
    });

    test('warning shows warning and error only', () {
      final result = service.filtered('warning');
      expect(result, hasLength(2));
      expect(result.every((e) => e.level == 'warning' || e.level == 'error'),
          isTrue);
    });

    test('error shows only errors', () {
      final result = service.filtered('error');
      expect(result, hasLength(1));
      expect(result.first.level, 'error');
    });
  });

  group('LogService.clear', () {
    test('removes all entries', () {
      service.info('Cat', 'msg');
      service.clear();
      expect(service.entries, isEmpty);
    });
  });

  group('LogService.addAll', () {
    test('adds multiple entries and groups repeated', () {
      final entries = [
        LogEntry(
          id: '1',
          timestamp: DateTime.now(),
          level: 'info',
          category: 'A',
          message: 'first',
        ),
        LogEntry(
          id: '2',
          timestamp: DateTime.now(),
          level: 'info',
          category: 'A',
          message: 'first', // duplicate of above
        ),
        LogEntry(
          id: '3',
          timestamp: DateTime.now(),
          level: 'error',
          category: 'B',
          message: 'second',
        ),
      ];
      service.addAll(entries);
      expect(service.entries.length, 2);
      expect(service.entries.first.repeatCount, 2);
    });
  });

  group('LogService notifications', () {
    test('notifies listeners on add', () {
      var notified = false;
      service.addListener(() => notified = true);
      service.info('Cat', 'msg');
      expect(notified, isTrue);
    });

    test('notifies listeners on clear', () {
      service.info('Cat', 'msg');
      var notified = false;
      service.addListener(() => notified = true);
      service.clear();
      expect(notified, isTrue);
    });
  });
}
