from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

from . import __version__
from .database import Database
from .indexer import Indexer
from .organizer import apply_move, preview_move, suggest, undo_action
from .search import list_indexed, search


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

    search_parser = commands.add_parser("search", help="Search indexed files")
    search_parser.add_argument("query")
    search_parser.add_argument("--limit", type=int, default=20)

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

    actions_parser = commands.add_parser("actions", help="List recorded file actions")
    actions_parser.add_argument(
        "--active-only",
        action="store_true",
        help="Only show actions that have not been undone",
    )

    commands.add_parser("status", help="Show database and action summary")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        with Database(args.db) as database:
            if args.command == "index":
                _print(asdict(Indexer(database).index_root(args.root)))
            elif args.command == "search":
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
            elif args.command == "actions":
                _print(
                    [
                        dict(row)
                        for row in database.list_actions(active_only=args.active_only)
                    ]
                )
            elif args.command == "status":
                _print(database.status_counts())
        return 0
    except (OSError, ValueError) as exc:
        print(f"macpilot: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
