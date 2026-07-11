import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_history_entry.dart';

final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistoryNotifier, List<SearchHistoryEntry>>(
  SearchHistoryNotifier.new,
);

class SearchHistoryNotifier extends AsyncNotifier<List<SearchHistoryEntry>> {
  static const _maxEntries = 50;

  @override
  Future<List<SearchHistoryEntry>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStrings = prefs.getStringList('searchHistory') ?? [];
    return jsonStrings
        .map((s) =>
            SearchHistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addEntry(String keyword) async {
    final current = state.asData?.value ?? [];
    final updated = [
      SearchHistoryEntry(keyword: keyword, searchedAt: DateTime.now()),
      ...current.where((e) => e.keyword != keyword),
    ].take(_maxEntries).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'searchHistory',
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
    state = AsyncValue.data(updated);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('searchHistory');
    state = const AsyncValue.data([]);
  }
}
