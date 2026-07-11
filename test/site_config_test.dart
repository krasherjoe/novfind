import 'package:flutter_test/flutter_test.dart';
import 'package:novfind/models/site_config.dart';

void main() {
  group('SiteConfig', () {
    const sampleQuery =
        '(site:syosetu.com OR site:kakuyomu.jp OR site:aozora.gr.jp)';

    test('parses sites from query', () {
      final config = SiteConfig.fromEnv(sampleQuery);
      expect(config.sites, hasLength(3));
      expect(config.sites[0], 'syosetu.com');
      expect(config.sites[1], 'kakuyomu.jp');
      expect(config.sites[2], 'aozora.gr.jp');
    });

    test('returns correct site count', () {
      final config = SiteConfig.fromEnv(sampleQuery);
      expect(config.siteCount, 3);
    });

    test('splits query into groups', () {
      final config = SiteConfig.fromEnv(sampleQuery);
      final groups = config.splitQuery(maxGroupSize: 2);
      expect(groups, hasLength(2));
      expect(groups[0], contains('site:syosetu.com'));
      expect(groups[0], contains('site:kakuyomu.jp'));
      expect(groups[1], contains('site:aozora.gr.jp'));
    });

    test('returns single group when less than maxGroupSize', () {
      final config = SiteConfig.fromEnv(sampleQuery);
      final groups = config.splitQuery(maxGroupSize: 10);
      expect(groups, hasLength(1));
    });

    test('handles empty query', () {
      final config = SiteConfig.fromEnv('');
      expect(config.sites, isEmpty);
      expect(config.splitQuery(), isEmpty);
    });
  });
}
