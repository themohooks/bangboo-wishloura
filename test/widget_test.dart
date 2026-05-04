// Top-level test file — unit checks that don't require platform channels.
// Widget rendering tests are intentionally skipped here because:
//   - The app uses Pigeon platform channels that require a real device/emulator
//   - Riverpod providers spin up VpnService which calls native code on init
//
// Run integration tests on a real device / emulator for full UI coverage.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_vpn_go/core/models/tunnel_status.dart';
import 'package:flutter_vpn_go/core/models/transport_type.dart';
import 'package:flutter_vpn_go/core/models/traffic_stats.dart';
import 'package:flutter_vpn_go/core/utils/byte_formatter.dart';
import 'package:flutter_vpn_go/core/utils/validators.dart';

void main() {
  group('Smoke — TunnelStatus', () {
    test('all statuses have displayName', () {
      for (final s in TunnelStatus.values) {
        expect(s.displayName, isNotEmpty);
      }
    });

    test('fromString / toJson round-trip', () {
      for (final s in TunnelStatus.values) {
        expect(TunnelStatus.fromString(s.toJson()), equals(s));
      }
    });
  });

  group('Smoke — TransportType', () {
    test('all types have displayName', () {
      for (final t in TransportType.values) {
        expect(t.displayName, isNotEmpty);
      }
    });

    test('toJson / fromJson round-trip', () {
      for (final t in TransportType.values) {
        expect(TransportType.fromJson(t.toJson()), equals(t));
      }
    });
  });

  group('Smoke — TrafficStats.zero', () {
    test('all counters are 0', () {
      expect(TrafficStats.zero.bytesIn, 0);
      expect(TrafficStats.zero.bytesOut, 0);
      expect(TrafficStats.zero.packetsIn, 0);
      expect(TrafficStats.zero.packetsOut, 0);
    });
  });

  group('Smoke — ByteFormatter', () {
    test('formats bytes', () => expect(ByteFormatter.format(512), '512 B'));
    test('formats KB', () => expect(ByteFormatter.format(1024), '1.0 KB'));
    test('formats MB', () => expect(ByteFormatter.format(1024 * 1024), '1.00 MB'));
    test('formats uptime', () {
      expect(ByteFormatter.formatUptime(0), '0s');
      expect(ByteFormatter.formatUptime(90), '1m 30s');
      expect(ByteFormatter.formatUptime(3661), '1h 1m 1s');
    });
  });

  group('Smoke — Validators', () {
    test('valid host passes', () => expect(Validators.serverHost('example.com'), isNull));
    test('empty host fails', () => expect(Validators.serverHost(''), isNotNull));
    test('valid port passes', () => expect(Validators.serverPort('443'), isNull));
    test('port 0 fails', () => expect(Validators.serverPort('0'), isNotNull));
    test('port 65536 fails', () => expect(Validators.serverPort('65536'), isNotNull));
    test('valid CIDR passes', () => expect(Validators.cidr('0.0.0.0/0'), isNull));
    test('invalid CIDR fails', () => expect(Validators.cidr('not-cidr'), isNotNull));
    test('maskSecret masks middle', () {
      expect(Validators.maskSecret('abcdef123456'), 'abcd********3456');
    });
  });
}
