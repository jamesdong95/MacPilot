# MacPilotDemo

Native SwiftUI read-only client for the MacPilot Python core.

## Run in Xcode

1. Open `MacPilotDemo.xcodeproj` in Xcode 15 or newer.
2. Select the shared `MacPilotDemo` scheme.
3. Choose **My Mac** as the run destination.
4. Press **Run**.

The client connects to the local Python core and demonstrates:

- Indexing a user-selected folder into local SQLite.
- Search over real filenames, paths, and indexed text.
- File metadata inspection from real search results.
- Deterministic organization suggestions from the core.
- Preview-before-apply moves: previews never pass `--apply`.
- Apply moves after an explicit confirmation dialog; every applied move is
  recorded in the local action log.
- Undo a recorded move from Activity with confirmation, restoring the file.
- Local-only privacy messaging.

The bridge discovers the core from an installed `macpilot` executable, the
`MACPILOT_CLI` environment variable, or `MACPILOT_PROJECT_ROOT` for a source
checkout. `MACPILOT_DB` can be used to isolate the SQLite database during
development. All mutations stay preview-first and confirm-first; the core
coordinates filesystem and SQLite updates with rollback handling.

## Command-line build

From the repository root:

```bash
xcodebuild \
  -project MacPilotDemo/MacPilotDemo.xcodeproj \
  -scheme MacPilotDemo \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/MacPilotDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```
