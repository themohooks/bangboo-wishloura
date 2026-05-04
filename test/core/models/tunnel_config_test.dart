import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/models/tunnel_config.dart';
import 'package:flutter_vpn_go/core/models/transport_type.dart';

void main() {
  group('TunnelConfig', () {
    late TunnelConfig config;

    setUp(() {
      config = TunnelConfig(
        id: 'test-id',
        name: 'Test Tunnel',
        serverHost: 'example.com',
        serverPort: 443,
        transportType: TransportType.mock,
        authToken: 'secret-token',
        deviceId: 'device-123',
        mtu: 1280,
        dnsServers: const ['1.1.1.1', '8.8.8.8'],
        ipv4Address: '10.7.0.2',
        ipv4SubnetMask: '255.255.255.0',
        allowedIPv4Routes: const ['0.0.0.0/0'],
        excludedIPv4Routes: const [],
        keepAliveSeconds: 25,
        workers: 4,
        sni: 'example.com',
        enableUdp: true,
        enableTcp: true,
        autoReconnect: true,
        maxReconnectAttempts: 3,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 2),
      );
    });

    test('toJson excludes authToken', () {
      final json = config.toJson();
      expect(json.containsKey('authToken'), isFalse,
          reason: 'authToken must not be in plain JSON storage');
    });

    test('toJson includes all other fields', () {
      final json = config.toJson();
      expect(json['id'], 'test-id');
      expect(json['serverHost'], 'example.com');
      expect(json['serverPort'], 443);
      expect(json['transportType'], 'mock');
      expect(json['mtu'], 1280);
      expect(json['workers'], 4);
      expect(json['dnsServers'], ['1.1.1.1', '8.8.8.8']);
      expect(json['allowedIPv4Routes'], ['0.0.0.0/0']);
      expect(json['enableUdp'], true);
      expect(json['autoReconnect'], true);
    });

    test('fromJson round-trip preserves all non-secret fields', () {
      final json = config.toJson();
      final restored = TunnelConfig.fromJson(json);

      expect(restored.id, config.id);
      expect(restored.name, config.name);
      expect(restored.serverHost, config.serverHost);
      expect(restored.serverPort, config.serverPort);
      expect(restored.transportType, config.transportType);
      expect(restored.mtu, config.mtu);
      expect(restored.dnsServers, config.dnsServers);
      expect(restored.allowedIPv4Routes, config.allowedIPv4Routes);
      expect(restored.enableUdp, config.enableUdp);
      expect(restored.autoReconnect, config.autoReconnect);
      // authToken is absent from JSON → null on restore
      expect(restored.authToken, isNull);
    });

    test('fromJson parses authToken when present in import JSON', () {
      final importJson = {
        ...config.toJson(),
        'authToken': 'import-token',
      };
      final restored = TunnelConfig.fromJson(importJson);
      expect(restored.authToken, 'import-token');
    });

    test('copyWith clearAuthToken removes the token', () {
      final cleared = config.copyWith(clearAuthToken: true);
      expect(cleared.authToken, isNull);
      expect(cleared.serverHost, config.serverHost);
    });

    test('defaults are sane', () {
      final d = TunnelConfig.defaults;
      expect(d.mtu, greaterThanOrEqualTo(576));
      expect(d.mtu, lessThanOrEqualTo(1500));
      expect(d.serverPort, inInclusiveRange(1, 65535));
      expect(d.workers, inInclusiveRange(1, 32));
      expect(d.keepAliveSeconds, inInclusiveRange(5, 300));
      expect(d.dnsServers, isNotEmpty);
    });

    test('equality based on id and updatedAt', () {
      final same = config.copyWith(updatedAt: config.updatedAt);
      final different = config.copyWith(updatedAt: DateTime(2025));
      expect(config, equals(same));
      expect(config, isNot(equals(different)));
    });
  });

  group('TunnelConfig.fromJson with real import payload', () {
    const sampleJson = '''
    {
      "name": "My Tunnel",
      "serverHost": "vpn.example.com",
      "serverPort": 443,
      "transportType": "socksKcpSmux",
      "authToken": "tok123",
      "deviceId": "auto",
      "mtu": 1280,
      "dnsServers": ["1.1.1.1"],
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

    test('parses valid import JSON without error', () {
      final map = json.decode(sampleJson) as Map<String, dynamic>;
      final config = TunnelConfig.fromJson(map);
      expect(config.serverHost, 'vpn.example.com');
      expect(config.transportType, TransportType.socksKcpSmux);
      expect(config.authToken, 'tok123');
    });

    test('provides defaults for missing optional fields', () {
      final minimal = TunnelConfig.fromJson({
        'serverHost': 'host.com',
        'serverPort': 8080,
      });
      expect(minimal.mtu, 1280);
      expect(minimal.workers, 4);
      expect(minimal.keepAliveSeconds, 25);
      expect(minimal.enableUdp, isTrue);
    });
  });
}
