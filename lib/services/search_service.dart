import '../data/services/google_search_service.dart';
import '../models/search_result.dart';
import '../models/site_config.dart';

class SearchService {
  final String query;

  SearchService({required this.query});

  Future<List<SearchResult>> search(String keyword) async {
    final siteConfig = SiteConfig.fromEnv(query);
    final service = GoogleSearchService(siteConfig: siteConfig);
    return service.search(keyword);
  }
}
