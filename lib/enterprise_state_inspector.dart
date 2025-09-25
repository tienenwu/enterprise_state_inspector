library enterprise_state_inspector;

/// Enterprise-grade state inspection utilities for Flutter applications.
///
/// This package collects state changes from popular state-management
/// solutions such as Riverpod and Bloc, and renders an interactive overlay to
/// inspect them at runtime.
export 'src/adapters/bloc_adapter.dart';
export 'src/adapters/riverpod_adapter.dart';
export 'src/adapters/getx_adapter.dart';
export 'src/controller/state_inspector_controller.dart';
export 'src/model/state_change_record.dart';
export 'src/model/state_diff_entry.dart';
export 'src/model/state_snapshot.dart';
export 'src/ui/state_inspector_overlay.dart';
