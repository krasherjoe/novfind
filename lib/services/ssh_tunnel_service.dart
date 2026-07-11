import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/connection_status.dart' show SshStatus, sshStatus;

class SshTunnelService {
  static final SshTunnelService instance = SshTunnelService._();

  Process? _process;
  bool _running = false;
  String? _lastError;

  bool get isRunning => _running;
  String? get lastError => _lastError;

  SshTunnelService._();

  Future<String> getSshDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/.ssh';
  }

  Future<String> getSshCommand() async {
    final sshDir = await getSshDir();
    return 'ssh -F $sshDir/config -i $sshDir/id_ed25519 -N -R 8100:localhost:8100 opencode-box';
  }

  Future<String> getSshDirCommand() async {
    // For adb shell / terminal usage
    final sshDir = await getSshDir();
    return 'cd $sshDir && ssh -F config -i id_ed25519 -N -R 8100:localhost:8100 opencode-box';
  }

  Future<bool> isSshAvailable() async {
    try {
      final result = await Process.run('which', ['ssh'],
          runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    if (_running) return;
    _lastError = null;

    final sshDir = await getSshDir();
    final configFile = File('$sshDir/config');
    final keyFile = File('$sshDir/id_ed25519');

    if (!await configFile.exists()) {
      _lastError = 'SSH config file not found';
      debugPrint('[SSH] Config file not found');
      return;
    }
    if (!await keyFile.exists()) {
      _lastError = 'SSH private key not found';
      debugPrint('[SSH] Key file not found');
      return;
    }

    // Key file permissions are managed by the app's private directory

    try {
      _process = await Process.start(
        'ssh',
        [
          '-F', '$sshDir/config',
          '-i', '$sshDir/id_ed25519',
          '-N',
          '-R', '8100:localhost:8100',
          'opencode-box',
        ],
        runInShell: true,
      );

      _running = true;
      sshStatus.value = SshStatus.configured;

      _process!.stderr.transform(utf8.decoder).listen((data) {
        _lastError = data.trim();
        debugPrint('[SSH] $data');
      });

      _process!.exitCode.then((code) {
        debugPrint('[SSH] Exited with code $code');
        _running = false;
        if (code != 0) {
          sshStatus.value = SshStatus.unconfigured;
        }
      });
    } catch (e) {
      _lastError = 'SSH start failed: $e';
      _running = false;
      sshStatus.value = SshStatus.unconfigured;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    try {
      _process?.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(milliseconds: 500));
      _process?.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _running = false;
    sshStatus.value = SshStatus.unconfigured;
  }

  Future<void> restart() async {
    await stop();
    await start();
  }
}
