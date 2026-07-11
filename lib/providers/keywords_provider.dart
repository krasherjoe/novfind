import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/keyword_repository.dart';
import '../models/keyword.dart';

final keywordRepositoryProvider = Provider<KeywordRepository>((ref) {
  return KeywordRepository();
});

final keywordsProvider =
    AsyncNotifierProvider<KeywordsNotifier, List<Keyword>>(KeywordsNotifier.new);

class KeywordsNotifier extends AsyncNotifier<List<Keyword>> {
  @override
  Future<List<Keyword>> build() async {
    final repository = ref.read(keywordRepositoryProvider);
    return repository.loadKeywords();
  }

  Future<void> addKeyword(String text) async {
    final previous = state.requireValue;
    final keyword = Keyword(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      createdAt: DateTime.now(),
    );
    final updated = <Keyword>[...previous, keyword];
    final repository = ref.read(keywordRepositoryProvider);
    await repository.saveKeywords(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> removeKeyword(String id) async {
    final previous = state.requireValue;
    final updated = previous.where((k) => k.id != id).toList();
    final repository = ref.read(keywordRepositoryProvider);
    await repository.saveKeywords(updated);
    state = AsyncValue.data(updated);
  }
}
