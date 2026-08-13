from __future__ import annotations

import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from typing import Any

from macpilot.cli import main


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name) / "workspace"
        self.workspace.mkdir()
        self.database = Path(self.temp_dir.name) / "macpilot.sqlite3"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def run_cli(self, *arguments: str) -> tuple[int, Any, str]:
        stdout = StringIO()
        stderr = StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = main(["--db", str(self.database), *arguments])
        payload = json.loads(stdout.getvalue()) if stdout.getvalue().strip() else None
        return exit_code, payload, stderr.getvalue()

    def test_status_and_actions_make_the_safe_flow_discoverable(self) -> None:
        source = self.workspace / "report.txt"
        destination = self.workspace / "organized" / "report.txt"
        source.write_text("quarterly report", encoding="utf-8")

        exit_code, index_payload, error = self.run_cli("index", str(self.workspace))
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(index_payload["indexed_files"], 1)

        exit_code, move_payload, error = self.run_cli(
            "move", str(source), str(destination), "--apply"
        )
        self.assertEqual(exit_code, 0, error)
        action_id = move_payload["action_id"]
        self.assertEqual(move_payload["mode"], "applied")
        self.assertFalse(source.exists())
        self.assertTrue(destination.exists())

        exit_code, status_payload, error = self.run_cli("status")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(status_payload["files"], 1)
        self.assertEqual(status_payload["active_actions"], 1)

        exit_code, actions_payload, error = self.run_cli("actions", "--active-only")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(len(actions_payload), 1)
        self.assertEqual(actions_payload[0]["id"], action_id)

        exit_code, undo_payload, error = self.run_cli("undo", str(action_id))
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(undo_payload["mode"], "preview")
        self.assertFalse(source.exists())
        self.assertTrue(destination.exists())

        exit_code, undo_payload, error = self.run_cli("undo", str(action_id), "--apply")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(undo_payload["mode"], "applied")
        self.assertTrue(source.exists())
        self.assertFalse(destination.exists())

    def test_read_only_payloads_have_stable_shapes(self) -> None:
        invoice_one = self.workspace / "invoice-january.pdf"
        invoice_two = self.workspace / "invoice-february.pdf"
        notes = self.workspace / "project-notes.txt"
        invoice_one.write_bytes(b"pdf-one")
        invoice_two.write_bytes(b"pdf-two")
        notes.write_text("project launch checklist", encoding="utf-8")

        exit_code, index_payload, error = self.run_cli("index", str(self.workspace))
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(
            set(index_payload),
            {
                "root",
                "indexed_files",
                "skipped_files",
                "removed_files",
                "content_files",
                "skipped_symlinks",
                "ignored_directories",
            },
        )

        exit_code, list_payload, error = self.run_cli("list", "--root", str(self.workspace))
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(len(list_payload), 3)
        self.assertEqual(
            set(list_payload[0]),
            {"file_id", "path", "filename", "extension", "size", "modified_at", "snippet", "score", "is_text"},
        )

        exit_code, search_payload, error = self.run_cli("search", "invoice")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(len(search_payload), 2)
        self.assertEqual(set(search_payload[0]), set(list_payload[0]))

        exit_code, suggest_payload, error = self.run_cli("suggest", str(self.workspace))
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(len(suggest_payload), 1)
        self.assertEqual(
            set(suggest_payload[0]),
            {"category", "destination", "files", "reason"},
        )
        self.assertEqual(suggest_payload[0]["category"], "Documents/PDF")

        destination = self.workspace / "Organized" / "invoice-january.pdf"
        exit_code, preview_payload, error = self.run_cli(
            "move", str(invoice_one), str(destination)
        )
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(
            set(preview_payload), {"action_id", "source", "destination", "mode"}
        )
        self.assertEqual(preview_payload["mode"], "preview")
        self.assertTrue(invoice_one.exists())
        self.assertFalse(destination.exists())

        exit_code, status_payload, error = self.run_cli("status")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(
            set(status_payload),
            {"files", "pending_suggestions", "active_actions", "undone_actions"},
        )
        self.assertEqual(status_payload["active_actions"], 0)

        exit_code, actions_payload, error = self.run_cli("actions")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(actions_payload, [])

    def test_applied_payloads_have_stable_shapes(self) -> None:
        source = self.workspace / "invoice.txt"
        destination = self.workspace / "Organized" / "invoice.txt"
        source.write_text("invoice body", encoding="utf-8")

        exit_code, _, error = self.run_cli("index", str(self.workspace))
        self.assertEqual(exit_code, 0, error)

        exit_code, move_payload, error = self.run_cli(
            "move", str(source), str(destination), "--apply"
        )
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(
            set(move_payload),
            {"applied", "action_id", "source_path", "destination_path", "mode"},
        )
        self.assertEqual(move_payload["mode"], "applied")
        self.assertIs(move_payload["applied"], True)
        self.assertGreater(move_payload["action_id"], 0)
        action_id = move_payload["action_id"]

        exit_code, undo_payload, error = self.run_cli("undo", str(action_id), "--apply")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(
            set(undo_payload),
            {"applied", "action_id", "source_path", "destination_path", "mode"},
        )
        self.assertEqual(undo_payload["mode"], "applied")
        self.assertIs(undo_payload["applied"], True)

    def test_search_rejects_non_positive_limit(self) -> None:
        exit_code, payload, error = self.run_cli("search", "report", "--limit", "0")
        self.assertEqual(exit_code, 2)
        self.assertIsNone(payload)
        self.assertIn("limit must be between 1 and 200", error)

    def test_duplicates_groups_identical_content(self) -> None:
        first = self.workspace / "copy-a.txt"
        second = self.workspace / "copy-b.txt"
        distinct = self.workspace / "distinct.txt"
        first.write_text("same content", encoding="utf-8")
        second.write_text("same content", encoding="utf-8")
        distinct.write_text("different content", encoding="utf-8")

        exit_code, _, error = self.run_cli("index", str(self.workspace))
        self.assertEqual(exit_code, 0, error)

        exit_code, payload, error = self.run_cli("duplicates")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(len(payload), 1)
        group = payload[0]
        self.assertEqual(set(group), {"fingerprint", "size", "paths"})
        self.assertEqual(len(group["paths"]), 2)
        self.assertEqual(
            set(Path(p).name for p in group["paths"]),
            {"copy-a.txt", "copy-b.txt"},
        )

    def test_rules_add_list_remove_and_apply(self) -> None:
        pdf_one = self.workspace / "one.pdf"
        pdf_two = self.workspace / "two.pdf"
        pdf_one.write_bytes(b"pdf-one")
        pdf_two.write_bytes(b"pdf-two")

        exit_code, _, error = self.run_cli("index", str(self.workspace))
        self.assertEqual(exit_code, 0, error)

        exit_code, payload, error = self.run_cli("rules", "list")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(payload, [])

        rule_dest = self.workspace / "PDFs"
        exit_code, payload, error = self.run_cli(
            "rules", "add", "*.pdf", str(rule_dest)
        )
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(set(payload), {"id", "pattern", "destination"})
        rule_id = payload["id"]

        exit_code, payload, error = self.run_cli("rules", "list")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(len(payload), 1)
        self.assertEqual(payload[0]["pattern"], "*.pdf")

        exit_code, suggest_payload, error = self.run_cli("suggest", str(self.workspace))
        self.assertEqual(exit_code, 0, error)
        rule_groups = [g for g in suggest_payload if g["category"] == "Rule: *.pdf"]
        self.assertEqual(len(rule_groups), 1)
        self.assertEqual(Path(rule_groups[0]["destination"]), rule_dest)
        self.assertEqual(len(rule_groups[0]["files"]), 2)

        exit_code, payload, error = self.run_cli("rules", "remove", str(rule_id))
        self.assertEqual(exit_code, 0, error)
        self.assertIs(payload["removed"], True)

        exit_code, payload, error = self.run_cli("rules", "list")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(payload, [])

    def test_rename_batch_preview_apply_and_undo(self) -> None:
        first = self.workspace / "photo-1.txt"
        second = self.workspace / "photo-2.txt"
        first.write_text("one", encoding="utf-8")
        second.write_text("two", encoding="utf-8")

        exit_code, _, error = self.run_cli("index", str(self.workspace))
        self.assertEqual(exit_code, 0, error)

        exit_code, payload, error = self.run_cli(
            "rename", str(self.workspace), "photo", "pic"
        )
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(payload["mode"], "preview")
        self.assertEqual(payload["count"], 2)
        self.assertTrue(first.exists())
        self.assertFalse((self.workspace / "pic-1.txt").exists())

        exit_code, payload, error = self.run_cli(
            "rename", str(self.workspace), "photo", "pic", "--apply"
        )
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(payload["mode"], "applied")
        self.assertEqual(payload["count"], 2)
        self.assertFalse(first.exists())
        self.assertTrue((self.workspace / "pic-1.txt").exists())
        self.assertTrue((self.workspace / "pic-2.txt").exists())
        action_id = payload["renames"][0]["action_id"]
        self.assertGreater(action_id, 0)

        exit_code, undo_payload, error = self.run_cli("undo", str(action_id), "--apply")
        self.assertEqual(exit_code, 0, error)
        self.assertTrue(first.exists())
        self.assertFalse((self.workspace / "pic-1.txt").exists())

    def test_undo_all_reverts_every_active_action(self) -> None:
        first = self.workspace / "a.txt"
        second = self.workspace / "b.txt"
        first.write_text("a", encoding="utf-8")
        second.write_text("b", encoding="utf-8")
        dest_a = self.workspace / "organized" / "a.txt"
        dest_b = self.workspace / "organized" / "b.txt"

        exit_code, _, error = self.run_cli("index", str(self.workspace))
        self.assertEqual(exit_code, 0, error)
        exit_code, _, error = self.run_cli("move", str(first), str(dest_a), "--apply")
        self.assertEqual(exit_code, 0, error)
        exit_code, _, error = self.run_cli("move", str(second), str(dest_b), "--apply")
        self.assertEqual(exit_code, 0, error)

        exit_code, payload, error = self.run_cli("undo-all")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(payload["mode"], "preview")
        self.assertEqual(payload["count"], 2)

        exit_code, payload, error = self.run_cli("undo-all", "--apply")
        self.assertEqual(exit_code, 0, error)
        self.assertEqual(payload["mode"], "applied")
        self.assertEqual(payload["count"], 2)
        self.assertTrue(first.exists())
        self.assertTrue(second.exists())
        self.assertFalse(dest_a.exists())
        self.assertFalse(dest_b.exists())

    def test_trash_preview_apply_and_undo(self) -> None:
        import os

        source = self.workspace / "notes.txt"
        source.write_text("scratch notes", encoding="utf-8")
        trash_dir = Path(self.temp_dir.name) / "Trash"

        exit_code, _, error = self.run_cli("index", str(self.workspace))
        self.assertEqual(exit_code, 0, error)

        old_trash = os.environ.get("MACPILOT_TRASH")
        os.environ["MACPILOT_TRASH"] = str(trash_dir)
        try:
            exit_code, preview_payload, error = self.run_cli("trash", str(source))
            self.assertEqual(exit_code, 0, error)
            self.assertEqual(preview_payload["mode"], "preview")
            self.assertTrue(source.exists())
            self.assertFalse((trash_dir / "notes.txt").exists())

            exit_code, apply_payload, error = self.run_cli("trash", str(source), "--apply")
            self.assertEqual(exit_code, 0, error)
            self.assertEqual(
                set(apply_payload),
                {"applied", "action_id", "source_path", "destination_path", "mode"},
            )
            self.assertIs(apply_payload["applied"], True)
            self.assertEqual(apply_payload["mode"], "applied")
            self.assertFalse(source.exists())
            self.assertTrue((trash_dir / "notes.txt").exists())

            exit_code, undo_payload, error = self.run_cli(
                "undo", str(apply_payload["action_id"]), "--apply"
            )
            self.assertEqual(exit_code, 0, error)
            self.assertTrue(source.exists())
            self.assertFalse((trash_dir / "notes.txt").exists())
        finally:
            if old_trash is None:
                os.environ.pop("MACPILOT_TRASH", None)
            else:
                os.environ["MACPILOT_TRASH"] = old_trash

    def test_summarize_via_mock_ollama(self) -> None:
        import json as _json
        import os as _os
        import threading
        from http.server import BaseHTTPRequestHandler, HTTPServer

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(length)
                body = _json.dumps(
                    {"response": "A concise mock summary.", "done": True}
                ).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args: object) -> None:
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        port = server.server_address[1]

        source = self.workspace / "doc.txt"
        source.write_text("A long document that needs summarizing.", encoding="utf-8")

        old_url = _os.environ.get("MACPILOT_OLLAMA_URL")
        _os.environ["MACPILOT_OLLAMA_URL"] = f"http://127.0.0.1:{port}"
        try:
            exit_code, payload, error = self.run_cli("summarize", str(source))
            self.assertEqual(exit_code, 0, error)
            self.assertEqual(payload["summary"], "A concise mock summary.")
            self.assertEqual(payload["path"], str(source))
        finally:
            server.shutdown()
            server.server_close()
            if old_url is None:
                _os.environ.pop("MACPILOT_OLLAMA_URL", None)
            else:
                _os.environ["MACPILOT_OLLAMA_URL"] = old_url

    def test_summarize_fails_gracefully_without_ollama(self) -> None:
        import os as _os

        source = self.workspace / "doc.txt"
        source.write_text("content", encoding="utf-8")

        old_url = _os.environ.get("MACPILOT_OLLAMA_URL")
        _os.environ["MACPILOT_OLLAMA_URL"] = "http://127.0.0.1:1"
        try:
            exit_code, payload, error = self.run_cli("summarize", str(source))
            self.assertEqual(exit_code, 2)
            self.assertIsNone(payload)
            self.assertIn("Ollama is not reachable", error)
        finally:
            if old_url is None:
                _os.environ.pop("MACPILOT_OLLAMA_URL", None)
            else:
                _os.environ["MACPILOT_OLLAMA_URL"] = old_url


if __name__ == "__main__":
    unittest.main()
