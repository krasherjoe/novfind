import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/connection_status.dart' show SshStatus, sshStatus;

class SshTunnelService {
  static final SshTunnelService instance = SshTunnelService._();

  SSHClient? _client;
  SSHSocket? _socket;
  SSHRemoteForward? _forward;
  bool _running = false;
  String? _lastError;
  StreamSubscription? _connectionsSub;

  bool get isRunning => _running;
  String? get lastError => _lastError;

  SshTunnelService._();

  Future<String> getSshDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/.ssh';
  }

  Future<String> getSshCommand() async {
    final sshDir = await getSshDir();
    return 'dartssh2 auto-tunnel: 8100 ← → localhost:8100\nfiles: $sshDir';
  }

  Map<String, String> _parseSshConfig(String config) {
    final result = <String, String>{};
    final lines = config.split('\n');
    int currentHostIndex = -1;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;

      final key = parts[0].toLowerCase();
      final value = parts.sublist(1).join(' ');

      if (key == 'host') {
        currentHostIndex++;
        result['host'] = value;
      } else if (currentHostIndex >= 0) {
        result[key] = value;
      }
    }
    return result;
  }

  Future<void> start() async {
    if (_running) return;
    _lastError = null;

    try {
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

      final configText = await configFile.readAsString();
      final keyText = await keyFile.readAsString();
      final config = _parseSshConfig(configText);

      final hostName = config['hostname'] ?? config['host'] ?? 'opencode-box';
      final port = int.tryParse(config['port'] ?? '22') ?? 22;
      final username = config['user'] ?? 'root';

      _lastError = 'Connecting to $username@$hostName:$port ...';
      debugPrint('[SSH] $_lastError');

      // Parse SSH key
      final keys = SSHKeyPair.fromPem(keyText);
      if (keys.isEmpty) {
        _lastError = 'No SSH keys found in key file';
        debugPrint('[SSH] $_lastError');
        return;
      }

      // Connect socket
      _socket = await SSHSocket.connect(
        hostName,
        port,
        timeout: const Duration(seconds: 15),
      );

      _lastError = 'Authenticating...';
      debugPrint('[SSH] Authenticating with key (${keys.length} keys)');

      _client = SSHClient(
        _socket!,
        username: username,
        identities: keys,
        keepAliveInterval: const Duration(seconds: 20),
        onPasswordRequest: () {
          _lastError = 'Password requested - key auth failed';
          debugPrint('[SSH] $_lastError');
          return null;
        },
        onVerifyHostKey: (_, __) => true,
      );

      // Wait for auth to complete
      await _client!.authenticated;

      _lastError = 'Requesting reverse forward :8100';
      debugPrint('[SSH] $_lastError');

      // Request remote port forwarding (empty host = all interfaces)
      _forward = await _client!.forwardRemote(
        host: '',
        port: 8100,
      );

      if (_forward == null) {
        _lastError = 'Remote port forward failed - server may not allow GatewayPorts';
        debugPrint('[SSH] $_lastError');
        // Try loopback only
        _forward = await _client!.forwardRemote(
          host: '127.0.0.1',
          port: 8100,
        );
        if (_forward == null) {
          _lastError = 'Port forwarding denied by server';
          _client?.close();
          _client = null;
          return;
        }
      }

      // Handle incoming forwarded connections - bridge to ICE API
      _connectionsSub = _forward!.connections.listen((channel) {
        debugPrint('[SSH] Incoming forwarded connection');
        _handleForwardedConnection(channel);
      });

      _running = true;
      sshStatus.value = SshStatus.configured;
      _lastError = '✓ Tunnel active: $username@$hostName:$port → :8100 → localhost:8100';
      debugPrint('[SSH] $_lastError');

      // Track disconnection
      _client!.done.then((_) {
        debugPrint('[SSH] Client disconnected');
        _running = false;
        sshStatus.value = SshStatus.unconfigured;
        _lastError = 'SSH disconnected';
      });
    } catch (e) {
      _lastError = 'SSH failed: $e';
      debugPrint('[SSH] $_lastError');
      await _cleanup();
      sshStatus.value = SshStatus.unconfigured;
    }
  }

  Future<void> _handleForwardedConnection(SSHForwardChannel channel) async {
    try {
      // Connect to ICE API server
      final localSocket = await Socket.connect(
        '127.0.0.1',
        8100,
        timeout: const Duration(seconds: 5),
      );

      // Bidirectional pipe
      channel.stream.listen(
        (data) {
          try {
            localSocket.add(data);
          } catch (_) {}
        },
        onDone: () {
          try { localSocket.destroy(); } catch (_) {}
        },
        onError: (_) {
          try { localSocket.destroy(); } catch (_) {}
        },
      );

      localSocket.listen(
        (data) {
          try {
            channel.sink.add(data);
          } catch (_) {}
        },
        onDone: () {
          try { channel.close(); } catch (_) {}
        },
        onError: (_) {
          try { channel.close(); } catch (_) {}
        },
      );
    } catch (e) {
      debugPrint('[SSH] Forward bridge failed: $e');
      try { channel.close(); } catch (_) {}
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _lastError = 'Disconnecting...';
    debugPrint('[SSH] $_lastError');
    await _cleanup();
    sshStatus.value = SshStatus.unconfigured;
    _lastError = 'SSH disconnected';
  }

  Future<void> _cleanup() async {
    _connectionsSub?.cancel();
    _connectionsSub = null;
    try { _forward?.close(); } catch (_) {}
    _forward = null;
    try { _client?.close(); } catch (_) {}
    _client = null;
    try { _socket?.close(); } catch (_) {}
    _socket = null;
    _running = false;
  }

  Future<void> restart() async {
    await stop();
    await start();
  }
}
