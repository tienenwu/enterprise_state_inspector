enum StateDiffKind { added, removed, changed }

/// Describes a granular difference between two structured state snapshots.
class StateDiffEntry {
  const StateDiffEntry({
    required this.path,
    required this.kind,
    this.before,
    this.after,
  });

  /// Sequence of keys/indices representing where the change occurred.
  final List<Object> path;

  /// The kind of structural change that happened.
  final StateDiffKind kind;

  /// The value before the change (if available).
  final Object? before;

  /// The value after the change (if available).
  final Object? after;

  /// Human-friendly representation of the path (e.g. `user.profile[0].name`).
  String get pathAsString {
    if (path.isEmpty) {
      return '<root>';
    }
    final buffer = StringBuffer();
    for (final segment in path) {
      if (segment is int) {
        buffer.write('[$segment]');
      } else {
        if (buffer.isNotEmpty) {
          buffer.write('.');
        }
        buffer.write(segment.toString());
      }
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() {
    return {
      'path': path,
      'kind': kind.name,
      if (before != null) 'before': before,
      if (after != null) 'after': after,
    };
  }

  factory StateDiffEntry.fromJson(Map<String, Object?> json) {
    final rawPath = json['path'];
    final List<Object> pathSegments;
    if (rawPath is List) {
      pathSegments = rawPath.map<Object>((segment) {
        if (segment is num) {
          return segment.toInt();
        }
        return segment.toString();
      }).toList(growable: false);
    } else {
      pathSegments = const <Object>[];
    }

    final kindName = json['kind'] as String? ?? StateDiffKind.changed.name;
    final kind = StateDiffKind.values.firstWhere(
        (value) => value.name == kindName,
        orElse: () => StateDiffKind.changed);

    return StateDiffEntry(
      path: pathSegments,
      kind: kind,
      before: json.containsKey('before') ? json['before'] : null,
      after: json.containsKey('after') ? json['after'] : null,
    );
  }
}
