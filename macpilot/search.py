from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path

from .models import SearchResult


_TOKEN_RE = re.compile(r"[\wÀ-ỹ][\wÀ-ỹ.\-]*", re.UNICODE)


def _match_query(query: str) -> str:
    tokens = _TOKEN_RE.findall(query)
    if not tokens:
        raise ValueError("Search query must contain at least one searchable term")
    return " AND ".join(
        f'"{token.replace(chr(34), chr(34) * 2)}"' for token in tokens
    )


def search(database, query: str, limit: int = 20) -> list[SearchResult]:
    if limit < 1 or limit > 200:
        raise ValueError("limit must be between 1 and 200")
    match = _match_query(query)
    rows = database.connection.execute(
        """
        SELECT f.id, f.path, f.name, f.extension, f.size, f.mtime_ns,
               snippet(file_fts, 1, '[', ']', '…', 24) AS snippet,
               bm25(file_fts) AS rank
        FROM file_fts
        JOIN files AS f ON f.id = file_fts.rowid
        WHERE file_fts MATCH ?
        ORDER BY rank ASC, f.mtime_ns DESC
        LIMIT ?
        """,
        (match, limit),
    ).fetchall()
    return [
        SearchResult(
            file_id=int(row["id"]),
            path=Path(row["path"]),
            filename=row["name"],
            extension=row["extension"],
            size=int(row["size"]),
            modified_at=datetime.fromtimestamp(row["mtime_ns"] / 1_000_000_000),
            snippet=row["snippet"] or row["name"],
            score=float(-row["rank"]),
        )
        for row in rows
    ]
