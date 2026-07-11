import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as parser;

import '../../models/search_result.dart';

class HeadlessSearchService {
  static HeadlessSearchService? _instance;
  static HeadlessSearchService get instance => _instance ??= HeadlessSearchService._();

  HeadlessSearchService._();

  Future<List<SearchResult>> search(String keyword, String siteQuery) async {
    final query = '$keyword $siteQuery';
    final uri = WebUri('https://www.google.com/search?q=${Uri.encodeComponent(query)}');

    final completer = Completer<List<SearchResult>>();
    late final HeadlessInAppWebView headlessWebView;

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: uri),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent:
            'Mozilla/5.0 (Linux; Android 14; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.6533.84 Mobile Safari/537.36',
        cacheEnabled: false,
        clearCache: true,
      ),
      onLoadStop: (controller, url) async {
        _handleLoadStop(controller, completer, headlessWebView);
      },
      onReceivedError: (controller, request, error) {
        if (!completer.isCompleted) {
          completer.complete([]);
        }
      },
    );

    try {
      await headlessWebView.run();
      return await completer.future.timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('[HeadlessSearch] Error: $e');
      try { await headlessWebView.dispose(); } catch (_) {}
      return [];
    }
  }

  Future<void> _handleLoadStop(
    InAppWebViewController controller,
    Completer<List<SearchResult>> completer,
    HeadlessInAppWebView headlessWebView,
  ) async {
    try {
      await Future.delayed(const Duration(seconds: 3));
      final html = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      final results = _parseGoogleResults(html ?? '');
      if (!completer.isCompleted) completer.complete(results);
    } catch (e) {
      debugPrint('[HeadlessSearch] onLoadStop error: $e');
      if (!completer.isCompleted) completer.complete([]);
    }
    await headlessWebView.dispose();
  }

  List<SearchResult> _parseGoogleResults(String html) {
    final document = parser.parse(html);
    final results = <SearchResult>[];
    final seen = <String>{};

    var anchors = document.querySelectorAll('a[href^="/url?q="]');
    for (final a in anchors) {
      final href = a.attributes['href'];
      if (href == null) continue;
      final parsed = Uri.tryParse(href);
      if (parsed == null) continue;
      final targetUrl = parsed.queryParameters['q'];
      if (targetUrl == null) continue;
      if (!targetUrl.startsWith('http')) continue;
      final h3 = a.querySelector('h3');
      if (h3 == null) continue;
      final title = h3.text.trim();
      if (title.isEmpty || !seen.add(targetUrl)) continue;
      final domain = Uri.tryParse(targetUrl)?.host ?? '';
      results.add(SearchResult(title: title, url: targetUrl, sourceDomain: domain));
    }

    if (results.isEmpty) {
      final divs = document.querySelectorAll('div.g');
      for (final div in divs) {
        final a = div.querySelector('a[href^="http"]');
        final h3 = div.querySelector('h3');
        if (a != null && h3 != null) {
          final href = a.attributes['href'] ?? '';
          final title = h3.text.trim();
          if (title.isNotEmpty && seen.add(href)) {
            final domain = Uri.tryParse(href)?.host ?? '';
            results.add(SearchResult(title: title, url: href, sourceDomain: domain));
          }
        }
      }
    }

    if (results.isEmpty) {
      final allResultElements = document.querySelectorAll('[data-hveid]');
      for (final el in allResultElements) {
        final a = el.querySelector('a[href^="http"]');
        final h3 = el.querySelector('h3');
        if (a != null && h3 != null) {
          final href = a.attributes['href'] ?? '';
          final title = h3.text.trim();
          if (title.isNotEmpty && seen.add(href)) {
            final domain = Uri.tryParse(href)?.host ?? '';
            results.add(SearchResult(title: title, url: href, sourceDomain: domain));
          }
        }
      }
    }

    return results;
  }
}
