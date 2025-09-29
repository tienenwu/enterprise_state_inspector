import 'dart:collection';

import '../model/state_change_record.dart';

class OriginTimelineStats {
  OriginTimelineStats({
    required this.origin,
    required this.count,
    required this.firstTimestamp,
    required this.lastTimestamp,
    required Map<StateEventKind, int> kindCounts,
    this.averageInterval,
    this.longestInterval,
    Duration? totalElapsed,
  })  : kindCounts = UnmodifiableMapView(kindCounts),
        totalElapsed = totalElapsed ??
            (lastTimestamp.isBefore(firstTimestamp)
                ? Duration.zero
                : lastTimestamp.difference(firstTimestamp));

  final String origin;
  final int count;
  final DateTime firstTimestamp;
  final DateTime lastTimestamp;
  final Map<StateEventKind, int> kindCounts;
  final Duration? averageInterval;
  final Duration? longestInterval;
  final Duration totalElapsed;
}

class StateTimelineAnalytics {
  StateTimelineAnalytics({
    required this.totalRecords,
    required Map<StateEventKind, int> kindCounts,
    required Map<String, OriginTimelineStats> originStats,
    this.averageGap,
    this.longestGap,
  })  : kindCounts = UnmodifiableMapView(kindCounts),
        originStats = UnmodifiableMapView(originStats);

  final int totalRecords;
  final Map<StateEventKind, int> kindCounts;
  final Map<String, OriginTimelineStats> originStats;
  final Duration? averageGap;
  final Duration? longestGap;

  bool get isEmpty => totalRecords == 0;

  List<OriginTimelineStats> topOriginsByCount([int limit = 5]) {
    final stats = originStats.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    if (stats.length > limit) {
      return stats.sublist(0, limit);
    }
    return stats;
  }

  List<OriginTimelineStats> slowestOrigins([int limit = 5]) {
    final stats = originStats.values
        .where((entry) => entry.longestInterval != null)
        .toList()
      ..sort((a, b) =>
          b.longestInterval!.compareTo(a.longestInterval ?? Duration.zero));
    if (stats.length > limit) {
      return stats.sublist(0, limit);
    }
    return stats;
  }

  static StateTimelineAnalytics empty() => StateTimelineAnalytics(
        totalRecords: 0,
        kindCounts: {
          for (final kind in StateEventKind.values) kind: 0,
        },
        originStats: const <String, OriginTimelineStats>{},
        averageGap: null,
        longestGap: null,
      );

  factory StateTimelineAnalytics.fromRecords(List<StateChangeRecord> records) {
    if (records.isEmpty) {
      return StateTimelineAnalytics.empty();
    }

    final sorted = List<StateChangeRecord>.from(records)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final Map<StateEventKind, int> kindCounts = {
      for (final kind in StateEventKind.values) kind: 0,
    };
    final Map<String, _OriginAccumulator> originAccumulators = {};

    DateTime? previousTimestamp;
    Duration totalGap = Duration.zero;
    Duration? longestGap;

    for (final record in sorted) {
      kindCounts.update(record.kind, (value) => value + 1, ifAbsent: () => 1);

      if (previousTimestamp != null) {
        final gap = record.timestamp.difference(previousTimestamp);
        if (!gap.isNegative) {
          totalGap += gap;
          if (longestGap == null || gap > longestGap) {
            longestGap = gap;
          }
        }
      }
      previousTimestamp = record.timestamp;

      final accumulator = originAccumulators.putIfAbsent(
        record.origin,
        () => _OriginAccumulator(firstTimestamp: record.timestamp),
      );
      accumulator.count++;
      accumulator.kindCounts.update(
        record.kind,
        (value) => value + 1,
        ifAbsent: () => 1,
      );

      if (accumulator.lastTimestamp != null) {
        final delta = record.timestamp.difference(accumulator.lastTimestamp!);
        if (!delta.isNegative) {
          accumulator.intervals.add(delta);
          if (accumulator.longestInterval == null ||
              delta > accumulator.longestInterval!) {
            accumulator.longestInterval = delta;
          }
        }
      }
      accumulator.lastTimestamp = record.timestamp;
    }

    final Map<String, OriginTimelineStats> originStats = {
      for (final entry in originAccumulators.entries)
        entry.key: entry.value.build(entry.key),
    };

    final gapCount = sorted.length - 1;
    final Duration? averageGap = gapCount > 0
        ? Duration(
            microseconds: totalGap.inMicroseconds ~/ gapCount,
          )
        : null;

    return StateTimelineAnalytics(
      totalRecords: sorted.length,
      kindCounts: kindCounts,
      originStats: originStats,
      averageGap: averageGap,
      longestGap: longestGap,
    );
  }
}

class _OriginAccumulator {
  _OriginAccumulator({required this.firstTimestamp})
      : kindCounts = <StateEventKind, int>{};

  final DateTime firstTimestamp;
  final Map<StateEventKind, int> kindCounts;
  DateTime? lastTimestamp;
  int count = 0;
  Duration? longestInterval;
  final List<Duration> intervals = <Duration>[];

  OriginTimelineStats build(String origin) {
    final Duration? averageInterval;
    if (intervals.isEmpty) {
      averageInterval = null;
    } else {
      final total = intervals.reduce((a, b) => a + b);
      averageInterval = Duration(
        microseconds: total.inMicroseconds ~/ intervals.length,
      );
    }
    final totalElapsed = lastTimestamp != null
        ? lastTimestamp!.difference(firstTimestamp)
        : Duration.zero;
    return OriginTimelineStats(
      origin: origin,
      count: count,
      firstTimestamp: firstTimestamp,
      lastTimestamp: lastTimestamp ?? firstTimestamp,
      kindCounts: kindCounts,
      averageInterval: averageInterval,
      longestInterval: longestInterval,
      totalElapsed: totalElapsed,
    );
  }
}
