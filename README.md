# MacPilot

Local-first file search and safe organization for macOS.

The first milestone is a dependency-free Python core that can be verified with
Python's standard library. It indexes user-selected folders into SQLite FTS5,
searches file names and text content, produces deterministic organization
suggestions, and requires an explicit flag before moving files.

## Current status

- [x] SQLite metadata index
- [x] FTS5 filename/content search
- [x] Background-friendly folder indexer
- [x] Deterministic organization suggestions
- [x] Preview before move
- [x] Action log and undo
- [ ] Ollama embeddings and semantic ranking
- [ ] Native SwiftUI application

## Run from source

```bash
python3 -m macpilot --db /tmp/macpilot.sqlite3 index ~/Downloads
python3 -m macpilot --db /tmp/macpilot.sqlite3 search "project contract"
python3 -m macpilot --db /tmp/macpilot.sqlite3 suggest ~/Downloads
```

A move is preview-only by default:

```bash
python3 -m macpilot move ~/Downloads/report.pdf ~/Documents/Reports/report.pdf
python3 -m macpilot --db /tmp/macpilot.sqlite3 move \
  ~/Downloads/report.pdf ~/Documents/Reports/report.pdf --apply
python3 -m macpilot --db /tmp/macpilot.sqlite3 undo 1
```

The core does not delete files and does not make network requests.

## Native SwiftUI demo

A native Xcode project is available at `MacPilotDemo/MacPilotDemo.xcodeproj`.
Open it with Xcode 15 or newer and run the shared `MacPilotDemo` scheme. The UI is a safe sample-data demo of search, suggestions, and undoable activity history; it does not touch real files.
