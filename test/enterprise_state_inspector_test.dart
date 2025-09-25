import 'dart:convert';

import 'package:enterprise_state_inspector/enterprise_state_inspector.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

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
}

class _CounterCubit extends Cubit<int> {
  _CounterCubit() : super(0);

  void increment() => emit(state + 1);
}
