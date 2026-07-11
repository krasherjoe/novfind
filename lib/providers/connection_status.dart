import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum IceStatus { online, offline }
enum SshStatus { configured, unconfigured }

final iceStatus = ValueNotifier<IceStatus>(IceStatus.offline);
final sshStatus = ValueNotifier<SshStatus>(SshStatus.unconfigured);
final isIceOnline = ValueNotifier<bool>(false);
final isSshConfigured = ValueNotifier<bool>(false);

String? _foundSshDir;

/// Clears the cached SSH directory so the next [getSshDir] call re-scans.
void resetSshDirCache() => _foundSshDir = null;

/// Returns the directory where SSH config/key files were FOUND.
/// If not found, returns the default app-private path.
Future<String> getSshDir() async {
  if (_foundSshDir != null) return _foundSshDir!;

  // Priority 1: app-private documents dir
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final p1 = '${appDir.path}/.ssh';
    if (await _hasSshFiles(p1)) {
      _foundSshDir = p1;
      debugPrint('[SSH] Found files in app dir: $p1');
      return p1;
    }
  } catch (_) {}

  // Priority 2: standard /storage emulated paths
  final fallbackPaths = [
    '/storage/emulated/0/Documents/.ssh',
    '/storage/emulated/0/.ssh',
    '/data/data/com.novfind.novfind/.ssh',
  ];

  for (final p in fallbackPaths) {
    if (await _hasSshFiles(p)) {
      _foundSshDir = p;
      debugPrint('[SSH] Found files in fallback: $p');
      return p;
    }
  }

  // Fallback: app-private dir (create if needed)
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final path = '${appDir.path}/.ssh';
    await Directory(path).create(recursive: true);
    _foundSshDir = path;
    debugPrint('[SSH] Using default path: $path');
    return path;
  } catch (_) {
    // Last resort
    _foundSshDir = '/storage/emulated/0/Documents/.ssh';
    return _foundSshDir!;
  }
}

Future<bool> _hasSshFiles(String dir) async {
  try {
    final hasConfig = await File('$dir/config').exists();
    final hasKey = await File('$dir/id_ed25519').exists();
    return hasConfig && hasKey;
  } catch (_) {
    return false;
  }
}

void _syncIceStatus() {
  isIceOnline.value = iceStatus.value == IceStatus.online;
}

void _syncSshStatus() {
  isSshConfigured.value = sshStatus.value == SshStatus.configured;
}

void initConnectionStatus() {
  _syncIceStatus();
  _syncSshStatus();
  iceStatus.addListener(_syncIceStatus);
  sshStatus.addListener(_syncSshStatus);
}

Future<void> updateSshStatus() async {
  try {
    final dir = await getSshDir();
    final configExists = await File('$dir/config').exists();
    final keyExists = await File('$dir/id_ed25519').exists();
    debugPrint('[SSH] Status check at $dir: config=$configExists key=$keyExists');
    sshStatus.value =
        (configExists || keyExists) ? SshStatus.configured : SshStatus.unconfigured;
  } catch (_) {
    sshStatus.value = SshStatus.unconfigured;
  }
}
