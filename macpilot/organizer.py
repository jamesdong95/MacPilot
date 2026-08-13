from __future__ import annotations

import errno
import fnmatch
import os
import re
import shutil
import stat
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
    rules = [dict(row) for row in database.list_rules()]
    groups: dict[tuple[str, str], list[Path]] = defaultdict(list)

    def matching_rule(name: str) -> dict | None:
        for rule in rules:
            if fnmatch.fnmatch(name, rule["pattern"]):
                return rule
        return None

    for row in database.files_under(root_path):
        path = Path(row["path"])
        rule = matching_rule(row["name"])
        if rule is not None:
            destination = Path(rule["destination"]).expanduser()
            if not destination.is_absolute():
                destination = root_path / destination
            category = f"Rule: {rule['pattern']}"
        else:
            category = CATEGORY_BY_EXTENSION.get(row["extension"])
            if category is None:
                continue
            destination = root_path / category
        if path.parent == destination:
            continue
        groups[(category, str(destination))].append(path)

    return [
        Suggestion(
            category=category,
            destination=Path(destination),
            files=tuple(sorted(files)),
            reason=f"{len(files)} files match {category}",
        )
        for (category, destination), files in sorted(groups.items())
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


def _absolute_path(value: Path | str) -> Path:
    """Normalize a path without resolving symlinks."""
    return Path(os.path.abspath(os.fspath(Path(value).expanduser())))


_SYSTEM_SYMLINK_ALIASES = {
    "/var": "/private/var",
    "/tmp": "/private/tmp",
    "/etc": "/private/etc",
}


def _symlink_component(path: Path) -> Path | None:
    current = Path(path.anchor) if path.anchor else Path()
    parts = path.parts[1:] if path.anchor else path.parts
    for part in parts:
        current /= part
        try:
            mode = os.lstat(os.fspath(current)).st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode):
            allowed_target = _SYSTEM_SYMLINK_ALIASES.get(os.fspath(current))
            if (
                allowed_target is not None
                and os.path.realpath(os.fspath(current)) == allowed_target
            ):
                continue
            return current
    return None


def _assert_no_symlink(path: Path, label: str) -> None:
    link = _symlink_component(path)
    if link is not None:
        raise ValueError(f"{label} cannot contain a symlink: {link}")


def _file_identity(path: Path) -> tuple[int, int]:
    file_stat = os.lstat(os.fspath(path))
    if not stat.S_ISREG(file_stat.st_mode):
        raise ValueError("Only regular files can be moved by MacPilot")
    return file_stat.st_dev, file_stat.st_ino


def preview_move(source: Path | str, destination: Path | str) -> MoveResult:
    source_path = _absolute_path(source)
    destination_path = _absolute_path(destination)
    _assert_no_symlink(source_path, "Source")
    _assert_no_symlink(destination_path, "Destination")
    try:
        source_stat = os.lstat(os.fspath(source_path))
    except FileNotFoundError:
        raise FileNotFoundError(source_path)
    if not stat.S_ISREG(source_stat.st_mode):
        raise ValueError("Only regular files can be moved by MacPilot")
    try:
        os.lstat(os.fspath(destination_path))
    except FileNotFoundError:
        pass
    else:
        raise FileExistsError(destination_path)
    return MoveResult(action_id=0, source=source_path, destination=destination_path)


def _copy_no_replace(
    source: Path,
    destination: Path,
    expected_identity: tuple[int, int],
) -> None:
    source_fd: int | None = None
    destination_fd: int | None = None
    destination_created = False
    try:
        source_flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        source_fd = os.open(os.fspath(source), source_flags)
        source_stat = os.fstat(source_fd)
        source_identity = (source_stat.st_dev, source_stat.st_ino)
        if not stat.S_ISREG(source_stat.st_mode) or source_identity != expected_identity:
            raise RuntimeError("Source changed while the move was being prepared")

        destination_fd = os.open(
            os.fspath(destination),
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            stat.S_IMODE(source_stat.st_mode),
        )
        destination_created = True
        with os.fdopen(source_fd, "rb") as source_file:
            source_fd = None
            with os.fdopen(destination_fd, "wb") as destination_file:
                destination_fd = None
                shutil.copyfileobj(source_file, destination_file)
                destination_file.flush()
                os.fsync(destination_file.fileno())

        if _file_identity(source) != expected_identity:
            raise RuntimeError("Source changed while the move was being completed")
        os.unlink(os.fspath(source))
    except Exception:
        if source_fd is not None:
            os.close(source_fd)
        if destination_fd is not None:
            os.close(destination_fd)
        if destination_created:
            try:
                os.unlink(os.fspath(destination))
            except FileNotFoundError:
                pass
        raise


