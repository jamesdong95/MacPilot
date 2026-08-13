"""SQLite persistence for the MacPilot local-first core."""

from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Any


class Database:
    """A small SQLite repository with FTS5 and an undoable action log."""

    def __init__(self, path: str | Path):
        self.path = Path(path).expanduser().resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(str(self.path))
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA foreign_keys = ON")
        self._closed = False
        try:
            self.connection.execute(
                "CREATE VIRTUAL TABLE temp.macpilot_fts5_check USING fts5(value)"
            )
            self.connection.execute("DROP TABLE temp.macpilot_fts5_check")
        except sqlite3.OperationalError as exc:
            self.connection.close()
            self._closed = True
            raise RuntimeError(
                "MacPilot requires a SQLite build with FTS5 support."
            ) from exc
        self._initialize_schema()

    def _initialize_schema(self) -> None:
        connection = self._ensure_open()
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                root_path TEXT NOT NULL DEFAULT '',
                name TEXT NOT NULL,
                extension TEXT NOT NULL,
                size INTEGER NOT NULL,
                mtime_ns INTEGER NOT NULL,
                fingerprint TEXT NOT NULL,
                is_text INTEGER NOT NULL CHECK (is_text IN (0, 1)),
                indexed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS file_fts USING fts5(
                name,
                content,
                tokenize = 'unicode61'
            );

            CREATE TABLE IF NOT EXISTS suggestions (
                id INTEGER PRIMARY KEY,
                source_path TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                group_key TEXT NOT NULL,
                reason TEXT NOT NULL,
                fingerprint TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'applied', 'undone')),
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(source_path, destination_path)
            );

            CREATE TABLE IF NOT EXISTS actions (
                id INTEGER PRIMARY KEY,
                suggestion_id INTEGER NOT NULL,
                source_path TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                fingerprint TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                undone_at TEXT,
                FOREIGN KEY (suggestion_id) REFERENCES suggestions(id)
            );

            CREATE INDEX IF NOT EXISTS idx_files_root_path ON files(root_path);
            CREATE INDEX IF NOT EXISTS idx_suggestions_status
                ON suggestions(status);
            CREATE INDEX IF NOT EXISTS idx_actions_undone_at
                ON actions(undone_at);
            """
        )
        columns = {
            row[1] for row in connection.execute("PRAGMA table_info(files)")
        }
        if "root_path" not in columns:
            connection.execute(
                "ALTER TABLE files ADD COLUMN root_path TEXT NOT NULL DEFAULT ''"
            )
        connection.commit()

    def __enter__(self) -> "Database":
        return self

    def __exit__(self, exc_type: Any, exc_value: Any, traceback: Any) -> None:
        self.close()

    def close(self) -> None:
        if not self._closed:
            self.connection.close()
            self._closed = True

    def _ensure_open(self) -> sqlite3.Connection:
        if self._closed:
            raise RuntimeError("The MacPilot database is closed.")
        return self.connection

    def rollback(self) -> None:
        """Roll back the current transaction, if one is open."""
        self._ensure_open().rollback()

    def file_record(self, path: str | Path) -> sqlite3.Row | None:
        connection = self._ensure_open()
        return connection.execute(
            "SELECT * FROM files WHERE path = ?", (str(Path(path).resolve()),)
        ).fetchone()

    def list_files(self, *, root_path: str | Path | None = None) -> list[sqlite3.Row]:
        connection = self._ensure_open()
        if root_path is None:
            return connection.execute(
                "SELECT * FROM files ORDER BY path COLLATE NOCASE"
            ).fetchall()
        normalized_root = str(Path(root_path).resolve())
        return connection.execute(
            """
            SELECT * FROM files
            WHERE root_path = ?
            ORDER BY path COLLATE NOCASE
            """,
            (normalized_root,),
        ).fetchall()

    def duplicate_groups(self) -> list[dict[str, Any]]:
        """Group indexed text files by identical content (SHA-256 fingerprint)."""
        connection = self._ensure_open()
        rows = connection.execute(
            """
            SELECT fingerprint, size, COUNT(*) AS count,
                   GROUP_CONCAT(path, ?) AS paths
            FROM files
            WHERE fingerprint != '' AND fingerprint NOT LIKE 'binary:%'
            GROUP BY fingerprint
            HAVING count > 1
            ORDER BY size DESC
            """,
            ("\x1f",),
        ).fetchall()
        return [
            {
                "fingerprint": row["fingerprint"],
                "size": int(row["size"]),
                "paths": row["paths"].split("\x1f"),
            }
            for row in rows
        ]

    def upsert_file(
        self,
        *,
        path: str | Path,
        root_path: str | Path = "",
        name: str,
        extension: str,
        size: int,
        mtime_ns: int,
        fingerprint: str,
        is_text: bool,
        content: str,
    ) -> bool:
        """Store a file and its FTS row, returning whether its fingerprint changed."""
        connection = self._ensure_open()
        normalized_path = str(Path(path).resolve())
        normalized_root = (
            str(Path(root_path).resolve()) if root_path else ""
        )
        existing = connection.execute(
            "SELECT id, fingerprint FROM files WHERE path = ?", (normalized_path,)
        ).fetchone()
        if existing is not None and existing["fingerprint"] == fingerprint:
            return False

        if existing is None:
            cursor = connection.execute(
                """
                INSERT INTO files
                    (path, root_path, name, extension, size, mtime_ns,
                     fingerprint, is_text)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    normalized_path,
                    normalized_root,
                    name,
                    extension,
                    size,
                    mtime_ns,
                    fingerprint,
                    int(is_text),
                ),
            )
            file_id = cursor.lastrowid
        else:
            file_id = existing["id"]
            connection.execute(
                """
                UPDATE files
                SET root_path = ?, name = ?, extension = ?, size = ?,
                    mtime_ns = ?, fingerprint = ?, is_text = ?,
                    indexed_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """,
                (
                    normalized_root,
                    name,
                    extension,
                    size,
                    mtime_ns,
                    fingerprint,
                    int(is_text),
                    file_id,
                ),
            )
            connection.execute("DELETE FROM file_fts WHERE rowid = ?", (file_id,))

        connection.execute(
            "INSERT INTO file_fts(rowid, name, content) VALUES (?, ?, ?)",
            (file_id, name, content if is_text else ""),
        )
        connection.commit()
        return True

    def files_under(self, root_path: str | Path) -> list[sqlite3.Row]:
        connection = self._ensure_open()
        normalized_root = str(Path(root_path).resolve())
        prefix = normalized_root.rstrip("/") + "/%"
        return connection.execute(
            """
            SELECT * FROM files
            WHERE root_path = ? OR path LIKE ?
            ORDER BY path COLLATE NOCASE
            """,
            (normalized_root, prefix),
        ).fetchall()

    def remove_missing(self, root_path: str | Path, seen_paths: list[Path]) -> int:
        connection = self._ensure_open()
        normalized_root = str(Path(root_path).resolve())
        seen = {str(Path(path).resolve()) for path in seen_paths}
        rows = connection.execute(
            "SELECT id, path FROM files WHERE root_path = ?", (normalized_root,)
        ).fetchall()
        removed = 0
        for row in rows:
            if row["path"] not in seen:
                connection.execute("DELETE FROM file_fts WHERE rowid = ?", (row["id"],))
                connection.execute("DELETE FROM files WHERE id = ?", (row["id"],))
                removed += 1
        connection.commit()
        return removed

    def update_file_root(self, path: str | Path, root_path: str | Path) -> None:
        connection = self._ensure_open()
        connection.execute(
            "UPDATE files SET root_path = ? WHERE path = ?",
            (str(Path(root_path).resolve()), str(Path(path).resolve())),
        )
        connection.commit()

    def relocate_file(self, source: str | Path, destination: str | Path) -> None:
        """Update an indexed file path without changing its FTS row."""
        connection = self._ensure_open()
        source_path = str(Path(source).resolve())
        destination_path = str(Path(destination).resolve())
        source_row = connection.execute(
            "SELECT id FROM files WHERE path = ?", (source_path,)
        ).fetchone()
        if source_row is None:
            raise KeyError(f"Indexed file not found: {source_path}")
        destination_row = connection.execute(
            "SELECT id FROM files WHERE path = ?", (destination_path,)
        ).fetchone()
        if destination_row is not None and destination_row["id"] != source_row["id"]:
            raise FileExistsError(f"An indexed file already exists: {destination_path}")
        connection.execute(
            "UPDATE files SET path = ?, indexed_at = CURRENT_TIMESTAMP WHERE id = ?",
            (destination_path, source_row["id"]),
        )
        connection.commit()

    def record_applied_move(
        self,
        *,
        suggestion_id: int,
        source_path: str | Path,
        destination_path: str | Path,
        fingerprint: str,
    ) -> int:
        """Atomically update the index and action log after a filesystem move."""
        connection = self._ensure_open()
        source = str(Path(source_path).resolve())
        destination = str(Path(destination_path).resolve())
        try:
            source_row = connection.execute(
                "SELECT id FROM files WHERE path = ?", (source,)
            ).fetchone()
            if source_row is None:
                raise KeyError(f"Indexed file not found: {source}")

            destination_row = connection.execute(
                "SELECT id FROM files WHERE path = ?", (destination,)
            ).fetchone()
            if (
                destination_row is not None
                and destination_row["id"] != source_row["id"]
            ):
                raise FileExistsError(f"An indexed file already exists: {destination}")

            suggestion_row = connection.execute(
                """
                SELECT id, source_path, destination_path, status
                FROM suggestions
                WHERE id = ?
                """,
                (suggestion_id,),
            ).fetchone()
            if suggestion_row is None:
                raise KeyError(f"Suggestion not found: {suggestion_id}")
            if (
                suggestion_row["source_path"] != source
                or suggestion_row["destination_path"] != destination
            ):
                raise ValueError("Suggestion paths do not match the applied move")
            if suggestion_row["status"] != "pending":
                raise ValueError(
                    f"Suggestion {suggestion_id} is already {suggestion_row['status']}"
                )

            connection.execute(
                "UPDATE files SET path = ?, indexed_at = CURRENT_TIMESTAMP WHERE id = ?",
                (destination, source_row["id"]),
            )
            cursor = connection.execute(
                """
                INSERT INTO actions
                    (suggestion_id, source_path, destination_path, fingerprint)
                VALUES (?, ?, ?, ?)
                """,
                (suggestion_id, source, destination, fingerprint),
            )
            updated = connection.execute(
                "UPDATE suggestions SET status = 'applied' WHERE id = ?",
                (suggestion_id,),
            )
            if updated.rowcount != 1:
                raise KeyError(f"Suggestion not found: {suggestion_id}")
            connection.commit()
            return int(cursor.lastrowid)
        except Exception:
            connection.rollback()
            raise

    def record_undone_move(
        self,
        *,
        action_id: int,
        source_path: str | Path,
        destination_path: str | Path,
    ) -> None:
        """Atomically restore the index and mark an action as undone."""
        connection = self._ensure_open()
        source = str(Path(source_path).resolve())
        destination = str(Path(destination_path).resolve())
        try:
            action = connection.execute(
                """
                SELECT suggestion_id, source_path, destination_path, undone_at
                FROM actions
                WHERE id = ?
                """,
                (action_id,),
            ).fetchone()
            if action is None:
                raise KeyError(f"Action not found: {action_id}")
            if action["undone_at"] is not None:
                raise ValueError(f"Action {action_id} is already undone")
            if (
                action["source_path"] != destination
                or action["destination_path"] != source
            ):
                raise ValueError("Action paths do not match the undo request")

            source_row = connection.execute(
                "SELECT id FROM files WHERE path = ?", (source,)
            ).fetchone()
            if source_row is None:
                raise KeyError(f"Indexed file not found: {source}")

            destination_row = connection.execute(
                "SELECT id FROM files WHERE path = ?", (destination,)
            ).fetchone()
            if (
                destination_row is not None
                and destination_row["id"] != source_row["id"]
            ):
                raise FileExistsError(f"An indexed file already exists: {destination}")

            connection.execute(
                "UPDATE files SET path = ?, indexed_at = CURRENT_TIMESTAMP WHERE id = ?",
                (destination, source_row["id"]),
            )
            updated = connection.execute(
                """
                UPDATE actions
                SET undone_at = CURRENT_TIMESTAMP
                WHERE id = ? AND undone_at IS NULL
                """,
                (action_id,),
            )
            if updated.rowcount != 1:
                raise ValueError(f"Action {action_id} is already undone")
            updated = connection.execute(
                "UPDATE suggestions SET status = 'undone' WHERE id = ?",
                (action["suggestion_id"],),
            )
            if updated.rowcount != 1:
                raise KeyError(f"Suggestion not found: {action['suggestion_id']}")
            connection.commit()
        except Exception:
            connection.rollback()
            raise

    def upsert_suggestion(
        self,
        *,
        source_path: str | Path,
        destination_path: str | Path,
        group_key: str,
        reason: str,
        fingerprint: str,
        commit: bool = True,
    ) -> sqlite3.Row:
        connection = self._ensure_open()
        source = str(Path(source_path).resolve())
        destination = str(Path(destination_path).resolve())
        row = connection.execute(
            """
            SELECT id FROM suggestions
            WHERE source_path = ? AND destination_path = ?
            """,
            (source, destination),
        ).fetchone()
        if row is None:
            cursor = connection.execute(
                """
                INSERT INTO suggestions
                    (source_path, destination_path, group_key, reason, fingerprint)
                VALUES (?, ?, ?, ?, ?)
                """,
                (source, destination, group_key, reason, fingerprint),
            )
            suggestion_id = cursor.lastrowid
        else:
            suggestion_id = row["id"]
            connection.execute(
                """
                UPDATE suggestions
                SET group_key = ?, reason = ?, fingerprint = ?
                WHERE id = ?
                """,
                (group_key, reason, fingerprint, suggestion_id),
            )
        if commit:
            connection.commit()
        return connection.execute(
            "SELECT * FROM suggestions WHERE id = ?", (suggestion_id,)
        ).fetchone()

    def get_suggestion(self, suggestion_id: int) -> sqlite3.Row | None:
        connection = self._ensure_open()
        return connection.execute(
            "SELECT * FROM suggestions WHERE id = ?", (suggestion_id,)
        ).fetchone()

    def list_suggestions(self, *, status: str | None = None) -> list[sqlite3.Row]:
        connection = self._ensure_open()
        if status is None:
            return connection.execute(
                "SELECT * FROM suggestions ORDER BY id"
            ).fetchall()
        return connection.execute(
            "SELECT * FROM suggestions WHERE status = ? ORDER BY id", (status,)
        ).fetchall()

    def set_suggestion_status(self, suggestion_id: int, status: str) -> None:
        if status not in {"pending", "applied", "undone"}:
            raise ValueError(f"Unsupported suggestion status: {status}")
        connection = self._ensure_open()
        connection.execute(
            "UPDATE suggestions SET status = ? WHERE id = ?",
            (status, suggestion_id),
        )
        connection.commit()

    def record_action(
        self,
        *,
        suggestion_id: int,
        source_path: str | Path,
        destination_path: str | Path,
        fingerprint: str,
    ) -> int:
        connection = self._ensure_open()
        cursor = connection.execute(
            """
            INSERT INTO actions
                (suggestion_id, source_path, destination_path, fingerprint)
            VALUES (?, ?, ?, ?)
            """,
            (
                suggestion_id,
                str(Path(source_path).resolve()),
                str(Path(destination_path).resolve()),
                fingerprint,
            ),
        )
        connection.commit()
        return int(cursor.lastrowid)

    def get_action(self, action_id: int) -> sqlite3.Row | None:
        connection = self._ensure_open()
        return connection.execute(
            "SELECT * FROM actions WHERE id = ?", (action_id,)
        ).fetchone()

    def list_actions(self, *, active_only: bool = False) -> list[sqlite3.Row]:
        connection = self._ensure_open()
        query = "SELECT * FROM actions"
        if active_only:
            query += " WHERE undone_at IS NULL"
        query += " ORDER BY id DESC"
        return connection.execute(query).fetchall()

    def mark_action_undone(self, action_id: int) -> None:
        connection = self._ensure_open()
        connection.execute(
            "UPDATE actions SET undone_at = CURRENT_TIMESTAMP WHERE id = ?",
            (action_id,),
        )
        connection.execute(
            """
            UPDATE suggestions
            SET status = 'undone'
            WHERE id = (SELECT suggestion_id FROM actions WHERE id = ?)
            """,
            (action_id,),
        )
        connection.commit()

    def action_count(self, *, undone: bool | None = None) -> int:
        connection = self._ensure_open()
        query = "SELECT COUNT(*) FROM actions"
        params: tuple[object, ...] = ()
        if undone is True:
            query += " WHERE undone_at IS NOT NULL"
        elif undone is False:
            query += " WHERE undone_at IS NULL"
        return int(connection.execute(query, params).fetchone()[0])

    def status_counts(self) -> dict[str, int]:
        connection = self._ensure_open()
        return {
            "files": int(connection.execute("SELECT COUNT(*) FROM files").fetchone()[0]),
            "pending_suggestions": int(
                connection.execute(
                    "SELECT COUNT(*) FROM suggestions WHERE status = 'pending'"
                ).fetchone()[0]
            ),
            "active_actions": self.action_count(undone=False),
            "undone_actions": self.action_count(undone=True),
        }
