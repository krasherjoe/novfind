import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/google_search_service.dart';
import '../data/services/search_query_service.dart';
import '../models/search_result.dart';
import '../models/site_config.dart';
import 'site_filter_provider.dart';

final searchResultsProvider =
    FutureProvider.family<List<SearchResult>, String>((ref, keyword) async {
  final query = await ref.watch(searchQueryProvider.future);
  final siteConfig = SiteConfig.fromEnv(query);
  final disabled = ref.watch(siteFilterProvider).asData?.value ?? {};
  if (disabled.isNotEmpty) {
    final filteredSites = siteConfig.sites.where((s) => !disabled.contains(s)).toList();
    final filteredQuery = filteredSites.map((s) => 'site:$s').join(' OR ');
    final filteredConfig = SiteConfig.fromEnv('($filteredQuery)');
    final service = GoogleSearchService(siteConfig: filteredConfig);
    return service.search(keyword);
  }
  final service = GoogleSearchService(siteConfig: siteConfig);
  return service.search(keyword);
});