def _move_no_replace(source: Path | str, destination: Path | str) -> None:
    """Move a regular file without following symlinks or replacing a destination."""
    plan = preview_move(source, destination)
    source_identity = _file_identity(plan.source)
    plan.destination.parent.mkdir(parents=True, exist_ok=True)
    _assert_no_symlink(plan.destination, "Destination")
    try:
        os.link(
            os.fspath(plan.source),
            os.fspath(plan.destination),
            follow_symlinks=False,
        )
    except OSError as exc:
        if exc.errno != errno.EXDEV:
            raise
        _copy_no_replace(plan.source, plan.destination, source_identity)
        return

    try:
        destination_identity = _file_identity(plan.destination)
        if (
            destination_identity != source_identity
            or _file_identity(plan.source) != source_identity
        ):
            raise RuntimeError("Source changed while the move was being completed")
        os.unlink(os.fspath(plan.source))
    except Exception:
        try:
            os.unlink(os.fspath(plan.destination))
        except FileNotFoundError:
            pass
        raise


def _rollback_filesystem_move(
    source: Path,
    destination: Path,
    original_error: Exception,
) -> None:
    try:
        _move_no_replace(destination, source)
    except Exception as rollback_error:
        raise RuntimeError(
            "Filesystem move succeeded, but the database update failed and "
            "automatic rollback also failed. "
            f"Original error: {original_error}; rollback error: {rollback_error}"
        ) from rollback_error


def _apply_recorded_move(
    database: Database,
    *,
    suggestion_id: int,
    source: Path,
    destination: Path,
    fingerprint: str,
) -> int:
    plan = preview_move(source, destination)
    _move_no_replace(plan.source, plan.destination)
    try:
        return database.record_applied_move(
            suggestion_id=suggestion_id,
            source_path=plan.source,
            destination_path=plan.destination,
            fingerprint=fingerprint,
        )
    except Exception as exc:
        _rollback_filesystem_move(plan.source, plan.destination, exc)
        raise


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
    plan = preview_move(source, destination)
    source_path = plan.source
    destination_path = plan.destination
    row = database.file_record(source_path)
    if row is None:
        raise ValueError(f"Source is not indexed: {source_path}")
    try:
        suggestion = database.upsert_suggestion(
            source_path=source_path,
            destination_path=destination_path,
            group_key="manual",
            reason="Explicit manual move",
            fingerprint=row["fingerprint"],
            commit=False,
        )
        if suggestion["status"] != "pending":
            raise ValueError(
                f"Suggestion {suggestion['id']} is already {suggestion['status']}"
            )
        action_id = _apply_recorded_move(
            database,
            suggestion_id=int(suggestion["id"]),
            source=source_path,
            destination=destination_path,
            fingerprint=row["fingerprint"],
        )
    except Exception:
        database.rollback()
        raise
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
    plan = preview_move(source, destination)
    if not apply:
        return OrganizationResult(False, action_id, plan.source, plan.destination)
    _move_no_replace(plan.source, plan.destination)
    try:
        database.record_undone_move(
            action_id=action_id,
            source_path=plan.source,
            destination_path=plan.destination,
        )
    except Exception as exc:
        _rollback_filesystem_move(plan.source, plan.destination, exc)
        raise
    return OrganizationResult(True, action_id, plan.source, plan.destination)


def undo(database: Database, action_id: int) -> MoveResult:
    result = undo_action(database, action_id, apply=True)
    return MoveResult(action_id, result.source_path, result.destination_path)


def _unique_trash_destination(directory: Path, name: str) -> Path:
    """Return a collision-free path inside `directory` for `name`."""
    candidate = directory / name
    if not candidate.exists():
        return candidate
    stem = candidate.stem
    suffix = candidate.suffix
    index = 2
    while True:
        candidate = directory / f"{stem} {index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def trash(database: Database, source: Path | str, *, apply: bool = False) -> MoveResult:
    """Move an indexed file into the macOS Trash (undoable via the action log).

    Preview returns the planned Trash destination without touching anything;
    apply performs the move, records it, and returns the action id.
    """
    source_path = Path(source).expanduser().resolve()
    if database.file_record(source_path) is None:
        raise ValueError(f"Source is not indexed: {source_path}")
    trash_directory = Path(
        os.environ.get("MACPILOT_TRASH") or (Path.home() / ".Trash")
    )
    trash_directory.mkdir(parents=True, exist_ok=True)
    destination = _unique_trash_destination(trash_directory, source_path.name)
    if not apply:
        return preview_move(source_path, destination)
    return apply_move(database, source_path, destination)
