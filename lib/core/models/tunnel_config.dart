import 'package:flutter_vpn_go/core/models/transport_type.dart';

class TunnelConfig {
  const TunnelConfig({
    required this.id,
    required this.name,
    required this.serverHost,
    required this.serverPort,
    required this.transportType,
    this.authToken,
    required this.deviceId,
    required this.mtu,
    required this.dnsServers,
    required this.ipv4Address,
    required this.ipv4SubnetMask,
    required this.allowedIPv4Routes,
    required this.excludedIPv4Routes,
    required this.keepAliveSeconds,
    required this.workers,
    this.sni,
    required this.enableUdp,
    required this.enableTcp,
    required this.autoReconnect,
    required this.maxReconnectAttempts,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String serverHost;
  final int serverPort;
  final TransportType transportType;

  /// WARNING: never persist to plain storage; use SecureStorage.
  final String? authToken;
  final String deviceId;
  final int mtu;
  final List<String> dnsServers;
  final String ipv4Address;
  final String ipv4SubnetMask;
  final List<String> allowedIPv4Routes;
  final List<String> excludedIPv4Routes;
  final int keepAliveSeconds;
  final int workers;
  final String? sni;
  final bool enableUdp;
  final bool enableTcp;
  final bool autoReconnect;
  final int maxReconnectAttempts;
  final DateTime createdAt;
  final DateTime updatedAt;

  static TunnelConfig get defaults => TunnelConfig(
        id: '',
        name: 'My Tunnel',
        serverHost: '',
        serverPort: 443,
        transportType: TransportType.mock,
        deviceId: 'auto',
        mtu: 1280,
        dnsServers: const ['1.1.1.1', '8.8.8.8'],
        ipv4Address: '10.7.0.2',
        ipv4SubnetMask: '255.255.255.0',
        allowedIPv4Routes: const ['0.0.0.0/0'],
        excludedIPv4Routes: const [],
        keepAliveSeconds: 25,
        workers: 4,
        enableUdp: true,
        enableTcp: true,
        autoReconnect: true,
        maxReconnectAttempts: 3,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  TunnelConfig copyWith({
    String? id,
    String? name,
    String? serverHost,
    int? serverPort,
    TransportType? transportType,
    String? authToken,
    String? deviceId,
    int? mtu,
    List<String>? dnsServers,
    String? ipv4Address,
    String? ipv4SubnetMask,
    List<String>? allowedIPv4Routes,
    List<String>? excludedIPv4Routes,
    int? keepAliveSeconds,
    int? workers,
    String? sni,
    bool? enableUdp,
    bool? enableTcp,
    bool? autoReconnect,
    int? maxReconnectAttempts,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearAuthToken = false,
    bool clearSni = false,
  }) {
    return TunnelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      transportType: transportType ?? this.transportType,
      authToken: clearAuthToken ? null : (authToken ?? this.authToken),
      deviceId: deviceId ?? this.deviceId,
      mtu: mtu ?? this.mtu,
      dnsServers: dnsServers ?? this.dnsServers,
      ipv4Address: ipv4Address ?? this.ipv4Address,
      ipv4SubnetMask: ipv4SubnetMask ?? this.ipv4SubnetMask,
      allowedIPv4Routes: allowedIPv4Routes ?? this.allowedIPv4Routes,
      excludedIPv4Routes: excludedIPv4Routes ?? this.excludedIPv4Routes,
      keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
      workers: workers ?? this.workers,
      sni: clearSni ? null : (sni ?? this.sni),
      enableUdp: enableUdp ?? this.enableUdp,
      enableTcp: enableTcp ?? this.enableTcp,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Serialize to JSON — authToken is EXCLUDED; persist it separately.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'serverHost': serverHost,
      'serverPort': serverPort,
      'transportType': transportType.toJson(),
      'deviceId': deviceId,
      'mtu': mtu,
      'dnsServers': dnsServers,
      'ipv4Address': ipv4Address,
      'ipv4SubnetMask': ipv4SubnetMask,
      'allowedIPv4Routes': allowedIPv4Routes,
      'excludedIPv4Routes': excludedIPv4Routes,
      'keepAliveSeconds': keepAliveSeconds,
      'workers': workers,
      'sni': sni,
      'enableUdp': enableUdp,
      'enableTcp': enableTcp,
      'autoReconnect': autoReconnect,
      'maxReconnectAttempts': maxReconnectAttempts,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static TunnelConfig fromJson(Map<String, dynamic> json) {
    return TunnelConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'My Tunnel',
      serverHost: json['serverHost'] as String? ?? '',
      serverPort: json['serverPort'] as int? ?? 443,
      transportType: TransportType.fromJson(json['transportType'] as String? ?? 'mock'),
      authToken: json['authToken'] as String?, // import only; strip before storage
      deviceId: json['deviceId'] as String? ?? 'auto',
      mtu: json['mtu'] as int? ?? 1280,
      dnsServers: _stringList(json['dnsServers']),
      ipv4Address: json['ipv4Address'] as String? ?? '10.7.0.2',
      ipv4SubnetMask: json['ipv4SubnetMask'] as String? ?? '255.255.255.0',
      allowedIPv4Routes: _stringList(json['allowedIPv4Routes']),
      excludedIPv4Routes: _stringList(json['excludedIPv4Routes']),
      keepAliveSeconds: json['keepAliveSeconds'] as int? ?? 25,
      workers: json['workers'] as int? ?? 4,
      sni: json['sni'] as String?,
      enableUdp: json['enableUdp'] as bool? ?? true,
      enableTcp: json['enableTcp'] as bool? ?? true,
      autoReconnect: json['autoReconnect'] as bool? ?? true,
      maxReconnectAttempts: json['maxReconnectAttempts'] as int? ?? 3,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    try {
      return DateTime.parse(value as String);
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TunnelConfig && other.id == id && other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, updatedAt);
}
