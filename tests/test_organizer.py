import errno
import shutil
import unittest
from pathlib import Path
from unittest.mock import patch

from macpilot.database import Database
from macpilot.indexer import Indexer
from macpilot.organizer import (
    _move_no_replace,
    apply_move,
    generate_suggestions,
    organize_suggestion,
    preview_move,
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

    def test_preview_rejects_source_symlink_without_resolving_it(self):
        root = self.case_root / "workspace"
        root.mkdir()
        real_source = root / "real.txt"
        source_link = root / "source-link.txt"
        destination = root / "moved.txt"
        real_source.write_text("protected", encoding="utf-8")
        source_link.symlink_to(real_source)

        with self.assertRaisesRegex(ValueError, "cannot contain a symlink"):
            preview_move(source_link, destination)

        self.assertTrue(source_link.is_symlink())
        self.assertEqual(real_source.read_text(encoding="utf-8"), "protected")
        self.assertFalse(destination.exists())

    def test_preview_rejects_broken_destination_symlink(self):
        root = self.case_root / "workspace"
        root.mkdir()
        source = root / "source.txt"
        destination_link = root / "destination-link.txt"
        source.write_text("protected", encoding="utf-8")
        destination_link.symlink_to(root / "missing.txt")

        with self.assertRaisesRegex(ValueError, "symlink"):
            preview_move(source, destination_link)

        self.assertTrue(source.exists())
        self.assertTrue(destination_link.is_symlink())

    def test_apply_rolls_back_when_index_contains_stale_destination(self):
        database, root = self._indexed_database()
        self.addCleanup(database.close)
        source = root / "invoice-january.pdf"
        destination = root / "stale-destination.pdf"
        database.upsert_file(
            path=destination,
            root_path=root,
            name=destination.name,
            extension=destination.suffix,
            size=0,
            mtime_ns=0,
            fingerprint="stale",
            is_text=False,
            content="",
        )

        with self.assertRaises(FileExistsError):
            apply_move(database, source, destination)

        self.assertTrue(source.exists())
        self.assertFalse(destination.exists())
        self.assertEqual(database.action_count(), 0)
        self.assertIsNotNone(database.file_record(source))

    def test_atomic_move_does_not_overwrite_destination_created_after_check(self):
        root = self.case_root / "workspace"
        root.mkdir()
        source = root / "source.txt"
        destination = root / "destination.txt"
        source.write_text("source", encoding="utf-8")

        def create_destination_then_race(*_args, **_kwargs):
            destination.write_text("racer", encoding="utf-8")
            raise FileExistsError(destination)

        with patch(
            "macpilot.organizer.os.link",
            side_effect=create_destination_then_race,
        ):
            with self.assertRaises(FileExistsError):
                _move_no_replace(source, destination)

        self.assertEqual(source.read_text(encoding="utf-8"), "source")
        self.assertEqual(destination.read_text(encoding="utf-8"), "racer")

    def test_cross_device_fallback_copies_without_overwriting(self):
        root = self.case_root / "workspace"
        root.mkdir()
        source = root / "source.txt"
        destination = root / "nested" / "destination.txt"
        source.write_text("source", encoding="utf-8")

        with patch(
            "macpilot.organizer.os.link",
            side_effect=OSError(errno.EXDEV, "cross-device link"),
        ):
            _move_no_replace(source, destination)

        self.assertFalse(source.exists())
        self.assertEqual(destination.read_text(encoding="utf-8"), "source")

    def test_apply_restores_file_when_database_recording_fails(self):
        database, root = self._indexed_database()
        self.addCleanup(database.close)
        source = root / "invoice-january.pdf"
        destination = root / "organized.pdf"

        with patch.object(
            database,
            "record_applied_move",
            side_effect=RuntimeError("database failure"),
        ):
            with self.assertRaisesRegex(RuntimeError, "database failure"):
                apply_move(database, source, destination)

        self.assertTrue(source.exists())
        self.assertFalse(destination.exists())
        self.assertEqual(database.action_count(), 0)
        self.assertEqual(database.list_suggestions(), [])

    def test_manual_apply_does_not_leave_suggestion_when_move_races(self):
        database, root = self._indexed_database()
        self.addCleanup(database.close)
        source = root / "invoice-january.pdf"
        destination = root / "organized.pdf"

        def create_destination_then_race(*_args, **_kwargs):
            destination.write_text("racer", encoding="utf-8")
            raise FileExistsError(destination)

        with patch(
            "macpilot.organizer.os.link",
            side_effect=create_destination_then_race,
        ):
            with self.assertRaises(FileExistsError):
                apply_move(database, source, destination)

        self.assertTrue(source.exists())
        self.assertEqual(destination.read_text(encoding="utf-8"), "racer")
        self.assertEqual(database.list_suggestions(), [])

    def test_manual_apply_cannot_reuse_an_undone_suggestion(self):
        database, root = self._indexed_database()
        self.addCleanup(database.close)
        source = root / "invoice-january.pdf"
        destination = root / "organized.pdf"

        applied = apply_move(database, source, destination)
        assert applied.action_id is not None
        undo_action(database, applied.action_id, apply=True)

        with self.assertRaisesRegex(ValueError, "already undone"):
            apply_move(database, source, destination)

        self.assertTrue(source.exists())
        self.assertFalse(destination.exists())
        self.assertEqual(database.action_count(undone=False), 0)
        self.assertEqual(database.action_count(undone=True), 1)

    def test_undo_restores_filesystem_when_database_recording_fails(self):
        database, _root = self._indexed_database()
        self.addCleanup(database.close)
        suggestion = generate_suggestions(database)[0]
        applied = organize_suggestion(database, suggestion.id, apply=True)
        action_id = applied.action_id
        assert action_id is not None

        with patch.object(
            database,
            "record_undone_move",
            side_effect=RuntimeError("database failure"),
        ):
            with self.assertRaisesRegex(RuntimeError, "database failure"):
                undo_action(database, action_id, apply=True)

        self.assertFalse(applied.source_path.exists())
        self.assertTrue(applied.destination_path.exists())
        self.assertEqual(database.action_count(undone=False), 1)

    def test_undo_rejects_a_symlink_at_the_original_destination(self):
        database, root = self._indexed_database()
        self.addCleanup(database.close)
        suggestion = generate_suggestions(database)[0]
        applied = organize_suggestion(database, suggestion.id, apply=True)
        action_id = applied.action_id
        assert action_id is not None
        malicious_target = root / "malicious-target.txt"
        malicious_target.write_text("protected", encoding="utf-8")
        applied.source_path.symlink_to(malicious_target)

        with self.assertRaisesRegex(ValueError, "symlink"):
            undo_action(database, action_id, apply=True)

        self.assertTrue(applied.source_path.is_symlink())
        self.assertTrue(applied.destination_path.exists())
        self.assertEqual(malicious_target.read_text(encoding="utf-8"), "protected")


if __name__ == "__main__":
    unittest.main()
