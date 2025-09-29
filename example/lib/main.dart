import 'dart:async';
import 'dart:math' as math;

import 'package:enterprise_state_inspector/enterprise_state_inspector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class EnterpriseInspectorExample extends StatefulWidget {
  const EnterpriseInspectorExample({super.key, required this.controller});

  final StateInspectorController controller;

  @override
  State<EnterpriseInspectorExample> createState() =>
      _EnterpriseInspectorExampleState();
}

class _EnterpriseInspectorExampleState
    extends State<EnterpriseInspectorExample> {
  late final StreamController<Map<String, Object?>> _timelineStream;
  late final StateInspectorSyncDelegate _syncDelegate;

  @override
  void initState() {
    super.initState();
    _timelineStream = StreamController<Map<String, Object?>>.broadcast();
    _syncDelegate = StreamSyncDelegate(_timelineStream.sink);
    widget.controller.addSyncDelegate(_syncDelegate);
  }

  @override
  void dispose() {
    widget.controller.removeSyncDelegate(_syncDelegate);
    _timelineStream.close();
    super.dispose();
  }

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
        builder: (context, child) => StateInspectorOverlay(
          controller: widget.controller,
          child: child ?? const SizedBox.shrink(),
        ),
        home: HomePage(
          controller: widget.controller,
          timelineStream: _timelineStream.stream,
        ),
      ),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.timelineStream,
  });

  final StateInspectorController controller;
  final Stream<Map<String, Object?>> timelineStream;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final ValueNotifier<double> _sliderValue;
  late final TextEditingController _emailController;
  late final CheckoutStore _checkoutStore;
  late final StateInspectorAdapterHandle _sliderAdapter;
  late final StateInspectorAdapterHandle _emailAdapter;
  late final StateInspectorAdapterHandle _checkoutAdapter;
  StreamSubscription<Map<String, Object?>>? _streamSubscription;
  int _streamEventCount = 0;
  String? _lastStreamEventType;
  WebSocketSyncDelegate? _webSocketDelegate;
  String _companionStatus = 'Not connected';

  final math.Random _random = math.Random();
  late final TextEditingController _companionUrlController;

  @override
  void initState() {
    super.initState();
    _sliderValue = ValueNotifier<double>(0.35);
    _emailController = TextEditingController(text: 'product@tienenwu.me');
    _checkoutStore = CheckoutStore();
    _companionUrlController =
        TextEditingController(text: 'ws://127.0.0.1:8787/timeline');

    _sliderAdapter = StateInspectorAdapters.observeValueListenable<double>(
      _sliderValue,
      origin: 'demo.sliderValue',
      controller: widget.controller,
      summaryBuilder: (value) => 'slider ${(value * 100).round()}%',
      tags: const ['demo', 'value-notifier'],
    );

    _emailAdapter =
        StateInspectorAdapters.observeValueListenable<TextEditingValue>(
      _emailController,
      origin: 'demo.contactEmail',
      controller: widget.controller,
      summaryBuilder: (value) => 'email=${value.text}',
      tags: const ['demo', 'form'],
    );

    _checkoutAdapter = StateInspectorAdapters.observeListenable(
      _checkoutStore,
      origin: 'checkout.store',
      controller: widget.controller,
      stateResolver: _checkoutStore.snapshot,
      summaryBuilder: (state) {
        final map = state as Map<String, Object?>?;
        final total = map?['total'] as num? ?? 0;
        final count = map?['itemsCount'] as int? ?? 0;
        return 'cart: $count items, total=\$${total.toStringAsFixed(2)}';
      },
      tags: const ['demo', 'change-notifier'],
    );

    _streamSubscription = widget.timelineStream.listen((event) {
      setState(() {
        _streamEventCount += 1;
        _lastStreamEventType = event['type'] as String? ?? 'unknown';
      });
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _sliderAdapter.dispose();
    _emailAdapter.dispose();
    _checkoutAdapter.dispose();
    if (_webSocketDelegate != null) {
      widget.controller.removeSyncDelegate(_webSocketDelegate!);
      _webSocketDelegate!.dispose();
    }
    _sliderValue.dispose();
    _emailController.dispose();
    _checkoutStore.dispose();
    _companionUrlController.dispose();
    super.dispose();
  }

  void _connectCompanion(BuildContext context) async {
    final url = _companionUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _companionStatus = 'Enter a WebSocket URL';
      });
      return;
    }
    setState(() {
      _companionStatus = 'Connecting…';
    });
    try {
      final delegate = await WebSocketSyncDelegate.connect(
        Uri.parse(url),
        onStatus: (status) {
          if (!mounted) {
            return;
          }
          setState(() {
            _companionStatus = status;
          });
        },
      );
      if (_webSocketDelegate != null) {
        widget.controller.removeSyncDelegate(_webSocketDelegate!);
        await _webSocketDelegate!.dispose();
      }
      _webSocketDelegate = delegate;
      widget.controller.addSyncDelegate(delegate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to companion at $url')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Companion connection failed: $error')),
        );
        setState(() {
          _companionStatus = 'Connection failed';
        });
      }
    }
  }

  void _addAnnotation(BuildContext context, StateAnnotationSeverity severity) {
    if (widget.controller.records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture a few events first.')),
      );
      return;
    }
    final record = widget.controller.records.last;
    final annotation = StateAnnotation(
      recordId: record.id,
      message: 'Investigate slider ${(_sliderValue.value * 100).round()}%',
      severity: severity,
      tags: {'demo', 'annotation'},
    );
    widget.controller.addAnnotation(record.id, annotation);
    widget.controller.addTags(record.id, {'demo'});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Annotation added to ${record.origin}.')),
    );
  }

  void _attachPlaceholder(BuildContext context) {
    if (widget.controller.records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture a few events first.')),
      );
      return;
    }
    final record = widget.controller.records.last;
    widget.controller.addAttachment(
      record.id,
      StateAttachment(
        recordId: record.id,
        uri:
            'file:///tmp/screenshot-${DateTime.now().millisecondsSinceEpoch}.png',
        description: 'Placeholder screenshot of the flow',
        type: StateAttachmentType.screenshot,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Attachment added to ${record.origin}.')),
    );
  }

  void _mergeSyntheticMetrics(BuildContext context) {
    if (widget.controller.records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture a few events first.')),
      );
      return;
    }
    final record = widget.controller.records.last;
    widget.controller.mergeMetrics(record.id, {
      'latencyMs': 50 + _random.nextInt(250),
      'count': (record.metrics['count'] ?? 0) + 1,
    });
    widget.controller.addTags(record.id, {'metrics'});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Synthetic metrics merged into ${record.origin}.')),
    );
  }

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
                await widget.controller.importSessionJson(json);
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
    final json = widget.controller.exportAsJson(pretty: true);
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

  void _showMarkdownExport(BuildContext context) {
    final markdown = widget.controller.exportAsMarkdown(limit: 20);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Markdown summary'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(markdown),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: markdown));
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<GetCounterController>()) {
      Get.put(GetCounterController(inspector: widget.controller));
    }

    final riverpodState = ref.watch(riverpodCounterProvider);
    final getController = Get.find<GetCounterController>();
    final analytics = widget.controller.analytics;

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
            onPressed: widget.controller.togglePanel,
            icon: const Icon(Icons.analytics_outlined),
          ),
          IconButton(
            tooltip: 'Clear timeline',
            onPressed: widget.controller.clear,
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
                        onPressed: () =>
                            ref.read(riverpodCounterProvider.notifier).reset(),
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
                        onPressed: () => context
                            .read<CounterBloc>()
                            .add(CounterEvent.increment),
                        icon: const Icon(Icons.add),
                        label: const Text('Increment'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context
                            .read<CounterBloc>()
                            .add(CounterEvent.decrement),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ValueListenable + form demo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<double>(
                    valueListenable: _sliderValue,
                    builder: (context, value, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Slider: ${(value * 100).round()}%'),
                          Slider(
                            value: value,
                            onChanged: (next) => _sliderValue.value = next,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Contact email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _checkoutStore,
            builder: (context, _) {
              final items = _checkoutStore.items;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ChangeNotifier checkout store',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                          'Items: ${items.isEmpty ? 'Empty' : '${items.length} item(s)'}'),
                      if (items.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final item in items)
                              Chip(
                                label: Text(
                                    '${item.label}  \$${item.price.toStringAsFixed(2)}'),
                              ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Total: \$${_checkoutStore.total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              _checkoutStore.addItem(
                                label: _checkoutStore.suggestLabel(),
                                price: 9 +
                                    _random.nextInt(30) +
                                    _random.nextDouble(),
                              );
                            },
                            icon: const Icon(Icons.shopping_cart_checkout),
                            label: const Text('Add random item'),
                          ),
                          TextButton(
                            onPressed: _checkoutStore.clear,
                            child: const Text('Clear cart'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Inspector extras',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _addAnnotation(
                            context, StateAnnotationSeverity.info),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Add info note'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _addAnnotation(
                          context,
                          StateAnnotationSeverity.warning,
                        ),
                        icon: const Icon(Icons.warning_amber_outlined),
                        label: const Text('Add warning note'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _attachPlaceholder(context),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Attach screenshot'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _mergeSyntheticMetrics(context),
                        icon: const Icon(Icons.calculate_outlined),
                        label: const Text('Merge metrics'),
                      ),
                      TextButton(
                        onPressed: () => _showMarkdownExport(context),
                        child: const Text('Markdown export'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _connectCompanion(context),
                        icon: const Icon(Icons.cast_connected),
                        label: const Text('Connect companion'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _companionUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Companion WebSocket URL',
                      hintText: 'ws://127.0.0.1:8787/timeline',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Companion status: $_companionStatus',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.cloud_sync_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final lastType = _lastStreamEventType;
                        final suffix =
                            lastType == null ? '' : ' (last: $lastType)';
                        return Text(
                          'Streaming $_streamEventCount updates via StreamSyncDelegate$suffix',
                        );
                      },
                    ),
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
                    'Live analytics snapshot',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Total records: ${analytics.totalRecords}'),
                  if (!analytics.isEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Top origins: ${analytics.topOriginsByCount(3).map((entry) => entry.origin).join(', ')}',
                    ),
                    if (analytics.longestGap != null)
                      Text(
                          'Longest gap: ${_formatDuration(analytics.longestGap!)}'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Interact with the counters, slider, form, and checkout store, then open the overlay using the analytics FAB. Try regex search, multi-tag filtering, annotation composer, and session exports to see the enriched tooling.',
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

final riverpodCounterProvider =
    StateNotifierProvider<CounterNotifier, CounterState>(
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
}

class CounterNotifier extends StateNotifier<CounterState> {
  CounterNotifier() : super(const CounterState(value: 0, history: <int>[0]));

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

class CheckoutStore extends ChangeNotifier {
  final List<CartItem> _items = <CartItem>[];

  List<CartItem> get items => List.unmodifiable(_items);

  double get total => _items.fold(0, (value, item) => value + item.price);

  void addItem({required String label, required double price}) {
    _items.add(CartItem(label, price));
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  String suggestLabel() {
    const options = <String>[
      'Seat Upgrade',
      'Premium Support',
      'Add-on API',
      'Analytics'
    ];
    return options[math.Random().nextInt(options.length)];
  }

  Map<String, Object?> snapshot() => {
        'total': total,
        'itemsCount': _items.length,
        'items': [
          for (final item in _items)
            {
              'label': item.label,
              'price': item.price,
            }
        ],
      };
}

class CartItem {
  const CartItem(this.label, this.price);

  final String label;
  final double price;
}

String _formatDuration(Duration duration) {
  if (duration.inMilliseconds < 1000) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inSeconds < 60) {
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  if (minutes < 60) {
    return '${minutes}m ${seconds}s';
  }
  final hours = duration.inHours;
  final remMinutes = minutes % 60;
  return '${hours}h ${remMinutes}m';
}
