import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/search_result.dart';

class GoogleCseService {
  static const String _prefsKey = 'google_cse_api_key';
  static const String _prefsCx = 'google_cse_cx';
  static const String _defaultCx = '0166d0eb3f9b14b04';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;
  String? _apiKey;
  String? _cx;

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_prefsKey);
    _cx = prefs.getString(_prefsCx) ?? _defaultCx;
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, key);
  }

  Future<void> setCx(String cx) async {
    _cx = cx;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCx, cx);
  }

  Future<List<SearchResult>> search(String keyword, String siteQuery) async {
    if (!isConfigured) return [];

    final query = '$keyword $siteQuery';
    final url = 'https://www.googleapis.com/customsearch/v1'
        '?key=$_apiKey&cx=$_cx&q=${Uri.encodeComponent(query)}&lr=lang_ja';

    try {
      final resp = await _dio.get(url);
      if (resp.statusCode != 200) return [];

      final data = resp.data as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return [];

      final results = <SearchResult>[];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final title = map['title'] as String? ?? '';
        final link = map['link'] as String? ?? '';
        if (title.isEmpty || link.isEmpty) continue;
        final domain = Uri.tryParse(link)?.host ?? '';
        results.add(SearchResult(title: title, url: link, sourceDomain: domain));
      }
      return results;
    } catch (e) {
      debugPrint('[GoogleCse] Error: $e');
      return [];
    }
  }
}
