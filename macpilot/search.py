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
    # Prefix match each term so partial words still hit ("inv" → invoice).
    # FTS5 also expands the last term as a prefix token for typo/prefix tolerance.
    return " AND ".join(
        f'"{token.replace(chr(34), chr(34) * 2)}"*' for token in tokens
    )


def search(database, query: str, limit: int = 20) -> list[SearchResult]:
    if limit < 1 or limit > 200:
        raise ValueError("limit must be between 1 and 200")
    match = _match_query(query)
    rows = database.connection.execute(
        """
        SELECT f.id, f.path, f.name, f.extension, f.size, f.mtime_ns,
               f.is_text,
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
            is_text=bool(row["is_text"]),
            tag=database.tag_for(int(row["id"])),
        )
        for row in rows
    ]


def list_indexed(
    database,
    *,
    root_path: str | Path | None = None,
    limit: int = 200,
) -> list[SearchResult]:
    """Return indexed files without changing the local database or filesystem."""
    if limit < 1 or limit > 200:
        raise ValueError("limit must be between 1 and 200")
    rows = database.list_files(root_path=root_path)[:limit]
    return [
        SearchResult(
            file_id=int(row["id"]),
            path=Path(row["path"]),
            filename=row["name"],
            extension=row["extension"],
            size=int(row["size"]),
            modified_at=datetime.fromtimestamp(row["mtime_ns"] / 1_000_000_000),
            snippet=row["name"],
            score=0.0,
            is_text=bool(row["is_text"]),
            tag=database.tag_for(int(row["id"])),
        )
        for row in rows
    ]


def _cosine_similarity(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = sum(x * x for x in a) ** 0.5
    norm_b = sum(y * y for y in b) ** 0.5
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def semantic_search(database, query: str, limit: int = 20) -> list[SearchResult]:
    """Rank indexed files by embedding similarity to `query`.

    Requires that files were indexed with ``--embed`` so their content vectors
    are stored. Raises LLMUnavailableError when no embedding provider is
    reachable (surfaced to the caller as a clear error).
    """
    if limit < 1 or limit > 200:
        raise ValueError("limit must be between 1 and 200")
    from .semantic import embed_texts

    query_vector = embed_texts([query])[0]
    scored: list[tuple[float, int, str]] = []
    for file_id, vector, path in database.load_embeddings():
        scored.append((_cosine_similarity(query_vector, vector), file_id, path))
    scored.sort(key=lambda item: item[0], reverse=True)

    results: list[SearchResult] = []
    for score, file_id, path in scored[:limit]:
        row = database.file_record(path)
        if row is None:
            continue
        results.append(
            SearchResult(
                file_id=file_id,
                path=Path(path),
                filename=row["name"],
                extension=row["extension"],
                size=int(row["size"]),
                modified_at=datetime.fromtimestamp(row["mtime_ns"] / 1_000_000_000),
                snippet=row["name"],
                score=float(score),
                is_text=bool(row["is_text"]),
                tag=database.tag_for(file_id),
            )
        )
    return results
