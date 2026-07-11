import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_service.dart';
import '../data/services/smart_search_service.dart';
import '../models/mattermost_config.dart';
import '../plugins/ice/ice_api_server.dart';
import '../plugins/ice/ssh_logger.dart';
import '../providers/connection_status.dart'
    show IceStatus, SshStatus, getSshDir, iceStatus, sshStatus;
import '../services/search_service.dart';
import '../services/ssh_tunnel_service.dart';
import 'mattermost_api.dart';

// Hardcoded Mattermost configuration (read from .env, embedded for reliability)
const _mmBaseUrl = 'https://mm.ka.sugeee.com';
const _mmTeam = 'cyb';
const _mmChannel = 'novfind';
const _mmBotName = 'novfind-android';
const _mmBotToken = 'adrfhe4fy3npmrut93sift9hoh';
const _mmOpencodeBot = 'oc-gui1';
const _mmOpencodeToken = '1gfhn9hya3yumk9hcejoe9x9ma';

class MattermostDebugBridge {
  static final MattermostDebugBridge instance = MattermostDebugBridge._();

  MattermostApi? _api;
  MattermostConfig? _config;
  Timer? _pollTimer;
  Timer? _logFlushTimer;
  bool _running = false;
  DateTime? _lastPollTime;
  final DateTime _bridgeStartTime = DateTime.now();
  final Set<String> _processedPostIds = {};
  static const int _maxProcessedIds = 100;
  final List<String> _pendingLogs = [];
  String? _lastError;

  bool get isRunning => _running;
  String? get lastError => _lastError;
  MattermostApi? get api => _api;

  MattermostDebugBridge._();

  Future<void> start() async {
    if (_running) return;
    _lastError = null;

    _config = const MattermostConfig(
      baseUrl: _mmBaseUrl,
      team: _mmTeam,
      channel: _mmChannel,
      botName: _mmBotName,
      botToken: _mmBotToken,
      opencodeBotName: _mmOpencodeBot,
      opencodeToken: _mmOpencodeToken,
    );

    _api = MattermostApi(_config!);

    try {
      await _api!.getChannelId();
      String version = '?';
      try {
        final info = await PackageInfo.fromPlatform();
        version = '${info.version}(${info.buildNumber})';
      } catch (_) {}
      await _api!.sendMessage('🟢 novfind v$version bridge started');
    } catch (e) {
      _lastError = 'Failed to connect to Mattermost: $e';
      debugPrint('[MMB] $_lastError');
      return;
    }

    _running = true;

    // Poll for commands
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());

    // Flush pending logs every 3 seconds
    _logFlushTimer = Timer.periodic(const Duration(seconds: 3), (_) => _flushLogs());

    // Subscribe to SSH logger for auto-forwarding
    SshLogger.instance.addListener(_onSshLog);

    // Subscribe to status changes
    sshStatus.addListener(_onSshStatus);
    iceStatus.addListener(_onIceStatus);

