import Foundation

// Bridge harness: exercises MacPilotClient against a real temp fixture and an
// isolated SQLite database. Exits non-zero on any assertion failure.
// Build: swiftc MacPilotDemo/Sources/MacPilotClient.swift MacPilotDemo/Tests/BridgeHarness/main.swift -o macpilot-bridge-harness
// Run:   MACPILOT_PROJECT_ROOT=/path/to/MacPilot ./macpilot-bridge-harness

let fileManager = FileManager.default

func temporaryDirectory(_ label: String) -> URL {
    fileManager.temporaryDirectory
        .appendingPathComponent("macpilot-harness-\(label)-\(UUID().uuidString)")
}

let fixtureRoot = temporaryDirectory("fixture")
let databaseURL = temporaryDirectory("db").appendingPathComponent("index.sqlite3")
try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: fixtureRoot) }
defer { try? fileManager.removeItem(at: databaseURL.deletingLastPathComponent()) }

func writeFixture(_ name: String, _ content: String) throws -> URL {
    let url = fixtureRoot.appendingPathComponent(name)
    try Data(content.utf8).write(to: url)
    return url
}

let invoiceJanuary = try writeFixture("invoice-january.pdf", "pdf-one")
let invoiceFebruary = try writeFixture("invoice-february.pdf", "pdf-two")
let meetingNotes = try writeFixture("meeting-notes.txt", "quarterly meeting notes")
let launchChecklist = try writeFixture("project-launch-checklist.md", "project launch checklist")

// Discovery must come from the parent environment (CI sets MACPILOT_PROJECT_ROOT).
setenv("MACPILOT_DB", databaseURL.path, 1)
guard let client = MacPilotClient.discover() else {
    print("FAIL | core discovery | set MACPILOT_PROJECT_ROOT / MACPILOT_CLI")
    exit(1)
}

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print(condition ? "PASS | \(label)" : "FAIL | \(label)")
    if !condition {
        failures += 1
    }
}

let projectRoot = URL(fileURLWithPath: fixtureRoot.path)
let destinationDir = fixtureRoot.appendingPathComponent("Documents/PDF", isDirectory: true)
let destination = destinationDir.appendingPathComponent("invoice-january.pdf").path
let source = invoiceJanuary.path

try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    Task {
        do {
            // 1. index returns the expected count
            let summary = try await client.index(root: projectRoot)
            check(summary.indexedFiles == 4, "index returns 4 files")

            // 2. list returns every fixture file
            let listed = try await client.list(root: projectRoot)
            check(listed.count == 4, "list returns every fixture file")

            // 3. search returns filename and content matches
            let byName = try await client.search(query: "invoice")
            check(byName.count == 2, "search finds both invoice files")
            let byContent = try await client.search(query: "checklist")
            check(byContent.count == 1, "search finds content match (checklist)")

            // 4. suggest returns deterministic category groups
            let suggestions = try await client.suggestions(root: projectRoot)
            check(
                suggestions.contains { $0.category == "Documents/PDF" && $0.files.count == 2 },
                "suggest groups the two PDFs"
            )
            check(
                suggestions.contains { $0.category == "Text" && $0.files.count == 2 },
                "suggest groups the two text files"
            )

            // 5. move without --apply returns mode == "preview"
            let preview = try await client.previewMove(source: source, destination: destination)
            check(preview.mode == "preview", "preview move reports mode == preview")

            // 6. source bytes are identical after preview
            let sourceAfterPreview = try Data(contentsOf: invoiceJanuary)
            check(sourceAfterPreview == Data("pdf-one".utf8), "source bytes identical after preview")

            // 7. destination is absent after preview
            check(!fileManager.fileExists(atPath: destination), "destination absent after preview")

            // 8. status has zero active actions and the action log is empty
            let idleStatus = try await client.status()
            check(idleStatus.activeActions == 0, "status reports zero active actions")
            let idleActions = try await client.actions()
            check(idleActions.isEmpty, "action log is empty before apply")

            // 9. apply moves the file and confirms mode == applied
            let applyOutcome = try await client.applyMove(source: source, destination: destination)
            check(applyOutcome.applied, "apply confirms applied == true")
            check(applyOutcome.mode == "applied", "apply reports mode == applied")
            check(!fileManager.fileExists(atPath: source), "source gone after apply")
            check(fileManager.fileExists(atPath: destination), "destination exists after apply")

            // 10. the action log records the applied move
            let recorded = try await client.actions()
            check(recorded.count == 1, "action log records the applied move")
            guard let action = recorded.first else {
                continuation.resume()
                return
            }
            check(action.undoneAt == nil, "action is not yet undone")

            // 11. undo restores the file to its original location
            let undoOutcome = try await client.undo(actionID: action.id)
            check(undoOutcome.applied, "undo confirms applied == true")
            check(undoOutcome.mode == "applied", "undo reports mode == applied")
            check(fileManager.fileExists(atPath: source), "source restored after undo")
            check(!fileManager.fileExists(atPath: destination), "destination gone after undo")

            // 12. the action is marked undone
            let finalStatus = try await client.status()
            check(finalStatus.activeActions == 0, "no active actions after undo")
            check(finalStatus.undoneActions == 1, "undo recorded in status")
            let finalActions = try await client.actions()
            check(finalActions.count == 1 && finalActions[0].undoneAt != nil, "action marked undone")

            continuation.resume()
        } catch {
            print("FAIL | harness error: \(error)")
            failures += 1
            continuation.resume()
        }
    }
}

print(failures == 0 ? "HARNESS_ALL_PASS" : "HARNESS_FAILURES=\(failures)")
exit(failures == 0 ? 0 : 1)
