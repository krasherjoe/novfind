import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/connection_status.dart';
import '../../providers/keywords_provider.dart';
import '../../providers/preset_provider.dart';
import '../../providers/search_history_provider.dart';
import '../../providers/site_filter_provider.dart';
import '../../providers/theme_provider.dart' show themeNotifier, toggleTheme;
import '../../services/search_service.dart';
import '../../services/ssh_tunnel_service.dart';
import 'ice_logger.dart';
import 'ice_state_collector.dart';

class IceApiServer {
  HttpServer? _server;
  late IceStateCollector _collector;
  int port;
  bool _running = false;
  final DateTime _startedAt = DateTime.now();

  IceApiServer({this.port = 8100}) {
    _collector = IceStateCollector();
  }

  Future<void> start() async {
    if (_running) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _running = true;
      iceStatus.value = IceStatus.online;
      IceLogger.info('SYS:start', 'ICE API server started on port $port');
      debugPrint('[ICE] Started on http://localhost:$port');
      _handleRequests();
    } catch (e) {
      iceStatus.value = IceStatus.offline;
      IceLogger.error('SYS:start', 'Failed to start server', error: e);
      debugPrint('[ICE] Failed to start: $e');
    }
  }

  Future<void> stop() async {
    _running = false;
    await _server?.close(force: true);
    _server = null;
    iceStatus.value = IceStatus.offline;
    IceLogger.info('SYS:stop', 'ICE API server stopped');
    debugPrint('[ICE] Stopped');
  }

  Future<void> restart({int? port}) async {
    await stop();
    if (port != null) this.port = port;
    await start();
  }

  bool get isRunning => _running;

  void _handleRequests() {
    _server?.listen(
      (request) async {
        _collector.incrementRequestCount();
        IceLogger.info('API:${request.method}', '${request.uri}');
        try {
          await _handleRequest(request);
        } catch (e) {
          _collector.incrementErrorCount();
          IceLogger.error('API:error', 'Request handler error', error: e);
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'error': e.toString()}));
            await request.response.close();
          } catch (_) {}
        }
      },
      onError: (e) {
        IceLogger.error('API:error', 'Server error', error: e);
      },
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final uri = Uri.parse(request.uri.toString());
    final path = uri.path;
    final method = request.method;

    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');

    if (method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    try {
      switch (path) {
        case '/health':
          await _json(request.response, {
            'status': 'ok',
            'service': 'novfind ICE API',
            'version': '1.0.0',
            'uptime': _formatUptime(),
          });

        case '/debug':
          await _json(request.response, _collectDebugInfo());

        case '/state':
          final state = await _collectFullState();
          await _json(request.response, state);

        case '/errors':
          if (method == 'DELETE') {
            IceLogger.info('API:/errors', 'Logs cleared');
            IceLogger.clear();
            await _json(request.response, {'cleared': true, 'deletedCount': IceLogger.count});
          } else {
            final logs = IceLogger.recentJson(minLevel: LogLevel.warn, count: 100);
            await _json(request.response, {
              'count': logs.length,
              'total': IceLogger.count,
              'errors': logs,
            });
          }

        case '/command':
          if (method != 'POST') {
            await _error(request.response, HttpStatus.methodNotAllowed, 'POST required');
            return;
          }
          await _handleCommand(request);

        case '/fs/read':
          if (method != 'GET') {
            await _error(request.response, HttpStatus.methodNotAllowed, 'GET required');
            return;
          }
          final readPath = uri.queryParameters['path'];
          if (readPath == null || readPath.isEmpty) {
            await _error(request.response, HttpStatus.badRequest, 'path is required');
            return;
          }
          await _handleFsRead(request.response, readPath);

        case '/fs/write':
          if (method != 'POST') {
            await _error(request.response, HttpStatus.methodNotAllowed, 'POST required');
            return;
          }
          await _handleFsWrite(request);

        case '/fs/list':
          if (method != 'GET') {
            await _error(request.response, HttpStatus.methodNotAllowed, 'GET required');
            return;
          }
          final listPath = uri.queryParameters['path'] ?? '.';
          await _handleFsList(request.response, listPath);

        case '/fs/download':
          if (method != 'GET') {
            await _error(request.response, HttpStatus.methodNotAllowed, 'GET required');
            return;
          }
          final dlPath = uri.queryParameters['path'];
          if (dlPath == null || dlPath.isEmpty) {
            await _error(request.response, HttpStatus.badRequest, 'path is required');
            return;
          }
          await _handleFsDownload(request.response, dlPath);

        default:
          await _json(request.response, {
            'service': 'novfind ICE API',
            'version': '1.0.0',
            'endpoints': [
              'GET  /health',
              'GET  /state',
              'GET  /errors',
              'DELETE /errors',
              'POST /command',
              'GET  /fs/read?path=...',
              'POST /fs/write',
              'GET  /fs/list?path=...',
              'GET  /fs/download?path=...',
            ],
            'commands': [
              'search <keyword>',
              'add_keyword <text>',
              'delete_keyword <id>',
              'list_keywords',
              'list_history',
              'clear_history',
              'theme <light|dark|system>',
              'site_list',
              'site_toggle <domain>',
              'app_info',
              'ice.status',
              'ice.start [port]',
              'ice.stop',
              'ice.restart [port]',
            ],
          });
      }
    } catch (e) {
      _collector.incrementErrorCount();
      IceLogger.error('API:error', 'Handler error', error: e);
      await _error(request.response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<Map<String, dynamic>> _collectFullState() async {
    final base = await _collector.collect();

    // Add novfind-specific state
    try {
      final keywords = await _resolveKeywords();
      final history = await _resolveHistory();
      final disabled = await _resolveDisabledSites();

      base['keywords'] = {
        'count': keywords.length,
        'items': keywords.map((k) => {'id': k.id, 'text': k.text, 'createdAt': k.createdAt.toIso8601String()}).toList(),
      };
      base['history'] = {
        'count': history.length,
        'items': history.map((h) => {'keyword': h.keyword, 'searchedAt': h.searchedAt.toIso8601String()}).toList(),
      };
      base['sites'] = {
        'total': 46,
        'disabledCount': disabled.length,
        'disabled': disabled.toList(),
      };
      base['sshTunnel'] = {
        'running': SshTunnelService.instance.isRunning,
        'lastError': SshTunnelService.instance.lastError,
      };
    } catch (e) {
      base['_error'] = e.toString();
    }

    return base;
  }

  Map<String, dynamic> _collectDebugInfo() {
    final ssh = SshTunnelService.instance;
    return {
      'server': {
        'running': _running,
        'port': port,
        'bindAddress': '127.0.0.1',
        'uptime': _formatUptime(),
        'startTime': _startedAt.toIso8601String(),
      },
      'sshTunnel': {
        'running': ssh.isRunning,
        'lastError': ssh.lastError ?? '(none)',
        'note': 'dartssh2 auto-tunnel: remote:8100 → localhost:8100',
      },
      'network': {
        'loopback': '127.0.0.1',
        'port': port,
        'note': 'ICE API listens on loopback only. SSH tunnel forwards remote:8100 -> localhost:8100',
      },
      'endpoints': [
        'GET /health - Health check',
        'GET /debug - This debug info',
        'GET /state - Full app state',
        'GET /errors - Error logs',
        'DELETE /errors - Clear logs',
        'POST /command - Execute command',
        'GET /fs/read?path=... - Read file',
        'POST /fs/write - Write file',
        'GET /fs/list?path=... - List directory',
      ],
    };
  }

  Future<void> _handleCommand(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final name = data['command'] as String?;
    final argsRaw = data['args'] as List<dynamic>?;
    final args = (argsRaw ?? []).map((a) => a.toString()).toList();

    if (name == null || name.isEmpty) {
      await _error(request.response, HttpStatus.badRequest, 'command is required');
      return;
    }

    IceLogger.info('CMD:$name', 'Executing with args: $args');

    try {
      String result;
      switch (name) {
        case 'search':
          result = await _cmdSearch(args);
        case 'add_keyword':
          result = await _cmdAddKeyword(args);
        case 'delete_keyword':
          result = await _cmdDeleteKeyword(args);
        case 'list_keywords':
          result = await _cmdListKeywords();
        case 'list_history':
          result = await _cmdListHistory();
        case 'clear_history':
          result = await _cmdClearHistory();
        case 'theme':
          result = await _cmdTheme(args);
        case 'site_list':
          result = await _cmdSiteList();
        case 'site_toggle':
          result = await _cmdSiteToggle(args);
        case 'app_info':
          result = await _cmdAppInfo();
        case 'ice.status':
          result = 'ICE: ${_running ? "running" : "stopped"} (port: $port)';
        case 'ice.start':
          final p = args.isNotEmpty ? int.tryParse(args[0]) ?? 8100 : 8100;
          await restart(port: p);
          result = 'ICE restarted on port $p';
        case 'ice.stop':
          await stop();
          result = 'ICE stopped';
        case 'ice.restart':
          final p = args.isNotEmpty ? int.tryParse(args[0]) ?? 8100 : port;
          await restart(port: p);
          result = 'ICE restarted on port $p';
        default:
          await _error(request.response, HttpStatus.badRequest, 'Unknown command: $name');
          return;
      }

      IceLogger.info('CMD:$name', 'Result: $result');
      await _json(request.response, {
        'command': name,
        'args': args,
        'result': result,
      });
    } catch (e) {
      IceLogger.error('CMD:$name', 'Command failed', error: e);
      await _error(request.response, HttpStatus.internalServerError, e.toString());
    }
  }

  Future<String> _cmdSearch(List<String> args) async {
    if (args.isEmpty) return 'error: keyword required';
    final keyword = args.join(' ');
    final query = await _loadSearchQuery();
    final service = SearchService(query: query);
    final results = await service.search(keyword);
    return '${results.length} results';
  }

  Future<String> _cmdAddKeyword(List<String> args) async {
    if (args.isEmpty) return 'error: text required';
    final text = args.join(' ');
    // Note: keywords are stored in Riverpod state; this requires a ref
    // For now, use SharedPreferences directly
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('keywords') ?? [];
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final entry = jsonEncode({
      'id': id,
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    });
    existing.add(entry);
    await prefs.setStringList('keywords', existing);
    return 'keyword added: $text';
  }

  Future<String> _cmdDeleteKeyword(List<String> args) async {
    return 'error: id required';
  }

  Future<String> _cmdListKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('keywords') ?? [];
    return '${existing.length} keywords';
  }

  Future<String> _cmdListHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList('searchHistory') ?? [];
    return '${items.length} history items';
  }

  Future<String> _cmdClearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('searchHistory');
    return 'history cleared';
  }

  Future<String> _cmdTheme(List<String> args) async {
    if (args.isEmpty) return 'error: light|dark|system required';
    await toggleTheme();
    return 'theme toggled';
  }

  Future<String> _cmdSiteList() async {
    return 'site list (not available without ref)';
  }

  Future<String> _cmdSiteToggle(List<String> args) async {
    return 'site toggle (not available without ref)';
  }

  Future<String> _cmdAppInfo() async {
    final state = await _collector.collect();
    return 'version: ${state['app']}';
  }

  Future<String> _loadSearchQuery() async {
    try {
      return await _loadAsset('assets/search_query.txt');
    } catch (_) {
      return '';
    }
  }

  Future<String> _loadAsset(String path) async {
    final file = File(path);
    if (await file.exists()) return file.readAsString();
    return '';
  }

  Future<dynamic> _resolveKeywords() async {
    return [];
  }

  Future<dynamic> _resolveHistory() async {
    return [];
  }

  Future<Set<String>> _resolveDisabledSites() async {
    return {};
  }

  Future<void> _handleFsRead(HttpResponse response, String path) async {
    final file = File(path);
    if (!await file.exists()) {
      IceLogger.error('API:/fs/read', 'File not found: $path');
      await _error(response, HttpStatus.notFound, 'File not found: $path');
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      final stat = await file.stat();
      final size = stat.size;

      if (size > 10 * 1024 * 1024) {
        await _error(response, HttpStatus.badRequest, 'File too large: $size bytes (max 10MB)');
        return;
      }

      final ext = p.extension(path).replaceFirst('.', '');
      final isText = ['txt', 'json', 'csv', 'xml', 'html', 'htm', 'md', 'yaml', 'yml', 'sql', 'log', 'key', 'pub', 'dart', 'yaml', 'toml', 'cfg', 'conf', 'ini', 'env', 'sh', 'bat', 'ps1'].contains(ext);

      IceLogger.info('API:/fs/read', 'Read file: $path ($size bytes, text: $isText)');

      if (isText) {
        final content = await file.readAsString();
        await _json(response, {
          'path': path,
          'size': size,
          'text': true,
          'content': content,
        });
      } else {
        final base64Content = base64Encode(bytes);
        response.headers.set('Content-Type', 'application/json');
        await _json(response, {
          'path': path,
          'size': size,
          'text': false,
          'content': base64Content,
        });
      }
    } catch (e) {
      IceLogger.error('API:/fs/read', 'Failed to read file: $path', error: e);
      await _error(response, HttpStatus.internalServerError, 'Failed to read file: $e');
    }
  }

  Future<void> _handleFsWrite(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final path = data['path'] as String?;
    final content = data['content'] as String?;
    final isBase64 = (data['isBase64'] as bool?) ?? false;

    if (path == null || path.isEmpty) {
      await _error(request.response, HttpStatus.badRequest, 'path is required');
      return;
    }
    if (content == null) {
      await _error(request.response, HttpStatus.badRequest, 'content is required');
      return;
    }

    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      if (isBase64) {
        await file.writeAsBytes(base64Decode(content));
      } else {
        await file.writeAsString(content);
      }
      final stat = await file.stat();
      IceLogger.info('API:/fs/write', 'Written: $path (${stat.size} bytes)');
      await _json(request.response, {
        'path': path,
        'size': stat.size,
        'written': true,
      });
    } catch (e) {
      IceLogger.error('API:/fs/write', 'Failed to write: $path', error: e);
      await _error(request.response, HttpStatus.internalServerError, 'Failed to write file: $e');
    }
  }

  Future<void> _handleFsList(HttpResponse response, String path) async {
    try {
      final entries = <Map<String, dynamic>>[];
      final dir = Directory(path);
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: false)) {
          final stat = await entity.stat();
          entries.add({
            'path': entity.path,
            'name': p.basename(entity.path),
            'type': stat.type == FileSystemEntityType.directory ? 'directory' : 'file',
            'size': stat.size,
          });
        }
      } else {
        final file = File(path);
        if (await file.exists()) {
          final stat = await file.stat();
          entries.add({
            'path': path,
            'name': p.basename(path),
            'type': 'file',
            'size': stat.size,
          });
        } else {
          await _error(response, HttpStatus.notFound, 'Path not found: $path');
          return;
        }
      }
      IceLogger.info('API:/fs/list', 'Listed: $path (${entries.length} entries)');
      await _json(response, {
        'path': path,
        'entries': entries,
        'count': entries.length,
      });
    } catch (e) {
      IceLogger.error('API:/fs/list', 'Failed to list: $path', error: e);
      await _error(response, HttpStatus.internalServerError, 'Failed to list: $e');
    }
  }

  Future<void> _handleFsDownload(HttpResponse response, String path) async {
    final file = File(path);
    if (!await file.exists()) {
      await _error(response, HttpStatus.notFound, 'File not found: $path');
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      response.headers.set('Content-Type', 'application/octet-stream');
      response.headers.set('Content-Disposition', 'attachment; filename="${p.basename(path)}"');
      response.add(bytes);
      await response.close();
      IceLogger.info('API:/fs/download', 'Downloaded: $path (${bytes.length} bytes)');
    } catch (e) {
      IceLogger.error('API:/fs/download', 'Failed to download: $path', error: e);
      await _error(response, HttpStatus.internalServerError, 'Failed to download: $e');
    }
  }

  Future<void> _json(HttpResponse response, dynamic data) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
  }

  Future<void> _error(HttpResponse response, int statusCode, String message) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'error': message}));
    await response.close();
  }

  String _formatUptime() {
    final duration = DateTime.now().difference(_startedAt);
    final d = duration.inDays;
    final h = duration.inHours % 24;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    if (d > 0) return '${d}d ${h}h ${m}m ${s}s';
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
