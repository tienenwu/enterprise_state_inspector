/// Represents a captured view of state at a point in time.
class StateSnapshot {
  const StateSnapshot({
    this.raw,
    this.structured,
    this.prettyJson,
    this.summary,
  });

  /// Original state object (may be null or non-serializable).
  final Object? raw;

  /// JSON-friendly representation (maps, lists, primitives) if available.
  final Object? structured;

  /// Pretty-printed JSON string representation, when [structured] exists.
  final String? prettyJson;

  /// Short textual summary used for quick display.
  final String? summary;

  bool get hasStructured => structured != null;

  Map<String, Object?> toJson() {
    return {
      if (structured != null) 'structured': structured,
      if (prettyJson != null) 'pretty': prettyJson,
      if (summary != null) 'summary': summary,
    };
  }

  factory StateSnapshot.fromJson(Map<String, Object?> json) {
    return StateSnapshot(
      raw: json['structured'] ?? json['summary'],
      structured: json['structured'],
      prettyJson: json['pretty'] as String?,
      summary: json['summary'] as String?,
    );
  }
}
