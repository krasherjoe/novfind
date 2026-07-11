import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/mattermost_config.dart';

class MattermostApi {
  final MattermostConfig config;
  late final Dio _dio;
  String? _channelId;
  bool _initialized = false;

  MattermostApi(this.config) {
    _dio = Dio(BaseOptions(
      baseUrl: config.baseUrl,
      headers: {'Authorization': 'Bearer ${config.botToken}'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  bool get isInitialized => _initialized;

  Future<String> getChannelId() async {
    if (_channelId != null) return _channelId!;
    try {
      final resp = await _dio.get(
        '/api/v4/teams/name/${config.team}/channels/name/${config.channel}',
      );
      _channelId = resp.data['id'] as String;
      _initialized = true;
      debugPrint('[MM] Channel ID: $_channelId');
      return _channelId!;
    } catch (e) {
      // Fallback: try listing teams and channels
      debugPrint('[MM] Channel lookup failed: $e');
      rethrow;
    }
  }

  Future<void> sendMessage(String text, {String? rootId}) async {
    final cid = await getChannelId();
    final body = <String, dynamic>{
      'channel_id': cid,
      'message': text,
    };
    if (rootId != null) body['root_id'] = rootId;

    await _dio.post('/api/v4/posts', data: jsonEncode(body));
  }

  Future<Map<String, DateTime>> getPostTimestamps() async {
    final cid = await getChannelId();
    final resp = await _dio.get('/api/v4/channels/$cid/posts');
    final posts = resp.data['posts'] as Map<String, dynamic>;
    final timestamps = <String, DateTime>{};
    for (final entry in posts.entries) {
      final ts = DateTime.tryParse(entry.value['create_at'] as String? ?? '');
      if (ts != null) timestamps[entry.key] = ts;
    }
    return timestamps;
  }

  Future<List<Map<String, dynamic>>> fetchPosts({DateTime? since}) async {
    final cid = await getChannelId();
    final resp = await _dio.get('/api/v4/channels/$cid/posts');
    final posts = resp.data['posts'] as Map<String, dynamic>;
    final order = (resp.data['order'] as List<dynamic>?) ?? [];

    final result = <Map<String, dynamic>>[];
    for (final id in order) {
      final post = posts[id as String] as Map<String, dynamic>;
      final createdAt = DateTime.tryParse(post['create_at'] as String? ?? '');
      if (since != null && createdAt != null && !createdAt.isAfter(since)) {
        continue;
      }
      result.add(post);
    }
    return result;
  }

  Future<void> postResult(String postId, String result) async {
    final cid = await getChannelId();
    await _dio.post('/api/v4/posts', data: jsonEncode({
      'channel_id': cid,
      'root_id': postId,
      'message': result,
    }));
  }
}
