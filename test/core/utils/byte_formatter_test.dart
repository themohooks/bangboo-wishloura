import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vpn_go/core/utils/byte_formatter.dart';

void main() {
  group('ByteFormatter.format', () {
    test('formats bytes', () {
      expect(ByteFormatter.format(0), '0 B');
      expect(ByteFormatter.format(512), '512 B');
      expect(ByteFormatter.format(1023), '1023 B');
    });

    test('formats kilobytes', () {
      expect(ByteFormatter.format(1024), '1.0 KB');
      expect(ByteFormatter.format(2048), '2.0 KB');
      expect(ByteFormatter.format(1536), '1.5 KB');
    });

    test('formats megabytes', () {
      expect(ByteFormatter.format(1024 * 1024), '1.00 MB');
      expect(ByteFormatter.format(5 * 1024 * 1024), '5.00 MB');
    });

    test('formats gigabytes', () {
      expect(ByteFormatter.format(1024 * 1024 * 1024), '1.00 GB');
    });
  });

  group('ByteFormatter.formatSpeed', () {
    test('appends /s suffix', () {
      expect(ByteFormatter.formatSpeed(1024), '1.0 KB/s');
    });
  });

  group('ByteFormatter.formatUptime', () {
    test('formats seconds', () {
      expect(ByteFormatter.formatUptime(0), '0s');
      expect(ByteFormatter.formatUptime(45), '45s');
    });

    test('formats minutes and seconds', () {
      expect(ByteFormatter.formatUptime(60), '1m 0s');
      expect(ByteFormatter.formatUptime(90), '1m 30s');
      expect(ByteFormatter.formatUptime(3599), '59m 59s');
    });

    test('formats hours, minutes, seconds', () {
      expect(ByteFormatter.formatUptime(3600), '1h 0m 0s');
      expect(ByteFormatter.formatUptime(3661), '1h 1m 1s');
      expect(ByteFormatter.formatUptime(7322), '2h 2m 2s');
    });
  });
}
