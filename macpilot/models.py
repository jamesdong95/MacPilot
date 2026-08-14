from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass(frozen=True)
class IndexSummary:
    root: Path
    indexed_files: int
    skipped_files: int
    removed_files: int
    content_files: int = 0
    skipped_symlinks: int = 0
    ignored_directories: int = 0


@dataclass(frozen=True)
class SearchResult:
    file_id: int
    path: Path
    filename: str
    extension: str
    size: int
    modified_at: datetime
    snippet: str
    score: float
    is_text: bool = False
    tag: str | None = None


@dataclass(frozen=True)
class Suggestion:
    category: str
    destination: Path
    files: tuple[Path, ...]
    reason: str


@dataclass(frozen=True)
class MoveResult:
    action_id: int
    source: Path
    destination: Path


@dataclass(frozen=True)
class OrganizationSuggestion:
    id: int
    source_path: Path
    destination_path: Path
    reason: str
    status: str = "pending"


@dataclass(frozen=True)
class OrganizationResult:
    applied: bool
    action_id: int | None
    source_path: Path
    destination_path: Path