    debugPrint('[MMB] Bridge started');
  }

  void _onSshLog() {
    final entries = SshLogger.instance.value;
    if (entries.isEmpty) return;
    final last = entries.last;
    _pendingLogs.add(last.message);
  }

  void _onSshStatus() {
    if (!_running) return;
    if (sshStatus.value == SshStatus.configured) {
      _pendingLogs.add('SSH: ✓ connected');
      _sendUrgent('🔌 SSH tunnel connected - ICE API accessible via localhost:8100');
    } else {
      _pendingLogs.add('SSH: disconnected');
      _sendUrgent('🔌 SSH tunnel disconnected - use !opencode commands via MM');
    }
  }

  Future<void> _sendUrgent(String text) async {
    if (_api == null) return;
    try {
      await _api!.sendMessage(text);
    } catch (_) {}
  }

  void _onIceStatus() {
    if (!_running) return;
    if (iceStatus.value == IceStatus.online) {
      _pendingLogs.add('ICE: ✓ running on :8100');
    } else {
      _pendingLogs.add('ICE: stopped');
    }
  }

  Future<void> _flushLogs() async {
    if (!_running || _pendingLogs.isEmpty || _api == null) return;
    final batch = _pendingLogs.take(5).toList();
    _pendingLogs.removeRange(0, batch.length);
    final text = batch.map((m) => '🔧 $m').join('\n');
    try {
      await _api!.sendMessage(text);
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (!_running || _api == null) return;
    try {
      final posts = await _api!.fetchPosts(since: _lastPollTime);
      if (posts.isEmpty) return;

      // Update last poll time from the latest post
      final latest = posts.last;
      final ts = _parseCreateAt(latest['create_at']);
      if (ts != null) _lastPollTime = ts;

      // Filter for !opencode commands
      for (final post in posts) {
        final message = post['message'] as String? ?? '';
        final postId = post['id'] as String? ?? '';
        final createdAt = _parseCreateAt(post['create_at']);

        // Skip already-processed posts
        if (postId.isNotEmpty && !_processedPostIds.add(postId)) continue;

        // Skip posts created before the bridge started
        if (createdAt != null && createdAt.isBefore(_bridgeStartTime)) continue;

        // Only process !opencode prefixed messages
        if (message.startsWith('!opencode ')) {
          await _handleCommand(post);
        }
      }

      // Trim processed IDs to prevent memory leak
      if (_processedPostIds.length > _maxProcessedIds) {
        final excess = _processedPostIds.length - _maxProcessedIds;
        for (var i = 0; i < excess; i++) {
          _processedPostIds.remove(_processedPostIds.first);
        }
      }
    } catch (e) {
      debugPrint('[MMB] Poll error: $e');
    }
  }

  Future<void> _handleCommand(Map<String, dynamic> post) async {
    final message = post['message'] as String? ?? '';
    final postId = post['id'] as String;
    final cmdText = message.substring('!opencode '.length).trim();
    final parts = cmdText.split(' ');
    final command = parts.isNotEmpty ? parts[0] : '';
    final args = parts.length > 1 ? parts.sublist(1) : <String>[];

    debugPrint('[MMB] Command: $command $args');

    try {
      String result;
      switch (command) {
        case 'ssh.status':
          final tunnel = SshTunnelService.instance;
          result = 'SSH: ${tunnel.isRunning ? "✓ connected" : "✗ disconnected"}'
              '\nlastError: ${tunnel.lastError ?? "(none)"}';
        case 'ssh.connect':
          await SshTunnelService.instance.start();
          result = 'SSH connection initiated (see log)';
        case 'ssh.disconnect':
          await SshTunnelService.instance.stop();
          result = 'SSH disconnected';
        case 'ssh.log':
          final n = args.isNotEmpty ? int.tryParse(args[0]) ?? 20 : 20;
          final entries = SshLogger.instance.value;
          final recent = entries.reversed.take(n).toList().reversed;
          result = recent.map((e) => e.message).join('\n');
        case 'ssh.config':
          final config = await _readSshConfig();
          result = config;
        case 'ice.status':
          final server = iceApiServer;
          final errors = await _getErrorCount();
          result = 'ICE: ${server.isRunning ? "✓ running" : "✗ stopped"}'
              '\nport: ${server.port}'
              '\nerrors: $errors';
        case 'ice.debug':
          result = await _collectDebugString();
        case 'ice.start':
          final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 8100 : 8100;
          await iceApiServer.restart(port: port);
          result = 'ICE started on port $port';
        case 'ice.stop':
          await iceApiServer.stop();
          result = 'ICE stopped';
        case 'ice.restart':
          final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 8100 : iceApiServer.port;
          await iceApiServer.restart(port: port);
          result = 'ICE restarted on port $port';
        case 'search':
          final keyword = args.join(' ');
          if (keyword.isEmpty) {
            result = 'Usage: search <keyword>';
          } else {
            try {
              final query = await rootBundle.loadString('assets/search_query.txt');
              final svc = SearchService(query: query);
              final results = await svc.search(keyword);
              if (results.isEmpty) {
                final sshInfo = SshTunnelService.instance.isRunning
                    ? '' : '\n\nSSH offline - results limited to MM bridge.\nUse !opencode ssh.connect to enable direct API access.';
                result = 'No results for "$keyword"$sshInfo';
              } else {
                result = 'Results for "$keyword" (${results.length}):\n';
                for (var i = 0; i < results.length && i < 10; i++) {
                  final r = results[i];
                  result += '${i + 1}. ${r.title}\n   ${r.url}\n';
                }
                if (results.length > 10) {
                  result += '...and ${results.length - 10} more';
                }
              }
            } catch (e) {
              result = 'Search failed: $e';
            }
          }
        case 'app.info':
          final prefs = await SharedPreferences.getInstance();
          final kw = prefs.getStringList('keywords') ?? [];
          final hist = prefs.getStringList('searchHistory') ?? [];
          result = 'novfind'
              '\nkeywords: ${kw.length}'
              '\nhistory: ${hist.length}'
              '\nICE: ${iceApiServer.isRunning ? "on" : "off"}'
              '\nSSH: ${SshTunnelService.instance.isRunning ? "on" : "off"}';
        case 'app.keywords':
          final prefs = await SharedPreferences.getInstance();
          final kw = prefs.getStringList('keywords') ?? [];
          if (kw.isEmpty) {
            result = 'No keywords';
          } else {
            result = 'Keywords (${kw.length}):\n${kw.asMap().entries.map((e) => "${e.key + 1}. ${e.value}").join("\n")}';
          }
        case 'app.history':
          final prefs = await SharedPreferences.getInstance();
          final hist = prefs.getStringList('searchHistory') ?? [];
          if (hist.isEmpty) {
            result = 'No history';
          } else {
            result = 'History (${hist.length}):\n${hist.reversed.take(10).join("\n")}';
          }
        case 'help':
          result = _helpText();
        default:
          result = 'Unknown command: $command\n\n${_helpText()}';
      }

      await _api!.postResult(postId, result);
    } catch (e) {
      await _api!.postResult(postId, 'Error: $e');
    }
  }

  Future<String> _readSshConfig() async {
    try {
      final dir = await getSshDir();
      final file = File('$dir/config');
      if (!await file.exists()) return 'No SSH config found at $dir/config';
      final text = await file.readAsString();
      return 'SSH config ($dir/config):\n```\n${text.trim()}\n```';
    } catch (e) {
      return 'Error reading SSH config: $e';
    }
  }

  Future<int> _getErrorCount() async {
    return 0;
  }

  Future<String> _collectDebugString() async {
    final tunnel = SshTunnelService.instance;
    String version = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}(${info.buildNumber})';
    } catch (_) {}
    return 'Version: $version'
        '\nServer: ${iceApiServer.isRunning ? "running" : "stopped"}'
        '\nPort: ${iceApiServer.port}'
        '\nSSH: ${tunnel.isRunning ? "connected" : "disconnected"}'
        '\nSSH error: ${tunnel.lastError ?? "(none)"}'
        '\nSearch: SmartSearchService (dio + HeadlessWebView)'
        '\nDio err: ${SmartSearchService.lastDioError ?? "(none)"}'
        '\nHL err: ${SmartSearchService.lastHeadlessError ?? "(none)"}';
  }

  String _helpText() {
    return 'Commands (all work without SSH):\n'
        'search <keyword> | help\n'
        'ssh.status | connect | disconnect | log [n] | config\n'
        'ice.status | debug | start [port] | stop | restart [port]\n'
        'app.info | keywords | history';
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _logFlushTimer?.cancel();
    _logFlushTimer = null;
    SshLogger.instance.removeListener(_onSshLog);
    sshStatus.removeListener(_onSshStatus);
    iceStatus.removeListener(_onIceStatus);
    try {
      await _api?.sendMessage('🔴 novfind bridge stopped');
    } catch (_) {}
    _api = null;
    debugPrint('[MMB] Bridge stopped');
  }

  Future<void> sendMessage(String text) async {
    if (!_running || _api == null) return;
    try {
      await _api!.sendMessage(text);
    } catch (e) {
      debugPrint('[MMB] Send failed: $e');
    }
  }

  DateTime? _parseCreateAt(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final ms = int.tryParse(value);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }
}
