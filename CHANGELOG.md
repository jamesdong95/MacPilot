# Changelog

All notable changes to MacPilot are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.0] - 2026-08-13

### Added

- Semantic search: index text content into embeddings (local Ollama or any
  OpenAI-compatible /v1/embeddings endpoint) and search by meaning with
  cosine-similarity ranking. A "Semantic" toggle in Search re-indexes with
  embeddings and switches to meaning-based results.
- Storage report: a "Storage" section showing total size, largest files, files
  not touched in 90 days, and screenshots — each with a one-click Trash.
- Global hotkey (⌘⇧Space) to open the window from anywhere (needs
  Accessibility permission).

## [0.9.0] - 2026-08-13

### Added

- Live index progress: the core streams "PROGRESS <n>" and the UI shows a
  live "Indexed N files…" indicator while a folder indexes.
- Duplicate sweep: a "Duplicates" section groups files by identical content
  and offers one-click "Clean N" to trash the surplus copies (undoable).
- First-run onboarding: the empty state is now a clear welcome with a
  3-step guide and a plain-language "everything stays on this Mac" promise.
- Local diagnostics log (opt-in, never uploaded) with open/clear actions in
  Settings.
- Filesystem hardening: iCloud `.icloud` placeholders are skipped (no forced
  downloads), permission-denied directories are counted not fatal, and the
  chosen folder's security-scoped access is restored on relaunch.

## [0.8.0] - 2026-08-13

### Added

- Configurable LLM provider for summarization: connect a local Ollama server
  or any OpenAI-compatible cloud API (base URL + model + API key). The API key
  is stored in the macOS Keychain, never in the app or the repository.
  Configured via Settings → Local AI.

## [0.7.0] - 2026-08-13

### Added

- Menu bar extra: shows the indexed-file count and the current folder, with
  "Open MacPilot" and "Quit" actions.
- Drag & drop: drop a folder (or a file) onto the window to index it directly.
- Window fit now guards against bogus virtual-display frames so the window
  never collapses to a titlebar sliver on VDI screens.

## [0.6.0] - 2026-08-13

### Added

- Custom organization rules: `rules add "*.pdf" <dir>` / `rules list` /
  `rules remove <id>`; suggestions apply user rules before extension
  categories.
- Batch rename: `rename <root> <find> <replace>` previews then applies a
  substring rename across a folder, each rename individually undoable.
- Undo-all: `undo-all` reverts every active action newest-first, with preview.
- Opt-in local AI summarization: `summarize <path>` calls a running local
  Ollama server (default model qwen2.5:7b). Dependency-free and graceful —
  a missing Ollama yields a clear error, never a crash. `MACPILOT_OLLAMA_URL`
  overrides the server address.

## [0.5.0] - 2026-08-13

### Added

- Working file filters: "All files", "Content" (text files only), and
  "Recently changed" (modified within 7 days); core list/search now expose
  `is_text` per result.
- Safe delete: move an indexed file to the macOS Trash (collision-safe naming)
  via right-click → "Move to Trash" with a destructive confirmation; the move
  is recorded and undoable from Activity.
- Prefix search (partial words still hit) and query-term highlighting in
  result snippets.
- Duplicate detection: `duplicates` command reports files grouped by identical
  content hash.

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
