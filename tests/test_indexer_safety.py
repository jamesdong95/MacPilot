import shutil
import unittest
from pathlib import Path

from macpilot.database import Database
from macpilot.indexer import Indexer
from macpilot.search import search


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_ROOT = PROJECT_ROOT / "tests" / ".runtime"


class IndexerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.case_root = RUNTIME_ROOT / self._testMethodName
        self.case_root.mkdir(parents=True, exist_ok=True)
        self.addCleanup(shutil.rmtree, self.case_root, ignore_errors=True)

    def test_ignores_noisy_directories_and_never_follows_symlinks(self):
        root = self.case_root / "workspace"
        root.mkdir()
        visible = root / "visible.md"
        visible.write_text("visible note", encoding="utf-8")
        binary = root / "archive.bin"
        binary.write_bytes(b"binary payload that is not text content")

        for directory_name in (".git", "node_modules"):
            ignored = root / directory_name
            ignored.mkdir()
            (ignored / "secret.md").write_text("do not index", encoding="utf-8")

        real_dir = root / "real"
        real_dir.mkdir()
        real_file = real_dir / "target.txt"
        real_file.write_text("target", encoding="utf-8")
        (root / "linked-dir").symlink_to(real_dir, target_is_directory=True)
        (root / "linked-file.txt").symlink_to(real_file)

        with Database(self.case_root / "index.sqlite3") as database:
            result = Indexer(database).index_root(root)
            records = database.list_files()
            archive_matches = search(database, "archive")
            payload_matches = search(database, "payload")

        indexed_paths = {Path(row["path"]) for row in records}
        self.assertEqual(result.indexed_files, 3)
        self.assertEqual(result.content_files, 2)
        self.assertEqual(result.skipped_symlinks, 2)
        self.assertEqual(result.ignored_directories, 2)
        self.assertIn(visible.resolve(), indexed_paths)
        self.assertIn(binary.resolve(), indexed_paths)
        self.assertIn(real_file.resolve(), indexed_paths)
        self.assertNotIn((root / ".git" / "secret.md").resolve(), indexed_paths)
        self.assertEqual([match.path for match in archive_matches], [binary.resolve()])
        self.assertEqual(payload_matches, [])
        binary_row = next(row for row in records if row["path"] == str(binary.resolve()))
        self.assertEqual(binary_row["is_text"], 0)

    def test_unchanged_fingerprint_does_not_replace_existing_fts_content(self):
        root = self.case_root / "workspace"
        root.mkdir()
        note = root / "stable.txt"
        note.write_text("original text", encoding="utf-8")
        db_path = self.case_root / "index.sqlite3"

        with Database(db_path) as database:
            first = Indexer(database).index_root(root)
            note.write_text("changed text", encoding="utf-8")
            second = Indexer(database).index_root(root)
            original_matches = search(database, "original")
            changed_matches = search(database, "changed")

        self.assertEqual(first.indexed_files, 1)
        self.assertEqual(second.indexed_files, 1)
        self.assertEqual(original_matches, [])
        self.assertEqual(len(changed_matches), 1)


if __name__ == "__main__":
    unittest.main()
