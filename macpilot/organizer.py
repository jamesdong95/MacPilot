from __future__ import annotations

import re
import shutil
from collections import defaultdict
from pathlib import Path

from .database import Database
from .models import (
    MoveResult,
    OrganizationResult,
    OrganizationSuggestion,
    Suggestion,
)


CATEGORY_BY_EXTENSION = {
    ".pdf": "Documents/PDF",
    ".doc": "Documents/Word",
    ".docx": "Documents/Word",
    ".xls": "Documents/Spreadsheets",
    ".xlsx": "Documents/Spreadsheets",
    ".csv": "Documents/Spreadsheets",
    ".png": "Images",
    ".jpg": "Images",
    ".jpeg": "Images",
    ".gif": "Images",
    ".webp": "Images",
    ".heic": "Images",
    ".zip": "Archives",
    ".tar": "Archives",
    ".gz": "Archives",
    ".dmg": "Installers",
    ".pkg": "Installers",
    ".md": "Text",
    ".txt": "Text",
}


def suggest(database: Database, root: Path | str) -> list[Suggestion]:
    root_path = Path(root).expanduser().resolve()
    groups: dict[str, list[Path]] = defaultdict(list)
    for row in database.files_under(root_path):
        path = Path(row["path"])
        category = CATEGORY_BY_EXTENSION.get(row["extension"])
        if category is None or path.parent == root_path / category:
            continue
        groups[category].append(path)

    return [
        Suggestion(
            category=category,
            destination=root_path / category,
            files=tuple(sorted(files)),
            reason=f"{len(files)} files share the {category} category",
        )
        for category, files in sorted(groups.items())
        if len(files) >= 2
    ]


def _group_key(row) -> str:
    stem = Path(row["name"]).stem.lower()
    match = re.search(r"[a-z0-9À-ỹ]+", stem)
    keyword = match.group(0) if match else "file"
    extension = row["extension"].lstrip(".") or "file"
    return f"{keyword}-{extension}"


def generate_suggestions(database: Database) -> list[OrganizationSuggestion]:
    """Create stable, persisted, one-file-at-a-time organization suggestions."""
    result: list[OrganizationSuggestion] = []
    for row in database.list_files():
        source = Path(row["path"])
        group_key = _group_key(row)
        destination = Path(row["root_path"]) / "Organized" / group_key / source.name
        persisted = database.upsert_suggestion(
            source_path=source,
            destination_path=destination,
            group_key=group_key,
            reason=f"Group by filename keyword and extension: {group_key}",
            fingerprint=row["fingerprint"],
        )
        result.append(
            OrganizationSuggestion(
                id=int(persisted["id"]),
                source_path=Path(persisted["source_path"]),
                destination_path=Path(persisted["destination_path"]),
                reason=persisted["reason"],
                status=persisted["status"],
            )
        )
    return sorted(result, key=lambda item: str(item.source_path))


def preview_move(source: Path | str, destination: Path | str) -> MoveResult:
    source_path = Path(source).expanduser().resolve()
    destination_path = Path(destination).expanduser().resolve()
    if not source_path.exists():
        raise FileNotFoundError(source_path)
    if source_path.is_symlink() or not source_path.is_file():
        raise ValueError("Only regular files can be moved by MacPilot")
    if destination_path.exists():
        raise FileExistsError(destination_path)
    return MoveResult(action_id=0, source=source_path, destination=destination_path)


def _apply_recorded_move(
    database: Database,
    *,
    suggestion_id: int,
    source: Path,
    destination: Path,
    fingerprint: str,
) -> int:
    plan = preview_move(source, destination)
    plan.destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(plan.source), str(plan.destination))
    database.relocate_file(plan.source, plan.destination)
    action_id = database.record_action(
        suggestion_id=suggestion_id,
        source_path=plan.source,
        destination_path=plan.destination,
        fingerprint=fingerprint,
    )
    database.set_suggestion_status(suggestion_id, "applied")
    return action_id


def organize_suggestion(
    database: Database, suggestion_id: int, *, apply: bool = False
) -> OrganizationResult:
    row = database.get_suggestion(suggestion_id)
    if row is None:
        raise ValueError(f"Unknown suggestion: {suggestion_id}")
    source = Path(row["source_path"])
    destination = Path(row["destination_path"])
    if not apply:
        return OrganizationResult(False, None, source, destination)
    if row["status"] != "pending":
        raise ValueError(f"Suggestion {suggestion_id} is already {row['status']}")
    action_id = _apply_recorded_move(
        database,
        suggestion_id=suggestion_id,
        source=source,
        destination=destination,
        fingerprint=row["fingerprint"],
    )
    return OrganizationResult(True, action_id, source, destination)


def apply_move(database: Database, source: Path | str, destination: Path | str) -> MoveResult:
    source_path = Path(source).expanduser().resolve()
    destination_path = Path(destination).expanduser().resolve()
    row = database.file_record(source_path)
    if row is None:
        raise ValueError(f"Source is not indexed: {source_path}")
    suggestion = database.upsert_suggestion(
        source_path=source_path,
        destination_path=destination_path,
        group_key="manual",
        reason="Explicit manual move",
        fingerprint=row["fingerprint"],
    )
    action_id = _apply_recorded_move(
        database,
        suggestion_id=int(suggestion["id"]),
        source=source_path,
        destination=destination_path,
        fingerprint=row["fingerprint"],
    )
    return MoveResult(action_id, source_path, destination_path)


def undo_action(
    database: Database, action_id: int, *, apply: bool = False
) -> OrganizationResult:
    action = database.get_action(action_id)
    if action is None:
        raise ValueError(f"Unknown action: {action_id}")
    if action["undone_at"] is not None:
        raise ValueError(f"Action {action_id} is already undone")
    source = Path(action["destination_path"])
    destination = Path(action["source_path"])
    if not apply:
        return OrganizationResult(False, action_id, source, destination)
    if destination.exists():
        raise FileExistsError(f"Undo would overwrite existing path: {destination}")
    if not source.exists():
        raise FileNotFoundError(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))
    database.relocate_file(source, destination)
    database.mark_action_undone(action_id)
    return OrganizationResult(True, action_id, source, destination)


def undo(database: Database, action_id: int) -> MoveResult:
    result = undo_action(database, action_id, apply=True)
    return MoveResult(action_id, result.source_path, result.destination_path)
