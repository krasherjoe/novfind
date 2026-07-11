import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/keyword.dart';

class KeywordRepository {
  static const _key = 'keywords';

  Future<List<Keyword>> loadKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStrings = prefs.getStringList(_key) ?? [];
    return jsonStrings
        .map((s) => Keyword.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveKeywords(List<Keyword> keywords) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStrings = keywords.map((k) => jsonEncode(k.toJson())).toList();
    await prefs.setStringList(_key, jsonStrings);
  }
}
