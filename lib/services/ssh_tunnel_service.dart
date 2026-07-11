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
      _lastError = 'SSH config file not found at $sshDir/config';
      debugPrint('[SSH] $_lastError');
      return;
    }
    if (!await keyFile.exists()) {
      _lastError = 'SSH private key not found at $sshDir/id_ed25519';
      debugPrint('[SSH] $_lastError');
      return;
    }

    final sshBinary = await _findSshBinary();
    if (sshBinary == null) {
      _lastError = 'ssh binary not found in PATH';
      debugPrint('[SSH] $_lastError');
      return;
    }

    final args = [
      '-vvv', // Verbose output for debugging
      '-F', '$sshDir/config',
      '-i', '$sshDir/id_ed25519',
      '-N',
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '-R', '8100:localhost:8100',
      'opencode-box',
    ];

    debugPrint('[SSH] Executing: $sshBinary ${args.join(' ')}');

    try {
      _process = await Process.start(
        sshBinary,
        args,
        runInShell: true,
        environment: {
          'HOME': sshDir,
          'SSH_AUTH_SOCK': '', // Disable ssh-agent
        },
      );

      _running = true;
      sshStatus.value = SshStatus.configured;

      // Capture stdout
      _process!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[SSH stdout] $data');
        if (data.contains('debug1: Remote connections from')) {
          _lastError = 'Tunnel established: $data';
        }
      });

      // Capture stderr (SSH outputs most info here)
      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[SSH stderr] $data');
        // Extract key information from verbose output
        if (data.contains('debug1: Remote connections from')) {
          _lastError = '✓ Tunnel active';
        } else if (data.contains('Permission denied')) {
          _lastError = '✗ Auth failed: check SSH key';
        } else if (data.contains('Connection refused')) {
          _lastError = '✗ Connection refused by remote';
        } else if (data.contains('could not resolve hostname')) {
          _lastError = '✗ Host not found';
        } else if (data.contains('Warning: Permanently added')) {
          _lastError = 'Connecting...';
        }
      });

      _process!.exitCode.then((code) {
        debugPrint('[SSH] Process exited with code $code');
        _running = false;
        if (code != 0) {
          _lastError = 'SSH exited with code $code';
          sshStatus.value = SshStatus.unconfigured;
        } else {
          _lastError = 'SSH disconnected normally';
          sshStatus.value = SshStatus.unconfigured;
        }
      });
    } catch (e) {
      _lastError = 'SSH start failed: $e';
      debugPrint('[SSH] $_lastError');
      _running = false;
      sshStatus.value = SshStatus.unconfigured;
    }
  }

  Future<String?> _findSshBinary() async {
    // Try common locations
    final paths = [
      '/system/bin/ssh',
      '/system/xbin/ssh',
      '/sbin/ssh',
      '/usr/bin/ssh',
      '/usr/local/bin/ssh',
      'ssh', // Try PATH
    ];

    for (final path in paths) {
      try {
        final result = await Process.run('test', ['-f', path]);
        if (result.exitCode == 0) {
          return path;
        }
      } catch (_) {}
    }

    // Try which
    try {
      final result = await Process.run('which', ['ssh']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}

    return null;
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
