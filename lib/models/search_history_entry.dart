class SearchHistoryEntry {
  final String keyword;
  final DateTime searchedAt;

  const SearchHistoryEntry({
    required this.keyword,
    required this.searchedAt,
  });

  Map<String, dynamic> toJson() => {
    'keyword': keyword,
    'searchedAt': searchedAt.toIso8601String(),
  };

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SearchHistoryEntry(
        keyword: json['keyword'] as String,
        searchedAt: DateTime.parse(json['searchedAt'] as String),
      );
}
