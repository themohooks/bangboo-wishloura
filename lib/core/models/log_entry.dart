class LogEntry {
  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.repeatCount = 1,
  });

  final String id;
  final DateTime timestamp;

  /// "debug" | "info" | "warning" | "error"
  final String level;
  final String category;
  final String message;
  final int repeatCount;

  LogEntry copyWith({int? repeatCount}) => LogEntry(
        id: id,
        timestamp: timestamp,
        level: level,
        category: category,
        message: message,
        repeatCount: repeatCount ?? this.repeatCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'level': level,
        'category': category,
        'message': message,
        'repeatCount': repeatCount,
      };

  static LogEntry fromJson(Map<String, dynamic> json) => LogEntry(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        level: json['level'] as String,
        category: json['category'] as String,
        message: json['message'] as String,
        repeatCount: json['repeatCount'] as int? ?? 1,
      );

  @override
  bool operator ==(Object other) =>
      other is LogEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// Convenient log level ordering for filtering
extension LogLevelExt on String {
  static const _order = {'debug': 0, 'info': 1, 'warning': 2, 'error': 3};

  int get levelOrder => LogLevelExt._order[this] ?? 0;
}
