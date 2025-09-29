import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controller/state_inspector_controller.dart';
import '../controller/state_timeline_analytics.dart';
import '../model/state_annotation.dart';
import '../model/state_attachment.dart';
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
  bool _useRegex = false;
  bool _caseSensitiveSearch = false;
  bool _filtersExpanded = false;
  final Set<String> _selectedTags = <String>{};
  Duration? _relativeTimeWindow;
  DateTimeRange? _customTimeRange;
  RegExp? _compiledSearch;
  String? _searchError;
  Set<StateAnnotationSeverity> _annotationSeverityFilter =
      StateAnnotationSeverity.values.toSet();
  bool _pendingControllerSync = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? StateInspectorController.instance;
    _controller.addListener(_handleControllerChanged);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _realignSelection();
      }
    });
    _activeKinds = StateEventKind.values.toSet();
    _searchController = TextEditingController();
    _annotationSeverityFilter = StateAnnotationSeverity.values.toSet();
  }

  @override
  void didUpdateWidget(covariant StateInspectorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextController =
        widget.controller ?? StateInspectorController.instance;
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
    if (!mounted || _pendingControllerSync) {
      return;
    }
    _pendingControllerSync = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _pendingControllerSync = false;
      setState(_realignSelection);
    });
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
    final rawQuery = _searchQuery.trim();
    final bool searchActive = !_useRegex && rawQuery.isNotEmpty;
    final List<StateChangeRecord> pinned = <StateChangeRecord>[];
    final List<StateChangeRecord> unpinned = <StateChangeRecord>[];
    final DateTime? lowerBound = _relativeTimeWindow == null
        ? null
        : DateTime.now().subtract(_relativeTimeWindow!);
    final DateTimeRange? customRange = _customTimeRange;

    for (final record in _controller.records) {
      if (!_activeKinds.contains(record.kind)) {
        continue;
      }
      if (!_matchesTimeFilters(record.timestamp, lowerBound, customRange)) {
        continue;
      }
      if (_selectedTags.isNotEmpty && !_matchesTags(record)) {
        continue;
      }
      if (!_matchesAnnotationSeverity(record)) {
        continue;
      }
      if (_useRegex && rawQuery.isNotEmpty) {
        if (_compiledSearch == null ||
            !_matchesRegex(record, _compiledSearch!)) {
          continue;
        }
      } else if (searchActive && !_matchesSearch(record, rawQuery)) {
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
    final normalizedQuery = _caseSensitiveSearch ? query : query.toLowerCase();

    bool contains(String? source) {
      if (source == null) {
        return false;
      }
      final candidate = _caseSensitiveSearch ? source : source.toLowerCase();
      return candidate.contains(normalizedQuery);
    }

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
      final path = _caseSensitiveSearch
          ? diff.pathAsString
          : diff.pathAsString.toLowerCase();
      if (path.contains(normalizedQuery)) {
        return true;
      }
      final before = diff.before?.toString();
      if (contains(before)) {
        return true;
      }
      final after = diff.after?.toString();
      if (contains(after)) {
        return true;
      }
    }

    return false;
  }

  bool _matchesRegex(StateChangeRecord record, RegExp pattern) {
    bool matches(String? source) => source != null && pattern.hasMatch(source);

    if (matches(record.origin) ||
        matches(record.summary) ||
        matches(record.previousSummary) ||
        matches(record.runtimeTypeName) ||
        matches(record.snapshot.summary) ||
        matches(record.snapshot.prettyJson) ||
        matches(record.details.toString())) {
      return true;
    }

    for (final diff in record.diffs) {
      if (pattern.hasMatch(diff.pathAsString) ||
          matches(diff.before?.toString()) ||
          matches(diff.after?.toString())) {
        return true;
      }
    }

    return false;
  }

  bool _matchesTags(StateChangeRecord record) {
    if (_selectedTags.isEmpty) {
      return true;
    }
    final recordTags = record.tags.toSet();
    if (recordTags.any(_selectedTags.contains)) {
      return true;
    }
    for (final annotation in record.annotations) {
      if (annotation.tags.any(_selectedTags.contains)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesAnnotationSeverity(StateChangeRecord record) {
    if (_annotationSeverityFilter.length ==
        StateAnnotationSeverity.values.length) {
      return true;
    }
    if (record.annotations.isEmpty) {
      return false;
    }
    for (final annotation in record.annotations) {
      if (_annotationSeverityFilter.contains(annotation.severity)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesTimeFilters(
    DateTime timestamp,
    DateTime? lowerBound,
    DateTimeRange? customRange,
  ) {
    if (lowerBound != null && timestamp.isBefore(lowerBound)) {
      return false;
    }
    if (customRange != null) {
      if (timestamp.isBefore(customRange.start) ||
          timestamp.isAfter(customRange.end)) {
        return false;
      }
    }
    return true;
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
      _updateSearchPattern();
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
      _compiledSearch = null;
      _searchError = null;
      _realignSelection();
    });
  }

  void _toggleRegexSearch() {
    setState(() {
      _useRegex = !_useRegex;
      _updateSearchPattern();
      _realignSelection();
    });
  }

  void _toggleCaseSensitivity() {
    setState(() {
      _caseSensitiveSearch = !_caseSensitiveSearch;
      _updateSearchPattern();
      _realignSelection();
    });
  }

  void _toggleFiltersExpanded() {
    setState(() {
      _filtersExpanded = !_filtersExpanded;
    });
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
      _realignSelection();
    });
  }

  void _clearTags() {
    setState(() {
      _selectedTags.clear();
      _realignSelection();
    });
  }

  void _setRelativeTimeWindow(Duration? duration) {
    setState(() {
      _relativeTimeWindow = duration;
      if (duration != null) {
        _customTimeRange = null;
      }
      _realignSelection();
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart =
        _customTimeRange?.start ?? now.subtract(const Duration(days: 1));
    final initialEnd = _customTimeRange?.end ?? now;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _relativeTimeWindow = null;
      _customTimeRange = DateTimeRange(
        start: picked.start,
        end:
            picked.end.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
      );
      _realignSelection();
    });
  }

  void _clearCustomRange() {
    if (_customTimeRange == null) {
      return;
    }
    setState(() {
      _customTimeRange = null;
      _realignSelection();
    });
  }

  void _toggleSeverity(StateAnnotationSeverity severity) {
    setState(() {
      if (_annotationSeverityFilter.contains(severity)) {
        if (_annotationSeverityFilter.length == 1) {
          return;
        }
        _annotationSeverityFilter.remove(severity);
      } else {
        _annotationSeverityFilter.add(severity);
      }
      _realignSelection();
    });
  }

  void _resetSeverityFilters() {
    setState(() {
      _annotationSeverityFilter = StateAnnotationSeverity.values.toSet();
      _realignSelection();
    });
  }

  void _updateSearchPattern() {
    if (!_useRegex) {
      _compiledSearch = null;
      _searchError = null;
      return;
    }
    final raw = _searchQuery.trim();
    if (raw.isEmpty) {
      _compiledSearch = null;
      _searchError = null;
      return;
    }
    try {
      _compiledSearch = RegExp(
        raw,
        caseSensitive: _caseSensitiveSearch,
        multiLine: true,
      );
      _searchError = null;
    } catch (error) {
      _compiledSearch = null;
      _searchError =
          error is FormatException ? error.message : error.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRecords = _visibleTimeline();
    final totalCount = _controller.records.length;
    final bool panelVisible = _controller.panelVisible;
    final bool isPaused = _controller.isPaused;
    final bool advancedFiltersActive = _selectedTags.isNotEmpty ||
        _relativeTimeWindow != null ||
        _customTimeRange != null ||
        _annotationSeverityFilter.length !=
            StateAnnotationSeverity.values.length;
    final bool filtersActive =
        _activeKinds.length != StateEventKind.values.length ||
            advancedFiltersActive;
    final bool searchActive =
        _searchQuery.trim().isNotEmpty && _searchError == null;
    final bool selectedPinned =
        _selected != null && _controller.isPinned(_selected!.id);

    final overlayState = context.findAncestorStateOfType<OverlayState>() ??
        context.findRootAncestorStateOfType<OverlayState>();
    final hasOverlay = overlayState != null;

    final stack = _buildOverlayStack(
      context: context,
      visibleRecords: visibleRecords,
      totalCount: totalCount,
      panelVisible: panelVisible,
      isPaused: isPaused,
      filtersActive: filtersActive,
      searchActive: searchActive,
      selectedPinned: selectedPinned,
      tooltipsEnabled: hasOverlay,
    );
    return stack;
  }

  Widget _buildOverlayStack({
    required BuildContext context,
    required List<StateChangeRecord> visibleRecords,
    required int totalCount,
    required bool panelVisible,
    required bool isPaused,
    required bool filtersActive,
    required bool searchActive,
    required bool selectedPinned,
    required bool tooltipsEnabled,
  }) {
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
                    child: panelVisible
                        ? _StateInspectorPanel(
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
                            onTogglePin: (record) =>
                                _controller.togglePin(record.id),
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
                            useRegex: _useRegex,
                            caseSensitive: _caseSensitiveSearch,
                            filtersExpanded: _filtersExpanded,
                            onToggleRegex: _toggleRegexSearch,
                            onToggleCaseSensitive: _toggleCaseSensitivity,
                            onToggleFilters: _toggleFiltersExpanded,
                            searchError: _searchError,
                            availableTags: _controller.availableTags.toList()
                              ..sort(),
                            selectedTags: _selectedTags,
                            onToggleTag: _toggleTag,
                            onClearTags: _clearTags,
                            relativeTimeWindow: _relativeTimeWindow,
                            onSelectRelativeWindow: _setRelativeTimeWindow,
                            onPickCustomRange: _pickCustomRange,
                            onClearCustomRange: _clearCustomRange,
                            customTimeRange: _customTimeRange,
                            annotationSeverityFilter: _annotationSeverityFilter,
                            onToggleSeverity: _toggleSeverity,
                            onResetSeverity: _resetSeverityFilters,
                            controller: _controller,
                            analytics: _controller.analytics,
                            tooltipsEnabled: tooltipsEnabled,
                          )
                        : const SizedBox.shrink(),
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

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
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
    final tooltipMessage =
        isActive ? 'Hide state inspector' : 'Show state inspector';

    final button = FloatingActionButton.small(
      onPressed: onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.analytics_outlined),
          if (recordCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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

    if (_overlayAvailable(context)) {
      return Tooltip(
        message: tooltipMessage,
        child: button,
      );
    }

    return Semantics(
      button: true,
      label: tooltipMessage,
      child: button,
    );
  }

  bool _overlayAvailable(BuildContext context) {
    return context.findAncestorStateOfType<OverlayState>() != null;
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
    required this.useRegex,
    required this.caseSensitive,
    required this.filtersExpanded,
    required this.onToggleRegex,
    required this.onToggleCaseSensitive,
    required this.onToggleFilters,
    required this.searchError,
    required this.availableTags,
    required this.selectedTags,
    required this.onToggleTag,
    required this.onClearTags,
    required this.relativeTimeWindow,
    required this.onSelectRelativeWindow,
    required this.onPickCustomRange,
    required this.onClearCustomRange,
    required this.customTimeRange,
    required this.annotationSeverityFilter,
    required this.onToggleSeverity,
    required this.onResetSeverity,
    required this.controller,
    required this.analytics,
    required this.tooltipsEnabled,
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
  final bool useRegex;
  final bool caseSensitive;
  final bool filtersExpanded;
  final VoidCallback onToggleRegex;
  final VoidCallback onToggleCaseSensitive;
  final VoidCallback onToggleFilters;
  final String? searchError;
  final List<String> availableTags;
  final Set<String> selectedTags;
  final ValueChanged<String> onToggleTag;
  final VoidCallback onClearTags;
  final Duration? relativeTimeWindow;
  final ValueChanged<Duration?> onSelectRelativeWindow;
  final Future<void> Function() onPickCustomRange;
  final VoidCallback onClearCustomRange;
  final DateTimeRange? customTimeRange;
  final Set<StateAnnotationSeverity> annotationSeverityFilter;
  final ValueChanged<StateAnnotationSeverity> onToggleSeverity;
  final VoidCallback onResetSeverity;
  final StateInspectorController controller;
  final StateTimelineAnalytics analytics;
  final bool tooltipsEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      color: surfaceColor.withAlpha((0.98 * 255).round()),
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
              tooltipsEnabled: tooltipsEnabled,
            ),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!analytics.isEmpty)
                      _AnalyticsSummary(analytics: analytics),
                    _SearchField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      onClear: onClearSearch,
                      query: searchQuery,
                      resultCount: resultCount,
                      useRegex: useRegex,
                      caseSensitive: caseSensitive,
                      onToggleRegex: onToggleRegex,
                      onToggleCaseSensitive: onToggleCaseSensitive,
                      onToggleFilters: onToggleFilters,
                      filtersExpanded: filtersExpanded,
                      filtersActive: filtersActive,
                      searchError: searchError,
                      tooltipsEnabled: tooltipsEnabled,
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 180),
                      firstChild: const SizedBox.shrink(),
                      secondChild: _AdvancedFilterPanel(
                        availableTags: availableTags,
                        selectedTags: selectedTags,
                        onToggleTag: onToggleTag,
                        onClearTags: onClearTags,
                        relativeTimeWindow: relativeTimeWindow,
                        onSelectRelativeWindow: onSelectRelativeWindow,
                        onPickCustomRange: onPickCustomRange,
                        onClearCustomRange: onClearCustomRange,
                        customTimeRange: customTimeRange,
                        annotationSeverityFilter: annotationSeverityFilter,
                        onToggleSeverity: onToggleSeverity,
                        onResetSeverity: onResetSeverity,
                      ),
                      crossFadeState: filtersExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                    ),
                    _EventFilterRow(
                      activeKinds: activeKinds,
                      onToggle: onFilterToggle,
                      onReset: onResetFilters,
                    ),
                  ],
                ),
              ),
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
                      tooltipsEnabled: tooltipsEnabled,
                    ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _DetailSection(
                record: selected,
                isPinned: selectedPinned,
                onTogglePin: onToggleSelectedPin,
                controller: controller,
                tooltipsEnabled: tooltipsEnabled,
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
    required this.tooltipsEnabled,
  });

  final VoidCallback onClose;
  final VoidCallback? onClear;
  final VoidCallback onTogglePause;
  final bool isPaused;
  final bool tooltipsEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.analytics_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'State Inspector',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                if (isPaused) _PausedIndicator(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                IconButton(
                  tooltip: tooltipsEnabled
                      ? (isPaused ? 'Resume capture' : 'Pause capture')
                      : null,
                  icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                  onPressed: onTogglePause,
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: tooltipsEnabled ? 'Clear timeline' : null,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: onClear,
                  ),
                IconButton(
                  tooltip: tooltipsEnabled ? 'Close inspector' : null,
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
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
    required this.useRegex,
    required this.caseSensitive,
    required this.onToggleRegex,
    required this.onToggleCaseSensitive,
    required this.onToggleFilters,
    required this.filtersExpanded,
    required this.filtersActive,
    required this.searchError,
    required this.tooltipsEnabled,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String query;
  final int resultCount;
  final bool useRegex;
  final bool caseSensitive;
  final VoidCallback onToggleRegex;
  final VoidCallback onToggleCaseSensitive;
  final VoidCallback onToggleFilters;
  final bool filtersExpanded;
  final bool filtersActive;
  final String? searchError;
  final bool tooltipsEnabled;

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.trim().isNotEmpty;
    final theme = Theme.of(context);
    final metricsLabel = resultCount == 0
        ? 'No results'
        : resultCount == 1
            ? '1 match'
            : '$resultCount matches';

    Color? _toggleColor(bool active) =>
        active ? theme.colorScheme.primary : theme.iconTheme.color;

    Widget withTooltip(String message, Widget child) {
      if (!tooltipsEnabled) {
        return child;
      }
      return Tooltip(
        message: message,
        child: child,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: hasQuery
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: tooltipsEnabled ? 'Clear search' : null,
                            onPressed: onClear,
                          )
                        : null,
                    hintText: 'Search timeline…',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    withTooltip(
                      useRegex ? 'Regex search enabled' : 'Enable regex search',
                      _CompactIconButton(
                        icon: Icons.data_array,
                        color: _toggleColor(useRegex),
                        onPressed: onToggleRegex,
                      ),
                    ),
                    withTooltip(
                      caseSensitive
                          ? 'Case sensitive search'
                          : 'Case insensitive search',
                      _CompactIconButton(
                        icon: Icons.text_fields,
                        color: _toggleColor(caseSensitive),
                        onPressed: onToggleCaseSensitive,
                      ),
                    ),
                    withTooltip(
                      filtersExpanded
                          ? 'Hide advanced filters'
                          : 'Show advanced filters',
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          _CompactIconButton(
                            icon: Icons.tune,
                            color:
                                _toggleColor(filtersExpanded || filtersActive),
                            onPressed: onToggleFilters,
                          ),
                          if (filtersActive)
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            metricsLabel,
            style: theme.textTheme.labelSmall,
          ),
          if (searchError != null) ...[
            const SizedBox(height: 4),
            Text(
              searchError!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
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

class _AnalyticsSummary extends StatelessWidget {
  const _AnalyticsSummary({required this.analytics});

  final StateTimelineAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    if (analytics.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final topOrigins = analytics.topOriginsByCount(3);
    final slowest = analytics.slowestOrigins(3);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined, size: 14),
              const SizedBox(width: 6),
              Text('Insights', style: theme.textTheme.labelMedium),
              const Spacer(),
              Text('${analytics.totalRecords} events',
                  style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final kind in StateEventKind.values)
                _MetricChip(
                  label: kind.name,
                  value: analytics.kindCounts[kind] ?? 0,
                ),
              if (analytics.averageGap != null)
                _MetricChip(
                  label: 'avg gap',
                  value: _formatDuration(analytics.averageGap!),
                ),
              if (analytics.longestGap != null)
                _MetricChip(
                  label: 'slowest gap',
                  value: _formatDuration(analytics.longestGap!),
                ),
            ],
          ),
          if (topOrigins.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Most active sources', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            for (final origin in topOrigins)
              _AnalyticsListTile(
                title: origin.origin,
                subtitle:
                    '${origin.count} events · ${_formatDuration(origin.averageInterval)} avg Δ',
              ),
          ],
          if (slowest.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Slowest transitions', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            for (final origin in slowest)
              _AnalyticsListTile(
                title: origin.origin,
                subtitle:
                    'Longest Δ ${_formatDuration(origin.longestInterval)} over ${origin.count} events',
              ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final Object value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _AnalyticsListTile extends StatelessWidget {
  const _AnalyticsListTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Colors.grey),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelMedium),
                Text(subtitle, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tags', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final tag in tags)
              Chip(
                label: Text(tag),
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
          ],
        ),
      ],
    );
  }
}

class _MetricsSection extends StatelessWidget {
  const _MetricsSection({required this.metrics});

  final Map<String, num> metrics;

  @override
  Widget build(BuildContext context) {
    final entries = metrics.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Metrics', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodySmall,
                    children: [
                      TextSpan(
                        text: '${entry.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: entry.value.toString()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AnnotationList extends StatelessWidget {
  const _AnnotationList({
    required this.annotations,
    required this.controller,
    required this.recordId,
    required this.tooltipsEnabled,
  });

  final List<StateAnnotation> annotations;
  final StateInspectorController controller;
  final int recordId;
  final bool tooltipsEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Annotations', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Column(
          children: [
            for (final annotation in annotations)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: _severityColorFor(annotation.severity, theme)
                    .withOpacity(0.08),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.sticky_note_2_outlined,
                    color: _severityColorFor(annotation.severity, theme),
                  ),
                  title: Text(annotation.message),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Added ${annotation.createdAt.toLocal().toIso8601String()}',
                        style: theme.textTheme.labelSmall,
                      ),
                      if (annotation.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              for (final tag in annotation.tags)
                                Chip(
                                  label: Text(tag),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: tooltipsEnabled ? 'Remove note' : null,
                    onPressed: () {
                      controller.removeAnnotation(recordId, annotation.id);
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({
    required this.attachments,
    required this.controller,
    required this.recordId,
    required this.tooltipsEnabled,
  });

  final List<StateAttachment> attachments;
  final StateInspectorController controller;
  final int recordId;
  final bool tooltipsEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attachments', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Column(
          children: [
            for (final attachment in attachments)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: Icon(_iconForAttachment(attachment.type)),
                  title: Text(attachment.description ?? attachment.uri),
                  subtitle: Text(
                    'Captured ${attachment.capturedAt.toLocal().toIso8601String()}',
                    style: theme.textTheme.labelSmall,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: tooltipsEnabled ? 'Remove attachment' : null,
                    onPressed: () {
                      controller.removeAttachment(recordId, attachment.id);
                    },
                  ),
                  onTap: () {
                    // Placeholder: consuming apps can override by listening to
                    // controller.recordStream and opening URIs.
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  IconData _iconForAttachment(StateAttachmentType type) {
    switch (type) {
      case StateAttachmentType.screenshot:
        return Icons.image_outlined;
      case StateAttachmentType.screenRecording:
        return Icons.movie_outlined;
      case StateAttachmentType.log:
        return Icons.description_outlined;
      case StateAttachmentType.custom:
        return Icons.attach_file;
    }
  }
}

class _AnnotationComposer extends StatelessWidget {
  const _AnnotationComposer({
    required this.controller,
    required this.recordId,
    required this.noteController,
    required this.tagsController,
    required this.severity,
    required this.onSeverityChanged,
  });

  final StateInspectorController controller;
  final int recordId;
  final TextEditingController noteController;
  final TextEditingController tagsController;
  final StateAnnotationSeverity severity;
  final ValueChanged<StateAnnotationSeverity> onSeverityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add annotation', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final option in StateAnnotationSeverity.values)
                ChoiceChip(
                  label: Text(option.name),
                  selected: severity == option,
                  onSelected: (_) => onSeverityChanged(option),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Describe why this event matters…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: tagsController,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText:
                  'Comma separated tags (e.g. regression,release-blocker)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: noteController,
            builder: (context, value, _) {
              final hasNote = value.text.trim().isNotEmpty;
              return Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: hasNote
                      ? () {
                          final message = noteController.text.trim();
                          if (message.isEmpty) {
                            return;
                          }
                          final rawTags = tagsController.text
                              .split(',')
                              .map((tag) => tag.trim())
                              .where((tag) => tag.isNotEmpty)
                              .toSet();
                          controller.addAnnotation(
                            recordId,
                            StateAnnotation(
                              recordId: recordId,
                              message: message,
                              severity: severity,
                              tags: rawTags,
                            ),
                          );
                          if (rawTags.isNotEmpty) {
                            controller.addTags(recordId, rawTags);
                          }
                          noteController.clear();
                          tagsController.clear();
                          FocusScope.of(context).unfocus();
                        }
                      : null,
                  icon: const Icon(Icons.add_comment),
                  label: const Text('Attach note'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({
    required this.records,
    required this.selected,
    required this.pinnedIds,
    required this.onSelect,
    required this.onTogglePin,
    required this.tooltipsEnabled,
  });

  final List<StateChangeRecord> records;
  final StateChangeRecord? selected;
  final Set<int> pinnedIds;
  final ValueChanged<StateChangeRecord> onSelect;
  final ValueChanged<StateChangeRecord> onTogglePin;
  final bool tooltipsEnabled;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight <= 0) {
          // When the panel header and filters consume all vertical space the
          // list collapses to zero height; skip building the sliver to avoid a
          // crash inside RenderSliverPadding's null geometry handling.
          return const SizedBox.shrink();
        }

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
            final hasTags = record.tags.isNotEmpty;
            final hasAnnotations = record.annotations.isNotEmpty;

            final List<Widget> subtitleChildren = [
              Text(
                record.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ];

            if (hasTags) {
              subtitleChildren.add(
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final tag in record.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tag,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            if (hasAnnotations) {
              subtitleChildren.add(
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final annotation in record.annotations)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _severityColorFor(annotation.severity, theme)
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.label_important_outline,
                                size: 12,
                                color: _severityColorFor(
                                  annotation.severity,
                                  theme,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                annotation.message,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: _severityColorFor(
                                    annotation.severity,
                                    theme,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            return Material(
              color: isSelected
                  ? color.withAlpha((0.08 * 255).round())
                  : Colors.transparent,
              child: ListTile(
                dense: true,
                isThreeLine: subtitleChildren.length > 1,
                leading: Icon(_iconFor(record.kind), color: color, size: 20),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.origin,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: subtitleChildren,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timestamp,
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        size: 18,
                      ),
                      tooltip:
                          tooltipsEnabled ? (isPinned ? 'Unpin' : 'Pin') : null,
                      onPressed: () => onTogglePin(record),
                    ),
                  ],
                ),
                onTap: () => onSelect(record),
              ),
            );
          },
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
    required this.controller,
    required this.tooltipsEnabled,
  });

  final StateChangeRecord? record;
  final bool isPinned;
  final VoidCallback? onTogglePin;
  final StateInspectorController controller;
  final bool tooltipsEnabled;

  @override
  State<_DetailSection> createState() => _DetailSectionState();
}

class _DetailSectionState extends State<_DetailSection> {
  late final ScrollController _scrollController;
  late final TextEditingController _noteController;
  late final TextEditingController _noteTagsController;
  StateAnnotationSeverity _noteSeverity = StateAnnotationSeverity.info;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _noteController = TextEditingController();
    _noteTagsController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteTagsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _DetailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record?.id != widget.record?.id) {
      _noteController.clear();
      _noteTagsController.clear();
      _noteSeverity = StateAnnotationSeverity.info;
    }
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
            if (record.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              _TagSection(tags: record.tags),
            ],
            if (record.metrics.isNotEmpty) ...[
              const SizedBox(height: 12),
              _MetricsSection(metrics: record.metrics),
            ],
            if (record.annotations.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AnnotationList(
                annotations: record.annotations,
                controller: widget.controller,
                recordId: record.id,
                tooltipsEnabled: widget.tooltipsEnabled,
              ),
            ],
            if (record.attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AttachmentList(
                attachments: record.attachments,
                controller: widget.controller,
                recordId: record.id,
                tooltipsEnabled: widget.tooltipsEnabled,
              ),
            ],
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
            const SizedBox(height: 16),
            _AnnotationComposer(
              controller: widget.controller,
              recordId: record.id,
              noteController: _noteController,
              tagsController: _noteTagsController,
              severity: _noteSeverity,
              onSeverityChanged: (next) {
                setState(() {
                  _noteSeverity = next;
                });
              },
            ),
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

class _JsonSection extends StatefulWidget {
  const _JsonSection({required this.title, required this.content});

  final String title;
  final String content;

  @override
  State<_JsonSection> createState() => _JsonSectionState();
}

class _JsonSectionState extends State<_JsonSection> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
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
            color: _surfaceContainerColor(scheme),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _controller,
              child: SelectableText(
                widget.content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiffSection extends StatefulWidget {
  const _DiffSection({required this.diffs});

  final List<StateDiffEntry> diffs;

  @override
  State<_DiffSection> createState() => _DiffSectionState();
}

class _DiffSectionState extends State<_DiffSection> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            controller: _controller,
            thumbVisibility: true,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _surfaceContainerColor(Theme.of(context).colorScheme),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                controller: _controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final diff in widget.diffs)
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

Color _surfaceContainerColor(ColorScheme scheme) {
  final dynamic dynamicScheme = scheme;
  try {
    final result = dynamicScheme.surfaceContainerHighest;
    if (result is Color) {
      return result;
    }
  } catch (_) {}
  try {
    final variant = dynamicScheme.surfaceVariant;
    if (variant is Color) {
      return variant;
    }
  } catch (_) {}
  return scheme.surface;
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

String _formatDuration(Duration? duration) {
  if (duration == null) {
    return '—';
  }
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

Color _severityColorFor(StateAnnotationSeverity severity, ThemeData theme) {
  switch (severity) {
    case StateAnnotationSeverity.info:
      return theme.colorScheme.primary;
    case StateAnnotationSeverity.warning:
      return Colors.orange.shade700;
    case StateAnnotationSeverity.error:
      return theme.colorScheme.error;
  }
}

class _AdvancedFilterPanel extends StatelessWidget {
  const _AdvancedFilterPanel({
    required this.availableTags,
    required this.selectedTags,
    required this.onToggleTag,
    required this.onClearTags,
    required this.relativeTimeWindow,
    required this.onSelectRelativeWindow,
    required this.onPickCustomRange,
    required this.onClearCustomRange,
    required this.customTimeRange,
    required this.annotationSeverityFilter,
    required this.onToggleSeverity,
    required this.onResetSeverity,
  });

  final List<String> availableTags;
  final Set<String> selectedTags;
  final ValueChanged<String> onToggleTag;
  final VoidCallback onClearTags;
  final Duration? relativeTimeWindow;
  final ValueChanged<Duration?> onSelectRelativeWindow;
  final Future<void> Function() onPickCustomRange;
  final VoidCallback onClearCustomRange;
  final DateTimeRange? customTimeRange;
  final Set<StateAnnotationSeverity> annotationSeverityFilter;
  final ValueChanged<StateAnnotationSeverity> onToggleSeverity;
  final VoidCallback onResetSeverity;

  static const List<Duration?> _quickWindows = <Duration?>[
    null,
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
    Duration(hours: 24),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 16),
          Text('Advanced filters', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Tags',
            child: availableTags.isEmpty
                ? const Text(
                    'No tags detected yet. Add annotations or tag records programmatically.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in availableTags)
                        FilterChip(
                          label: Text(tag),
                          selected: selectedTags.contains(tag),
                          onSelected: (_) => onToggleTag(tag),
                        ),
                      if (selectedTags.isNotEmpty)
                        TextButton(
                          onPressed: onClearTags,
                          child: const Text('Clear tags'),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _buildSection(
            context,
            title: 'Time range',
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final window in _quickWindows)
                  ChoiceChip(
                    label: Text(_labelForWindow(window)),
                    selected: _windowMatches(window),
                    onSelected: (_) => onSelectRelativeWindow(window),
                  ),
                TextButton.icon(
                  onPressed: onPickCustomRange,
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: Text(
                    customTimeRange == null
                        ? 'Custom range'
                        : _describeRange(customTimeRange!),
                  ),
                ),
                if (customTimeRange != null)
                  TextButton(
                    onPressed: onClearCustomRange,
                    child: const Text('Clear custom range'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSection(
            context,
            title: 'Annotation severity',
            action: annotationSeverityFilter.length !=
                    StateAnnotationSeverity.values.length
                ? TextButton(
                    onPressed: onResetSeverity, child: const Text('Reset'))
                : null,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final severity in StateAnnotationSeverity.values)
                  FilterChip(
                    label: Text(severity.name),
                    selected: annotationSeverityFilter.contains(severity),
                    onSelected: (_) => onToggleSeverity(severity),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required Widget child,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: theme.textTheme.labelMedium),
            if (action != null) ...[
              const SizedBox(width: 8),
              action,
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  bool _windowMatches(Duration? window) {
    if (window == null && relativeTimeWindow == null) {
      return true;
    }
    if (window == null || relativeTimeWindow == null) {
      return false;
    }
    return relativeTimeWindow == window;
  }

  static String _labelForWindow(Duration? duration) {
    if (duration == null) {
      return 'All';
    }
    if (duration.inHours >= 24) {
      return '${duration.inHours ~/ 24}d';
    }
    if (duration.inHours >= 1) {
      return '${duration.inHours}h';
    }
    return '${duration.inMinutes}m';
  }

  static String _describeRange(DateTimeRange range) {
    final start = range.start.toLocal();
    final end = range.end.toLocal();
    return '${start.month}/${start.day} - ${end.month}/${end.day}';
  }
}
