import 'dart:collection';

enum LogLevel { debug, info, warn, error }

class IceLogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;
  final String? data;

  const IceLogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'source': source,
    'message': message,
    if (data != null) 'data': data,
  };
}

class IceLogger {
  static const int _maxEntries = 200;
  static final ListQueue<IceLogEntry> _buffer = ListQueue();

  static void debug(String source, String message, {dynamic data}) {
    _add(LogLevel.debug, source, message, data);
  }

  static void info(String source, String message, {dynamic data}) {
    _add(LogLevel.info, source, message, data);
  }

  static void warn(String source, String message, {dynamic data}) {
    _add(LogLevel.warn, source, message, data);
  }

  static void error(String source, String message, {dynamic data, dynamic error}) {
    _add(LogLevel.error, source, message, _mergeData(data, error));
  }

  static void _add(LogLevel level, String source, String message, dynamic data) {
    _buffer.add(IceLogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
      data: data != null ? _stringify(data) : null,
    ));
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }
  }

  static String _stringify(dynamic data) {
    if (data is String) return data;
    try {
      return data.toString();
    } catch (_) {
      return '$data';
    }
  }

  static String? _mergeData(dynamic data, dynamic error) {
    if (error == null && data == null) return null;
    final parts = <String>[];
    if (data != null) parts.add(_stringify(data));
    if (error != null) parts.add('error: $error');
    return parts.join(' | ');
  }

  static List<IceLogEntry> recent({LogLevel? minLevel, int count = 50}) {
    final result = _buffer.toList().reversed;
    if (minLevel == null) return result.take(count).toList();
    return result
        .where((e) => e.level.index >= minLevel.index)
        .take(count)
        .toList();
  }

  static List<Map<String, dynamic>> recentJson({LogLevel? minLevel, int count = 50}) {
    return recent(minLevel: minLevel, count: count).map((e) => e.toJson()).toList();
  }

  static void clear() {
    _buffer.clear();
  }

  static int get count => _buffer.length;
}
