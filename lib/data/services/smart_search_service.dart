import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/search_result.dart';
import '../../models/site_config.dart';
import 'google_cse_service.dart';
import 'google_search_service.dart';
import 'headless_search_service.dart';

class SmartSearchService {
  final SiteConfig siteConfig;
  static String? lastError;
  static String? lastDioError;
  static String? lastHeadlessError;
  static String? lastCseError;
  static final GoogleCseService _cse = GoogleCseService();

  SmartSearchService({required this.siteConfig});

  Future<List<SearchResult>> search(String keyword) async {
    lastError = null;
    lastDioError = null;
    lastHeadlessError = null;
    lastCseError = null;

    // Phase 0: Google Custom Search API (best results, requires API key)
    await _cse.loadConfig();
    if (_cse.isConfigured) {
      try {
        debugPrint('[SmartSearch] Trying Google CSE...');
        final results = await _cse.search(keyword, _buildSiteQuery());
        if (results.isNotEmpty) {
          debugPrint('[SmartSearch] CSE returned ${results.length} results');
          return results;
        }
        lastCseError = 'CSE returned 0 results';
      } catch (e) {
        lastCseError = '$e';
        debugPrint('[SmartSearch] CSE failed: $e');
      }
    }

    try {
      final dioService = GoogleSearchService(siteConfig: siteConfig);
      final results = await dioService.search(keyword);
      if (results.isNotEmpty) {
        debugPrint('[SmartSearch] dio returned ${results.length} results');
        return results;
      }
    } catch (e) {
      lastDioError = '$e';
      debugPrint('[SmartSearch] dio failed: $e');
    }

    if (!Platform.isAndroid) {
      lastError = 'Not on Android, skipping headless';
      return [];
    }

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
      lastHeadlessError = 'Headless returned 0 results';
    } catch (e) {
      lastHeadlessError = '$e';
      debugPrint('[SmartSearch] headless failed: $e');
    }

    lastError = 'Both dio and headless failed';
    return [];
  }

  String _buildSiteQuery() {
    return siteConfig.sites.map((s) => 'site:$s').join(' OR ');
  }
}
