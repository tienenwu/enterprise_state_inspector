/// Types of rich media that can be associated with a timeline event.
enum StateAttachmentType {
  screenshot,
  screenRecording,
  log,
  custom,
}

/// Metadata describing an external artifact linked to a state record.
class StateAttachment {
  StateAttachment({
    String? id,
    required this.recordId,
    required this.uri,
    this.type = StateAttachmentType.custom,
    this.thumbnailUri,
    this.description,
    DateTime? capturedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  })  : id = id ?? _generateId(),
        capturedAt = capturedAt ?? DateTime.now(),
        metadata = Map.unmodifiable(metadata);

  static int _autoIncrement = 0;

  static String _generateId() {
    final seed = DateTime.now().microsecondsSinceEpoch;
    final next = _autoIncrement++;
    return 'attachment_${seed}_$next';
  }

  final String id;
  final int recordId;
  final String uri;
  final StateAttachmentType type;
  final String? thumbnailUri;
  final String? description;
  final DateTime capturedAt;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
        'id': id,
        'recordId': recordId,
        'uri': uri,
        'type': type.name,
        if (thumbnailUri != null) 'thumbnailUri': thumbnailUri,
        if (description != null) 'description': description,
        'capturedAt': capturedAt.toIso8601String(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory StateAttachment.fromJson(Map<String, Object?> json) {
    final rawMetadata = json['metadata'];
    return StateAttachment(
      id: json['id'] as String?,
      recordId: (json['recordId'] as num?)?.toInt() ?? 0,
      uri: json['uri'] as String? ?? '',
      type: StateAttachmentType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => StateAttachmentType.custom,
      ),
      thumbnailUri: json['thumbnailUri'] as String?,
      description: json['description'] as String?,
      capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.now(),
      metadata: rawMetadata is Map
          ? rawMetadata.map((key, value) => MapEntry(key.toString(), value))
          : const <String, Object?>{},
    );
  }

  StateAttachment copyWith({
    String? id,
    int? recordId,
    String? uri,
    StateAttachmentType? type,
    String? thumbnailUri,
    String? description,
    DateTime? capturedAt,
    Map<String, Object?>? metadata,
  }) {
    return StateAttachment(
      id: id ?? this.id,
      recordId: recordId ?? this.recordId,
      uri: uri ?? this.uri,
      type: type ?? this.type,
      thumbnailUri: thumbnailUri ?? this.thumbnailUri,
      description: description ?? this.description,
      capturedAt: capturedAt ?? this.capturedAt,
      metadata: metadata ?? this.metadata,
    );
  }
}
