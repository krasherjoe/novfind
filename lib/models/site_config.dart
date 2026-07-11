class SiteConfig {
  final String query;

  const SiteConfig({required this.query});

  factory SiteConfig.fromEnv(String query) => SiteConfig(query: query);

  List<String> get sites {
    final regex = RegExp(r'site:([^\s)]+)');
    return regex.allMatches(query).map((m) => m.group(1)!).toList();
  }

  int get siteCount => sites.length;

  List<String> splitQuery({int maxGroupSize = 10}) {
    final groups = <String>[];
    for (var i = 0; i < sites.length; i += maxGroupSize) {
      final group = sites.sublist(i, (i + maxGroupSize).clamp(0, sites.length));
      groups.add(group.map((s) => 'site:$s').join(' OR '));
    }
    return groups;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SiteConfig && runtimeType == other.runtimeType && query == other.query;

  @override
  int get hashCode => query.hashCode;
}
