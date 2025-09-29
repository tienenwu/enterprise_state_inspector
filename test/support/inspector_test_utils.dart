import 'dart:async';

import 'package:enterprise_state_inspector/enterprise_state_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Future<T> runWithInspectorCapture<T>(
  FutureOr<T> Function(StateInspectorController controller) body, {
  int maxRecords = 200,
}) async {
  final controller = StateInspectorController(maxRecords: maxRecords);
  try {
    return await body(controller);
  } finally {
    controller.dispose();
  }
}

void expectTimelineContains(
  StateInspectorController controller,
  bool Function(StateChangeRecord record) predicate, {
  String? reason,
}) {
  final match = controller.records.any(predicate);
  expect(match, isTrue, reason: reason ?? 'Expected timeline to contain match');
}

Future<void> waitForTimeline(
  StateInspectorController controller,
  bool Function(StateChangeRecord record) predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (controller.records.any(predicate)) {
    return;
  }

  final completer = Completer<void>();
  late final StreamSubscription<StateChangeRecord> subscription;
  subscription = controller.recordStream.listen((record) {
    if (predicate(record)) {
      if (!completer.isCompleted) {
        completer.complete();
      }
      subscription.cancel();
    }
  });

  final timer = Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException('Timeline condition not met within $timeout'),
      );
      subscription.cancel();
    }
  });

  try {
    await completer.future;
  } finally {
    timer.cancel();
    await subscription.cancel();
  }
}
