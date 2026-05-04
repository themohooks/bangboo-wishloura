// ignore_for_file: constant_identifier_names

enum TransportType {
  mock,
  socksKcpSmux,
  wireguard,
  custom;

  String toJson() {
    switch (this) {
      case mock:
        return 'mock';
      case socksKcpSmux:
        return 'socksKcpSmux';
      case wireguard:
        return 'wireguard';
      case custom:
        return 'custom';
    }
  }

  static TransportType fromJson(String value) {
    switch (value) {
      case 'mock':
        return mock;
      case 'socksKcpSmux':
        return socksKcpSmux;
      case 'wireguard':
        return wireguard;
      case 'custom':
        return custom;
      default:
        throw ArgumentError('Unknown transport type: $value');
    }
  }

  String get displayName {
    switch (this) {
      case mock:
        return 'Mock (testing)';
      case socksKcpSmux:
        return 'SOCKS+KCP+SMUX';
      case wireguard:
        return 'WireGuard';
      case custom:
        return 'Custom';
    }
  }
}
