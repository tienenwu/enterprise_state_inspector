import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/state_change_record.dart';
import '../model/state_diff_entry.dart';
import '../model/state_snapshot.dart';
import '../util/state_introspection.dart';

class _NoPreviousValue {
  const _NoPreviousValue();
}

const _noPreviousValue = _NoPreviousValue();

/// Central coordinator that stores state change snapshots and notifies listeners.
class StateInspectorController extends ChangeNotifier {
  StateInspectorController({int maxRecords = 200})
      : assert(maxRecords > 0),
        _maxRecords = maxRecords;

  static final StateInspectorController _instance =
      StateInspectorController._internal();

  StateInspectorController._internal() : _maxRecords = 200;

  /// Accessor for a shared singleton controller when consumers do not wish to
  /// manage their own instance.
  static StateInspectorController get instance => _instance;

  final List<StateChangeRecord> _records = <StateChangeRecord>[];
  final int _maxRecords;
  int _sequence = 0;
  bool _panelVisible = false;
  bool _isPaused = false;
  final Set<int> _pinned = <int>{};

  /// Exposes the recorded state changes as an unmodifiable view.
  UnmodifiableListView<StateChangeRecord> get records =>
      UnmodifiableListView<StateChangeRecord>(_records);

  /// Returns whether the overlay panel is currently visible.
  bool get panelVisible => _panelVisible;

  /// Whether the controller is currently skipping capture events.
  bool get isPaused => _isPaused;

  /// IDs of pinned records.
  Set<int> get pinnedRecords => Set.unmodifiable(_pinned);

  /// Clear all recorded state changes.
  void clear() {
    if (_records.isEmpty) {
      return;
    }
    _records.clear();
    _pinned.clear();
    notifyListeners();
  }

  /// Toggle the visibility of the overlay panel.
  void togglePanel([bool? value]) {
    final bool next = value ?? !_panelVisible;
    if (next == _panelVisible) {
      return;
    }
    _panelVisible = next;
    notifyListeners();
  }

  /// Toggle capture pause state.
  void togglePause([bool? value]) {
    final bool next = value ?? !_isPaused;
    if (next == _isPaused) {
      return;
    }
    _isPaused = next;
    notifyListeners();
  }

  /// Pause the controller, preventing additional timeline entries.
  void pause() => togglePause(true);

  /// Resume the controller, allowing new entries to be captured.
  void resume() => togglePause(false);

  /// Returns whether the record with [id] is pinned.
  bool isPinned(int id) => _pinned.contains(id);

  /// Pin a record, keeping it highlighted in the UI.
  void pinRecord(int id) {
    if (_pinned.add(id)) {
      notifyListeners();
    }
  }

  /// Remove a record from the pinned set.
  void unpinRecord(int id) {
    if (_pinned.remove(id)) {
      notifyListeners();
    }
  }

  /// Toggle a record's pinned status.
  void togglePin(int id) {
    if (_pinned.contains(id)) {
      _pinned.remove(id);
    } else {
      _pinned.add(id);
    }
    notifyListeners();
  }

  /// Adds a new state change record to the timeline.
  void addRecord(StateChangeRecord record) {
    if (_isPaused) {
      return;
    }
    _records.add(record);
    if (_records.length > _maxRecords) {
      final removed = _records.removeAt(0);
      _pinned.remove(removed.id);
    }
    notifyListeners();
  }

  /// Helper for creating and storing a record from primitive values.
  void capture({
    required String origin,
    required StateEventKind kind,
    required String summary,
    Object? state,
    Object? previousState = _noPreviousValue,
    String? previousSummary,
    String? runtimeTypeName,
    Map<String, Object?>? details,
    StateSnapshot? snapshot,
    StateSnapshot? previousSnapshot,
    List<StateDiffEntry>? diffs,
  }) {
    if (_isPaused) {
      return;
    }
    final bool hasExplicitPrevious = !identical(previousState, _noPreviousValue);
    final StateSnapshot currentSnapshot = snapshot ?? buildSnapshot(state);
    final StateSnapshot? resolvedPreviousSnapshot = previousSnapshot ??
        (hasExplicitPrevious ? buildSnapshot(previousState) : null);
    final List<StateDiffEntry> resolvedDiffs = diffs ??
        buildDiff(resolvedPreviousSnapshot, currentSnapshot);

    addRecord(
      StateChangeRecord(
        id: ++_sequence,
        origin: origin,
        kind: kind,
        timestamp: DateTime.now(),
        summary: summary,
        previousSummary: previousSummary,
        runtimeTypeName: runtimeTypeName,
        state: state,
        details: details ?? const <String, Object?>{},
        snapshot: currentSnapshot,
        previousSnapshot: resolvedPreviousSnapshot,
        diffs: resolvedDiffs,
      ),
    );
  }

  /// Create JSON-serializable representations of the current timeline.
  List<Map<String, Object?>> exportRecords() =>
      _records.map((record) => record.toJson()).toList(growable: false);

  /// Serialize the collected records as JSON (pretty printed when desired).
  String exportAsJson({bool pretty = false}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(exportRecords());
  }

  /// Export the current session with metadata and pinned records.
  Map<String, Object?> exportSession({String? label}) {
    final pinnedIds = <int>[];
    for (final record in _records) {
      if (_pinned.contains(record.id)) {
        pinnedIds.add(record.id);
      }
    }
    return {
      'version': 1,
      if (label != null) 'label': label,
      'generatedAt': DateTime.now().toIso8601String(),
      'records': exportRecords(),
      if (pinnedIds.isNotEmpty) 'pinnedRecordIds': pinnedIds,
      'maxRecords': _maxRecords,
    };
  }

  /// Serialize the current session (with metadata) to JSON.
  String exportSessionJson({bool pretty = false, String? label}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(exportSession(label: label));
  }

  /// Replace the current timeline with records from a JSON string.
  Future<void> importSessionJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, Object?>) {
      importSessionData(decoded);
    } else if (decoded is List) {
      // Legacy support: treat as plain records list.
      importSessionData({'records': decoded});
    }
  }

  /// Replace the current timeline with records from JSON-compatible data.
  void importSessionData(Map<String, Object?> data) {
    final rawRecords = data['records'];
    if (rawRecords is! List) {
      return;
    }

    final parsed = rawRecords
        .whereType<Map<String, Object?>>()
        .map(StateChangeRecord.fromJson)
        .toList();
    parsed.sort((a, b) => a.id.compareTo(b.id));

    List<StateChangeRecord> trimmed = parsed;
    if (parsed.length > _maxRecords) {
      trimmed = parsed.sublist(parsed.length - _maxRecords);
    }

    _records
      ..clear()
      ..addAll(trimmed);

    final pinnedIds = <int>{};
    final rawPinned = data['pinnedRecordIds'];
    if (rawPinned is List) {
      for (final entry in rawPinned) {
        if (entry is num) {
          final id = entry.toInt();
          if (_records.any((record) => record.id == id)) {
            pinnedIds.add(id);
          }
        }
      }
    }

    _pinned
      ..clear()
      ..addAll(pinnedIds);

    _sequence = _records.fold<int>(0,
        (currentMax, record) => math.max(currentMax, record.id));

    notifyListeners();
  }
}
