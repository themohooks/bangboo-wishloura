import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/utils/validators.dart';

void main() {
  group('Validators.serverHost', () {
    test('rejects empty string', () {
      expect(Validators.serverHost(''), isNotNull);
      expect(Validators.serverHost('   '), isNotNull);
    });
    test('rejects null', () => expect(Validators.serverHost(null), isNotNull));
    test('accepts valid hostname', () {
      expect(Validators.serverHost('example.com'), isNull);
      expect(Validators.serverHost('192.168.1.1'), isNull);
    });
  });

  group('Validators.serverPort', () {
    test('rejects empty / null', () {
      expect(Validators.serverPort(''), isNotNull);
      expect(Validators.serverPort(null), isNotNull);
    });
    test('rejects non-numeric', () {
      expect(Validators.serverPort('abc'), isNotNull);
    });
    test('rejects out-of-range ports', () {
      expect(Validators.serverPort('0'), isNotNull);
      expect(Validators.serverPort('65536'), isNotNull);
      expect(Validators.serverPort('-1'), isNotNull);
    });
    test('accepts valid ports', () {
      expect(Validators.serverPort('1'), isNull);
      expect(Validators.serverPort('443'), isNull);
      expect(Validators.serverPort('65535'), isNull);
    });
  });

  group('Validators.mtu', () {
    test('rejects out-of-range', () {
      expect(Validators.mtu('575'), isNotNull);
      expect(Validators.mtu('1501'), isNotNull);
    });
    test('accepts boundary values', () {
      expect(Validators.mtu('576'), isNull);
      expect(Validators.mtu('1500'), isNull);
      expect(Validators.mtu('1280'), isNull);
    });
  });

  group('Validators.workers', () {
    test('rejects 0 and 33', () {
      expect(Validators.workers('0'), isNotNull);
      expect(Validators.workers('33'), isNotNull);
    });
    test('accepts 1..32', () {
      expect(Validators.workers('1'), isNull);
      expect(Validators.workers('32'), isNull);
      expect(Validators.workers('4'), isNull);
    });
  });

  group('Validators.keepAlive', () {
    test('rejects < 5 and > 300', () {
      expect(Validators.keepAlive('4'), isNotNull);
      expect(Validators.keepAlive('301'), isNotNull);
    });
    test('accepts 5..300', () {
      expect(Validators.keepAlive('5'), isNull);
      expect(Validators.keepAlive('300'), isNull);
      expect(Validators.keepAlive('25'), isNull);
    });
  });

  group('Validators.cidr', () {
    test('accepts valid CIDRs', () {
      expect(Validators.cidr('0.0.0.0/0'), isNull);
      expect(Validators.cidr('192.168.1.0/24'), isNull);
      expect(Validators.cidr('10.0.0.0/8'), isNull);
    });
    test('rejects invalid formats', () {
      expect(Validators.cidr('not-a-cidr'), isNotNull);
      expect(Validators.cidr('192.168.1.0'), isNotNull);   // missing prefix
      expect(Validators.cidr('192.168.1.0/33'), isNotNull); // prefix > 32
    });
    test('accepts null / empty (optional field)', () {
      expect(Validators.cidr(null), isNull);
      expect(Validators.cidr(''), isNull);
    });
  });

  group('Validators.dnsServer', () {
    test('accepts valid IP addresses', () {
      expect(Validators.dnsServer('1.1.1.1'), isNull);
      expect(Validators.dnsServer('8.8.8.8'), isNull);
    });
    test('rejects non-IP values', () {
      expect(Validators.dnsServer('not-an-ip'), isNotNull);
      expect(Validators.dnsServer(''), isNotNull);
    });
  });

  group('Validators.maskSecret', () {
    test('masks long secrets', () {
      final masked = Validators.maskSecret('abcdef123456');
      expect(masked, 'abcd********3456');
      expect(masked.contains('ef12'), isFalse);
    });
    test('masks short secrets with ****', () {
      expect(Validators.maskSecret('short'), '****');
      expect(Validators.maskSecret(''), '****');
    });
    test('masks null with ****', () {
      expect(Validators.maskSecret(null), '****');
    });
  });
}
