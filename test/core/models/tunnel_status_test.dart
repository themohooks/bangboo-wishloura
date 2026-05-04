import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/models/tunnel_status.dart';

void main() {
  group('TunnelStatus', () {
    test('fromString parses all known values', () {
      expect(TunnelStatus.fromString('disconnected'), TunnelStatus.disconnected);
      expect(TunnelStatus.fromString('preparing'), TunnelStatus.preparing);
      expect(TunnelStatus.fromString('connecting'), TunnelStatus.connecting);
      expect(TunnelStatus.fromString('connected'), TunnelStatus.connected);
      expect(TunnelStatus.fromString('reconnecting'), TunnelStatus.reconnecting);
      expect(TunnelStatus.fromString('disconnecting'), TunnelStatus.disconnecting);
      expect(TunnelStatus.fromString('failed'), TunnelStatus.failed);
    });

    test('fromString returns disconnected for unknown value', () {
      expect(TunnelStatus.fromString('bogus'), TunnelStatus.disconnected);
    });

    group('isActive', () {
      test('connected, connecting, reconnecting are active', () {
        expect(TunnelStatus.connected.isActive, isTrue);
        expect(TunnelStatus.connecting.isActive, isTrue);
        expect(TunnelStatus.reconnecting.isActive, isTrue);
      });

      test('disconnected, preparing, disconnecting, failed are not active', () {
        expect(TunnelStatus.disconnected.isActive, isFalse);
        expect(TunnelStatus.preparing.isActive, isFalse);
        expect(TunnelStatus.disconnecting.isActive, isFalse);
        expect(TunnelStatus.failed.isActive, isFalse);
      });
    });

    group('canConnect', () {
      test('disconnected and failed can connect', () {
        expect(TunnelStatus.disconnected.canConnect, isTrue);
        expect(TunnelStatus.failed.canConnect, isTrue);
      });

      test('active states cannot connect', () {
        expect(TunnelStatus.connected.canConnect, isFalse);
        expect(TunnelStatus.connecting.canConnect, isFalse);
        expect(TunnelStatus.reconnecting.canConnect, isFalse);
        expect(TunnelStatus.preparing.canConnect, isFalse);
        expect(TunnelStatus.disconnecting.canConnect, isFalse);
      });
    });

    group('canDisconnect', () {
      test('connected, connecting, reconnecting can disconnect', () {
        expect(TunnelStatus.connected.canDisconnect, isTrue);
        expect(TunnelStatus.connecting.canDisconnect, isTrue);
        expect(TunnelStatus.reconnecting.canDisconnect, isTrue);
      });

      test('disconnected, failed, preparing, disconnecting cannot', () {
        expect(TunnelStatus.disconnected.canDisconnect, isFalse);
        expect(TunnelStatus.failed.canDisconnect, isFalse);
        expect(TunnelStatus.preparing.canDisconnect, isFalse);
        expect(TunnelStatus.disconnecting.canDisconnect, isFalse);
      });
    });

    test('displayName is non-empty for all values', () {
      for (final s in TunnelStatus.values) {
        expect(s.displayName, isNotEmpty);
      }
    });
  });

  group('TunnelStatusState', () {
    test('initial state is disconnected with no error', () {
      const state = TunnelStatusState.initial;
      expect(state.status, TunnelStatus.disconnected);
      expect(state.lastError, isNull);
      expect(state.serverHost, isNull);
    });

    test('copyWith updates individual fields', () {
      const original = TunnelStatusState(status: TunnelStatus.disconnected);
      final updated = original.copyWith(
        status: TunnelStatus.connected,
        serverHost: 'example.com',
        uptimeSeconds: 42,
      );
      expect(updated.status, TunnelStatus.connected);
      expect(updated.serverHost, 'example.com');
      expect(updated.uptimeSeconds, 42);
      expect(updated.lastError, isNull);
    });

    test('copyWith clearError removes lastError', () {
      const state = TunnelStatusState(
        status: TunnelStatus.failed,
        lastError: 'something went wrong',
      );
      final cleared = state.copyWith(
        status: TunnelStatus.disconnected,
        clearError: true,
      );
      expect(cleared.lastError, isNull);
    });

    test('equality works correctly', () {
      const a = TunnelStatusState(
        status: TunnelStatus.connected,
        serverHost: 'host.com',
      );
      const b = TunnelStatusState(
        status: TunnelStatus.connected,
        serverHost: 'host.com',
      );
      expect(a, equals(b));
    });
  });
}
