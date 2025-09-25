import 'package:flutter_bloc/flutter_bloc.dart';

import '../controller/state_inspector_controller.dart';
import '../model/state_change_record.dart';
import '../util/value_formatter.dart';

/// Bloc observer that forwards lifecycle events into the inspector timeline.
class StateInspectorBlocObserver extends BlocObserver {
  StateInspectorBlocObserver({StateInspectorController? controller})
      : _controller = controller ?? StateInspectorController.instance;

  final StateInspectorController _controller;

  String _label(BlocBase<dynamic> bloc) => bloc.runtimeType.toString();

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    _controller.capture(
      origin: _label(bloc),
      kind: StateEventKind.add,
      summary: 'created with ${describeValue(bloc.state)}',
      runtimeTypeName: bloc.runtimeType.toString(),
      state: bloc.state,
    );
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    _controller.capture(
      origin: _label(bloc),
      kind: StateEventKind.update,
      summary: describeValue(change.nextState),
      previousSummary: describeValue(change.currentState),
      runtimeTypeName: bloc.runtimeType.toString(),
      state: change.nextState,
      previousState: change.currentState,
    );
  }

  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    super.onTransition(bloc, transition);
    _controller.capture(
      origin: _label(bloc),
      kind: StateEventKind.transition,
      summary: '${transition.event.runtimeType}: ${describeValue(transition.nextState)}',
      previousSummary: describeValue(transition.currentState),
      runtimeTypeName: bloc.runtimeType.toString(),
      state: transition.nextState,
      previousState: transition.currentState,
      details: {
        'event': transition.event.toString(),
      },
    );
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    _controller.capture(
      origin: _label(bloc),
      kind: StateEventKind.error,
      summary: describeError(error, stackTrace),
      runtimeTypeName: bloc.runtimeType.toString(),
      state: bloc.state,
      details: {
        'error': error.toString(),
      },
    );
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    _controller.capture(
      origin: _label(bloc),
      kind: StateEventKind.dispose,
      summary: 'closed',
      runtimeTypeName: bloc.runtimeType.toString(),
    );
  }
}
