class TrafficStats {
  const TrafficStats({
    required this.bytesIn,
    required this.bytesOut,
    required this.packetsIn,
    required this.packetsOut,
    required this.activeStreams,
    required this.updatedAt,
  });

  final int bytesIn;
  final int bytesOut;
  final int packetsIn;
  final int packetsOut;
  final int activeStreams;
  final DateTime updatedAt;

  static const TrafficStats zero = TrafficStats(
    bytesIn: 0,
    bytesOut: 0,
    packetsIn: 0,
    packetsOut: 0,
    activeStreams: 0,
    updatedAt: _epoch,
  );

  static const DateTime _epoch = DateTime.utc(1970);

  Map<String, dynamic> toJson() => {
        'bytesIn': bytesIn,
        'bytesOut': bytesOut,
        'packetsIn': packetsIn,
        'packetsOut': packetsOut,
        'activeStreams': activeStreams,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static TrafficStats fromJson(Map<String, dynamic> json) => TrafficStats(
        bytesIn: json['bytesIn'] as int? ?? 0,
        bytesOut: json['bytesOut'] as int? ?? 0,
        packetsIn: json['packetsIn'] as int? ?? 0,
        packetsOut: json['packetsOut'] as int? ?? 0,
        activeStreams: json['activeStreams'] as int? ?? 0,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      other is TrafficStats &&
      other.bytesIn == bytesIn &&
      other.bytesOut == bytesOut &&
      other.packetsIn == packetsIn &&
      other.packetsOut == packetsOut &&
      other.activeStreams == activeStreams;

  @override
  int get hashCode =>
      Object.hash(bytesIn, bytesOut, packetsIn, packetsOut, activeStreams);
}
