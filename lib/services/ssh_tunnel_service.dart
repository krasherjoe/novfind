import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/connection_status.dart' show SshStatus, sshStatus;

class SshTunnelService {
  static final SshTunnelService instance = SshTunnelService._();

  SSHClient? _targetClient;
  SSHClient? _jumpClient;
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

  /// Parse SSH config into a map of Host sections.
  /// Returns list of {host, hostname, user, port, proxyjump, ...}
  List<Map<String, String>> _parseSshConfig(String config) {
    final sections = <Map<String, String>>[];
    Map<String, String>? current;

    for (final rawLine in config.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Check for Host directive (new section)
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[0].toLowerCase() == 'host') {
        current = <String, String>{'host': parts.sublist(1).join(' ')};
        sections.add(current);
        continue;
      }

      if (current == null) continue;
      final key = parts[0].toLowerCase();
      final value = parts.sublist(1).join(' ');
      current[key] = value;
    }
    return sections;
  }

  /// Find matching Host section for a given alias.
  Map<String, String>? _findHostConfig(List<Map<String, String>> sections, String alias) {
    for (final section in sections) {
      final hostPattern = section['host'] ?? '';
      // Exact match
      if (hostPattern == alias) return section;
      // Wildcard match (*)
      if (hostPattern == '*') continue; // Save as fallback
    }
    // Fallback to wildcard section
    for (final section in sections) {
      if (section['host'] == '*') return section;
    }
    return null;
  }

  /// Parse ProxyJump value like "user@host:port" into (host, port, user)
  (String host, int port, String user) _parseJumpTarget(String value) {
    var target = value.trim();
    String user = 'root';
    String host;
    int port = 22;

    // user@host
    final atIdx = target.lastIndexOf('@');
    if (atIdx >= 0) {
      user = target.substring(0, atIdx);
      target = target.substring(atIdx + 1);
    }

    // host:port
    final colonIdx = target.lastIndexOf(':');
    if (colonIdx >= 0 && colonIdx == target.length - 5 && int.tryParse(target.substring(colonIdx + 1)) != null) {
      port = int.parse(target.substring(colonIdx + 1));
      host = target.substring(0, colonIdx);
    } else {
      host = target;
    }

    return (host, port, user);
  }

  /// Connect to a host via SSH and optionally through a jump host (ProxyJump).
  Future<SSHClient?> _connectWithProxy({
    required String host,
    required int port,
    required String user,
    required String? proxyJump,
    required List<SSHKeyPair> keys,
    required String label,
  }) async {
    _lastError = '$label: resolving proxyjump=$proxyJump';
    debugPrint('[SSH] $_lastError');

    if (proxyJump != null && proxyJump.isNotEmpty) {
      // ProxyJump chain: connect to jump host first
      final (jumpHost, jumpPort, jumpUser) = _parseJumpTarget(proxyJump);

      _lastError = '$label: connecting to jump host $jumpUser@$jumpHost:$jumpPort';
      debugPrint('[SSH] $_lastError');

      final jumpSocket = await SSHSocket.connect(jumpHost, jumpPort,
          timeout: const Duration(seconds: 15));

      _jumpClient = SSHClient(
        jumpSocket,
        username: jumpUser,
        identities: keys,
        keepAliveInterval: const Duration(seconds: 20),
        onPasswordRequest: () { _lastError = 'Jump host key auth failed'; return null; },
        onVerifyHostKey: (_, __) => true,
      );
      await _jumpClient!.authenticated;

      _lastError = '$label: opening direct-tcpip channel to $host:$port through jump';
      debugPrint('[SSH] $_lastError');

      // Open direct-tcpip channel through jump host to target
      final forwardChannel = await _jumpClient!.forwardLocal(host, port);

      // Use the forward channel as SSH transport for target connection (SSH-in-SSH)
      _lastError = '$label: connecting via jump (SSH-in-SSH)';
      debugPrint('[SSH] $_lastError');

      final targetClient = SSHClient(
        forwardChannel,
        username: user,
        identities: keys,
        keepAliveInterval: const Duration(seconds: 20),
        onPasswordRequest: () { _lastError = 'Target host key auth failed'; return null; },
        onVerifyHostKey: (_, __) => true,
      );
      await targetClient.authenticated;

      _lastError = '$label: connected via jump host';
      debugPrint('[SSH] $_lastError');
      return targetClient;
    } else {
      // Direct connection (no proxy jump)
      _lastError = '$label: direct connect to $user@$host:$port';
      debugPrint('[SSH] $_lastError');

      final socket = await SSHSocket.connect(host, port,
          timeout: const Duration(seconds: 15));

      final client = SSHClient(
        socket,
        username: user,
        identities: keys,
        keepAliveInterval: const Duration(seconds: 20),
        onPasswordRequest: () { _lastError = 'Key auth failed'; return null; },
        onVerifyHostKey: (_, __) => true,
      );
      await client.authenticated;

      _lastError = '$label: connected';
      debugPrint('[SSH] $_lastError');
      return client;
    }
  }

  Future<void> start() async {
    if (_running) return;
    _lastError = null;

    try {
      final sshDir = await getSshDir();
      final configFile = File('$sshDir/config');
      final keyFile = File('$sshDir/id_ed25519');

      if (!await configFile.exists()) {
        _lastError = 'SSH config not found at $sshDir/config';
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

      final keys = SSHKeyPair.fromPem(keyText);
      if (keys.isEmpty) {
        _lastError = 'No valid SSH keys found';
        debugPrint('[SSH] $_lastError');
        return;
      }

      // Parse SSH config and find matching section for "opencode-box"
      final sections = _parseSshConfig(configText);
      final hostConfig = _findHostConfig(sections, 'opencode-box');

      if (hostConfig == null) {
        _lastError = 'No SSH config found for "opencode-box"';
        debugPrint('[SSH] $_lastError');
        return;
      }

      final hostName = hostConfig['hostname'] ?? hostConfig['host'] ?? 'opencode-box';
      final port = int.tryParse(hostConfig['port'] ?? '22') ?? 22;
      final userName = hostConfig['user'] ?? 'root';
      final proxyJump = hostConfig['proxyjump'];

      _lastError = 'Target: $userName@$hostName:$port, ProxyJump: ${proxyJump ?? "(none)"}';
      debugPrint('[SSH] $_lastError');

      // Connect to target (possibly through jump host)
      _targetClient = await _connectWithProxy(
        host: hostName,
        port: port,
        user: userName,
        proxyJump: proxyJump,
        keys: keys,
        label: 'target',
      );

      if (_targetClient == null) {
        _lastError = 'Failed to connect to target host';
        debugPrint('[SSH] $_lastError');
        return;
      }

      // Request reverse port forwarding on the TARGET host
      _lastError = 'Requesting reverse forward :8100';
      debugPrint('[SSH] $_lastError');

      _forward = await _targetClient!.forwardRemote(host: '', port: 8100);

      if (_forward == null) {
        _lastError = 'Port forward :8100 denied, trying 127.0.0.1:8100';
        debugPrint('[SSH] $_lastError');
        _forward = await _targetClient!.forwardRemote(host: '127.0.0.1', port: 8100);
      }

      if (_forward == null) {
        _lastError = 'Port forwarding denied by server';
        debugPrint('[SSH] $_lastError');
        await _cleanup();
        return;
      }

      // Bridge incoming forwarded connections to ICE API
      _connectionsSub = _forward!.connections.listen((channel) {
        debugPrint('[SSH] Incoming connection bridged');
        _bridgeToIceApi(channel);
      });

      _running = true;
      sshStatus.value = SshStatus.configured;
      _lastError = '✓ Tunnel active: target:8100 ↔ localhost:8100';
      debugPrint('[SSH] $_lastError');

      // Monitor disconnection
      _targetClient!.done.then((_) {
        debugPrint('[SSH] Target client disconnected');
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

  Future<void> _bridgeToIceApi(SSHForwardChannel channel) async {
    try {
      final local = await Socket.connect('127.0.0.1', 8100,
          timeout: const Duration(seconds: 5));

      channel.stream.listen(
        (data) { try { local.add(data); } catch (_) {} },
        onDone: () { try { local.destroy(); } catch (_) {} },
        onError: (_) { try { local.destroy(); } catch (_) {} },
      );

      local.listen(
        (data) { try { channel.sink.add(data); } catch (_) {} },
        onDone: () { try { channel.close(); } catch (_) {} },
        onError: (_) { try { channel.close(); } catch (_) {} },
      );
    } catch (e) {
      debugPrint('[SSH] Bridge failed: $e');
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
    try { _targetClient?.close(); } catch (_) {}
    _targetClient = null;
    try { _jumpClient?.close(); } catch (_) {}
    _jumpClient = null;
    _running = false;
  }

  Future<void> restart() async {
    await stop();
    await start();
  }
}
