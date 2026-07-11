import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../plugins/ice/ice_api_server.dart';
import '../../plugins/ice/ice_logger.dart';
import '../../providers/connection_status.dart';
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
  bool _running = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _running = widget.apiServer.isRunning;
    _portController.text = widget.apiServer.port.toString();
    _loadSshFiles();
  }

  @override
  void dispose() {
    _portController.dispose();
    _sshConfigController.dispose();
    _sshKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSshFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final sshDir = Directory('${dir.path}/.ssh');

      final configFile = File('${sshDir.path}/config');
      if (await configFile.exists()) {
        _sshConfigController.text = await configFile.readAsString();
      }

      final keyFile = File('${sshDir.path}/id_ed25519');
      if (await keyFile.exists()) {
        _sshKeyController.text = await keyFile.readAsString();
      }

      // Also load from SharedPreferences as fallback
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
      final dir = await getApplicationDocumentsDirectory();
      final sshDir = Directory('${dir.path}/.ssh');
      await sshDir.create(recursive: true);

      final configFile = File('${sshDir.path}/config');
      await configFile.writeAsString(_sshConfigController.text);

      // Also save to SharedPreferences for status detection
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ssh_config', _sshConfigController.text);

      await updateSshStatus();

      if (mounted) {
        setState(() {
          _statusMessage = 'SSH Config saved to ${configFile.path}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH Config saved')),
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
      final dir = await getApplicationDocumentsDirectory();
      final sshDir = Directory('${dir.path}/.ssh');
      await sshDir.create(recursive: true);

      final keyFile = File('${sshDir.path}/id_ed25519');
      await keyFile.writeAsString(_sshKeyController.text);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ssh_key', _sshKeyController.text);

      await updateSshStatus();

      if (mounted) {
        setState(() {
          _statusMessage = 'Private key saved to ${keyFile.path}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Private key saved')),
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
            StatusDot(
              notifier: ValueNotifier(sshStatus.value == SshStatus.configured),
              tooltip: sshStatus.value == SshStatus.configured ? 'SSH configured' : 'SSH not configured',
              onTap: () {},
            ),
            StatusDot(
              notifier: ValueNotifier(iceStatus.value == IceStatus.online),
              tooltip: iceStatus.value == IceStatus.online ? 'ICE API running' : 'ICE API stopped',
              onTap: () {},
            ),
            const Text('ICE Debug'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildServerCard(cs),
          const SizedBox(height: 16),
          _buildSshConfigCard(cs),
          const SizedBox(height: 16),
          _buildSshKeyCard(cs),
          const SizedBox(height: 16),
          _buildEndpointsCard(cs),
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
                Text(
                  _running ? 'API Running' : 'API Stopped',
                  style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
                ),
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
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'http://localhost:${widget.apiServer.port}',
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
            Text(
              'Paste SSH config. Persisted to local file.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _sshConfigController,
              maxLines: 12,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Host opencode-box\n  HostName example.com\n  User developer\n  IdentityFile ~/.ssh/id_ed25519\n  RemoteForward 8100 localhost:8100',
                hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontFamily: 'monospace'),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveSshConfig,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save SSH Config'),
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
            Text(
              'Paste your private key. Persisted to local file.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _sshKeyController,
              maxLines: 16,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurface),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                hintStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontFamily: 'monospace'),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveSshKey,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save Private Key'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointsCard(ColorScheme cs) {
    final endpoints = [
      'GET  /health   Health check',
      'GET  /state    App state',
      'GET  /errors   Error logs',
      'DELETE /errors Clear logs',
      'POST /command  Execute command',
      'GET  /fs/read  Read file',
      'POST /fs/write Write file',
      'GET  /fs/list  List directory',
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
}
