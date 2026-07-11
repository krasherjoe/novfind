import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/preset.dart';

final presetProvider =
    AsyncNotifierProvider<PresetNotifier, List<Preset>>(PresetNotifier.new);

class PresetNotifier extends AsyncNotifier<List<Preset>> {
  @override
  Future<List<Preset>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStrings = prefs.getStringList('presets') ?? [];
    return jsonStrings
        .map((s) => Preset.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addPreset(String name, String query) async {
    final current = state.asData?.value ?? [];
    final preset = Preset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      query: query,
      createdAt: DateTime.now(),
    );
    final updated = [...current, preset];
    await _save(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> deletePreset(String id) async {
    final current = state.asData?.value ?? [];
    final updated = current.where((p) => p.id != id).toList();
    await _save(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> _save(List<Preset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'presets',
      presets.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }
}
