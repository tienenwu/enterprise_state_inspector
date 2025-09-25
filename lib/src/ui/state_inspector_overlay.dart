import 'package:flutter/material.dart';

import '../controller/state_inspector_controller.dart';
import '../model/state_change_record.dart';
import '../model/state_diff_entry.dart';
import '../util/value_formatter.dart';

/// Wraps application UI with an always-available inspector overlay panel.
class StateInspectorOverlay extends StatefulWidget {
  const StateInspectorOverlay({
    super.key,
    required this.child,
    this.controller,
    this.showToggleButton = true,
    this.toggleAlignment = Alignment.bottomRight,
    this.togglePadding = const EdgeInsets.all(16),
    this.panelWidth = 420,
    this.panelMaxHeight = 520,
    this.animationDuration = const Duration(milliseconds: 220),
  });

  /// The widget tree the overlay should wrap.
  final Widget child;

  /// Optional controller. When omitted the singleton instance is used.
  final StateInspectorController? controller;

  /// Whether to render the floating toggle button.
  final bool showToggleButton;

  /// Alignment for the toggle button relative to the stack.
  final Alignment toggleAlignment;

  /// Padding applied around the toggle button.
  final EdgeInsets togglePadding;

  /// Maximum width of the inspector panel.
  final double panelWidth;

  /// Maximum height of the inspector panel.
  final double panelMaxHeight;

  /// Duration used for fade/slide animations.
  final Duration animationDuration;

  @override
  State<StateInspectorOverlay> createState() => _StateInspectorOverlayState();
}

class _StateInspectorOverlayState extends State<StateInspectorOverlay> {
  late StateInspectorController _controller;
  StateChangeRecord? _selected;
  late Set<StateEventKind> _activeKinds;
  late TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? StateInspectorController.instance;
    _controller.addListener(_handleControllerChanged);
    _activeKinds = StateEventKind.values.toSet();
    _searchController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant StateInspectorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextController = widget.controller ?? StateInspectorController.instance;
    if (!identical(nextController, _controller)) {
      _controller.removeListener(_handleControllerChanged);
      _controller = nextController;
      _controller.addListener(_handleControllerChanged);
      _selected = null;
      _realignSelection();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(_realignSelection);
  }

  void _realignSelection() {
    final visible = _visibleTimeline();
    if (visible.isEmpty) {
      _selected = null;
      return;
    }
    final selectedId = _selected?.id;
    if (selectedId == null) {
      _selected = visible.last;
      return;
    }
    final matchIndex = visible.indexWhere((record) => record.id == selectedId);
    _selected = matchIndex == -1 ? visible.last : visible[matchIndex];
  }

  List<StateChangeRecord> _visibleTimeline() {
    final query = _searchQuery.trim().toLowerCase();
    final bool searchActive = query.isNotEmpty;
    final List<StateChangeRecord> pinned = <StateChangeRecord>[];
    final List<StateChangeRecord> unpinned = <StateChangeRecord>[];

    for (final record in _controller.records) {
      if (!_activeKinds.contains(record.kind)) {
        continue;
      }
      if (searchActive && !_matchesSearch(record, query)) {
        continue;
      }
      if (_controller.isPinned(record.id)) {
        pinned.add(record);
      } else {
        unpinned.add(record);
      }
    }

    return <StateChangeRecord>[...pinned, ...unpinned];
  }

  bool _matchesSearch(StateChangeRecord record, String query) {
    bool contains(String? source) =>
        source != null && source.toLowerCase().contains(query);

    if (contains(record.origin) ||
        contains(record.summary) ||
        contains(record.previousSummary) ||
        contains(record.runtimeTypeName) ||
        contains(record.snapshot.summary) ||
        contains(record.snapshot.prettyJson) ||
        contains(record.details.toString())) {
      return true;
    }

    for (final diff in record.diffs) {
      if (diff.pathAsString.toLowerCase().contains(query) ||
          (diff.before?.toString().toLowerCase().contains(query) ?? false) ||
          (diff.after?.toString().toLowerCase().contains(query) ?? false)) {
        return true;
      }
    }

    return false;
  }

  void _togglePanel() => _controller.togglePanel();

  void _toggleFilter(StateEventKind kind) {
    setState(() {
      final next = Set<StateEventKind>.from(_activeKinds);
      if (next.contains(kind)) {
        if (next.length == 1) {
          return;
        }
        next.remove(kind);
      } else {
        next.add(kind);
      }
      _activeKinds = next;
      _realignSelection();
    });
  }

