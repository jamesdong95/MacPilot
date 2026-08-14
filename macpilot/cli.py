from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable
from dataclasses import asdict
from pathlib import Path

from . import __version__
from .database import Database
from .indexer import Indexer
from .organizer import (
    apply_move,
    preview_move,
    rename_batch,
    suggest,
    trash,
    undo_action,
    undo_all,
)
from .search import list_indexed, search, semantic_search
from .semantic import DEFAULT_MODEL, OllamaUnavailableError, summarize_file


def _path(value: str) -> Path:
    return Path(value).expanduser()


def _json_default(value):
    if isinstance(value, Path):
        return str(value)
    if hasattr(value, "isoformat"):
        return value.isoformat()
    if isinstance(value, tuple):
        return list(value)
    raise TypeError(f"Cannot encode {type(value).__name__}")


def _print(value) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2, default=_json_default))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="macpilot",
        description="Local-first file search and safe organization for macOS.",
    )
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument(
        "--db",
        type=_path,
        default=Path.home() / ".macpilot" / "index.sqlite3",
        help="SQLite database path (default: ~/.macpilot/index.sqlite3)",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    index_parser = commands.add_parser("index", help="Index a folder")
    index_parser.add_argument("root", type=_path)
    index_parser.add_argument(
        "--progress",
        action="store_true",
        help="Emit PROGRESS <n> lines on stderr while indexing",
    )
    index_parser.add_argument(
        "--embed",
        action="store_true",
        help="Also embed text file content for semantic search (needs a running embedding provider)",
    )

    search_parser = commands.add_parser("search", help="Search indexed files")
    search_parser.add_argument("query")
    search_parser.add_argument("--limit", type=int, default=20)
    search_parser.add_argument(
        "--semantic",
        action="store_true",
        help="Search by meaning (embedding similarity) instead of keywords",
    )

    list_parser = commands.add_parser("list", help="List indexed files")
    list_parser.add_argument("--root", type=_path)
    list_parser.add_argument("--limit", type=int, default=200)

    suggest_parser = commands.add_parser("suggest", help="Suggest safe file grouping")
    suggest_parser.add_argument("root", type=_path)

    move_parser = commands.add_parser("move", help="Preview or apply one file move")
    move_parser.add_argument("source", type=_path)
    move_parser.add_argument("destination", type=_path)
    move_parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually move the file; without this flag only a preview is produced",
    )

    undo_parser = commands.add_parser("undo", help="Undo a completed move")
    undo_parser.add_argument("action_id", type=int)
    undo_parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually undo the move; without this flag only a preview is produced",
    )

    trash_parser = commands.add_parser("trash", help="Move an indexed file to the Trash")
    trash_parser.add_argument("source", type=_path)
    trash_parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually move the file to the Trash; without this flag only a preview is produced",
    )

    actions_parser = commands.add_parser("actions", help="List recorded file actions")
    actions_parser.add_argument(
        "--active-only",
        action="store_true",
        help="Only show actions that have not been undone",
    )

    commands.add_parser("status", help="Show database and action summary")

    commands.add_parser("duplicates", help="Report duplicate files by content hash")

    commands.add_parser("storage", help="Summarize disk usage (largest, stale, screenshots, duplicates)")

    tags_parser = commands.add_parser("tags", help="List auto-assigned tags and their files")
    tags_parser.add_argument("tag_name", nargs="?", help="Show files with a specific tag")

    saved_parser = commands.add_parser("saved", help="Manage saved searches (smart folders)")
    saved_sub = saved_parser.add_subparsers(dest="saved_action", required=True)
    saved_sub.add_parser("list", help="List saved searches")
    saved_add = saved_sub.add_parser("add", help="Save a search query")
    saved_add.add_argument("name", help="Display name for the saved search")
    saved_add.add_argument("query", help="Search query text")
    saved_remove = saved_sub.add_parser("remove", help="Remove a saved search")
    saved_remove.add_argument("search_id", type=int, help="Saved search id from 'saved list'")

    rules_parser = commands.add_parser("rules", help="Manage organization rules")
    rules_sub = rules_parser.add_subparsers(dest="rules_action", required=True)
    rules_sub.add_parser("list", help="List rules")
    rules_add = rules_sub.add_parser("add", help="Add a rule")
    rules_add.add_argument("pattern", help="Filename glob pattern, e.g. '*.pdf'")
    rules_add.add_argument("destination", help="Destination directory (relative to root or absolute)")
    rules_remove = rules_sub.add_parser("remove", help="Remove a rule")
    rules_remove.add_argument("rule_id", type=int, help="Rule id from 'rules list'")

    rename_parser = commands.add_parser("rename", help="Batch rename files in a folder")
    rename_parser.add_argument("root", type=_path)
    rename_parser.add_argument("find", help="Substring to find in filenames")
    rename_parser.add_argument("replace", help="Replacement substring")
    rename_parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually rename the files; without this flag only a preview is produced",
    )

    undo_all_parser = commands.add_parser("undo-all", help="Undo every active action")
    undo_all_parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually revert the actions; without this flag only a preview is produced",
    )

    summarize_parser = commands.add_parser(
        "summarize", help="Summarize a text file with a local Ollama model"
    )
    summarize_parser.add_argument("path", type=_path)
    summarize_parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Ollama model to use (default: {DEFAULT_MODEL})",
    )

    summarize_batch_parser = commands.add_parser(
        "summarize-batch", help="Summarize multiple text files"
    )
    summarize_batch_parser.add_argument("paths", nargs="+", type=_path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        with Database(args.db) as database:
            if args.command == "index":
                progress: Callable[[int], None] | None = None
                if getattr(args, "progress", False):
                    def progress(n: int) -> None:
                        print(f"PROGRESS {n}", file=sys.stderr, flush=True)
                _print(asdict(Indexer(database).index_root(
                    args.root,
                    progress=progress,
                    embed=getattr(args, "embed", False),
                )))
            elif args.command == "search":
                if getattr(args, "semantic", False):
                    _print([asdict(result) for result in semantic_search(
                        database, args.query, args.limit
                    )])
                else:
                    _print([asdict(result) for result in search(database, args.query, args.limit)])
            elif args.command == "list":
                _print(
                    [
                        asdict(result)
                        for result in list_indexed(
                            database, root_path=args.root, limit=args.limit
                        )
                    ]
                )
            elif args.command == "suggest":
                _print([asdict(item) for item in suggest(database, args.root)])
            elif args.command == "move":
                if args.apply:
                    result = apply_move(database, args.source, args.destination)
                    payload = {
                        "applied": True,
                        "action_id": result.action_id,
                        "source_path": str(result.source),
                        "destination_path": str(result.destination),
                    }
                else:
                    payload = asdict(preview_move(args.source, args.destination))
                payload["mode"] = "applied" if args.apply else "preview"
                _print(payload)
            elif args.command == "undo":
                result = undo_action(database, args.action_id, apply=args.apply)
                if args.apply:
                    payload = {
                        "applied": True,
                        "action_id": result.action_id,
                        "source_path": str(result.source_path),
                        "destination_path": str(result.destination_path),
                    }
                else:
                    payload = asdict(result)
                payload["mode"] = "applied" if args.apply else "preview"
                _print(payload)
            elif args.command == "trash":
                result = trash(database, args.source, apply=args.apply)
                if args.apply:
                    payload = {
                        "applied": True,
                        "action_id": result.action_id,
                        "source_path": str(result.source),
                        "destination_path": str(result.destination),
                    }
                else:
                    payload = asdict(result)
                payload["mode"] = "applied" if args.apply else "preview"
                _print(payload)
            elif args.command == "actions":
                _print(
                    [
                        dict(row)
                        for row in database.list_actions(active_only=args.active_only)
                    ]
                )
            elif args.command == "status":
                _print(database.status_counts())
            elif args.command == "duplicates":
                _print(database.duplicate_groups())
            elif args.command == "storage":
                _print(database.storage_report())
            elif args.command == "tags":
                if args.tag_name:
                    _print([dict(row) for row in database.files_with_tag(args.tag_name)])
                else:
                    rows = database.connection.execute(
                        "SELECT tag, COUNT(*) AS count FROM file_tags "
                        "GROUP BY tag ORDER BY count DESC"
                    ).fetchall()
                    _print([{"tag": row["tag"], "count": int(row["count"])} for row in rows])
            elif args.command == "saved":
                if args.saved_action == "list":
                    _print([dict(row) for row in database.list_saved_searches()])
                elif args.saved_action == "add":
                    search_id = database.add_saved_search(args.name, args.query)
                    _print({"id": search_id, "name": args.name, "query": args.query})
                elif args.saved_action == "remove":
                    _print({"removed": database.remove_saved_search(args.search_id)})
            elif args.command == "rules":
                if args.rules_action == "list":
                    _print([dict(row) for row in database.list_rules()])
                elif args.rules_action == "add":
                    rule_id = database.add_rule(args.pattern, args.destination)
                    _print(
                        {
                            "id": rule_id,
                            "pattern": args.pattern,
                            "destination": args.destination,
                        }
                    )
                elif args.rules_action == "remove":
                    _print(
                        {
                            "id": args.rule_id,
                            "removed": database.remove_rule(args.rule_id),
                        }
                    )
            elif args.command == "rename":
                results = rename_batch(
                    database, args.root, args.find, args.replace, apply=args.apply
                )
                payload = {"count": len(results), "renames": results}
                payload["mode"] = "applied" if args.apply else "preview"
                _print(payload)
            elif args.command == "undo-all":
                results = undo_all(database, apply=args.apply)
                payload = {"count": len(results), "actions": results}
                payload["mode"] = "applied" if args.apply else "preview"
                _print(payload)
            elif args.command == "summarize":
                summary = summarize_file(args.path, model=args.model)
                _print(
                    {
                        "path": str(args.path),
                        "model": args.model,
                        "summary": summary,
                    }
                )
            elif args.command == "summarize-batch":
                results = []
                for p in args.paths:
                    try:
                        results.append({"path": str(p), "summary": summarize_file(p)})
                    except Exception as exc:  # noqa: BLE001 - keep the batch going
                        results.append({"path": str(p), "error": str(exc)})
                _print(results)
        return 0
    except (OSError, ValueError, OllamaUnavailableError) as exc:
        print(f"macpilot: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
