import 'state_annotation.dart';
import 'state_attachment.dart';
import 'state_diff_entry.dart';
import 'state_snapshot.dart';

/// Describes the type of state change captured by the inspector.
enum StateEventKind {
  update,
  transition,
  add,
  dispose,
  error,
}

/// Immutable model representing a recorded state change.
class StateChangeRecord {
  StateChangeRecord({
    required this.id,
    required this.origin,
    required this.kind,
    required this.timestamp,
    required this.summary,
    this.previousSummary,
    this.runtimeTypeName,
    this.state,
    Map<String, Object?> details = const <String, Object?>{},
    this.snapshot = const StateSnapshot(),
    this.previousSnapshot,
    List<StateDiffEntry> diffs = const <StateDiffEntry>[],
    Iterable<String> tags = const <String>[],
    Map<String, num> metrics = const <String, num>{},
    Iterable<StateAnnotation> annotations = const <StateAnnotation>[],
    Iterable<StateAttachment> attachments = const <StateAttachment>[],
  })  : _details = Map.unmodifiable(details),
        diffs = List.unmodifiable(diffs),
        tags = List.unmodifiable(
          tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty),
        ),
        metrics = Map.unmodifiable(metrics),
        annotations = List.unmodifiable(annotations),
        attachments = List.unmodifiable(attachments);

  /// Sequence number; monotonic increasing for ordering.
  final int id;

  /// Logical source of the change (provider name, bloc class, etc.).
  final String origin;

  /// Kind of lifecycle or runtime event that occurred.
  final StateEventKind kind;

  /// Timestamp of when the change was captured.
  final DateTime timestamp;

  /// Short summary describing the new state or event.
  final String summary;

  /// Optional summary describing the previous state (if available).
  final String? previousSummary;

  /// Optional runtime type information reported by the source.
  final String? runtimeTypeName;

  /// Raw state object when available; used for programmatic inspection.
  final Object? state;

  /// Additional structured metadata related to the change.
  final Map<String, Object?> _details;

  Map<String, Object?> get details => _details;

  /// Structured snapshot of the state after the change.
  final StateSnapshot snapshot;

  /// Structured snapshot of the state before the change, if known.
  final StateSnapshot? previousSnapshot;

  /// Structural differences between [previousSnapshot] and [snapshot].
  final List<StateDiffEntry> diffs;

  /// Classification tags attached to this record (for filtering/grouping).
  final List<String> tags;

  /// Quantitative metrics captured during this change (duration, counts, etc.).
  final Map<String, num> metrics;

  /// Developer-authored annotations to provide additional insight.
  final List<StateAnnotation> annotations;

  /// External artifacts (screenshots, recordings) linked to this record.
  final List<StateAttachment> attachments;

  /// String-friendly representation for serialization or logs.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'origin': origin,
      'kind': kind.name,
      'timestamp': timestamp.toIso8601String(),
      'summary': summary,
      if (previousSummary != null) 'previousSummary': previousSummary,
      if (runtimeTypeName != null) 'runtimeType': runtimeTypeName,
      if (state != null) 'state': state.toString(),
      if (details.isNotEmpty) 'details': details,
      if (snapshot.hasStructured || snapshot.summary != null)
        'snapshot': snapshot.toJson(),
      if (previousSnapshot?.hasStructured == true ||
          previousSnapshot?.summary != null)
        'previousSnapshot': previousSnapshot?.toJson(),
      if (diffs.isNotEmpty)
        'diffs': diffs.map((entry) => entry.toJson()).toList(),
      if (tags.isNotEmpty) 'tags': tags,
      if (metrics.isNotEmpty) 'metrics': metrics,
      if (annotations.isNotEmpty)
        'annotations': annotations.map((e) => e.toJson()).toList(),
      if (attachments.isNotEmpty)
        'attachments': attachments.map((e) => e.toJson()).toList(),
    };
  }

  factory StateChangeRecord.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'] as String? ?? StateEventKind.update.name;
    final kind = StateEventKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => StateEventKind.update,
    );

    final snapshotJson = json['snapshot'];
    final previousSnapshotJson = json['previousSnapshot'];
    final diffsJson = json['diffs'];
    final tagsJson = json['tags'];
    final metricsJson = json['metrics'];
    final annotationsJson = json['annotations'];
    final attachmentsJson = json['attachments'];

    return StateChangeRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      origin: json['origin'] as String? ?? 'unknown',
      kind: kind,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      summary: json['summary'] as String? ?? '',
      previousSummary: json['previousSummary'] as String?,
      runtimeTypeName: json['runtimeType'] as String?,
      state: json['state'],
      details: _castDetails(json['details']),
      snapshot: snapshotJson is Map<String, Object?>
          ? StateSnapshot.fromJson(snapshotJson)
          : const StateSnapshot(),
      previousSnapshot: previousSnapshotJson is Map<String, Object?>
          ? StateSnapshot.fromJson(previousSnapshotJson)
          : null,
      diffs: diffsJson is List
          ? diffsJson
              .whereType<Map<String, Object?>>()
              .map(StateDiffEntry.fromJson)
              .toList()
          : const <StateDiffEntry>[],
      tags: tagsJson is Iterable
          ? tagsJson.map((entry) => entry.toString())
          : const <String>[],
      metrics: metricsJson is Map
          ? metricsJson.map(
              (key, value) => MapEntry(key.toString(), _parseNum(value)),
            )
          : const <String, num>{},
      annotations: annotationsJson is List
          ? annotationsJson
              .whereType<Map<String, Object?>>()
              .map(StateAnnotation.fromJson)
              .toList()
          : const <StateAnnotation>[],
      attachments: attachmentsJson is List
          ? attachmentsJson
              .whereType<Map<String, Object?>>()
              .map(StateAttachment.fromJson)
              .toList()
          : const <StateAttachment>[],
    );
  }

  StateChangeRecord copyWith({
    int? id,
    String? origin,
    StateEventKind? kind,
    DateTime? timestamp,
    String? summary,
    String? previousSummary,
    String? runtimeTypeName,
    Object? state,
    Map<String, Object?>? details,
    StateSnapshot? snapshot,
    StateSnapshot? previousSnapshot,
    List<StateDiffEntry>? diffs,
    Iterable<String>? tags,
    Map<String, num>? metrics,
    Iterable<StateAnnotation>? annotations,
    Iterable<StateAttachment>? attachments,
  }) {
    return StateChangeRecord(
      id: id ?? this.id,
      origin: origin ?? this.origin,
      kind: kind ?? this.kind,
      timestamp: timestamp ?? this.timestamp,
      summary: summary ?? this.summary,
      previousSummary: previousSummary ?? this.previousSummary,
      runtimeTypeName: runtimeTypeName ?? this.runtimeTypeName,
      state: state ?? this.state,
      details: details ?? _details,
      snapshot: snapshot ?? this.snapshot,
      previousSnapshot: previousSnapshot ?? this.previousSnapshot,
      diffs: diffs ?? this.diffs,
      tags: tags ?? this.tags,
      metrics: metrics ?? this.metrics,
      annotations: annotations ?? this.annotations,
      attachments: attachments ?? this.attachments,
    );
  }
}

Map<String, Object?> _castDetails(Object? value) {
  if (value is Map) {
    return value.map((key, dynamic entry) => MapEntry(key.toString(), entry));
  }
  return const {};
}

num _parseNum(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value) ?? 0;
  }
  return 0;
}