  void _resetFilters() {
    setState(() {
      _activeKinds = StateEventKind.values.toSet();
      _realignSelection();
    });
  }

  void _handleSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _realignSelection();
    });
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty) {
      return;
    }
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _realignSelection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleRecords = _visibleTimeline();
    final totalCount = _controller.records.length;
    final bool panelVisible = _controller.panelVisible;
    final bool isPaused = _controller.isPaused;
    final bool filtersActive =
        _activeKinds.length != StateEventKind.values.length;
    final bool searchActive = _searchQuery.trim().isNotEmpty;
    final selectedPinned =
        _selected != null && _controller.isPinned(_selected!.id);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.showToggleButton)
          Align(
            alignment: widget.toggleAlignment,
            child: Padding(
              padding: widget.togglePadding,
              child: _InspectorToggleButton(
                isActive: panelVisible,
                onPressed: _togglePanel,
                recordCount: totalCount,
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: IgnorePointer(
              ignoring: !panelVisible,
              child: AnimatedOpacity(
                opacity: panelVisible ? 1 : 0,
                duration: widget.animationDuration,
                child: AnimatedSlide(
                  offset: panelVisible ? Offset.zero : const Offset(0, 0.2),
                  duration: widget.animationDuration,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widget.panelWidth,
                      maxHeight: widget.panelMaxHeight,
                    ),
                    child: _StateInspectorPanel(
                      records: visibleRecords,
                      selected: _selected,
                      onSelect: (record) {
                        setState(() {
                          _selected = record;
                        });
                      },
                      onClose: () => _controller.togglePanel(false),
                      onClear: _controller.clear,
                      onTogglePause: _controller.togglePause,
                      isPaused: isPaused,
                      activeKinds: _activeKinds,
                      filtersActive: filtersActive,
                      searchActive: searchActive,
                      onFilterToggle: _toggleFilter,
                      onResetFilters: _resetFilters,
                      pinnedIds: _controller.pinnedRecords,
                      onTogglePin: (record) => _controller.togglePin(record.id),
                      hasAnyRecords: totalCount > 0,
                      searchController: _searchController,
                      searchQuery: _searchQuery,
                      onSearchChanged: _handleSearchChanged,
                      onClearSearch: _clearSearch,
                      resultCount: visibleRecords.length,
                      selectedPinned: selectedPinned,
                      onToggleSelectedPin: _selected == null
                          ? null
                          : () => _controller.togglePin(_selected!.id),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InspectorToggleButton extends StatelessWidget {
  const _InspectorToggleButton({
    required this.isActive,
    required this.onPressed,
    required this.recordCount,
  });

  final bool isActive;
  final VoidCallback onPressed;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      onPressed: onPressed,
      tooltip: isActive ? 'Hide state inspector' : 'Show state inspector',
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.analytics_outlined),
          if (recordCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  recordCount > 99 ? '99+' : recordCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StateInspectorPanel extends StatelessWidget {
  const _StateInspectorPanel({
    required this.records,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.onClear,
    required this.onTogglePause,
    required this.isPaused,
    required this.activeKinds,
    required this.filtersActive,
    required this.searchActive,
    required this.onFilterToggle,
    required this.onResetFilters,
    required this.pinnedIds,
    required this.onTogglePin,
    required this.hasAnyRecords,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.resultCount,
    required this.selectedPinned,
    required this.onToggleSelectedPin,
  });

  final List<StateChangeRecord> records;
  final StateChangeRecord? selected;
  final ValueChanged<StateChangeRecord> onSelect;
  final VoidCallback onClose;
  final VoidCallback onClear;
  final VoidCallback onTogglePause;
  final bool isPaused;
  final Set<StateEventKind> activeKinds;
  final bool filtersActive;
  final bool searchActive;
  final ValueChanged<StateEventKind> onFilterToggle;
  final VoidCallback onResetFilters;
  final Set<int> pinnedIds;
  final ValueChanged<StateChangeRecord> onTogglePin;
  final bool hasAnyRecords;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final int resultCount;
  final bool selectedPinned;
  final VoidCallback? onToggleSelectedPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      color: surfaceColor.withOpacity(0.98),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(
              onClose: onClose,
              onClear: hasAnyRecords ? onClear : null,
              onTogglePause: onTogglePause,
              isPaused: isPaused,
            ),
            _SearchField(
              controller: searchController,
              onChanged: onSearchChanged,
              onClear: onClearSearch,
              query: searchQuery,
              resultCount: resultCount,
            ),
            _EventFilterRow(
              activeKinds: activeKinds,
              onToggle: onFilterToggle,
              onReset: onResetFilters,
            ),
            const Divider(height: 1),
            Expanded(
              child: records.isEmpty
                  ? _EmptyState(
                      filtersActive: filtersActive,
                      searchActive: searchActive,
                      searchQuery: searchQuery,
                      isPaused: isPaused,
                    )
                  : _TimelineList(
                      records: records,
                      selected: selected,
                      pinnedIds: pinnedIds,
                      onSelect: onSelect,
                      onTogglePin: onTogglePin,
                    ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _DetailSection(
                record: selected,
                isPinned: selectedPinned,
                onTogglePin: onToggleSelectedPin,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.onClose,
    this.onClear,
    required this.onTogglePause,
    required this.isPaused,
  });

  final VoidCallback onClose;
  final VoidCallback? onClear;
  final VoidCallback onTogglePause;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.analytics_outlined, size: 18),
          const SizedBox(width: 8),
          const Text(
            'State Inspector',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (isPaused) ...[
            const SizedBox(width: 8),
            _PausedIndicator(),
          ],
          const Spacer(),
          IconButton(
            tooltip: isPaused ? 'Resume capture' : 'Pause capture',
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
            onPressed: onTogglePause,
          ),
          if (onClear != null)
            IconButton(
              tooltip: 'Clear timeline',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: onClear,
            ),
          IconButton(
            tooltip: 'Close inspector',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.query,
    required this.resultCount,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String query;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          suffixIcon: hasQuery
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear search',
                  onPressed: onClear,
                )
              : null,
          labelText: 'Search timeline',
          helperText: hasQuery ? '$resultCount matches' : null,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _EventFilterRow extends StatelessWidget {
  const _EventFilterRow({
    required this.activeKinds,
    required this.onToggle,
    required this.onReset,
  });

  final Set<StateEventKind> activeKinds;
  final ValueChanged<StateEventKind> onToggle;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Events:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          for (final kind in StateEventKind.values)
            FilterChip(
              label: Text(_labelFor(kind)),
              selected: activeKinds.contains(kind),
              onSelected: (_) => onToggle(kind),
            ),
          if (activeKinds.length < StateEventKind.values.length)
            TextButton(
              onPressed: onReset,
              child: const Text('Reset'),
            ),
        ],
      ),
    );
  }

  String _labelFor(StateEventKind kind) {
    switch (kind) {
      case StateEventKind.update:
        return 'Update';
      case StateEventKind.transition:
        return 'Transition';
      case StateEventKind.add:
        return 'Create';
      case StateEventKind.dispose:
        return 'Dispose';
      case StateEventKind.error:
        return 'Error';
    }
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({
    required this.records,
    required this.selected,
    required this.pinnedIds,
    required this.onSelect,
    required this.onTogglePin,
  });

  final List<StateChangeRecord> records;
  final StateChangeRecord? selected;
  final Set<int> pinnedIds;
  final ValueChanged<StateChangeRecord> onSelect;
  final ValueChanged<StateChangeRecord> onTogglePin;

  Color _kindColor(StateEventKind kind, ThemeData theme) {
    switch (kind) {
      case StateEventKind.update:
        return theme.colorScheme.primary;
      case StateEventKind.transition:
        return theme.colorScheme.secondary;
      case StateEventKind.add:
        return Colors.green.shade600;
      case StateEventKind.dispose:
        return Colors.grey;
      case StateEventKind.error:
        return theme.colorScheme.error;
    }
  }

  IconData _iconFor(StateEventKind kind) {
    switch (kind) {
      case StateEventKind.update:
        return Icons.change_circle_outlined;
      case StateEventKind.transition:
        return Icons.alt_route;
      case StateEventKind.add:
        return Icons.add_circle_outline;
      case StateEventKind.dispose:
        return Icons.delete_outline;
      case StateEventKind.error:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: records.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 52),
      itemBuilder: (context, index) {
        final record = records[index];
        final isSelected = selected?.id == record.id;
        final color = _kindColor(record.kind, theme);
        final timestamp = _formatTimestamp(record.timestamp);
        final isPinned = pinnedIds.contains(record.id);

        return Material(
          color: isSelected ? color.withOpacity(0.08) : Colors.transparent,
          child: ListTile(
            dense: true,
            leading: Icon(_iconFor(record.kind), color: color, size: 20),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    record.origin,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isPinned)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.push_pin, size: 14),
                  ),
              ],
            ),
            subtitle: Text(
              record.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timestamp,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(width: 8),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18,
                  ),
                  tooltip: isPinned ? 'Unpin' : 'Pin',
                  onPressed: () => onTogglePin(record),
                ),
              ],
            ),
            onTap: () => onSelect(record),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.filtersActive,
    required this.searchActive,
    required this.searchQuery,
    required this.isPaused,
  });

  final bool filtersActive;
  final bool searchActive;
  final String searchQuery;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = searchQuery.trim();
    final message = searchActive
        ? 'No events match "$trimmedQuery".'
        : filtersActive
            ? 'No events match the current filters.'
            : isPaused
                ? 'Capture is paused. Resume to collect new events.'
                : 'State changes will appear here.';
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _PausedIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pause_circle_filled,
              size: 14, color: colorScheme.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            'Paused',
            style: TextStyle(
              color: colorScheme.onTertiaryContainer,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatefulWidget {
  const _DetailSection({
    required this.record,
    required this.isPinned,
    required this.onTogglePin,
  });

  final StateChangeRecord? record;
  final bool isPinned;
  final VoidCallback? onTogglePin;

  @override
  State<_DetailSection> createState() => _DetailSectionState();
}

class _DetailSectionState extends State<_DetailSection> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    if (record == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        alignment: Alignment.centerLeft,
        child: const Text(
          'Select a timeline event to inspect details.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Details',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                if (widget.onTogglePin != null)
                  TextButton.icon(
                    icon: Icon(widget.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined),
                    label: Text(widget.isPinned ? 'Unpin' : 'Pin'),
                    onPressed: widget.onTogglePin,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _DetailRow(label: 'Origin', value: record.origin),
            _DetailRow(label: 'Kind', value: record.kind.name),
            if (record.runtimeTypeName != null)
              _DetailRow(label: 'Type', value: record.runtimeTypeName!),
            if (record.previousSummary != null)
              _DetailRow(label: 'Prev', value: record.previousSummary!),
            _DetailRow(label: 'Summary', value: record.summary),
            if (record.details.isNotEmpty)
              _DetailRow(label: 'Details', value: record.details.toString()),
            _DetailRow(
              label: 'Timestamp',
              value: record.timestamp.toIso8601String(),
            ),
            if (record.diffs.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DiffSection(diffs: record.diffs),
            ],
            if (record.previousSnapshot?.prettyJson != null) ...[
              const SizedBox(height: 12),
              _JsonSection(
                title: 'Previous state',
                content: record.previousSnapshot!.prettyJson!,
              ),
            ],
            if (record.snapshot.prettyJson != null) ...[
              const SizedBox(height: 12),
              _JsonSection(
                title: 'Current state',
                content: record.snapshot.prettyJson!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.labelMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _JsonSection extends StatelessWidget {
  const _JsonSection({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 160),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiffSection extends StatelessWidget {
  const _DiffSection({required this.diffs});

  final List<StateDiffEntry> diffs;

  @override
  Widget build(BuildContext context) {
    final controller = ScrollController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Differences',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: Scrollbar(
            thumbVisibility: true,
            controller: controller,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final diff in diffs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DiffRow(entry: diff),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.entry});

  final StateDiffEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kindLabel = _diffKindLabel(entry.kind);
    final beforeText = describeValue(entry.before, maxChars: 120);
    final afterText = describeValue(entry.after, maxChars: 120);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.pathAsString} · $kindLabel',
          style: theme.textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        if (entry.kind == StateDiffKind.changed) ...[
          Text('from: $beforeText', style: theme.textTheme.bodySmall),
          Text('to:   $afterText', style: theme.textTheme.bodySmall),
        ] else if (entry.kind == StateDiffKind.added)
          Text('value: $afterText', style: theme.textTheme.bodySmall)
        else if (entry.kind == StateDiffKind.removed)
          Text('value: $beforeText', style: theme.textTheme.bodySmall),
      ],
    );
  }

  String _diffKindLabel(StateDiffKind kind) {
    switch (kind) {
      case StateDiffKind.added:
        return 'added';
      case StateDiffKind.removed:
        return 'removed';
      case StateDiffKind.changed:
        return 'changed';
    }
  }
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final time = local.toIso8601String();
  final separatorIndex = time.indexOf('T');
  if (separatorIndex == -1 || separatorIndex + 1 >= time.length) {
    return time;
  }
  final part = time.substring(separatorIndex + 1, separatorIndex + 9);
  return part;
}
