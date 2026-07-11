import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_service.dart';
import '../plugins/ice/ssh_logger.dart';
import '../providers/connection_status.dart' show getSshDir;
import 'mattermost_debug_bridge.dart';
import 'ssh_tunnel_service.dart';

class WatchdogService {
  static final WatchdogService instance = WatchdogService._();

  Timer? _iceTimer;
  Timer? _sshTimer;
  Timer? _mmTimer;
  bool _running = false;
  int _iceRestarts = 0;
  int _sshRestarts = 0;
  int _mmRestarts = 0;

  bool get isRunning => _running;
  int get iceRestarts => _iceRestarts;
  int get sshRestarts => _sshRestarts;
  int get mmRestarts => _mmRestarts;

  WatchdogService._();

  void start() {
    if (_running) return;
    _running = true;

    SshLogger.i('Watchdog started');

    // ICE API watchdog (every 15 seconds)
    _iceTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkIce());

    // SSH tunnel watchdog (every 30 seconds)
    _sshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkSsh());

    // MM bridge watchdog (every 30 seconds)
    _mmTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkMm());
  }

  void stop() {
    _running = false;
    _iceTimer?.cancel();
    _iceTimer = null;
    _sshTimer?.cancel();
    _sshTimer = null;
    _mmTimer?.cancel();
    _mmTimer = null;
    SshLogger.i('Watchdog stopped');
  }

  Future<void> _checkIce() async {
    try {
      if (!iceApiServer.isRunning) {
        SshLogger.w('Watchdog: ICE API down, restarting...');
        await iceApiServer.start();
        _iceRestarts++;
        SshLogger.i('Watchdog: ICE API restarted (#$_iceRestarts)');
      }
    } catch (e) {
      SshLogger.e('Watchdog: ICE restart failed: $e');
    }
  }

  Future<void> _checkSsh() async {
    try {
      final tunnel = SshTunnelService.instance;
      if (!tunnel.isRunning) {
        // Check if SSH config/key exist before attempting restart
        final sshDir = await getSshDir();
        final configFile = File('$sshDir/config');
        final keyFile = File('$sshDir/id_ed25519');
        if (await configFile.exists() && await keyFile.exists()) {
          SshLogger.w('Watchdog: SSH tunnel down, reconnecting...');
          await tunnel.start();
          _sshRestarts++;
          SshLogger.i('Watchdog: SSH reconnected (#$_sshRestarts)');
        }
      }
    } catch (e) {
      SshLogger.e('Watchdog: SSH reconnect failed: $e');
    }
  }

  Future<void> _checkMm() async {
    try {
      final bridge = MattermostDebugBridge.instance;
      if (!bridge.isRunning) {
        SshLogger.w('Watchdog: MM bridge down, restarting...');
        await bridge.start();
        _mmRestarts++;
        SshLogger.i('Watchdog: MM bridge restarted (#$_mmRestarts)');
      }
    } catch (e) {
      debugPrint('[Watchdog] MM restart failed: $e');
    }
  }
}
