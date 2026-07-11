class SearchResult {
  final String title;
  final String url;
  final String sourceDomain;

  const SearchResult({
    required this.title,
    required this.url,
    required this.sourceDomain,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'sourceDomain': sourceDomain,
  };

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    title: json['title'] as String,
    url: json['url'] as String,
    sourceDomain: json['sourceDomain'] as String,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;
}
