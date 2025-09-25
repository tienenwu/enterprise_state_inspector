import 'package:enterprise_state_inspector/enterprise_state_inspector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final inspector = StateInspectorController.instance;
  Bloc.observer = StateInspectorBlocObserver(controller: inspector);

  runApp(
    ProviderScope(
      observers: [StateInspectorRiverpodObserver(controller: inspector)],
      child: EnterpriseInspectorExample(controller: inspector),
    ),
  );
}

class EnterpriseInspectorExample extends StatelessWidget {
  const EnterpriseInspectorExample({super.key, required this.controller});

  final StateInspectorController controller;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => CounterBloc()),
      ],
      child: GetMaterialApp(
        title: 'Enterprise State Inspector',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        builder: (context, child) => Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (overlayContext) => StateInspectorOverlay(
                controller: controller,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        home: HomePage(controller: controller),
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.controller});

  final StateInspectorController controller;

  void _showImportDialog(BuildContext context) {
    final textController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import timeline JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: textController,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Paste a JSON session exported from the inspector',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              final json = textController.text.trim();
              if (json.isEmpty) {
                navigator.pop();
                return;
              }
              try {
                await controller.importSessionJson(json);
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Timeline imported.')),
                );
              } catch (error) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Import failed: $error')),
                );
              }
            },
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    final json = controller.exportAsJson(pretty: true);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Timeline export'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(json),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Get.isRegistered<GetCounterController>()) {
      Get.put(GetCounterController(inspector: controller));
    }

    final riverpodState = ref.watch(riverpodCounterProvider);
    final getController = Get.find<GetCounterController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enterprise State Inspector'),
        actions: [
          IconButton(
            tooltip: 'Import timeline JSON',
            onPressed: () => _showImportDialog(context),
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'Export timeline JSON',
            onPressed: () => _showExportDialog(context),
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Toggle inspector',
            onPressed: controller.togglePanel,
            icon: const Icon(Icons.analytics_outlined),
          ),
          IconButton(
            tooltip: 'Clear timeline',
            onPressed: controller.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Riverpod counter',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Value: ${riverpodState.value}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          'History: ${riverpodState.history.isEmpty ? '—' : riverpodState.history.join(', ')}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => ref
                            .read(riverpodCounterProvider.notifier)
                            .increment(),
                        icon: const Icon(Icons.add),
                        label: const Text('Increment'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => ref
                            .read(riverpodCounterProvider.notifier)
                            .decrement(),
                        icon: const Icon(Icons.remove),
                        label: const Text('Decrement'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => ref
                            .read(riverpodCounterProvider.notifier)
                            .reset(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bloc counter',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  BlocBuilder<CounterBloc, int>(
                    builder: (context, value) {
                      return Text(
                        'Value: $value',
                        style: Theme.of(context).textTheme.headlineMedium,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.read<CounterBloc>().add(CounterEvent.increment),
                        icon: const Icon(Icons.add),
                        label: const Text('Increment'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.read<CounterBloc>().add(CounterEvent.decrement),
                        icon: const Icon(Icons.remove),
                        label: const Text('Decrement'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.read<CounterBloc>().add(CounterEvent.reset),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _GetXCounterCard(controller: getController),
          const SizedBox(height: 16),
          const Text(
            'Use the actions above or the floating inspector toggle to open the overlay. Try searching, pinning events, pausing capture, filtering event kinds, or exporting/importing the timeline after interacting with the counters.',
          ),
        ],
      ),
    );
  }
}

class _GetXCounterCard extends StatelessWidget {
  const _GetXCounterCard({required this.controller});

  final GetCounterController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GetX counter',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Obx(() => Text(
                  'Value: ${controller.count.value}',
                  style: Theme.of(context).textTheme.headlineMedium,
                )),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Obx(() {
                  final items = controller.history;
                  final label = items.isEmpty ? '—' : items.join(', ');
                  return Chip(
                    label: Text(
                      'History: $label',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }),
                ElevatedButton.icon(
                  onPressed: controller.increment,
                  icon: const Icon(Icons.add),
                  label: const Text('Increment'),
                ),
                ElevatedButton.icon(
                  onPressed: controller.decrement,
                  icon: const Icon(Icons.remove),
                  label: const Text('Decrement'),
                ),
                ElevatedButton.icon(
                  onPressed: controller.reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GetCounterController extends GetxController {
  GetCounterController({required this.inspector});

  final StateInspectorController inspector;
  final RxInt count = 0.obs;
  final RxList<int> history = <int>[0].obs;

  late final Worker _countWorker;
  late final Worker _historyWorker;

  @override
  void onInit() {
    super.onInit();
    _countWorker = StateInspectorGetAdapter.observeRx<int>(
      count,
      origin: '${runtimeType.toString()}.count',
      controller: inspector,
      summaryBuilder: (value) => 'count=$value',
    );
    _historyWorker = StateInspectorGetAdapter.observeList<int>(
      history,
      origin: '${runtimeType.toString()}.history',
      controller: inspector,
    );
  }

  @override
  void onClose() {
    _countWorker.dispose();
    _historyWorker.dispose();
    super.onClose();
  }

  void increment() {
    count.value += 1;
    history.add(count.value);
    _trimHistory();
  }

  void decrement() {
    count.value -= 1;
    history.add(count.value);
    _trimHistory();
  }

  void reset() {
    count.value = 0;
    history.assignAll(const <int>[0]);
  }

  void _trimHistory() {
    if (history.length > 10) {
      history.removeAt(0);
    }
  }
}

final riverpodCounterProvider = StateNotifierProvider<CounterNotifier, CounterState>(
  (ref) => CounterNotifier(),
  name: 'riverpodCounter',
);

class CounterState {
  const CounterState({required this.value, required this.history});

  final int value;
  final List<int> history;

  CounterState copyWith({int? value, List<int>? history}) {
    return CounterState(
      value: value ?? this.value,
      history: history ?? this.history,
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'history': history,
      };
}

class CounterNotifier extends StateNotifier<CounterState> {
  CounterNotifier() : super(const CounterState(value: 0, history: <int>[]));

  void increment() {
    final nextValue = state.value + 1;
    final nextHistory = List<int>.from(state.history)..add(nextValue);
    if (nextHistory.length > 10) {
      nextHistory.removeAt(0);
    }
    state = state.copyWith(value: nextValue, history: nextHistory);
  }

  void decrement() {
    final nextValue = state.value - 1;
    final nextHistory = List<int>.from(state.history)..add(nextValue);
    if (nextHistory.length > 10) {
      nextHistory.removeAt(0);
    }
    state = state.copyWith(value: nextValue, history: nextHistory);
  }

  void reset() {
    state = const CounterState(value: 0, history: <int>[0]);
  }
}

enum CounterEvent { increment, decrement, reset }

class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc() : super(0) {
    on<CounterEvent>((event, emit) {
      switch (event) {
        case CounterEvent.increment:
          emit(state + 1);
          break;
        case CounterEvent.decrement:
          emit(state - 1);
          break;
        case CounterEvent.reset:
          emit(0);
          break;
      }
    });
  }
}
