import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/search_query_service.dart';
import '../models/site_config.dart';

final siteFilterProvider =
    AsyncNotifierProvider<SiteFilterNotifier, Set<String>>(
  SiteFilterNotifier.new,
);

class SiteFilterNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('disabledSites');
    if (json == null) return {};
    return (jsonDecode(json) as List).cast<String>().toSet();
  }

  Future<void> toggle(String domain) async {
    final current = Set<String>.from(state.asData?.value ?? {});
    if (current.contains(domain)) {
      current.remove(domain);
    } else {
      current.add(domain);
    }
    await _save(current);
    state = AsyncValue.data(current);
  }

  Future<void> setAllEnabled() async {
    await _save({});
    state = const AsyncValue.data({});
  }

  Future<List<String>> getEnabledSites(SiteConfig config) async {
    final disabled = state.asData?.value ?? {};
    return config.sites.where((s) => !disabled.contains(s)).toList();
  }

  Future<void> _save(Set<String> disabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('disabledSites', jsonEncode(disabled.toList()));
  }
}
