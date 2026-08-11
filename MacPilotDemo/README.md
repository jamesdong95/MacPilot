# MacPilotDemo

Native SwiftUI read-only client for the MacPilot Python core.

## Run in Xcode

1. Open `MacPilotDemo.xcodeproj` in Xcode 15 or newer.
2. Select the shared `MacPilotDemo` scheme.
3. Choose **My Mac** as the run destination.
4. Press **Run**.

The client is intentionally read-only to explore. It connects to the local
Python core and demonstrates:

- Indexing a user-selected folder into local SQLite.
- Search over real filenames, paths, and indexed text.
- File metadata inspection from real search results.
- Deterministic organization suggestions from the core.
- Move previews that never pass `--apply`.
- Read-only action-log presentation.
- Local-only privacy messaging.

The bridge discovers the core from an installed `macpilot` executable, the
`MACPILOT_CLI` environment variable, or `MACPILOT_PROJECT_ROOT` for a source
checkout. `MACPILOT_DB` can be used to isolate the SQLite database during
development. The native UI does not apply moves or execute undo yet.

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
