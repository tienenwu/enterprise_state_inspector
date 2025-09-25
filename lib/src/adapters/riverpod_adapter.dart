import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controller/state_inspector_controller.dart';
import '../model/state_change_record.dart';
import '../util/value_formatter.dart';

/// Observer that bridges Riverpod provider updates into the inspector timeline.
class StateInspectorRiverpodObserver extends ProviderObserver {
  StateInspectorRiverpodObserver({StateInspectorController? controller})
      : _controller = controller ?? StateInspectorController.instance;

  final StateInspectorController _controller;

  String _providerLabel(ProviderBase provider) {
    final name = provider.name?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return provider.runtimeType.toString();
  }

  @override
  void didAddProvider(
    ProviderBase provider,
    Object? value,
    ProviderContainer container,
  ) {
    _controller.capture(
      origin: _providerLabel(provider),
      kind: StateEventKind.add,
      summary: 'created with ${describeValue(value)}',
      state: value,
      runtimeTypeName: provider.runtimeType.toString(),
    );
  }

  @override
  void didUpdateProvider(
    ProviderBase provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    _controller.capture(
      origin: _providerLabel(provider),
      kind: StateEventKind.update,
      summary: describeValue(newValue),
      previousSummary: describeValue(previousValue),
      state: newValue,
      previousState: previousValue,
      runtimeTypeName: provider.runtimeType.toString(),
    );
  }

  @override
  void didDisposeProvider(ProviderBase provider, ProviderContainer container) {
    _controller.capture(
      origin: _providerLabel(provider),
      kind: StateEventKind.dispose,
      summary: 'disposed',
      runtimeTypeName: provider.runtimeType.toString(),
    );
  }

  @override
  void providerDidFail(
    ProviderBase provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    _controller.capture(
      origin: _providerLabel(provider),
      kind: StateEventKind.error,
      summary: describeError(error, stackTrace),
      runtimeTypeName: provider.runtimeType.toString(),
      details: {
        'error': error.toString(),
      },
    );
  }
}
