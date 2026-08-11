# Contributing to MacPilot

Thank you for helping improve the MacPilot MVP.

## Before opening a change

Run the checks from the repository root:

```bash
python3 -m unittest discover -s tests -v
python3 -m compileall -q macpilot
python3 -m macpilot --help
```

On macOS with Xcode installed, also build the native demo:

```bash
xcodebuild \
  -project MacPilotDemo/MacPilotDemo.xcodeproj \
  -scheme MacPilotDemo \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/MacPilotDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## Safety expectations

- Keep the Python core local-first and dependency-light.
- Do not add telemetry, uploads, or network calls without a clear product
  decision and documentation.
- Preserve preview-first behavior for filesystem mutations.
- Any applied move must remain undoable and must not overwrite an existing
  destination.
- Add a regression test before changing behavior.
- Do not commit databases, build products, credentials, or user data.

## Pull requests

Describe the behavior change, the tests run, and any known limitations. Keep
commits focused and use a conventional prefix such as `feat:`, `fix:`, `test:`,
`docs:`, or `ci:`.
