import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/state_annotation.dart';
import '../model/state_attachment.dart';
import '../model/state_change_record.dart';
import '../model/state_diff_entry.dart';
import '../model/state_snapshot.dart';
import '../util/state_introspection.dart';
import 'state_inspector_sync.dart';
import 'state_timeline_analytics.dart';

class _NoPreviousValue {
  const _NoPreviousValue();
}

const _noPreviousValue = _NoPreviousValue();

/// Central coordinator that stores state change snapshots and notifies listeners.
class StateInspectorController extends ChangeNotifier {
  StateInspectorController({int maxRecords = 200})
      : assert(maxRecords > 0),
        _maxRecords = maxRecords,
        _recordStreamController =
            StreamController<StateChangeRecord>.broadcast(),
        _analyticsStreamController =
            StreamController<StateTimelineAnalytics>.broadcast();

  static final StateInspectorController _instance =
      StateInspectorController._internal();

  StateInspectorController._internal()
      : _maxRecords = 200,
        _recordStreamController =
            StreamController<StateChangeRecord>.broadcast(),
        _analyticsStreamController =
            StreamController<StateTimelineAnalytics>.broadcast();

  /// Accessor for a shared singleton controller when consumers do not wish to
  /// manage their own instance.
  static StateInspectorController get instance => _instance;

  final List<StateChangeRecord> _records = <StateChangeRecord>[];
  final int _maxRecords;
  int _sequence = 0;
  bool _panelVisible = false;
  bool _isPaused = false;
  final Set<int> _pinned = <int>{};
  final StreamController<StateChangeRecord> _recordStreamController;
  final StreamController<StateTimelineAnalytics> _analyticsStreamController;
  final List<StateInspectorSyncDelegate> _syncDelegates =
      <StateInspectorSyncDelegate>[];
  Set<String> _tagRegistry = <String>{};
  StateTimelineAnalytics _analytics = StateTimelineAnalytics.empty();

  /// Exposes the recorded state changes as an unmodifiable view.
  UnmodifiableListView<StateChangeRecord> get records =>
      UnmodifiableListView<StateChangeRecord>(_records);

  /// Stream that emits each new record as it is captured (for live tooling).
  Stream<StateChangeRecord> get recordStream => _recordStreamController.stream;

  /// Stream that emits analytics snapshots whenever the timeline changes.
  Stream<StateTimelineAnalytics> get analyticsStream =>
      _analyticsStreamController.stream;

  /// Returns whether the overlay panel is currently visible.
  bool get panelVisible => _panelVisible;

  /// Whether the controller is currently skipping capture events.
  bool get isPaused => _isPaused;

  /// IDs of pinned records.
  Set<int> get pinnedRecords => Set.unmodifiable(_pinned);

  /// Aggregate analytics derived from the current timeline.
  StateTimelineAnalytics get analytics => _analytics;

  /// All tags referenced by records or annotations.
  Set<String> get availableTags => Set.unmodifiable(_tagRegistry);

  /// Registered sync delegates.
  List<StateInspectorSyncDelegate> get syncDelegates =>
      List.unmodifiable(_syncDelegates);

