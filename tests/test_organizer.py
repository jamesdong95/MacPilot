import shutil
import unittest
from pathlib import Path

from macpilot.database import Database
from macpilot.indexer import Indexer
from macpilot.organizer import (
    generate_suggestions,
    organize_suggestion,
    undo_action,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_ROOT = PROJECT_ROOT / "tests" / ".runtime"


class OrganizerTests(unittest.TestCase):
    def setUp(self):
        self.case_root = RUNTIME_ROOT / self._testMethodName
        self.case_root.mkdir(parents=True, exist_ok=True)
        self.addCleanup(shutil.rmtree, self.case_root, ignore_errors=True)

    def _indexed_database(self):
        root = self.case_root / "workspace"
        root.mkdir()
        (root / "invoice-january.pdf").write_bytes(b"January invoice")
        (root / "invoice-february.pdf").write_bytes(b"February invoice")
        (root / "todo.md").write_text("Remember lunch", encoding="utf-8")
        database = Database(self.case_root / "index.sqlite3")
        Indexer(database).index_root(root)
        return database, root

    def test_suggestions_are_deterministic_and_group_keyword_with_extension(self):
        database, root = self._indexed_database()
        self.addCleanup(database.close)

        first = generate_suggestions(database)
        second = generate_suggestions(database)

        first_view = [
            (item.id, item.source_path, item.destination_path, item.reason)
            for item in first
        ]
        second_view = [
            (item.id, item.source_path, item.destination_path, item.reason)
            for item in second
        ]
        self.assertEqual(first_view, second_view)
        self.assertEqual(len(first), 3)
        invoice_suggestions = [
            item for item in first if item.source_path.suffix == ".pdf"
        ]
        self.assertEqual(
            {item.destination_path.parent for item in invoice_suggestions},
            {root / "Organized" / "invoice-pdf"},
        )
        self.assertTrue(all(item.status == "pending" for item in first))

    def test_organize_dry_run_does_not_move_or_log_an_action(self):
        database, _root = self._indexed_database()
        self.addCleanup(database.close)
        suggestion = generate_suggestions(database)[0]

        result = organize_suggestion(database, suggestion.id, apply=False)

        self.assertFalse(result.applied)
        self.assertTrue(result.source_path.exists())
        self.assertFalse(result.destination_path.exists())
        self.assertEqual(database.action_count(), 0)

    def test_apply_moves_file_and_records_undoable_action(self):
        database, _root = self._indexed_database()
        self.addCleanup(database.close)
        suggestion = generate_suggestions(database)[0]

        result = organize_suggestion(database, suggestion.id, apply=True)

        self.assertTrue(result.applied)
        self.assertIsNotNone(result.action_id)
        self.assertFalse(result.source_path.exists())
        self.assertTrue(result.destination_path.exists())
        self.assertEqual(database.action_count(), 1)
        self.assertEqual(database.file_record(result.destination_path)["path"], str(result.destination_path))

    def test_undo_requires_apply_and_restores_the_original_path(self):
        database, _root = self._indexed_database()
        self.addCleanup(database.close)
        suggestion = generate_suggestions(database)[0]
        applied = organize_suggestion(database, suggestion.id, apply=True)

        preview = undo_action(database, applied.action_id, apply=False)
        self.assertFalse(preview.applied)
        self.assertTrue(preview.source_path.exists())
        self.assertFalse(preview.destination_path.exists())

        undone = undo_action(database, applied.action_id, apply=True)
        self.assertTrue(undone.applied)
        self.assertTrue(undone.destination_path.exists())
        self.assertFalse(undone.source_path.exists())
        self.assertEqual(database.action_count(undone=False), 0)


if __name__ == "__main__":
    unittest.main()
