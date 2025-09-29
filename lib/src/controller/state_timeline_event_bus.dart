import 'dart:async';

import '../model/state_change_record.dart';
import 'state_inspector_controller.dart';
import 'state_inspector_sync.dart';
import 'state_timeline_analytics.dart';

/// Enumeration describing the kinds of broadcast events the timeline hub emits.
enum TimelineBroadcastType {
  record,
  update,
  clear,
  bulkImport,
  analytics,
}

/// Payload wrapper exposed by [StateTimelineEventBus]. Consumers can easily
/// serialise the data or transform it into custom protocols.
class TimelineBroadcastEvent {
  const TimelineBroadcastEvent({
    required this.type,
    this.record,
    this.records,
    this.analytics,
  });

  final TimelineBroadcastType type;
  final StateChangeRecord? record;
  final List<StateChangeRecord>? records;
  final StateTimelineAnalytics? analytics;

  Map<String, Object?> toJson() {
    switch (type) {
      case TimelineBroadcastType.record:
      case TimelineBroadcastType.update:
        return {
          'type': type.name,
          'payload': record?.toJson(),
        };
      case TimelineBroadcastType.clear:
        return {'type': type.name};
      case TimelineBroadcastType.bulkImport:
        return {
          'type': type.name,
          'payload': records?.map((r) => r.toJson()).toList(),
        };
      case TimelineBroadcastType.analytics:
        return {
          'type': type.name,
          'payload': {
            'totalRecords': analytics?.totalRecords,
            'kindCounts': analytics?.kindCounts
                .map((key, value) => MapEntry(key.name, value)),
          },
        };
    }
  }
}

/// A hub that multiplexes inspector events to multiple listeners. It implements
/// [StateInspectorSyncDelegate], so it can be added to the controller alongside
/// WebSocket or stream delegates.
class StateTimelineEventBus extends StateInspectorSyncDelegate {
  StateTimelineEventBus(StateInspectorController controller)
      : _controller = controller {
    _controller.addSyncDelegate(this);
    _analyticsSubscription = controller.analyticsStream.listen((analytics) {
      _events.add(
        TimelineBroadcastEvent(
          type: TimelineBroadcastType.analytics,
          analytics: analytics,
        ),
      );
    });
  }

  final StateInspectorController _controller;
  final StreamController<TimelineBroadcastEvent> _events =
      StreamController<TimelineBroadcastEvent>.broadcast();
  StreamSubscription<StateTimelineAnalytics>? _analyticsSubscription;

  /// Stream of broadcast events (records, clears, analytics updates).
  Stream<TimelineBroadcastEvent> get events => _events.stream;

  @override
  void onRecordAdded(StateChangeRecord record) {
    _events.add(
      TimelineBroadcastEvent(
        type: TimelineBroadcastType.record,
        record: record,
      ),
    );
  }

  @override
  void onRecordMutated(StateChangeRecord record) {
    _events.add(
      TimelineBroadcastEvent(
        type: TimelineBroadcastType.update,
        record: record,
      ),
    );
  }

  @override
  void onRecordsCleared() {
    _events.add(
      const TimelineBroadcastEvent(type: TimelineBroadcastType.clear),
    );
  }

  @override
  void onBulkImport(List<StateChangeRecord> records) {
    _events.add(
      TimelineBroadcastEvent(
        type: TimelineBroadcastType.bulkImport,
        records: List<StateChangeRecord>.from(records),
      ),
    );
  }

  /// Releases resources and detaches the hub from the controller.
  Future<void> dispose() async {
    _controller.removeSyncDelegate(this);
    await _analyticsSubscription?.cancel();
    await _events.close();
  }
}
