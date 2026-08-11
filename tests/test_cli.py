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

    def test_search_rejects_non_positive_limit(self) -> None:
        exit_code, payload, error = self.run_cli("search", "report", "--limit", "0")
        self.assertEqual(exit_code, 2)
        self.assertIsNone(payload)
        self.assertIn("limit must be between 1 and 200", error)


if __name__ == "__main__":
    unittest.main()
