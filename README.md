# MacPilot

MacPilot is a local-first file search and safe organization tool for macOS. The
repository contains a dependency-light Python core and a native SwiftUI demo.
The Python core never uploads file contents, never deletes files, and requires
an explicit flag before a file move or undo is applied.

## What is ready to try

- SQLite metadata index with FTS5 filename and text-content search.
- Safe indexing that skips common dependency directories and never follows
  symlinks.
- Deterministic organization suggestions.
- Preview-first move and undo flows with an action log.
- `status` and `actions` commands so a test run is inspectable.
- Native SwiftUI sample-data demo for search, file details, suggestions, and
  activity history. The demo does **not** touch real files and is intentionally
  not connected to the Python core yet.
- GitHub Actions checks for the Python package and macOS SwiftUI build.

This is an MVP for local testing, not a finished background file-management
agent. Semantic embeddings, Ollama integration, a real-file SwiftUI bridge,
and a signed/notarized distribution are intentionally out of scope for this
milestone.

## Requirements

- macOS for the native demo.
- Python 3.11 or newer for the core.
- SQLite with FTS5 support (the macOS and standard CPython builds normally have
  it).
- Xcode 15 or newer for the native demo. The project has been built locally
  with Xcode 26.6.

The runtime core uses only Python's standard library. Build tooling is needed
only when creating a wheel.

## Run from source

From the repository root:

```bash
python3 -m unittest discover -s tests -v
python3 -m compileall -q macpilot
```

Use an isolated database while testing:

```bash
DB=/tmp/macpilot.sqlite3
python3 -m macpilot --db "$DB" index ~/Downloads
python3 -m macpilot --db "$DB" search "project contract"
python3 -m macpilot --db "$DB" suggest ~/Downloads
python3 -m macpilot --db "$DB" status
```

If `macpilot` is installed from the package, the same commands can be run with
`macpilot` instead of `python3 -m macpilot`. Without `--db`, the default path is
`~/.macpilot/index.sqlite3`.

### Safe move and undo flow

Every mutating operation is preview-only unless `--apply` is present:

```bash
# Preview; the source is not changed.
python3 -m macpilot --db "$DB" move \
  ~/Downloads/report.pdf ~/Documents/Reports/report.pdf

# Apply only after reviewing the JSON preview.
python3 -m macpilot --db "$DB" move \
  ~/Downloads/report.pdf ~/Documents/Reports/report.pdf --apply

# Find the action id if needed.
python3 -m macpilot --db "$DB" actions --active-only

# Preview the undo, then apply it explicitly.
python3 -m macpilot --db "$DB" undo 1
python3 -m macpilot --db "$DB" undo 1 --apply
```

`move --apply` requires the source file to be indexed first. MacPilot records
the original and destination paths and refuses to overwrite an existing path.
It does not provide a delete command.

### Install the package locally (optional)

Using `uv`:

```bash
uv venv
uv pip install -e .
```

Using a regular virtual environment:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e .
```

Build a wheel with:

```bash
uv build --wheel
```

## Native SwiftUI demo

Open `MacPilotDemo/MacPilotDemo.xcodeproj` in Xcode, select the shared
`MacPilotDemo` scheme, and press **Run**. The demo uses sample data and is safe
to explore.

A command-line build that does not require signing is:

```bash
xcodebuild \
  -project MacPilotDemo/MacPilotDemo.xcodeproj \
  -scheme MacPilotDemo \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/MacPilotDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

The resulting app is at:
`/tmp/MacPilotDerivedData/Build/Products/Debug/MacPilotDemo.app`.

## Project layout

```text
macpilot/                 Python core and CLI
tests/                    Standard-library unittest suite
MacPilotDemo/             Native SwiftUI sample-data application
.github/workflows/        Python and macOS CI
```

## Safety and privacy

- All indexing and search data stays in the local SQLite database.
- No network/API dependency is used by the core.
- Symlinks and common dependency directories are skipped during indexing.
- File changes require an explicit `--apply` flag and are recorded for undo.
- Review the JSON preview before applying a move.

See `CONTRIBUTING.md` for the verification checklist used before publishing
changes.
