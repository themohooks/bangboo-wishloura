import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/models/traffic_stats.dart';

void main() {
  group('TrafficStats', () {
    test('zero has all counters at 0', () {
      const s = TrafficStats.zero;
      expect(s.bytesIn, 0);
      expect(s.bytesOut, 0);
      expect(s.packetsIn, 0);
      expect(s.packetsOut, 0);
      expect(s.activeStreams, 0);
    });

    test('toJson / fromJson round-trip', () {
      final stats = TrafficStats(
        bytesIn: 1024,
        bytesOut: 2048,
        packetsIn: 10,
        packetsOut: 20,
        activeStreams: 3,
        updatedAt: DateTime(2024, 6, 1, 12, 0, 0),
      );
      final json = stats.toJson();
      final restored = TrafficStats.fromJson(json);

      expect(restored.bytesIn, 1024);
      expect(restored.bytesOut, 2048);
      expect(restored.packetsIn, 10);
      expect(restored.packetsOut, 20);
      expect(restored.activeStreams, 3);
    });

    test('fromJson provides zero defaults for missing fields', () {
      final stats = TrafficStats.fromJson({});
      expect(stats.bytesIn, 0);
      expect(stats.packetsIn, 0);
      expect(stats.activeStreams, 0);
    });

    test('equality ignores updatedAt', () {
      final a = TrafficStats(
        bytesIn: 100,
        bytesOut: 200,
        packetsIn: 1,
        packetsOut: 2,
        activeStreams: 0,
        updatedAt: DateTime(2024),
      );
      final b = TrafficStats(
        bytesIn: 100,
        bytesOut: 200,
        packetsIn: 1,
        packetsOut: 2,
        activeStreams: 0,
        updatedAt: DateTime(2025),
      );
      expect(a, equals(b));
    });
  });
}
