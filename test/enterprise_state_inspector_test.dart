import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enterprise_state_inspector/enterprise_state_inspector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'support/inspector_test_utils.dart';

void main() {
  test('controller stores captured records up to maxRecords', () {
    final controller = StateInspectorController(maxRecords: 2);

    controller.capture(
      origin: 'test',
      kind: StateEventKind.update,
      summary: 'first',
    );
    controller.capture(
      origin: 'test',
      kind: StateEventKind.update,
      summary: 'second',
    );
    controller.capture(
      origin: 'test',
      kind: StateEventKind.update,
      summary: 'third',
    );

    expect(controller.records.length, 2);
    expect(controller.records.first.summary, 'second');
    expect(controller.records.last.summary, 'third');
  });

  test('riverpod observer records provider updates', () {
    final controller = StateInspectorController(maxRecords: 10);
    final observer = StateInspectorRiverpodObserver(controller: controller);
    final provider = StateProvider<int>((ref) => 0, name: 'counter');

    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    // Trigger update.
    container.read(provider.notifier).state = 1;

    final record = controller.records.last;
    expect(record.origin, 'counter');
    expect(record.summary.contains('1'), isTrue);
    expect(record.diffs, isNotEmpty);
  });

  test('bloc observer records transitions', () async {
    final controller = StateInspectorController(maxRecords: 10);
    final previousObserver = Bloc.observer;
    final observer = StateInspectorBlocObserver(controller: controller);
    Bloc.observer = observer;

    addTearDown(() {
      Bloc.observer = previousObserver;
    });

    final cubit = _CounterCubit();
    addTearDown(cubit.close);

    cubit.increment();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final cubitRecord = controller.records.lastWhere(
      (record) => record.origin == '_CounterCubit',
    );
    expect(cubitRecord.diffs, isNotEmpty);
  });

  test('pause prevents capture until resumed', () {
    final controller = StateInspectorController(maxRecords: 5);

    controller.pause();
    controller.capture(
      origin: 'paused',
      kind: StateEventKind.update,
      summary: 'ignored',
    );

    expect(controller.records, isEmpty);

    controller.resume();
    controller.capture(
      origin: 'active',
      kind: StateEventKind.update,
      summary: 'captured',
    );

    expect(controller.records.length, 1);
    expect(controller.records.first.summary, 'captured');
  });

  test('diff entries are generated for structured states', () {
    final controller = StateInspectorController(maxRecords: 5);

    controller.capture(
      origin: 'map',
      kind: StateEventKind.add,
      summary: 'first',
      state: {'value': 1},
    );

    controller.capture(
      origin: 'map',
      kind: StateEventKind.update,
      summary: 'second',
      previousSummary: 'first',
      state: {'value': 2},
      previousState: {'value': 1},
    );

    final record = controller.records.last;
    expect(record.diffs, isNotEmpty);
    final diff = record.diffs.first;
    expect(diff.kind, StateDiffKind.changed);
    expect(diff.pathAsString, anyOf('<root>', 'value'));
  });

  test('GetX adapter observes rx changes', () async {
    final controller = StateInspectorController(maxRecords: 5);
    final rx = 0.obs;

    final worker = StateInspectorGetAdapter.observeRx<int>(
      rx,
      origin: 'getx.counter',
      controller: controller,
    );

    rx.value = 1;
    rx.value = 2;

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.records.length, greaterThanOrEqualTo(3));
    final latest = controller.records.last;
    expect(latest.origin, 'getx.counter');
    expect(latest.diffs, isNotEmpty);

    worker.dispose();
  });

  test('pinning toggles record state', () {
    final controller = StateInspectorController(maxRecords: 5);
    controller.capture(
      origin: 'sample',
      kind: StateEventKind.add,
      summary: 'created',
    );

    final recordId = controller.records.first.id;
    expect(controller.isPinned(recordId), isFalse);
    controller.togglePin(recordId);
    expect(controller.isPinned(recordId), isTrue);
    controller.togglePin(recordId);
    expect(controller.isPinned(recordId), isFalse);
  });

  test('session export and import preserves pinned records', () async {
    final controller = StateInspectorController(maxRecords: 5);
    controller.capture(
      origin: 'session',
      kind: StateEventKind.add,
      summary: 'created',
      state: {'value': 1},
    );
    controller.pinRecord(controller.records.first.id);

    final json = controller.exportSessionJson(pretty: true, label: 'demo');

    final restored = StateInspectorController(maxRecords: 5);
    await restored.importSessionJson(json);

    expect(restored.records.length, 1);
    expect(restored.isPinned(restored.records.first.id), isTrue);
  });

  test('exportAsJson returns serialized timeline', () {
    final controller = StateInspectorController(maxRecords: 5);
    controller.capture(
      origin: 'test',
      kind: StateEventKind.add,
      summary: 'created',
    );

    final jsonString = controller.exportAsJson(pretty: true);
    final decoded = jsonDecode(jsonString) as List<dynamic>;
    expect(decoded, isNotEmpty);
    expect((decoded.first as Map<String, dynamic>)['origin'], 'test');
  });

  test('value listenable adapter forwards updates', () async {
    final controller = StateInspectorController(maxRecords: 10);
    final notifier = ValueNotifier<int>(0);

    final handle = StateInspectorAdapters.observeValueListenable<int>(
      notifier,
      origin: 'demo.notifier',
      controller: controller,
      summaryBuilder: (value) => 'count=$value',
      tags: const ['adapter-test'],
    );

    notifier.value = 1;
    notifier.value = 2;

    await Future<void>.delayed(const Duration(milliseconds: 5));

    final matching =
        controller.records.where((record) => record.origin == 'demo.notifier');
    expect(matching.length, greaterThanOrEqualTo(3));
    expect(controller.availableTags.contains('adapter-test'), isTrue);

    handle.dispose();
    notifier.dispose();
  });

  test('stream adapter captures events', () async {
    final controller = StateInspectorController(maxRecords: 10);
    final stream = Stream<int>.fromIterable(<int>[1, 2, 3]);

    final handle = StateInspectorAdapters.observeStream<int>(
      stream,
      origin: 'stream.demo',
      controller: controller,
      summaryBuilder: (value) => 'value=$value',
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      controller.records.any((record) => record.origin == 'stream.demo'),
      isTrue,
    );

    handle.dispose();
    controller.dispose();
  });

  test('adapter registry installs custom adapter', () async {
    StateInspectorAdapterRegistry.reset();
    final controller = StateInspectorController(maxRecords: 10);
    final streamController = StreamController<int>();

    StateInspectorAdapterRegistry.register<Stream<int>>(({
      required Stream<int> target,
      required String origin,
      StateInspectorController? controller,
      Map<String, Object?>? extras,
    }) {
      return StateInspectorAdapters.observeStream<int>(
        target,
        origin: origin,
        controller: controller,
        tags: const ['registry'],
      );
    }, description: 'int-stream');

    final handle = StateInspectorAdapterRegistry.install(
      target: streamController.stream,
      origin: 'registry.demo',
      controller: controller,
    );

    streamController
      ..add(42)
      ..add(5);
    await streamController.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(handle, isNotNull);
    expect(
      controller.records.any((record) =>
          record.origin == 'registry.demo' && record.tags.contains('registry')),
      isTrue,
    );

    handle?.dispose();
    StateInspectorAdapterRegistry.reset();
    controller.dispose();
  });

  test('analytics aggregates timeline insights', () {
    final base = DateTime(2024, 01, 01, 12, 0, 0);
    final records = <StateChangeRecord>[
      StateChangeRecord(
        id: 1,
        origin: 'bloc',
        kind: StateEventKind.update,
        timestamp: base,
        summary: 'bloc->1',
      ),
      StateChangeRecord(
        id: 2,
        origin: 'bloc',
        kind: StateEventKind.update,
        timestamp: base.add(const Duration(milliseconds: 200)),
        summary: 'bloc->2',
      ),
      StateChangeRecord(
        id: 3,
        origin: 'riverpod',
        kind: StateEventKind.add,
        timestamp: base.add(const Duration(seconds: 1)),
        summary: 'riverpod init',
      ),
    ];

    final analytics = StateTimelineAnalytics.fromRecords(records);
    expect(analytics.totalRecords, 3);
    expect(analytics.topOriginsByCount().first.origin, 'bloc');
    expect(analytics.kindCounts[StateEventKind.update], 2);
    expect(analytics.longestGap, isNotNull);
    expect(analytics.originStats['bloc']!.count, 2);
  });

  test('sync delegate mirrors timeline events', () async {
    final controller = StateInspectorController(maxRecords: 5);
    final stream = StreamController<Map<String, Object?>>();
    final delegate = StreamSyncDelegate(stream.sink);
    controller.addSyncDelegate(delegate);

    final events = <Map<String, Object?>>[];
    stream.stream.listen(events.add);

    controller.capture(
      origin: 'sync',
      kind: StateEventKind.add,
      summary: 'created',
    );
    controller.clear();

    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(events, isNotEmpty);
    expect(events.first['type'], 'record');
    expect(events.any((event) => event['type'] == 'clear'), isTrue);

    controller.removeSyncDelegate(delegate);
    await stream.close();
  });

  test('websocket delegate streams events over ws', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final messages = <Map<String, dynamic>>[];

    server.listen((HttpRequest request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((dynamic data) {
        if (data is String) {
          messages.add(jsonDecode(data) as Map<String, dynamic>);
        }
      });
    });

    final uri = Uri.parse('ws://127.0.0.1:${server.port}/timeline');
    final status = <String>[];
    final wsDelegate = await WebSocketSyncDelegate.connect(
      uri,
      onStatus: status.add,
    );

    final controller = StateInspectorController(maxRecords: 5);
    controller.addSyncDelegate(wsDelegate);

    controller.capture(
      origin: 'ws-demo',
      kind: StateEventKind.add,
      summary: 'created',
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(messages, isNotEmpty);
    expect(messages.first['type'], 'record');
    expect(status.any((entry) => entry.contains('connected')), isTrue);

    controller.removeSyncDelegate(wsDelegate);
    await wsDelegate.dispose();
    await server.close(force: true);
  });

  test('event bus broadcasts timeline events', () async {
    final controller = StateInspectorController(maxRecords: 5);
    final bus = StateTimelineEventBus(controller);
    final events = <TimelineBroadcastEvent>[];
    final sub = bus.events.listen(events.add);

    controller.capture(
      origin: 'bus-demo',
      kind: StateEventKind.add,
      summary: 'created',
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(events.any((event) => event.type == TimelineBroadcastType.record),
        isTrue);

    await sub.cancel();
    await bus.dispose();
    controller.dispose();
  });

  test('waitForTimeline resolves when predicate satisfied', () async {
    final controller = StateInspectorController(maxRecords: 5);

    final waitFuture = waitForTimeline(
      controller,
      (record) => record.origin == 'async',
      timeout: const Duration(milliseconds: 200),
    );

    controller.capture(
      origin: 'async',
      kind: StateEventKind.add,
      summary: 'created',
    );

    await waitFuture;
    controller.dispose();
  });

  test('annotations contribute tags and metadata', () {
    final controller = StateInspectorController(maxRecords: 5);
    controller.capture(
      origin: 'annotated',
      kind: StateEventKind.add,
      summary: 'created',
    );
    final recordId = controller.records.first.id;

    controller.addAnnotation(
      recordId,
      StateAnnotation(
        recordId: recordId,
        message: 'Investigate',
        severity: StateAnnotationSeverity.error,
        tags: const ['urgent'],
      ),
    );

    controller.mergeMetrics(recordId, {'latencyMs': 120});

    final updated =
        controller.records.firstWhere((record) => record.id == recordId);
    expect(updated.annotations.length, 1);
    expect(updated.metrics['latencyMs'], 120);
    expect(controller.availableTags.contains('urgent'), isTrue);
  });
}

class _CounterCubit extends Cubit<int> {
  _CounterCubit() : super(0);

  void increment() => emit(state + 1);
}
