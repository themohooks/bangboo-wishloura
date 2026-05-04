import 'dart:io';

class Validators {
  const Validators._();

  static String? serverHost(String? value) {
    if (value == null || value.trim().isEmpty) return 'Server host is required';
    return null;
  }

  static String? serverPort(String? value) {
    if (value == null || value.trim().isEmpty) return 'Port is required';
    final port = int.tryParse(value.trim());
    if (port == null) return 'Port must be a number';
    if (port < 1 || port > 65535) return 'Port must be 1–65535';
    return null;
  }

  static String? mtu(String? value) {
    if (value == null || value.trim().isEmpty) return 'MTU is required';
    final mtu = int.tryParse(value.trim());
    if (mtu == null) return 'MTU must be a number';
    if (mtu < 576 || mtu > 1500) return 'MTU must be 576–1500';
    return null;
  }

  static String? workers(String? value) {
    if (value == null || value.trim().isEmpty) return 'Workers is required';
    final w = int.tryParse(value.trim());
    if (w == null) return 'Workers must be a number';
    if (w < 1 || w > 32) return 'Workers must be 1–32';
    return null;
  }

  static String? keepAlive(String? value) {
    if (value == null || value.trim().isEmpty) return 'Keep-alive is required';
    final s = int.tryParse(value.trim());
    if (s == null) return 'Keep-alive must be a number';
    if (s < 5 || s > 300) return 'Keep-alive must be 5–300 seconds';
    return null;
  }

  static String? ipAddress(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    try {
      InternetAddress(value.trim());
    } catch (_) {
      return 'Invalid IP address';
    }
    return null;
  }

  static String? dnsServer(String? value) {
    if (value == null || value.trim().isEmpty) return 'DNS server is required';
    try {
      InternetAddress(value.trim());
    } catch (_) {
      return 'Invalid IP address for DNS';
    }
    return null;
  }

  static String? cidr(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.trim().split('/');
    if (parts.length != 2) return 'Must be in CIDR format (e.g. 0.0.0.0/0)';
    try {
      InternetAddress(parts[0]);
    } catch (_) {
      return 'Invalid IP in CIDR';
    }
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return 'Prefix must be 0–32';
    return null;
  }

  static List<String> validateDnsServers(List<String> servers) {
    return servers.map((s) => dnsServer(s) ?? '').where((e) => e.isNotEmpty).toList();
  }

  static List<String> validateRoutes(List<String> routes) {
    return routes.map((r) => cidr(r) ?? '').where((e) => e.isNotEmpty).toList();
  }

  /// Masks sensitive strings: "abcdef123456" -> "abcd********3456"
  static String maskSecret(String? secret) {
    if (secret == null || secret.length <= 8) return '****';
    final start = secret.substring(0, 4);
    final end = secret.substring(secret.length - 4);
    return '$start********$end';
  }
}
