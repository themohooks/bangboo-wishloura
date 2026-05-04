import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/services/config_service.dart';
import 'package:flutter_vpn_go/core/models/transport_type.dart';
import 'package:flutter_vpn_go/core/storage/config_storage.dart';
import 'package:flutter_vpn_go/core/storage/secure_storage.dart';
import 'package:flutter_vpn_go/core/models/tunnel_config.dart';

void main() {
  late ConfigService service;

  setUp(() {
    service = ConfigService(
      _FakeConfigStorage(),
      // forTesting() does not call native Keychain — safe in unit tests
      SecureStorage.forTesting(),
    );
  });

  group('ConfigService.parseImport', () {
    test('rejects invalid JSON', () {
      final result = service.parseImport('not { valid json');
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });

    test('rejects missing serverHost', () {
      final result = service.parseImport('{"serverPort":443}');
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('serverHost')), isTrue);
    });

    test('rejects port = 0', () {
      final result = service.parseImport(
          '{"serverHost":"h.com","serverPort":0}');
      expect(result.isValid, isFalse);
    });

    test('rejects port > 65535', () {
      final result = service.parseImport(
          '{"serverHost":"h.com","serverPort":99999}');
      expect(result.isValid, isFalse);
    });

    test('rejects invalid mtu', () {
      final result = service.parseImport(
          '{"serverHost":"h.com","serverPort":443,"mtu":100}');
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('mtu')), isTrue);
    });

    test('rejects workers = 0', () {
      final result = service.parseImport(
          '{"serverHost":"h.com","serverPort":443,"workers":0}');
      expect(result.isValid, isFalse);
    });

    test('rejects workers > 32', () {
      final result = service.parseImport(
          '{"serverHost":"h.com","serverPort":443,"workers":33}');
      expect(result.isValid, isFalse);
    });

    test('rejects invalid DNS', () {
      final result = service.parseImport(
          '{"serverHost":"h.com","serverPort":443,"dnsServers":["not-ip"]}');
      expect(result.isValid, isFalse);
    });

    test('rejects invalid CIDR in allowedIPv4Routes', () {
      final result = service.parseImport(
          '{"serverHost":"h.com","serverPort":443,"allowedIPv4Routes":["bad"]}');
      expect(result.isValid, isFalse);
    });

    test('accepts minimal valid config (host + port only)', () {
      final result = service.parseImport(
          '{"serverHost":"example.com","serverPort":443}');
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
      expect(result.config, isNotNull);
      expect(result.config!.serverHost, 'example.com');
      expect(result.config!.serverPort, 443);
    });

    test('applies sane defaults for missing optional fields', () {
      final result = service.parseImport(
          '{"serverHost":"example.com","serverPort":443}');
      expect(result.isValid, isTrue);
      expect(result.config!.mtu, 1280);
      expect(result.config!.workers, 4);
      expect(result.config!.keepAliveSeconds, 25);
    });

    test('parses full import payload', () {
      const payload = '''
      {
        "name": "My VPN",
        "serverHost": "vpn.example.com",
        "serverPort": 443,
        "transportType": "mock",
        "authToken": "secret-token",
        "deviceId": "auto",
        "mtu": 1280,
        "dnsServers": ["1.1.1.1", "8.8.8.8"],
        "ipv4Address": "10.7.0.2",
        "ipv4SubnetMask": "255.255.255.0",
        "allowedIPv4Routes": ["0.0.0.0/0"],
        "excludedIPv4Routes": [],
        "keepAliveSeconds": 25,
        "workers": 4,
        "enableUdp": true,
        "enableTcp": true,
        "autoReconnect": true,
        "maxReconnectAttempts": 3
      }
      ''';
      final result = service.parseImport(payload);
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
      expect(result.config!.name, 'My VPN');
      expect(result.config!.serverHost, 'vpn.example.com');
      expect(result.config!.transportType, TransportType.mock);
      // authToken is present in parsed config (stripped before storage)
      expect(result.config!.authToken, 'secret-token');
    });
  });

  group('ConfigValidationResult', () {
    test('isValid = false when errors non-empty', () {
      final r = ConfigValidationResult(errors: ['oops'], config: null);
      expect(r.isValid, isFalse);
    });

    test('isValid = true when errors empty', () {
      final r = ConfigValidationResult(errors: [], config: null);
      expect(r.isValid, isTrue);
    });
  });
}

// ── Minimal stub ─────────────────────────────────────────────────────────────

class _FakeConfigStorage extends ConfigStorage {
  @override
  Future<List<TunnelConfig>> loadAll() async => [];
  @override
  Future<void> saveOne(TunnelConfig config) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> saveAll(List<TunnelConfig> configs) async {}
}
