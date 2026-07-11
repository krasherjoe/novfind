import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as parser;

import '../../models/search_result.dart';
import '../../models/site_config.dart';

enum SearchErrorType {
  network,
  captcha,
  empty,
  parse,
  timeout,
}

List<SearchResult> deduplicateResults(List<SearchResult> results) {
  final seen = <String>{};
  return results.where((r) => seen.add(r.url)).toList();
}

class SearchException implements Exception {
  final SearchErrorType type;
  final String message;
  final dynamic originalError;
  final String? searchUrl;
  final String? htmlSnippet;

  const SearchException(this.type, this.message,
      {this.originalError, this.searchUrl, this.htmlSnippet});

  @override
  String toString() => 'SearchException($type): $message';
}

class GoogleSearchService {
  final Dio _dio;
  final SiteConfig _siteConfig;

  GoogleSearchService({
    required SiteConfig siteConfig,
    Dio? dio,
  })  : _siteConfig = siteConfig,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 14; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.6533.84 Mobile Safari/537.36',
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
                'Accept-Language': 'ja-JP,ja;q=0.9,en;q=0.8',
                'Sec-Fetch-Mode': 'navigate',
                'Sec-Fetch-Site': 'none',
                'Sec-Fetch-User': '?1',
                'Upgrade-Insecure-Requests': '1',
                'Cache-Control': 'no-cache',
              },
            ));

  Future<List<SearchResult>> search(String keyword) async {
    final queryGroups = _siteConfig.splitQuery(maxGroupSize: 10);
    final allResults = <SearchResult>[];
    final seenUrls = <String>{};

    for (final groupQuery in queryGroups) {
      final results = await _searchGroup(keyword, groupQuery);
      for (final result in results) {
        if (seenUrls.add(result.url)) {
          allResults.add(result);
        }
      }
      if (queryGroups.length > 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    return allResults;
  }

  Future<List<SearchResult>> _searchGroup(
      String keyword, String groupQuery) async {
    final query = '$keyword $groupQuery';
    final url = 'https://www.google.com/search?q=${Uri.encodeComponent(query)}';

    try {
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == 200) {
        final html = response.data as String;
        return parseResults(html, searchUrl: url);
      } else {
        throw SearchException(
          SearchErrorType.network,
          'HTTP ${response.statusCode}',
          searchUrl: url,
        );
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw SearchException(SearchErrorType.timeout, 'Request timed out',
            originalError: e, searchUrl: url);
      }
      throw SearchException(SearchErrorType.network, 'Network error',
          originalError: e, searchUrl: url);
    } catch (e) {
      if (e is SearchException) rethrow;
      throw SearchException(SearchErrorType.parse, 'Unexpected error',
          originalError: e, searchUrl: url);
    }
  }

  @visibleForTesting
  List<SearchResult> parseResults(String html, {String? searchUrl}) {
    final snippet = html.length > 500 ? html.substring(0, 500) : html;

    if (html.contains('captcha') || html.contains('unusual traffic')) {
      throw SearchException(SearchErrorType.captcha, 'CAPTCHA detected',
          searchUrl: searchUrl, htmlSnippet: snippet);
    }

    final document = parser.parse(html);
    final results = <SearchResult>[];

    // Strategy 1: a[href^="/url?q="] > h3 (classic Google SERP)
    var anchors = document.querySelectorAll('a[href^="/url?q="]');
    for (final anchor in anchors) {
      _tryExtract(anchor, results);
    }

    // Strategy 2: h3 inside a with http href
    if (results.isEmpty) {
      final h3s = document.querySelectorAll('h3');
      for (final h3 in h3s) {
        final parent = h3.parent;
        if (parent == null) continue;
        if (parent.localName == 'a') {
          _tryExtractAnchor(parent, h3, results);
        }
      }
    }

    // Strategy 3: div.g > div > a h3 (standard result container)
    if (results.isEmpty) {
      final divs = document.querySelectorAll('div.g');
      for (final div in divs) {
        final firstA = div.querySelector('a[href^="http"]');
        final firstH3 = div.querySelector('h3');
        if (firstA != null && firstH3 != null) {
          _addResult(firstA, firstH3, results);
        }
      }
    }

    // Strategy 4: Any a + h3 pair
    if (results.isEmpty) {
      final allH3s = document.querySelectorAll('h3');
      for (final h3 in allH3s) {
        // Walk up to find enclosing anchor
        var el = h3.parent;
        while (el != null) {
          if (el.localName == 'a') {
            final href = el.attributes['href'] ?? '';
            if (href.startsWith('http://') || href.startsWith('https://')) {
              _addResult(el, h3, results);
            }
            break;
          }
          el = el.parent;
        }
      }
    }

    // Debug info
    final totalH3s = document.querySelectorAll('h3').length;
    final totalAnchors = document.querySelectorAll('a').length;
    final urlAnchors = document.querySelectorAll('a[href^="/url?q="]').length;

    if (results.isEmpty) {
      throw SearchException(
        SearchErrorType.empty,
        'h3=$totalH3s anchors(url)=$urlAnchors totalA=$totalAnchors',
        searchUrl: searchUrl,
        htmlSnippet: snippet,
      );
    }

    return results;
  }

  void _tryExtract(anchor, List<SearchResult> results) {
    final href = anchor.attributes['href'];
    if (href == null) return;

    final parsed = Uri.tryParse(href);
    if (parsed == null) return;

    final targetUrl = parsed.queryParameters['q'];
    if (targetUrl == null) return;
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) return;

    final h3 = anchor.querySelector('h3');
    if (h3 == null) return;

    _addResultString(targetUrl, h3.text.trim(), results);
  }

  void _tryExtractAnchor(anchor, h3, List<SearchResult> results) {
    final href = anchor.attributes['href'] ?? '';
    _addResultString(href, h3.text.trim(), results);
  }

  void _addResult(anchor, h3, List<SearchResult> results) {
    final href = anchor.attributes['href'] ?? '';
    _addResultString(href, h3.text.trim(), results);
  }

  void _addResultString(String url, String title, List<SearchResult> results) {
    final t = title.trim();
    if (t.isEmpty) return;

    // Handle Google redirect URLs
    String targetUrl = url;
    if (url.startsWith('/url?q=')) {
      final parsed = Uri.tryParse(url);
      if (parsed != null) {
        final q = parsed.queryParameters['q'];
        if (q != null) targetUrl = q;
      }
    }

    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) return;

    final sourceDomain = Uri.tryParse(targetUrl)?.host ?? '';
    if (sourceDomain.isEmpty) return;

    results.add(SearchResult(
      title: t,
      url: targetUrl,
      sourceDomain: sourceDomain,
    ));
  }
}

final googleSearchServiceProvider = Provider.family<GoogleSearchService, SiteConfig>(
  (ref, siteConfig) => GoogleSearchService(siteConfig: siteConfig),
);
