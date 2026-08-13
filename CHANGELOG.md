# Changelog

All notable changes to MacPilot are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-08-13

### Added

- Indexing gets its own 300-second timeout so large folders no longer fail
  mid-index; other core commands keep the 30-second default.
- Recent-workspaces list (up to 8, persisted) shown on the empty-state card
  for one-click re-index, plus a Settings sheet (gear in the sidebar) showing
  the core, database path, indexed folder, and a "clear recent" action.
- Runtime Settings: edit the core path and database path in the Settings
  sheet; applying re-discovers the local core and re-indexes the current
  folder.
- Re-index button in the sidebar, and automatic re-index on app activation
  when the last index is older than 60 seconds.
- Actionable error messages: timeouts suggest retrying a smaller folder,
  command failures note nothing was changed, invalid output hints the core
  may need an update.

### Fixed

- Closed the install-to-run TOCTOU window in the Process bridge so a stop
  requested between install and run terminates the child instead of leaking it.
- Replaced an ambiguous "read-only slice" message with accurate
  "changes require explicit confirmation" wording.

## [0.3.0] - 2026-08-12

### Added

- Apply moves from the native UI with an explicit confirmation dialog; each
  move is recorded in the local action log.
- Undo a recorded move from Activity with confirmation; the file is restored
  to its original location.
- `CoreMoveOutcome` bridge model and `applyMove`/`undo` client methods.

### Changed

- Unified the CLI applied payload for `move --apply` and `undo --apply` to
  `{applied, action_id, source_path, destination_path, mode}` so the client
  decodes one consistent contract.
- Activity and Suggestions views now expose apply/undo with confirmation
  instead of read-only labels.
- `MARKETING_VERSION` bumped to `0.3.0`.

### Security

- Mutations remain preview-first and confirm-first; the Python core preserves
  no-overwrite, no-symlink, and rollback guarantees (covered by tests).

## [0.2.0] - 2026-08-12

### Added

- Native SwiftUI client now talks to the local Python core through a `Process` bridge
  (`MacPilotClient`), replacing the sample-data demo layer:
  - Discovers the core via `MACPILOT_PROJECT_ROOT`, `MACPILOT_CLI`, or `macpilot` on `PATH`.
  - Runs `index`, `list`, `search`, `suggest`, `status`, `actions`, and move previews
    against the real local filesystem and SQLite index.
  - Handles missing executables, non-zero exits, invalid JSON, timeouts, and cancellation.
- Sidebar layout fits the window: workspace and privacy controls are pinned to the bottom
  with `safeAreaInset` so nothing is clipped when the window is resized.

### Changed

- `DemoStore` is wired to real core data: folder selection, indexing, search, suggestions,
  read-only move previews, and the local action log.
- `MARKETING_VERSION` bumped to `0.2.0`.

### Security

- The UI remains strictly read-only: it never passes `--apply` and never executes undo.

## [0.1.0] - 2026-08-11

### Added

- Local-first Python core: SQLite FTS5 indexing, deterministic organization suggestions,
  preview-before-apply moves, undoable action log, symlink refusal, and no-overwrite guarantees.
- Native SwiftUI demo project skeleton with sample data.
- Python and macOS CI workflows.
