import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../providers/connection_status.dart' show sshStatus, SshStatus, getSshDir;
import '../../providers/theme_provider.dart' show themeNotifier;

class IceStateCollector {
  final DateTime _startedAt;
  int _requestCount = 0;
  int _errorCount = 0;

  IceStateCollector() : _startedAt = DateTime.now();

  int get requestCount => _requestCount;
  int get errorCount => _errorCount;
  void incrementRequestCount() => _requestCount++;
  void incrementErrorCount() => _errorCount++;
  DateTime get startedAt => _startedAt;

  Future<Map<String, dynamic>> collect() async {
    final info = await PackageInfo.fromPlatform();
    final themeMode = themeNotifier.value;

    String themeStr;
    switch (themeMode) {
      case ThemeMode.light:
        themeStr = 'light';
      case ThemeMode.dark:
        themeStr = 'dark';
      default:
        themeStr = 'system';
    }

    return {
      'app': {
        'version': '${info.version}(${info.buildNumber})',
        'packageName': info.packageName,
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'uptime': _formatUptime(),
        'themeMode': themeStr,
      },
      'server': {
        'port': 8100,
        'startedAt': _startedAt.toIso8601String(),
        'requestCount': _requestCount,
        'errorCount': _errorCount,
      },
      'ssh': await _collectSsh(),
    };
  }

  Future<Map<String, dynamic>> _collectSsh() async {
    final sshDir = await _getSshDir();
    final configExists = await File('$sshDir/config').exists();
    final keyExists = await File('$sshDir/id_ed25519').exists();
    return {
      'configured': sshStatus.value == SshStatus.configured,
      'configExists': configExists,
      'keyExists': keyExists,
      'dir': sshDir,
    };
  }

  Future<String> _getSshDir() async {
    try {
      return await getSshDir();
    } catch (_) {
      return '(unknown)';
    }
  }

  String _formatUptime() {
    final duration = DateTime.now().difference(_startedAt);
    final d = duration.inDays;
    final h = duration.inHours % 24;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    if (d > 0) return '${d}d ${h}h ${m}m ${s}s';
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
