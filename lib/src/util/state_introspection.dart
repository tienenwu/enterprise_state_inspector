import 'dart:convert';

import '../model/state_diff_entry.dart';
import '../model/state_snapshot.dart';
import 'value_formatter.dart';

StateSnapshot buildSnapshot(Object? value, {int maxDepth = 6}) {
  final structured = _normalize(value, 0, maxDepth, <int>{});
  final prettyJson = structured == null
      ? null
      : const JsonEncoder.withIndent('  ').convert(structured);
  return StateSnapshot(
    raw: value,
    structured: structured,
    prettyJson: prettyJson,
    summary: describeValue(value, maxChars: 200),
  );
}

List<StateDiffEntry> buildDiff(StateSnapshot? previous, StateSnapshot current,
    {int maxEntries = 200}) {
  final previousData = previous?.structured;
  final currentData = current.structured;
  if (previousData == null || currentData == null) {
    return const <StateDiffEntry>[];
  }
  final results = <StateDiffEntry>[];
  _diffRecursive(previousData, currentData, <Object>[], results, maxEntries);
  return List.unmodifiable(results);
}

Object? _normalize(
  Object? value,
  int depth,
  int maxDepth,
  Set<int> visited,
) {
  if (value == null ||
      value is num ||
      value is bool ||
      value is String) {
    return value;
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  if (value is Enum) {
    return value.name;
  }

  if (depth >= maxDepth) {
    return '<max-depth>'; // Indicate truncation.
  }

  if (value is Map) {
    final identity = identityHashCode(value);
    if (visited.contains(identity)) {
      return '<cycle>';
    }
    visited.add(identity);

    final result = <String, Object?>{};
    value.forEach((key, dynamic entryValue) {
      result[key.toString()] =
          _normalize(entryValue, depth + 1, maxDepth, visited);
    });
    visited.remove(identity);
    return result;
  }

  if (value is Iterable) {
    final identity = identityHashCode(value);
    if (visited.contains(identity)) {
      return '<cycle>';
    }
    visited.add(identity);
    final list = value
        .map((element) => _normalize(element, depth + 1, maxDepth, visited))
        .toList(growable: false);
    visited.remove(identity);
    return list;
  }

  if (value is Set) {
    return _normalize(value.toList(growable: false), depth, maxDepth, visited);
  }

  try {
    final encoded = jsonEncode(value);
    final decoded = jsonDecode(encoded);
    return decoded;
  } catch (_) {
    return null;
  }
}

void _diffRecursive(
  Object? previous,
  Object? current,
  List<Object> path,
  List<StateDiffEntry> results,
  int maxEntries,
) {
  if (results.length >= maxEntries) {
    return;
  }

  if (_deepEquals(previous, current)) {
    return;
  }

  if (previous == null) {
    results.add(StateDiffEntry(
      path: List<Object>.from(path),
      kind: StateDiffKind.added,
      after: current,
    ));
    return;
  }

  if (current == null) {
    results.add(StateDiffEntry(
      path: List<Object>.from(path),
      kind: StateDiffKind.removed,
      before: previous,
    ));
    return;
  }

  if (previous is Map && current is Map) {
    final keySet = <String>{
      ...previous.keys.map((key) => key.toString()),
      ...current.keys.map((key) => key.toString()),
    };
    for (final key in keySet) {
      if (results.length >= maxEntries) {
        return;
      }
      _diffRecursive(
        previous[key],
        current[key],
        [...path, key],
        results,
        maxEntries,
      );
    }
    return;
  }

  if (previous is List && current is List) {
    final length = previous.length > current.length
        ? previous.length
        : current.length;
    for (var index = 0; index < length; index += 1) {
      if (results.length >= maxEntries) {
        return;
      }
      final prevValue = index < previous.length ? previous[index] : null;
      final currValue = index < current.length ? current[index] : null;
      _diffRecursive(prevValue, currValue, [...path, index], results, maxEntries);
    }
    return;
  }

  results.add(StateDiffEntry(
    path: List<Object>.from(path),
    kind: StateDiffKind.changed,
    before: previous,
    after: current,
  ));
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key)) {
        return false;
      }
      if (!_deepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index += 1) {
      if (!_deepEquals(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
