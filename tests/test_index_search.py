import shutil
import unittest
from pathlib import Path

from macpilot.database import Database
from macpilot.indexer import Indexer
from macpilot.search import search


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_ROOT = PROJECT_ROOT / "tests" / ".runtime"


class IndexSearchTests(unittest.TestCase):
    def setUp(self):
        self.case_root = RUNTIME_ROOT / self._testMethodName
        self.case_root.mkdir(parents=True, exist_ok=True)
        self.addCleanup(shutil.rmtree, self.case_root, ignore_errors=True)

    def test_indexed_filename_and_text_are_searchable(self):
        root = self.case_root / "workspace"
        root.mkdir()
        note = root / "project-notes.md"
        note.write_text("Remember the MacPilot launch checklist.", encoding="utf-8")
        db_path = self.case_root / "index.sqlite3"

        with Database(db_path) as database:
            result = Indexer(database).index_root(root)
            matches = search(database, "launch checklist")

        self.assertEqual(result.indexed_files, 1)
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0].path, note.resolve())
        self.assertIn("launch", matches[0].snippet.lower())
        self.assertIn("checklist", matches[0].snippet.lower())


if __name__ == "__main__":
    unittest.main()
