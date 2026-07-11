class Preset {
  final String id;
  final String name;
  final String query;
  final DateTime createdAt;

  const Preset({
    required this.id,
    required this.name,
    required this.query,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'query': query,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Preset.fromJson(Map<String, dynamic> json) => Preset(
    id: json['id'] as String,
    name: json['name'] as String,
    query: json['query'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
