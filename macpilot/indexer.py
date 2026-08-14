from __future__ import annotations

import hashlib
import os
from collections.abc import Callable
from pathlib import Path

from .database import Database
from .models import IndexSummary


TEXT_EXTENSIONS = {
    ".c", ".css", ".csv", ".go", ".h", ".html", ".htm", ".java", ".js",
    ".json", ".md", ".markdown", ".py", ".rs", ".sh", ".swift", ".toml",
    ".ts", ".tsx", ".txt", ".xml", ".yaml", ".yml",
}

EXCLUDED_DIRECTORIES = {
    ".git", ".hg", ".svn", ".tox", ".venv", "__pycache__", "node_modules",
}

MAX_TEXT_BYTES = 4 * 1024 * 1024


class Indexer:
    def __init__(self, database: Database):
        self.database = database

    def index_root(
        self,
        root: Path | str,
        progress: "Callable[[int], None] | None" = None,
    ) -> IndexSummary:
        root_path = Path(root).expanduser().resolve()
        if not root_path.is_dir():
            raise ValueError(f"Index root is not a directory: {root_path}")

        indexed = 0
        skipped = 0
        content_files = 0
        skipped_symlinks = 0
        ignored_directories = 0
        processed = 0
        seen: list[Path] = []
        walk_errors = [0]

        def _on_walk_error(error: OSError) -> None:
            # Permission-denied / unreadable directories are counted, not fatal.
            walk_errors[0] += 1

        for current, directories, filenames in os.walk(
            root_path, followlinks=False, onerror=_on_walk_error
        ):
            current_path = Path(current)
            allowed_directories: list[str] = []
            for name in directories:
                candidate = current_path / name
                if name in EXCLUDED_DIRECTORIES:
                    ignored_directories += 1
                elif candidate.is_symlink():
                    skipped_symlinks += 1
                else:
                    allowed_directories.append(name)
            directories[:] = allowed_directories

            for filename in filenames:
                # iCloud Drive placeholders end in ".icloud"; reading one
                # forces a download, so skip them instead of stalling.
                if filename.endswith(".icloud"):
                    skipped += 1
                    continue
                path = current_path / filename
                if path.is_symlink():
                    skipped_symlinks += 1
                    continue
                try:
                    stat = path.stat()
                    if not path.is_file():
                        skipped += 1
                        continue
                    content, fingerprint, is_text = self._read_content(
                        path, stat.st_size, stat.st_mtime_ns
                    )
                    changed = self.database.upsert_file(
                        path=path.resolve(),
                        root_path=root_path,
                        name=path.name,
                        extension=path.suffix.lower(),
                        size=stat.st_size,
                        mtime_ns=stat.st_mtime_ns,
                        fingerprint=fingerprint,
                        is_text=is_text,
                        content=content,
                    )
                    resolved = path.resolve()
                    seen.append(resolved)
                    indexed += int(changed)
                    content_files += int(is_text)
                except (OSError, UnicodeError):
                    # A file that disappears mid-walk, loses permission, or is
                    # being written while indexed is skipped, never fatal.
                    skipped += 1
                processed += 1
                if progress is not None and processed % 50 == 0:
                    progress(processed)

        ignored_directories += walk_errors[0]
        removed = self.database.remove_missing(root_path, seen)
        return IndexSummary(
            root=root_path,
            indexed_files=indexed,
            skipped_files=skipped,
            removed_files=removed,
            content_files=content_files,
            skipped_symlinks=skipped_symlinks,
            ignored_directories=ignored_directories,
        )

    @staticmethod
    def _read_content(path: Path, size: int, mtime_ns: int) -> tuple[str, str, bool]:
        if path.suffix.lower() not in TEXT_EXTENSIONS or size > MAX_TEXT_BYTES:
            return "", f"binary:{size}:{mtime_ns}", False
        data = path.read_bytes()
        if b"\x00" in data:
            return "", f"binary:{size}:{mtime_ns}", False
        content = data.decode("utf-8", errors="replace")
        return content, hashlib.sha256(data).hexdigest(), True
