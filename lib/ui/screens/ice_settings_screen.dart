import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../plugins/ice/ice_api_server.dart';
import '../../plugins/ice/ice_logger.dart';
import '../../plugins/ice/ssh_logger.dart';
import '../../providers/connection_status.dart' show isIceOnline, isSshConfigured, getSshDir, updateSshStatus;
import '../../services/mattermost_debug_bridge.dart';
import '../../services/ssh_tunnel_service.dart';
import '../../services/watchdog_service.dart';
import '../widgets/status_dot.dart';

class IceSettingsScreen extends StatefulWidget {
  final IceApiServer apiServer;

  const IceSettingsScreen({required this.apiServer, super.key});

  @override
  State<IceSettingsScreen> createState() => _IceSettingsScreenState();
}

class _IceSettingsScreenState extends State<IceSettingsScreen> {
  final _portController = TextEditingController(text: '8100');
  final _sshConfigController = TextEditingController();
  final _sshKeyController = TextEditingController();
  Timer? _configDebounce;
  Timer? _keyDebounce;
  bool _running = false;
  String? _statusMessage;
  String? _sshDirPath;
  bool _configExists = false;
  bool _keyExists = false;

  @override
  void initState() {
    super.initState();
    _running = widget.apiServer.isRunning;
    _portController.text = widget.apiServer.port.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSshFiles();
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    _sshConfigController.dispose();
    _sshKeyController.dispose();
    _configDebounce?.cancel();
    _keyDebounce?.cancel();
    super.dispose();
  }

  void _onConfigChanged(String text) {
    _configDebounce?.cancel();
    _configDebounce = Timer(const Duration(milliseconds: 800), () {
      _saveSshConfig();
    });
  }

  void _onKeyChanged(String text) {
    _keyDebounce?.cancel();
    _keyDebounce = Timer(const Duration(milliseconds: 800), () {
      _saveSshKey();
    });
  }

  Future<void> _loadSshFiles() async {
    try {
      final sshDir = await getSshDir();
      _sshDirPath = sshDir;

      final configFile = File('$sshDir/config');
      _configExists = await configFile.exists();
      if (_configExists) {
        _sshConfigController.text = await configFile.readAsString();
      }

      final keyFile = File('$sshDir/id_ed25519');
      _keyExists = await keyFile.exists();
      if (_keyExists) {
        _sshKeyController.text = await keyFile.readAsString();
      }

      // Load from SharedPreferences fallback
      final prefs = await SharedPreferences.getInstance();
      if (_sshConfigController.text.isEmpty) {
        _sshConfigController.text = prefs.getString('ssh_config') ?? '';
      }
      if (_sshKeyController.text.isEmpty) {
        _sshKeyController.text = prefs.getString('ssh_key') ?? '';
      }
    } catch (e) {
      debugPrint('[ICE] SSH load error: $e');
    }
  }

