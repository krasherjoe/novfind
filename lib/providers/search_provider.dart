import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/google_search_service.dart';
import '../data/services/search_query_service.dart';
import '../models/search_result.dart';
import '../models/site_config.dart';

final searchResultsProvider =
    FutureProvider.family<List<SearchResult>, String>((ref, keyword) async {
  final query = await ref.watch(searchQueryProvider.future);
  final siteConfig = SiteConfig.fromEnv(query);
  final service = GoogleSearchService(siteConfig: siteConfig);
  return service.search(keyword);
});