  /// Clear all recorded state changes.
  void clear() {
    if (_records.isEmpty) {
      return;
    }
    _records.clear();
    _pinned.clear();
    _sequence = 0;
    _refreshDerivedState();
    for (final delegate in _syncDelegates) {
      delegate.onRecordsCleared();
    }
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
    _refreshDerivedState();
    notifyListeners();
    _recordStreamController.add(record);
    for (final delegate in _syncDelegates) {
      delegate.onRecordAdded(record);
    }
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
    Iterable<String>? tags,
    Map<String, num>? metrics,
    Iterable<StateAnnotation>? annotations,
    Iterable<StateAttachment>? attachments,
  }) {
    if (_isPaused) {
      return;
    }
    final bool hasExplicitPrevious =
        !identical(previousState, _noPreviousValue);
    final StateSnapshot currentSnapshot = snapshot ?? buildSnapshot(state);
    final StateSnapshot? resolvedPreviousSnapshot = previousSnapshot ??
        (hasExplicitPrevious ? buildSnapshot(previousState) : null);
    final List<StateDiffEntry> resolvedDiffs =
        diffs ?? buildDiff(resolvedPreviousSnapshot, currentSnapshot);

    final int recordId = ++_sequence;
    final Iterable<StateAnnotation> normalizedAnnotations =
        annotations?.map((annotation) {
              if (annotation.recordId == recordId) {
                return annotation;
              }
              return annotation.copyWith(recordId: recordId);
            }) ??
            const <StateAnnotation>[];
    final Iterable<StateAttachment> normalizedAttachments =
        attachments?.map((attachment) {
              if (attachment.recordId == recordId) {
                return attachment;
              }
              return attachment.copyWith(recordId: recordId);
            }) ??
            const <StateAttachment>[];

    addRecord(
      StateChangeRecord(
        id: recordId,
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
        tags: tags ?? const <String>[],
        metrics: metrics ?? const <String, num>{},
        annotations: normalizedAnnotations,
        attachments: normalizedAttachments,
      ),
    );
  }

  /// Create JSON-serializable representations of the current timeline.
  List<Map<String, Object?>> exportRecords() =>
      _records.map((record) => record.toJson()).toList(growable: false);

  /// Serialize the collected records as JSON (pretty printed when desired).
  String exportAsJson({bool pretty = false}) {
    final encoder =
        pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
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
      'version': 2,
      if (label != null) 'label': label,
      'generatedAt': DateTime.now().toIso8601String(),
      'records': exportRecords(),
      if (pinnedIds.isNotEmpty) 'pinnedRecordIds': pinnedIds,
      'maxRecords': _maxRecords,
    };
  }

  /// Serialize the current session (with metadata) to JSON.
  String exportSessionJson({bool pretty = false, String? label}) {
    final encoder =
        pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(exportSession(label: label));
  }

  /// Export the timeline as a Markdown summary suitable for tickets.
  String exportAsMarkdown({int limit = 50}) {
    final buffer = StringBuffer()
      ..writeln('# State Timeline')
      ..writeln();
    final recent = _records.reversed.take(limit).toList().reversed;
    for (final record in recent) {
      buffer.writeln(
          '- **${record.timestamp.toIso8601String()}** · `${record.origin}` · `${record.kind.name}` — ${record.summary}');
      if (record.previousSummary != null) {
        buffer.writeln('  - Previous: ${record.previousSummary}');
      }
      if (record.diffs.isNotEmpty) {
        buffer.writeln(
            '  - Diff paths: ${record.diffs.map((d) => d.pathAsString).join(', ')}');
      }
      if (record.tags.isNotEmpty) {
        buffer.writeln('  - Tags: ${record.tags.join(', ')}');
      }
      if (record.annotations.isNotEmpty) {
        for (final annotation in record.annotations) {
          buffer.writeln(
              '  - Note (${annotation.severity.name}): ${annotation.message}');
        }
      }
    }
    return buffer.toString();
  }

  /// Export a lightweight CLI table (pipe separated) for logs.
  String exportAsCliTable({int limit = 100}) {
    final buffer = StringBuffer()
      ..writeln('timestamp|origin|kind|summary|tags');
    final recent = _records.reversed.take(limit).toList().reversed;
    for (final record in recent) {
      buffer.writeln(
          '${record.timestamp.toIso8601String()}|${record.origin}|${record.kind.name}|${record.summary}|${record.tags.join(',')}');
    }
    return buffer.toString();
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

    _sequence = _records.fold<int>(
        0, (currentMax, record) => math.max(currentMax, record.id));

    _refreshDerivedState();
    notifyListeners();

    for (final delegate in _syncDelegates) {
      delegate.onBulkImport(List<StateChangeRecord>.from(_records));
    }
  }

  /// Attach an annotation to a record and notify listeners.
  StateChangeRecord? addAnnotation(
    int recordId,
    StateAnnotation annotation,
  ) {
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index == -1) {
      return null;
    }
    final record = _records[index];
    final nextAnnotations = <StateAnnotation>[
      ...record.annotations.where((entry) => entry.id != annotation.id),
      annotation,
    ];
    final updated = record.copyWith(annotations: nextAnnotations);
    _records[index] = updated;
    _refreshDerivedState();
    notifyListeners();
    for (final delegate in _syncDelegates) {
      delegate.onRecordMutated(updated);
    }
    return updated;
  }

  /// Remove an annotation by id.
  bool removeAnnotation(int recordId, String annotationId) {
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index == -1) {
      return false;
    }
    final record = _records[index];
    final filtered =
        record.annotations.where((entry) => entry.id != annotationId).toList();
    if (filtered.length == record.annotations.length) {
      return false;
    }
    _records[index] = record.copyWith(annotations: filtered);
    _refreshDerivedState();
    notifyListeners();
    for (final delegate in _syncDelegates) {
      delegate.onRecordMutated(_records[index]);
    }
    return true;
  }

  /// Merge new tags into a record.
  StateChangeRecord? addTags(int recordId, Iterable<String> tags) {
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index == -1) {
      return null;
    }
    final record = _records[index];
    final merged = <String>{...record.tags, ...tags};
    final updated = record.copyWith(tags: merged);
    _records[index] = updated;
    _refreshDerivedState();
    notifyListeners();
    for (final delegate in _syncDelegates) {
      delegate.onRecordMutated(updated);
    }
    return updated;
  }

  /// Replace the tag list for a record.
  StateChangeRecord? setTags(int recordId, Iterable<String> tags) {
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index == -1) {
      return null;
    }
    final updated = _records[index].copyWith(tags: tags);
    _records[index] = updated;
    _refreshDerivedState();
    notifyListeners();
    for (final delegate in _syncDelegates) {
      delegate.onRecordMutated(updated);
    }
    return updated;
  }

  /// Attach rich-media artifact metadata to a record.
  StateChangeRecord? addAttachment(
    int recordId,
    StateAttachment attachment,
  ) {
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index == -1) {
      return null;
    }
    final record = _records[index];
    final merged = <StateAttachment>[
      ...record.attachments.where((entry) => entry.id != attachment.id),
      attachment,
    ];
    final updated = record.copyWith(attachments: merged);
    _records[index] = updated;
    _refreshDerivedState();
    notifyListeners();
    for (final delegate in _syncDelegates) {
      delegate.onRecordMutated(updated);
    }
    return updated;
  }

  /// Remove an attachment from a record using its id.
  bool removeAttachment(int recordId, String attachmentId) {
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index == -1) {
      return false;
    }
    final record = _records[index];
    final filtered =
        record.attachments.where((entry) => entry.id != attachmentId).toList();
    if (filtered.length == record.attachments.length) {
      return false;
    }
    _records[index] = record.copyWith(attachments: filtered);
    _refreshDerivedState();
    notifyListeners();
    for (final delegate in _syncDelegates) {
      delegate.onRecordMutated(_records[index]);
    }
    return true;
  }

  /// Merge metrics into a record.
  StateChangeRecord? mergeMetrics(
    int recordId,
    Map<String, num> metrics,
  ) {
    final index = _records.indexWhere((record) => record.id == recordId);
    if (index == -1) {
      return null;
    }
    final record = _records[index];
    final merged = Map<String, num>.from(record.metrics)..addAll(metrics);
    final updated = record.copyWith(metrics: merged);
    _records[index] = updated;
    _refreshDerivedState();
    notifyListeners();
    for (final delegate in _syncDelegates) {
      delegate.onRecordMutated(updated);
    }
    return updated;
  }

  /// Register a sync delegate that mirrors timeline changes remotely.
  void addSyncDelegate(StateInspectorSyncDelegate delegate) {
    _syncDelegates.add(delegate);
  }

  /// Remove a previously registered sync delegate.
  void removeSyncDelegate(StateInspectorSyncDelegate delegate) {
    _syncDelegates.remove(delegate);
  }

  @override
  void dispose() {
    _recordStreamController.close();
    _analyticsStreamController.close();
    super.dispose();
  }

  void _refreshDerivedState() {
    _analytics = StateTimelineAnalytics.fromRecords(_records);
    if (!_analyticsStreamController.isClosed) {
      _analyticsStreamController.add(_analytics);
    }
    final tags = <String>{};
    for (final record in _records) {
      tags.addAll(record.tags);
      for (final annotation in record.annotations) {
        tags.addAll(annotation.tags);
      }
    }
    _tagRegistry = tags;
  }
}