  Future<void> _saveSshConfig() async {
    try {
      final sshDir = await getSshDir();
      final dir = Directory(sshDir);
      await dir.create(recursive: true);

      final configFile = File('$sshDir/config');
      await configFile.writeAsString(_sshConfigController.text);
      _configExists = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ssh_config', _sshConfigController.text);

      await updateSshStatus();
      if (mounted) setState(() {});

      if (mounted) {
        setState(() => _statusMessage = 'SSH Config saved to $sshDir/config');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SSH Config saved ($sshDir/config)')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Save failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  Future<void> _saveSshKey() async {
    try {
      final sshDir = await getSshDir();
      final dir = Directory(sshDir);
      await dir.create(recursive: true);

      final keyFile = File('$sshDir/id_ed25519');
      await keyFile.writeAsString(_sshKeyController.text);
      _keyExists = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ssh_key', _sshKeyController.text);

      await updateSshStatus();
      if (mounted) setState(() {});

      if (mounted) {
        setState(() => _statusMessage = 'Private key saved to $sshDir/id_ed25519');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Private key saved ($sshDir/id_ed25519)')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Save failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  Future<void> _toggleServer() async {
    if (_running) {
      await widget.apiServer.stop();
      setState(() {
        _running = false;
        _statusMessage = 'Server stopped';
      });
    } else {
      final port = int.tryParse(_portController.text);
      if (port == null || port < 1024 || port > 65535) {
        setState(() => _statusMessage = 'Port must be 1024-65535');
        return;
      }
      try {
        await widget.apiServer.restart(port: port);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('ice_port', port);
        setState(() {
          _running = true;
          _statusMessage = 'Server running on http://localhost:$port';
        });
      } catch (e) {
        setState(() => _statusMessage = 'Start failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(notifier: isSshConfigured, tooltip: 'SSH', onTap: () {}),
            StatusDot(notifier: isIceOnline, tooltip: 'ICE', onTap: () {}),
            const Text('ICE Debug'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildServerCard(cs),
          const SizedBox(height: 16),
          _buildSshStatusCard(cs),
          const SizedBox(height: 16),
          _buildSshConfigCard(cs),
          const SizedBox(height: 16),
          _buildSshKeyCard(cs),
          const SizedBox(height: 16),
          _buildSshLogCard(cs),
          const SizedBox(height: 16),
          _buildEndpointsCard(cs),
          const SizedBox(height: 16),
          _buildWatchdogCard(cs),
          const SizedBox(height: 16),
          _buildMmStatusCard(cs),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_statusMessage!, style: TextStyle(color: cs.onPrimaryContainer)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServerCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _running ? Colors.green : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_running ? 'API Running' : 'API Stopped',
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                const Spacer(),
                Text('v1.0.0', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.number,
                    enabled: !_running,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _toggleServer,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                  label: Text(_running ? 'Stop' : 'Start'),
                ),
              ],
            ),
            if (_running) ...[
              const SizedBox(height: 8),
              _copyablePath(cs, 'http://localhost:${widget.apiServer.port}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSshStatusCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('SSH Diagnostics', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 8),
            _diagLine(cs, 'SSH Directory', _sshDirPath ?? '(loading...)'),
            _diagLine(cs, 'Config file',
                _configExists ? 'EXISTS ✓' : 'NOT FOUND ✗',
                valueColor: _configExists ? Colors.green : Colors.red),
            _diagLine(cs, 'Private key',
                _keyExists ? 'EXISTS ✓' : 'NOT FOUND ✗',
                valueColor: _keyExists ? Colors.green : Colors.red),
            if (_sshDirPath != null) ...[
              const SizedBox(height: 8),
              _buildTunnelControls(cs),
            ],
          ],
        ),
      ),
    );
  }

  Widget _diagLine(ColorScheme cs, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: valueColor ?? cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSshConfigCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SSH Config', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('Paste SSH config. Persisted to local file.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _sshConfigController,
              maxLines: 8,
              onChanged: _onConfigChanged,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Host opencode-box',
                hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontFamily: 'monospace'),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSshKeyCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Private Key (id_ed25519)', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('Paste your private key. Persisted to local file.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _sshKeyController,
              maxLines: 10,
              onChanged: _onKeyChanged,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontFamily: 'monospace'),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSshLogCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('SSH Log', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                const Spacer(),
                TextButton(
                  onPressed: () => SshLogger.instance.clear(),
                  child: const Text('Clear', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<List<SshLogEntry>>(
              valueListenable: SshLogger.instance,
              builder: (context, entries, _) {
                if (entries.isEmpty) {
                  return Text('No SSH log yet',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant));
                }
                final reversed = entries.reversed.take(80).toList().reversed.toList();
                return Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: reversed.length,
                    itemBuilder: (context, index) {
                      final entry = reversed[index];
                      final color = switch (entry.level) {
                        SshLogLevel.error => Colors.red.shade300,
                        SshLogLevel.warn => Colors.orange.shade300,
                        SshLogLevel.data => Colors.grey.shade400,
                        SshLogLevel.info => Colors.green.shade300,
                      };
                      final ts = '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        child: Text(
                          '$ts ${entry.message}',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: color,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTunnelControls(ColorScheme cs) {
    final tunnel = SshTunnelService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tunnel.isRunning ? Colors.green : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Text(tunnel.isRunning ? 'Tunnel Connected' : 'Tunnel Disconnected',
                style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface, fontSize: 13)),
          ],
        ),
        if (tunnel.lastError != null) ...[
          const SizedBox(height: 4),
          Text(tunnel.lastError!, style: TextStyle(fontSize: 11, color: Colors.red.shade300)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            if (!tunnel.isRunning)
              FilledButton.icon(
                onPressed: () async {
                  await tunnel.start();
                  setState(() {});
                },
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Connect SSH'),
              )
            else
              FilledButton.icon(
                onPressed: () async {
                  await tunnel.stop();
                  setState(() {});
                },
                icon: const Icon(Icons.stop, size: 16),
                label: const Text('Disconnect'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _sshDirPath!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Path copied to clipboard')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy path'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWatchdogCard(ColorScheme cs) {
    final wd = WatchdogService.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.autorenew, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Auto-Recovery',
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
                const Spacer(),
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: wd.isRunning ? Colors.green : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statBadge(cs, 'ICE', wd.iceRestarts),
                const SizedBox(width: 8),
                _statBadge(cs, 'SSH', wd.sshRestarts),
                const SizedBox(width: 8),
                _statBadge(cs, 'MM', wd.mmRestarts),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBadge(ColorScheme cs, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: count > 0 ? Colors.orange.shade900 : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label:$count',
          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onSurface)),
    );
  }

  Widget _buildMmStatusCard(ColorScheme cs) {
    final bridge = MattermostDebugBridge.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.forum, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Mattermost Bridge',
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bridge.isRunning ? Colors.green : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(bridge.isRunning ? 'Connected' : 'Disconnected',
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
              ],
            ),
            if (bridge.lastError != null) ...[
              const SizedBox(height: 4),
              Text(bridge.lastError!,
                  style: TextStyle(fontSize: 11, color: Colors.red.shade300)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (!bridge.isRunning)
                  FilledButton.icon(
                    onPressed: () async { await bridge.start(); setState(() {}); },
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Start Bridge'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () async { await bridge.stop(); setState(() {}); },
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Stop Bridge'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  ),
              ],
            ),
            if (bridge.isRunning)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Logs auto-forwarded to Mattermost',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointsCard(ColorScheme cs) {
    final endpoints = [
      'GET  /health',
      'GET  /state',
      'GET  /errors',
      'DELETE /errors',
      'POST /command',
      'GET  /fs/read',
      'POST /fs/write',
      'GET  /fs/list',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Endpoints', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 8),
            ...endpoints.map((ep) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(ep, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onSurfaceVariant)),
            )),
          ],
        ),
      ),
    );
  }

  Widget _copyablePath(ColorScheme cs, String path) {
    final ctx = context;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: path));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard')),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(Icons.link, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(path,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurfaceVariant)),
            ),
            Icon(Icons.copy, size: 14, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
