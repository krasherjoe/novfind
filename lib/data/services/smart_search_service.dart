import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/search_result.dart';
import '../../models/site_config.dart';
import 'google_search_service.dart';
import 'headless_search_service.dart';

class SmartSearchService {
  final SiteConfig siteConfig;

  SmartSearchService({required this.siteConfig});

  Future<List<SearchResult>> search(String keyword) async {
    try {
      final dioService = GoogleSearchService(siteConfig: siteConfig);
      final results = await dioService.search(keyword);
      if (results.isNotEmpty) {
        debugPrint('[SmartSearch] dio returned ${results.length} results');
        return results;
      }
    } catch (e) {
      debugPrint('[SmartSearch] dio failed: $e');
    }

    if (!Platform.isAndroid) return [];

    try {
      debugPrint('[SmartSearch] Falling back to headless WebView...');
      final headlessResults = await HeadlessSearchService.instance.search(
        keyword,
        _buildSiteQuery(),
      );
      if (headlessResults.isNotEmpty) {
        debugPrint('[SmartSearch] headless returned ${headlessResults.length} results');
        return headlessResults;
      }
    } catch (e) {
      debugPrint('[SmartSearch] headless failed: $e');
    }

    return [];
  }

  String _buildSiteQuery() {
    return siteConfig.sites.map((s) => 'site:$s').join(' OR ');
  }
}
