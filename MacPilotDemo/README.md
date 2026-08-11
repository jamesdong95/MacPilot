# MacPilotDemo

Native SwiftUI sample-data demo for MacPilot.

## Run in Xcode

1. Open `MacPilotDemo.xcodeproj` in Xcode 15 or newer.
2. Select the shared `MacPilotDemo` scheme.
3. Choose **My Mac** as the run destination.
4. Press **Run**.

The demo is intentionally safe to explore. It uses in-memory sample data and
does not read, move, delete, or upload files. It demonstrates:

- Local file search presentation.
- File metadata inspection.
- Deterministic organization suggestions.
- Preview-style action confirmation.
- Undoable activity history.
- Local-only privacy messaging.

The SwiftUI demo is a visual product prototype for this MVP. It is not yet
bridged to the Python core or to real filesystem permissions.

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
