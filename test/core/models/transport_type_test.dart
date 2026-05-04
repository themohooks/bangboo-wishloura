import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/models/transport_type.dart';

void main() {
  group('TransportType', () {
    test('toJson returns correct string for each value', () {
      expect(TransportType.mock.toJson(), 'mock');
      expect(TransportType.socksKcpSmux.toJson(), 'socksKcpSmux');
      expect(TransportType.wireguard.toJson(), 'wireguard');
      expect(TransportType.custom.toJson(), 'custom');
    });

    test('fromJson parses all known values', () {
      expect(TransportType.fromJson('mock'), TransportType.mock);
      expect(TransportType.fromJson('socksKcpSmux'), TransportType.socksKcpSmux);
      expect(TransportType.fromJson('wireguard'), TransportType.wireguard);
      expect(TransportType.fromJson('custom'), TransportType.custom);
    });

    test('fromJson throws on unknown value', () {
      expect(() => TransportType.fromJson('unknown'), throwsArgumentError);
    });

    test('displayName is non-empty for all values', () {
      for (final t in TransportType.values) {
        expect(t.displayName, isNotEmpty);
      }
    });

    test('toJson / fromJson round-trip', () {
      for (final t in TransportType.values) {
        expect(TransportType.fromJson(t.toJson()), t);
      }
    });
  });
}
