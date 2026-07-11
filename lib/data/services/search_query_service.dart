import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchQueryService {
  String? _query;

  Future<String> loadQuery() async {
    if (_query != null) return _query!;
    _query = await rootBundle.loadString('assets/search_query.txt');
    return _query!;
  }

  String? get query => _query;
}

final searchQueryServiceProvider = Provider<SearchQueryService>((ref) {
  return SearchQueryService();
});

final searchQueryProvider = FutureProvider<String>((ref) async {
  final service = ref.watch(searchQueryServiceProvider);
  return service.loadQuery();
});
