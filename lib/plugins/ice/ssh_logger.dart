import 'dart:collection';
import 'package:flutter/foundation.dart';

enum SshLogLevel { info, warn, error, data }

class SshLogEntry {
  final DateTime timestamp;
  final SshLogLevel level;
  final String message;

  const SshLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });
}

class SshLogger extends ValueNotifier<List<SshLogEntry>> {
  static final SshLogger instance = SshLogger._();
  static const int _maxEntries = 500;
  final ListQueue<SshLogEntry> _buffer = ListQueue();

  SshLogger._() : super([]);

  void log(SshLogLevel level, String message) {
    final entry = SshLogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );
    _buffer.add(entry);
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }
    // Notify listeners with a copy
    value = _buffer.toList();
  }

  static void i(String msg) => instance.log(SshLogLevel.info, msg);
  static void w(String msg) => instance.log(SshLogLevel.warn, msg);
  static void e(String msg) => instance.log(SshLogLevel.error, msg);
  static void d(String msg) => instance.log(SshLogLevel.data, msg);

  void clear() {
    _buffer.clear();
    value = [];
  }
}
