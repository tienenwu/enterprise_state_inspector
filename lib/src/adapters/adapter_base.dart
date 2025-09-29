import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controller/state_inspector_controller.dart';
import '../model/state_change_record.dart';
import '../util/state_introspection.dart';
import '../util/value_formatter.dart';

typedef _DisposeCallback = void Function();

typedef StateInspectorAdapterInstaller<T> = StateInspectorAdapterHandle
    Function({
  required T target,
  required String origin,
  StateInspectorController? controller,
  Map<String, Object?>? extras,
});

class _AdapterRegistration {
  _AdapterRegistration({
    required this.description,
    required this.canInstall,
    required this.install,
  });

  final String description;
  final bool Function(Object target) canInstall;
  final StateInspectorAdapterHandle Function(
    Object target,
    String origin,
    StateInspectorController? controller,
    Map<String, Object?>? extras,
  ) install;
}

/// Registry that allows packages to publish custom adapters without touching
/// the core library. Third-party state managers can register an installer and
/// later invoke it through [install].
class StateInspectorAdapterRegistry {
  StateInspectorAdapterRegistry._();

  static final List<_AdapterRegistration> _registrations =
      <_AdapterRegistration>[];

  /// Registers a new adapter installer for the type [T].
  static void register<T>(
    StateInspectorAdapterInstaller<T> installer, {
    String? description,
  }) {
    _registrations.add(
      _AdapterRegistration(
        description: description ?? T.toString(),
        canInstall: (target) => target is T,
        install: (target, origin, controller, extras) => installer(
          target: target as T,
          origin: origin,
          controller: controller,
          extras: extras,
        ),
      ),
    );
  }

  /// Removes all installers matching [description]. Mainly intended for tests.
  static void unregisterWhere(bool Function(String description) predicate) {
    _registrations.removeWhere((entry) => predicate(entry.description));
  }

  /// Clears the registry – exposed for testing scenarios.
  @visibleForTesting
  static void reset() => _registrations.clear();

  /// Attempts to install an adapter for [target] using the first matching
  /// registration. Returns `null` when no installer handles the target.
  static StateInspectorAdapterHandle? install({
    required Object target,
    required String origin,
    StateInspectorController? controller,
    Map<String, Object?>? extras,
  }) {
    for (final registration in _registrations) {
      if (registration.canInstall(target)) {
        return registration.install(target, origin, controller, extras);
      }
    }
    return null;
  }

  /// Human readable descriptions of all registered installers.
  static List<String> get registrations =>
      _registrations.map((entry) => entry.description).toList(growable: false);
}

/// Lightweight handle that disposes the adapter wiring when no longer needed.
class StateInspectorAdapterHandle {
  StateInspectorAdapterHandle(this._dispose);

  final _DisposeCallback _dispose;

  void dispose() => _dispose();
}

/// Shared helper utilities for writing custom adapters against popular state managers.
class StateInspectorAdapters {
  const StateInspectorAdapters._();

  /// Observe a [ValueListenable] (ValueNotifier, TextEditingController, etc.) and forward
  /// changes into the inspector.
  static StateInspectorAdapterHandle observeValueListenable<T>(
    ValueListenable<T> listenable, {
    required String origin,
    StateInspectorController? controller,
    String? runtimeTypeName,
    String Function(T value)? summaryBuilder,
    Iterable<String> tags = const <String>[],
  }) {
    final inspector = controller ?? StateInspectorController.instance;
    final runtime = runtimeTypeName ?? listenable.runtimeType.toString();

    final T initialValue = listenable.value;
    inspector.capture(
      origin: origin,
      kind: StateEventKind.add,
      summary:
          summaryBuilder?.call(initialValue) ?? describeValue(initialValue),
      state: initialValue,
      runtimeTypeName: runtime,
      snapshot: buildSnapshot(initialValue),
      tags: tags,
    );

    T previousValue = initialValue;

    void listener() {
      final value = listenable.value;
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
        tags: tags,
      );
      previousValue = value;
    }

