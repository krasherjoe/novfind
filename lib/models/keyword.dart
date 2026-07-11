class Keyword {
  final String id;
  final String text;
  final DateTime createdAt;

  const Keyword({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  Keyword copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
  }) {
    return Keyword(
      id: id ?? this.id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Keyword.fromJson(Map<String, dynamic> json) => Keyword(
    id: json['id'] as String,
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Keyword && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
