import 'package:flutter_test/flutter_test.dart';
import 'package:novfind/data/services/google_search_service.dart';
import 'package:novfind/models/site_config.dart';

void main() {
  late GoogleSearchService service;

  setUp(() {
    service = GoogleSearchService(
      siteConfig: SiteConfig.fromEnv('(site:test.com)'),
    );
  });

  group('HTML parsing', () {
    test('parses standard Google SERP result', () {
      final html = '''
        <html>
        <body>
        <a href="/url?q=https://example.com/novel&sa=U&ved=2ahUKEwjU">
          <h3>Test Novel Title</h3>
        </a>
        <a href="/url?q=https://other.com/story&sa=U&ved=2ahUKEwjU">
          <h3>Another Story</h3>
        </a>
        </body>
        </html>
      ''';

      final results = service.parseResults(html);
      expect(results, hasLength(2));
      expect(results[0].title, 'Test Novel Title');
      expect(results[0].url, 'https://example.com/novel');
      expect(results[0].sourceDomain, 'example.com');
      expect(results[1].title, 'Another Story');
      expect(results[1].sourceDomain, 'other.com');
    });

    test('skips non-http results', () {
      final html = '''
        <html>
        <body>
        <a href="/url?q=javascript:void(0)&sa=U&ved=2ahUKEwjU">
          <h3>Skip this</h3>
        </a>
        <a href="/url?q=https://example.com/valid&sa=U&ved=2ahUKEwjU">
          <h3>Valid Result</h3>
        </a>
        </body>
        </html>
      ''';

      final results = service.parseResults(html);
      expect(results, hasLength(1));
      expect(results[0].url, 'https://example.com/valid');
    });

    test('throws empty when no h3 elements found', () {
      final html = '''
        <html>
        <body>
        <a href="/url?q=https://example.com/novel&sa=U">
          No h3 here
        </a>
        </body>
        </html>
      ''';

      expect(
        () => service.parseResults(html),
        throwsA(isA<SearchException>().having(
          (e) => e.type,
          'type',
          SearchErrorType.empty,
        )),
      );
    });

    test('throws on CAPTCHA page', () {
      final html = '''
        <html>
        <body>
        Please show you are not a robot.
        Our systems have detected unusual traffic.
        </body>
        </html>
      ''';

      expect(
        () => service.parseResults(html),
        throwsA(isA<SearchException>().having(
          (e) => e.type,
          'type',
          SearchErrorType.captcha,
        )),
      );
    });

    test('throws on empty results page without h3', () {
      final html = '''
        <html>
        <body>
        No results found.
        </body>
        </html>
      ''';

      expect(
        () => service.parseResults(html),
        throwsA(isA<SearchException>().having(
          (e) => e.type,
          'type',
          SearchErrorType.empty,
        )),
      );
    });

    test('parses Japanese novel titles correctly', () {
      final html = '''
        <html>
        <body>
        <a href="/url?q=https://syosetu.com/n123&sa=U&ved=2ahUKEwjU">
          <h3>転生したらスライムだった件</h3>
        </a>
        </body>
        </html>
      ''';

      final results = service.parseResults(html);
      expect(results, hasLength(1));
      expect(results[0].title, '転生したらスライムだった件');
      expect(results[0].sourceDomain, 'syosetu.com');
    });
  });
}