    listenable.addListener(listener);
    return StateInspectorAdapterHandle(() {
      listenable.removeListener(listener);
    });
  }

  /// Observe any [Listenable] and provide custom state snapshots through
  /// [stateResolver]. Useful for ChangeNotifier, MobX store, or Redux store proxies.
  static StateInspectorAdapterHandle observeListenable(
    Listenable listenable, {
    required String origin,
    required Object? Function() stateResolver,
    StateInspectorController? controller,
    String? runtimeTypeName,
    String Function(Object? value)? summaryBuilder,
    Iterable<String> tags = const <String>[],
  }) {
    final inspector = controller ?? StateInspectorController.instance;
    final runtime = runtimeTypeName ?? listenable.runtimeType.toString();

    Object? previousValue;

    void sync({required StateEventKind kind, Object? value}) {
      inspector.capture(
        origin: origin,
        kind: kind,
        summary: summaryBuilder?.call(value) ?? describeValue(value),
        previousSummary:
            summaryBuilder?.call(previousValue) ?? describeValue(previousValue),
        state: value,
        previousState: previousValue,
        runtimeTypeName: runtime,
        snapshot: buildSnapshot(value),
        previousSnapshot:
            previousValue != null ? buildSnapshot(previousValue) : null,
        tags: tags,
      );
      previousValue = value;
    }

    final initialValue = stateResolver();
    sync(kind: StateEventKind.add, value: initialValue);

    void listener() {
      sync(kind: StateEventKind.update, value: stateResolver());
    }

    listenable.addListener(listener);
    return StateInspectorAdapterHandle(() {
      listenable.removeListener(listener);
      inspector.capture(
        origin: origin,
        kind: StateEventKind.dispose,
        summary: 'disposed',
        runtimeTypeName: runtime,
        tags: tags,
      );
    });
  }

  /// Observes a [Stream] and records each value as a timeline update. Errors
  /// surface as `StateEventKind.error` events and completion is tracked with a
  /// dispose entry.
  static StateInspectorAdapterHandle observeStream<T>(
    Stream<T> stream, {
    required String origin,
    StateInspectorController? controller,
    String? runtimeTypeName,
    String Function(T value)? summaryBuilder,
    Iterable<String> tags = const <String>[],
    Map<String, Object?>? details,
  }) {
    final inspector = controller ?? StateInspectorController.instance;
    final runtime = runtimeTypeName ?? stream.runtimeType.toString();

    inspector.capture(
      origin: origin,
      kind: StateEventKind.add,
      summary: 'stream subscribed',
      runtimeTypeName: runtime,
      details: details,
      tags: tags,
    );

    final subscription = stream.listen(
      (value) {
        inspector.capture(
          origin: origin,
          kind: StateEventKind.update,
          summary: summaryBuilder?.call(value) ?? describeValue(value),
          runtimeTypeName: runtime,
          state: value,
          snapshot: buildSnapshot(value),
          tags: tags,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        inspector.capture(
          origin: origin,
          kind: StateEventKind.error,
          summary: describeError(error, stackTrace),
          runtimeTypeName: runtime,
          state: error,
          details: {
            'stackTrace': stackTrace.toString(),
            if (details != null) ...details,
          },
          tags: tags,
        );
      },
      onDone: () {
        inspector.capture(
          origin: origin,
          kind: StateEventKind.dispose,
          summary: 'stream closed',
          runtimeTypeName: runtime,
          tags: tags,
        );
      },
    );

    return StateInspectorAdapterHandle(() {
      subscription.cancel();
    });
  }

  /// Convenience wrapper around [observeListenable] for `ChangeNotifier`
  /// implementations where the state can be projected via [extractState].
  static StateInspectorAdapterHandle
      observeNotifier<T extends ChangeNotifier, R>(
    T notifier, {
    required String origin,
    required R Function(T notifier) extractState,
    StateInspectorController? controller,
    String? runtimeTypeName,
    String Function(R value)? summaryBuilder,
    Iterable<String> tags = const <String>[],
  }) {
    return observeListenable(
      notifier,
      origin: origin,
      controller: controller,
      runtimeTypeName: runtimeTypeName ?? notifier.runtimeType.toString(),
      stateResolver: () => extractState(notifier),
      summaryBuilder:
          summaryBuilder == null ? null : (value) => summaryBuilder(value as R),
      tags: tags,
    );
  }
}
