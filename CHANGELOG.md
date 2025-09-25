## 0.1.0-dev.1

- Initial preview release with Riverpod and Bloc observers feeding the inspector timeline.
- Overlay panel now supports pause/resume capture, search, pinning, event-kind filtering,
  and structured diff inspection for map/list states.
- Added GetX adapter helpers to observe `Rx`, `RxList`, and `RxMap` values with one line.
- Adds session import/export APIs so timelines (and pinned events) can be shared across devices.
- Example application demonstrates Riverpod + Bloc integration plus the new import/export dialogs
  and structured Riverpod state for richer diffs, alongside a GetX counter showcase.
