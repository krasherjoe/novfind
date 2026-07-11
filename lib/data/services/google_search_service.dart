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

typedef SearchResultParser = List<SearchResult> Function(String html);

class SearchException implements Exception {
  final SearchErrorType type;
  final String message;
  final dynamic originalError;

  const SearchException(this.type, this.message, {this.originalError});

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
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
                'Accept-Language': 'ja-JP,ja;q=0.9,en;q=0.8',
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
          extra: {'retry': 2},
        ),
      );

      if (response.statusCode == 200) {
        return parseResults(response.data as String);
      } else {
        throw SearchException(
          SearchErrorType.network,
          'HTTP ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw SearchException(SearchErrorType.timeout, 'Request timed out',
            originalError: e);
      }
      throw SearchException(SearchErrorType.network, 'Network error',
          originalError: e);
    } catch (e) {
      if (e is SearchException) rethrow;
      throw SearchException(SearchErrorType.parse, 'Unexpected error',
          originalError: e);
    }
  }

  @visibleForTesting
  List<SearchResult> parseResults(String html) {
    if (html.contains('captcha') || html.contains('unusual traffic')) {
      throw SearchException(SearchErrorType.captcha, 'CAPTCHA detected');
    }

    final document = parser.parse(html);
    final results = <SearchResult>[];

    final anchors = document.querySelectorAll('a[href^="/url?q="]');
    for (final anchor in anchors) {
      final href = anchor.attributes['href'];
      if (href == null) continue;

      final url = Uri.tryParse(href);
      if (url == null) continue;

      final queryParams = url.queryParameters;
      final targetUrl = queryParams['q'];
      if (targetUrl == null) continue;
      if (targetUrl.startsWith('http://') || targetUrl.startsWith('https://')) {
        final h3 = anchor.querySelector('h3');
        if (h3 == null) continue;

        final title = h3.text.trim();
        if (title.isEmpty) continue;

        final sourceDomain = Uri.tryParse(targetUrl)?.host ?? '';
        if (sourceDomain.isEmpty) continue;

        results.add(SearchResult(
          title: title,
          url: targetUrl,
          sourceDomain: sourceDomain,
        ));
      }
    }

    if (results.isEmpty) {
      final h3s = document.querySelectorAll('h3');
      if (h3s.isEmpty) {
        throw SearchException(SearchErrorType.empty, 'No results found');
      }
    }

    return results;
  }
}

final googleSearchServiceProvider = Provider.family<GoogleSearchService, SiteConfig>(
  (ref, siteConfig) => GoogleSearchService(siteConfig: siteConfig),
);
