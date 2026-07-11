import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/connection_status.dart' show SshStatus, sshStatus;
import '../plugins/ice/ssh_logger.dart';

class SshTunnelService {
  static final SshTunnelService instance = SshTunnelService._();

  SSHClient? _targetClient;
  SSHClient? _jumpClient;
  SSHSocket? _directSocket;
  SSHRemoteForward? _forward;
  bool _running = false;
  String? _lastError;
  StreamSubscription? _connectionsSub;

  bool get isRunning => _running;
  String? get lastError => _lastError;

  SshTunnelService._();

  Future<String> getSshDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/.ssh';
    SshLogger.d('SSH directory: $path');
    return path;
  }

  List<Map<String, String>> _parseSshConfig(String config) {
    final sections = <Map<String, String>>[];
    Map<String, String>? current;
    for (final rawLine in config.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[0].toLowerCase() == 'host') {
        current = <String, String>{'host': parts.sublist(1).join(' ')};
        sections.add(current);
        continue;
      }
      if (current == null) continue;
      current[parts[0].toLowerCase()] = parts.sublist(1).join(' ');
    }
    return sections;
  }

  Map<String, String>? _findHostConfig(List<Map<String, String>> sections, String alias) {
    Map<String, String>? wildcard;
    for (final section in sections) {
      final pattern = section['host'] ?? '';
      if (pattern == alias) return section;
      if (pattern == '*') wildcard = section;
    }
    return wildcard;
  }

  (String host, int port, String user) _parseJumpTarget(String value) {
    var target = value.trim();
    String user = 'root';
    String host;
    int port = 22;
    final atIdx = target.lastIndexOf('@');
    if (atIdx >= 0) {
      user = target.substring(0, atIdx);
      target = target.substring(atIdx + 1);
    }
    final colonIdx = target.lastIndexOf(':');
    if (colonIdx >= 0) {
      final p = int.tryParse(target.substring(colonIdx + 1));
      if (p != null && p > 0 && p < 65536) {
        port = p;
        host = target.substring(0, colonIdx);
      } else {
        host = target;
      }
    } else {
      host = target;
    }
    return (host, port, user);
  }

  Future<void> start() async {
    if (_running) return;
    _lastError = null;
    SshLogger.i('=== SSH Tunnel Start ===');

    try {
      final sshDir = await getSshDir();
      final configFile = File('$sshDir/config');
      final keyFile = File('$sshDir/id_ed25519');

      SshLogger.i('Checking config: $sshDir/config');
      if (!await configFile.exists()) {
        _lastError = 'SSH config not found: $sshDir/config';
        SshLogger.e(_lastError!);
        return;
      }
      SshLogger.i('config exists ✓ (${await configFile.length()} bytes)');

      SshLogger.i('Checking key: $sshDir/id_ed25519');
      if (!await keyFile.exists()) {
        _lastError = 'SSH key not found: $sshDir/id_ed25519';
        SshLogger.e(_lastError!);
        return;
      }
      SshLogger.i('key exists ✓ (${await keyFile.length()} bytes)');

      final configText = await configFile.readAsString();
      final keyText = await keyFile.readAsString();
      SshLogger.d('config: ${configText.length} chars, key: ${keyText.length} chars');

      final keys = SSHKeyPair.fromPem(keyText);
      if (keys.isEmpty) {
        _lastError = 'No valid SSH keys in key file';
        SshLogger.e(_lastError!);
        return;
      }
      SshLogger.i('Parsed ${keys.length} key(s)');

      final sections = _parseSshConfig(configText);
      SshLogger.d('Config sections: ${sections.length}');
      for (final s in sections) {
        SshLogger.d('  Host ${s['host']} → ${s['hostname'] ?? "(direct)"} proxyjump=${s['proxyjump'] ?? "none"}');
      }

      final hostConfig = _findHostConfig(sections, 'opencode-box');
      if (hostConfig == null) {
        _lastError = 'No SSH config section for "opencode-box"';
        SshLogger.e(_lastError!);
        return;
      }

      final hostName = hostConfig['hostname'] ?? '';
      final port = int.tryParse(hostConfig['port'] ?? '22') ?? 22;
      final userName = hostConfig['user'] ?? 'root';
      final proxyJump = hostConfig['proxyjump'];

      if (hostName.isEmpty) {
        _lastError = 'Missing HostName in config for opencode-box';
        SshLogger.e(_lastError!);
        return;
      }

      SshLogger.i('Target: $userName@$hostName:$port');
      SshLogger.i('ProxyJump: ${proxyJump ?? "(none)"}');

      // Connect
      _targetClient = await _connectWithProxy(
        host: hostName, port: port, user: userName,
        proxyJump: proxyJump, keys: keys, label: 'target',
      );

      if (_targetClient == null) {
        _lastError ??= 'Failed to connect to target';
        SshLogger.e(_lastError!);
        await _cleanup();
        return;
      }

      SshLogger.i('✓ Connected! Requesting reverse port forward :8100');

      _forward = await _targetClient!.forwardRemote(host: '', port: 8100);
      if (_forward == null) {
        SshLogger.w('GatewayPorts denied, trying 127.0.0.1:8100');
        _forward = await _targetClient!.forwardRemote(host: '127.0.0.1', port: 8100);
      }
      if (_forward == null) {
        _lastError = 'Port forwarding denied by server';
        SshLogger.e(_lastError!);
        await _cleanup();
        return;
      }

      _connectionsSub = _forward!.connections.listen((channel) {
        SshLogger.d('Incoming connection → bridging to ICE API');
        _bridgeToIceApi(channel);
      });

      _running = true;
      sshStatus.value = SshStatus.configured;
      _lastError = '✓ Active: remote:8100 → localhost:8100';
      SshLogger.i('$_lastError');

      _targetClient!.done.then((_) {
        SshLogger.w('SSH connection closed');
        _running = false;
        sshStatus.value = SshStatus.unconfigured;
        _lastError = 'Disconnected';
      });
    } catch (e) {
      _lastError = 'Error: $e';
      SshLogger.e('$_lastError');
      await _cleanup();
      sshStatus.value = SshStatus.unconfigured;
    }
  }

  Future<SSHClient?> _connectWithProxy({
    required String host, required int port, required String user,
    required String? proxyJump, required List<SSHKeyPair> keys,
    required String label,
  }) async {
    if (proxyJump != null && proxyJump.isNotEmpty) {
      final (jumpHost, jumpPort, jumpUser) = _parseJumpTarget(proxyJump);
      SshLogger.i('=== ProxyJump: $jumpUser@$jumpHost:$jumpPort → $user@$host:$port ===');

      SshLogger.i('[$label] Connecting to jump host $jumpHost:$jumpPort');
      SSHSocket jumpSocket;
      try {
        jumpSocket = await SSHSocket.connect(jumpHost, jumpPort,
            timeout: const Duration(seconds: 20));
      } catch (e) {
        _lastError = 'Jump host connection failed: $e';
        SshLogger.e('[$label] $_lastError');
        return null;
      }
      SshLogger.i('[$label] Jump TCP connected, authenticating as $jumpUser');

      _jumpClient = SSHClient(
        jumpSocket, username: jumpUser, identities: keys,
        keepAliveInterval: const Duration(seconds: 20),
        onPasswordRequest: () { SshLogger.w('[$label] Jump host requested password'); return null; },
        onVerifyHostKey: (_, __) { SshLogger.d('[$label] Accepting jump host key'); return true; },
        disableHostkeyVerification: true,
      );

      try {
        await _jumpClient!.authenticated;
      } catch (e) {
        _lastError = 'Jump host auth failed: $e';
        SshLogger.e('[$label] $_lastError');
        return null;
      }
      SshLogger.i('[$label] Jump host authenticated ✓');

      SshLogger.i('[$label] Opening direct-tcpip channel to $host:$port through jump');

      SSHForwardChannel forwardChannel;
      try {
        forwardChannel = await _jumpClient!.forwardLocal(host, port);
      } catch (e) {
        _lastError = 'Direct-tcpip channel failed: $e';
        SshLogger.e('[$label] $_lastError');
        return null;
      }
      SshLogger.i('[$label] Direct-tcpip channel open ✓');

      SshLogger.i('[$label] Wrapping channel as SSH transport (SSH-in-SSH)...');
      final targetClient = SSHClient(
        forwardChannel, username: user, identities: keys,
        keepAliveInterval: const Duration(seconds: 20),
        onPasswordRequest: () { SshLogger.w('[$label] Target requested password'); return null; },
        onVerifyHostKey: (_, __) { SshLogger.d('[$label] Accepting target host key'); return true; },
        disableHostkeyVerification: true,
      );

      try {
        await targetClient.authenticated;
      } catch (e) {
        _lastError = 'Target host auth failed: $e';
        SshLogger.e('[$label] $_lastError');
        return null;
      }
      SshLogger.i('[$label] ✓ SSH-in-SSH established');
      return targetClient;
    } else {
      SshLogger.i('[$label] Direct connect to $user@$host:$port');
      SSHSocket socket;
      try {
        socket = await SSHSocket.connect(host, port,
            timeout: const Duration(seconds: 20));
      } catch (e) {
        _lastError = 'TCP connection failed: $e';
        SshLogger.e('[$label] $_lastError');
        return null;
      }
      SshLogger.i('[$label] TCP connected, authenticating...');

      final client = SSHClient(
        socket, username: user, identities: keys,
        keepAliveInterval: const Duration(seconds: 20),
        onPasswordRequest: () { SshLogger.w('[$label] Password requested'); return null; },
        onVerifyHostKey: (_, __) { SshLogger.d('[$label] Accepting host key'); return true; },
        disableHostkeyVerification: true,
      );

      try {
        await client.authenticated;
      } catch (e) {
        _lastError = 'Auth failed: $e';
        SshLogger.e('[$label] $_lastError');
        return null;
      }
      SshLogger.i('[$label] ✓ Authenticated');
      return client;
    }
  }

  Future<void> _bridgeToIceApi(SSHForwardChannel channel) async {
    try {
      final local = await Socket.connect('127.0.0.1', 8100,
          timeout: const Duration(seconds: 5));
      SshLogger.d('Bridge established: SSH tunnel → ICE API');
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
      SshLogger.e('Bridge failed: $e');
      try { channel.close(); } catch (_) {}
    }
  }

  Future<void> stop() async {
    SshLogger.i('Stopping SSH tunnel');
    await _cleanup();
    sshStatus.value = SshStatus.unconfigured;
    _lastError = 'Disconnected';
  }

  Future<void> _cleanup() async {
    _connectionsSub?.cancel(); _connectionsSub = null;
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
