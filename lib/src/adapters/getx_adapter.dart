import 'package:get/get.dart';

import '../controller/state_inspector_controller.dart';
import '../model/state_change_record.dart';
import '../util/value_formatter.dart';
import '../util/state_introspection.dart';

/// Helpers for wiring GetX reactivity into the enterprise state inspector.
class StateInspectorGetAdapter {
  const StateInspectorGetAdapter._();

  /// Observes a GetX [RxInterface] and forwards value changes into the inspector.
  ///
  /// Returns a [Worker] which should be disposed (via [Worker.dispose]) when
  /// the observation should stop (typically in `onClose`).
  static Worker observeRx<T>(
    RxInterface<T> rx, {
    required String origin,
    StateInspectorController? controller,
    String? runtimeTypeName,
    String Function(T value)? summaryBuilder,
  }) {
    final inspector = controller ?? StateInspectorController.instance;
    final runtime = runtimeTypeName ?? rx.runtimeType.toString();

    final initialValue = _readValue(rx);
    inspector.capture(
      origin: origin,
      kind: StateEventKind.add,
      summary: summaryBuilder?.call(initialValue) ?? describeValue(initialValue),
      state: initialValue,
      runtimeTypeName: runtime,
      snapshot: buildSnapshot(initialValue),
    );

    T previousValue = initialValue;

    return ever<T>(rx, (value) {
      inspector.capture(
        origin: origin,
        kind: StateEventKind.update,
        summary: summaryBuilder?.call(value) ?? describeValue(value),
        previousSummary:
            summaryBuilder?.call(previousValue) ?? describeValue(previousValue),
        state: value,
        previousState: previousValue,
        runtimeTypeName: runtime,
        snapshot: buildSnapshot(value),
        previousSnapshot: buildSnapshot(previousValue),
      );
      previousValue = value;
    });
  }

  /// Observes an [RxMap] and records granular diff updates.
  static Worker observeMap<K, V>(
    RxMap<K, V> map, {
    required String origin,
    StateInspectorController? controller,
  }) {
    return observeRx<Map<K, V>>(map, origin: origin, controller: controller);
  }

  /// Observes an [RxList] and records granular diff updates.
  static Worker observeList<T>(
    RxList<T> list, {
    required String origin,
    StateInspectorController? controller,
  }) {
    return observeRx<List<T>>(list, origin: origin, controller: controller);
  }

  /// Observes an [RxSet] and records granular diff updates.
  static Worker observeSet<T>(
    RxSet<T> set, {
    required String origin,
    StateInspectorController? controller,
  }) {
    return observeRx<Set<T>>(set, origin: origin, controller: controller);
  }
}

T _readValue<T>(RxInterface<T> rx) => (rx as dynamic).value as T;
