import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mattermost_config.dart';

Future<MattermostConfig?> loadMattermostConfig() async {
  try {
    final file = File('.env');
    if (!await file.exists()) {
      debugPrint('[MM] .env not found');
      return null;
    }

    String? novfindToken, opencodeToken, novfindBot, opencodeBot, channelUrl;

    final lines = await file.readAsLines();
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      value = value.replaceAll('"', '');

      switch (key) {
        case 'NOVFIND_MM_CHANNEL':
          channelUrl = value;
        case 'NOVFIND_MM_BOT':
          novfindBot = value;
        case 'NOVFIND_MM_TOKEN':
          novfindToken = value;
        case 'OPENCODE_MM_BOT':
          opencodeBot = value;
        case 'OPENCODE_MM_TOKEN':
          opencodeToken = value;
      }
    }

    if (novfindToken == null || channelUrl == null) {
      debugPrint('[MM] Incomplete config');
      return null;
    }

    // Parse channel URL to get baseUrl, team, channel
    // Format: https://mm.ka.sugee.com/cyb/channels/novfind
    final uri = Uri.tryParse(channelUrl);
    if (uri == null) {
      debugPrint('[MM] Invalid channel URL: $channelUrl');
      return null;
    }

    final segments = uri.pathSegments; // ['cyb', 'channels', 'novfind']
    final team = segments.isNotEmpty ? segments[0] : 'cyb';
    final channel = segments.length >= 3 ? segments[2] : 'novfind';
    final baseUrl = '${uri.scheme}://${uri.host}';

    final config = MattermostConfig(
      baseUrl: baseUrl,
      team: team,
      channel: channel,
      botName: novfindBot ?? 'novfind-android',
      botToken: novfindToken,
      opencodeBotName: opencodeBot ?? 'oc-gui1',
      opencodeToken: opencodeToken ?? '',
    );

    // Cache to SharedPreferences for runtime access
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mm_base_url', config.baseUrl);
    await prefs.setString('mm_team', config.team);
    await prefs.setString('mm_channel', config.channel);
    await prefs.setString('mm_bot_token', config.botToken);
    await prefs.setString('mm_bot_name', config.botName);
    await prefs.setString('mm_opencode_bot', config.opencodeBotName);

    debugPrint('[MM] Config loaded: ${config.botName} @ ${config.baseUrl}/${config.team}/${config.channel}');
    return config;
  } catch (e) {
    debugPrint('[MM] Config load error: $e');
    return null;
  }
}
