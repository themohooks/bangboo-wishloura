// ignore_for_file: constant_identifier_names

enum TunnelStatus {
  disconnected,
  preparing,
  connecting,
  connected,
  reconnecting,
  disconnecting,
  failed;

  static TunnelStatus fromString(String value) {
    switch (value) {
      case 'disconnected':
        return disconnected;
      case 'preparing':
        return preparing;
      case 'connecting':
        return connecting;
      case 'connected':
        return connected;
      case 'reconnecting':
        return reconnecting;
      case 'disconnecting':
        return disconnecting;
      case 'failed':
        return failed;
      default:
        return disconnected;
    }
  }

  String toJson() => name;

  bool get isActive => this == connected || this == connecting || this == reconnecting;
  bool get isTransitioning => this == connecting || this == disconnecting || this == preparing || this == reconnecting;
  bool get canConnect => this == disconnected || this == failed;
  bool get canDisconnect => this == connected || this == connecting || this == reconnecting;

  String get displayName {
    switch (this) {
      case disconnected:
        return 'Disconnected';
      case preparing:
        return 'Preparing…';
      case connecting:
        return 'Connecting…';
      case connected:
        return 'Connected';
      case reconnecting:
        return 'Reconnecting…';
      case disconnecting:
        return 'Disconnecting…';
      case failed:
        return 'Failed';
    }
  }
}

class TunnelStatusState {
  const TunnelStatusState({
    required this.status,
    this.lastError,
    this.serverHost,
    this.transportType,
    this.uptimeSeconds,
  });

  final TunnelStatus status;
  final String? lastError;
  final String? serverHost;
  final String? transportType;
  final int? uptimeSeconds;

  static const TunnelStatusState initial = TunnelStatusState(status: TunnelStatus.disconnected);

  TunnelStatusState copyWith({
    TunnelStatus? status,
    String? lastError,
    String? serverHost,
    String? transportType,
    int? uptimeSeconds,
    bool clearError = false,
  }) {
    return TunnelStatusState(
      status: status ?? this.status,
      lastError: clearError ? null : (lastError ?? this.lastError),
      serverHost: serverHost ?? this.serverHost,
      transportType: transportType ?? this.transportType,
      uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TunnelStatusState &&
      other.status == status &&
      other.lastError == lastError &&
      other.serverHost == serverHost &&
      other.transportType == transportType &&
      other.uptimeSeconds == uptimeSeconds;

  @override
  int get hashCode => Object.hash(status, lastError, serverHost, transportType, uptimeSeconds);
}
