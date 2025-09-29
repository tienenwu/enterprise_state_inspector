/// Severity level for timeline annotations.
enum StateAnnotationSeverity {
  info,
  warning,
  error,
}

/// Additional context that developers can attach to timeline events.
class StateAnnotation {
  StateAnnotation({
    String? id,
    required this.recordId,
    required this.message,
    this.author,
    this.severity = StateAnnotationSeverity.info,
    Iterable<String> tags = const <String>[],
    DateTime? createdAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  })  : id = id ?? _generateId(),
        tags = List.unmodifiable(
          tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty),
        ),
        createdAt = createdAt ?? DateTime.now(),
        metadata = Map.unmodifiable(metadata);

  static int _autoIncrement = 0;

  static String _generateId() {
    final seed = DateTime.now().microsecondsSinceEpoch;
    final next = _autoIncrement++;
    return 'annotation_${seed}_$next';
  }

  /// Stable identifier so annotations can be updated or removed.
  final String id;

  /// Identifier of the record the annotation is attached to.
  final int recordId;

  /// Short message describing the insight or note.
  final String message;

  /// Optional author label (person, bot, CI system).
  final String? author;

  /// Severity indicator to keep triage focused.
  final StateAnnotationSeverity severity;

  /// Optional tags to support filtering or grouping.
  final List<String> tags;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Arbitrary metadata (e.g., ticket IDs, reproduction steps).
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
        'id': id,
        'recordId': recordId,
        'message': message,
        if (author != null) 'author': author,
        'severity': severity.name,
        if (tags.isNotEmpty) 'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory StateAnnotation.fromJson(Map<String, Object?> json) {
    final rawTags = json['tags'];
    final rawMetadata = json['metadata'];
    return StateAnnotation(
      id: json['id'] as String?,
      recordId: (json['recordId'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
      author: json['author'] as String?,
      severity: StateAnnotationSeverity.values.firstWhere(
        (value) => value.name == json['severity'],
        orElse: () => StateAnnotationSeverity.info,
      ),
      tags: rawTags is Iterable
          ? rawTags.map((tag) => tag.toString())
          : const <String>[],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      metadata: rawMetadata is Map
          ? rawMetadata.map((key, value) => MapEntry(key.toString(), value))
          : const <String, Object?>{},
    );
  }

  StateAnnotation copyWith({
    String? id,
    int? recordId,
    String? message,
    String? author,
    StateAnnotationSeverity? severity,
    Iterable<String>? tags,
    DateTime? createdAt,
    Map<String, Object?>? metadata,
  }) {
    return StateAnnotation(
      id: id ?? this.id,
      recordId: recordId ?? this.recordId,
      message: message ?? this.message,
      author: author ?? this.author,
      severity: severity ?? this.severity,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }
}
