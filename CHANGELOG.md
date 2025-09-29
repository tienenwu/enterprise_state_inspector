## 0.1.3

- Added flexible adapter primitives for `ValueListenable`, `Listenable`, and stream-based
  state managers via `StateInspectorAdapters`, enabling quick hooks for MobX, Redux,
  `ChangeNotifier`, and custom architectures without new package dependencies.
- Timeline records now carry tags, metrics, annotations, and rich-media attachments so teams can
  prioritise issues, enrich bug reports, and bundle contextual evidence directly from the overlay.
- Advanced overlay tooling: regex/case-sensitive search, multi-tag filters, time-range preset
  chips, annotation severity filters, and a quick analytics header with hotspot/latency insights.
- Added annotation composer UI to create tagged notes in-line, plus removal actions for annotations
  and attachments to keep the timeline curated during live debugging sessions.
- Export helpers now include Markdown and CLI-friendly tabular formats alongside JSON, and session
  payloads are versioned (`version: 2`) for compatibility with the richer model.
- Introduced live timeline streaming hooks via `StateInspectorSyncDelegate`/`StreamSyncDelegate`
  so sessions can be mirrored to companion tooling over WebSocket/HTTP bridges.
- Example app now showcases adapters for `ValueListenable`/`ChangeNotifier`, live streaming logs,
  annotation/attachment helpers, and Markdown exports to help teams evaluate the new surface area quickly.
- Adapter registry與 `observeStream`/`observeNotifier` helper 讓第三方 state manager
  可以無縫註冊 inspector adapter。
- 新增 `analyticsStream` 與 `StateTimelineEventBus`，支援多客戶端儀表板與 DevTools。
- WebSocket companion (`tool/timeline_companion.dart`) 以及 `WebSocketSyncDelegate`
  完整展示遠端事件匯流排；測試工具 (`test/support/inspector_test_utils.dart`) 協助在測試中等待事件。
- Added a WebSocket sync delegate and `tool/timeline_companion.dart` CLI so timelines can be
  streamed into external terminals or desktop tooling with zero setup.
- Centralised package version management via `tool/version.txt` and the generated
  `lib/src/version.dart`, keeping `pubspec.yaml`, README snippets, and example lockfiles in sync.

## 0.1.2

- README example section now showcases screenshots/GIF instead of build steps.
- Removed internal publish checklist from public documentation.

## 0.1.1

- Incremental release with README image assets included in the package.
- Bumped homepage to https://tienenwu.me/ and kept API unchanged.

## 0.1.0-dev.1

- Initial preview release with Riverpod and Bloc observers feeding the inspector timeline.
- Overlay panel now supports pause/resume capture, search, pinning, event-kind filtering,
  and structured diff inspection for map/list states.
- Added GetX adapter helpers to observe `Rx`, `RxList`, and `RxMap` values with one line.
- Adds session import/export APIs so timelines (and pinned events) can be shared across devices.
- Example application demonstrates Riverpod + Bloc integration plus the new import/export dialogs
  and structured Riverpod state for richer diffs, alongside a GetX counter showcase.
