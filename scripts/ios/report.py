#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_report(path: Path) -> dict:
    if path.exists():
        return json.loads(path.read_text())
    return {
        "created_at": now_utc(),
        "repo_root": "",
        "entries": [],
    }


def write_report(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def cmd_init(args: argparse.Namespace) -> int:
    path = Path(args.report)
    payload = load_report(path)
    if args.repo_root:
        payload["repo_root"] = args.repo_root
    payload.setdefault("created_at", now_utc())
    payload.setdefault("entries", [])
    write_report(path, payload)
    return 0


def parse_bool(value: str) -> bool:
    return value.lower() in {"1", "true", "yes", "y"}


def cmd_add(args: argparse.Namespace) -> int:
    path = Path(args.report)
    payload = load_report(path)
    payload.setdefault("entries", [])
    entry = {
        "timestamp": now_utc(),
        "gate": args.gate,
        "status": args.status,
        "command": args.command,
        "duration_sec": float(args.duration),
        "notes": args.notes,
        "artifacts": [item for item in args.artifacts.split(",") if item],
        "requires_manual": parse_bool(args.requires_manual),
        "lane": args.lane,
        "resource_group": args.resource_group,
        "worker": args.worker,
        "coverage_mode": args.coverage_mode,
    }
    payload["entries"].append(entry)
    write_report(path, payload)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    init_parser = sub.add_parser("init")
    init_parser.add_argument("--report", required=True)
    init_parser.add_argument("--repo-root", default="")
    init_parser.set_defaults(func=cmd_init)

    add_parser = sub.add_parser("add")
    add_parser.add_argument("--report", required=True)
    add_parser.add_argument("--gate", required=True)
    add_parser.add_argument("--status", required=True)
    add_parser.add_argument("--command", required=True)
    add_parser.add_argument("--duration", default="0")
    add_parser.add_argument("--notes", default="")
    add_parser.add_argument("--artifacts", default="")
    add_parser.add_argument("--requires-manual", default="false")
    add_parser.add_argument("--lane", default="")
    add_parser.add_argument("--resource-group", default="")
    add_parser.add_argument("--worker", default="")
    add_parser.add_argument("--coverage-mode", default="")
    add_parser.set_defaults(func=cmd_add)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
