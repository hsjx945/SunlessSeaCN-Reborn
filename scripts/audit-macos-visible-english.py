#!/usr/bin/env python3
"""Audit player-visible event text in a source JSON or packaged macOS ZIP."""

from __future__ import annotations

import argparse
import json
import re
import zipfile
from pathlib import Path
from typing import Any, Iterable


ENGLISH = re.compile(r"[A-Za-z]")
RESULT_FIELDS = ("DefaultEvent", "SuccessEvent", "RareDefaultEvent", "RareSuccessEvent")
VISIBLE_FIELDS = ("Name", "Description", "Teaser", "ButtonText")
HTML_TAG = re.compile(r"</?[^>\r\n]*>", re.IGNORECASE)
BRACKET_TOKEN = re.compile(r"\[[^\]\r\n]*\]")
URL_OR_EMAIL = re.compile(r"(?:https?://|www\.)[^\s<>]+|[\w.+-]+@[\w.-]+")
CODE_TOKEN = re.compile(
    r"(?<![A-Za-z])(?:A\s*\([^)]*\)|CHANGE_TERRAIN|GAME_END_EFFECT_[A-Z_]+|"
    r"EmpireofHands/[A-Za-z0-9_/-]+|[A-Z]{2,}_[A-Z0-9_]+|DLC|BR|SAY)(?![A-Za-z])"
)
MALFORMED_TAG = re.compile(r"<\s*/?\s*br\b[^>\r\n]*[./]", re.IGNORECASE)
MALFORMED_NEWLINE = re.compile(r"/(?:r|n)(?:/(?:r|n))?")
SINGLE_LATIN = re.compile(r"(?<![A-Za-z])[A-Za-z](?![A-Za-z])")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--events", type=Path, help="events.json path")
    source.add_argument("--zip", dest="package", type=Path, help="macOS package ZIP")
    parser.add_argument("--allowlist", type=Path, help="optional exact allowlist JSON")
    return parser.parse_args()


def load_events(args: argparse.Namespace) -> tuple[Any, str]:
    if args.events:
        return json.loads(args.events.read_text(encoding="utf-8")), str(args.events)
    with zipfile.ZipFile(args.package) as package:
        names = [name for name in package.namelist() if name.endswith("/payload/data/addon/Sunless_sea_CN_reborn/entities/events.json")]
        if len(names) != 1:
            raise SystemExit(f"audit-macos-visible-english: expected one events.json in ZIP, found {len(names)}")
        return json.loads(package.read(names[0]).decode("utf-8")), f"{args.package}:{names[0]}"


def visible_text(value: str) -> str:
    """Remove markup and non-prose tokens before looking for Latin words.

    Event text uses HTML-like tags and a small set of formatting/technical
    tokens. They are not rendered as English prose and must not create false
    positives (for example a bare ``<i>`` tag or ``[X]`` placeholder).
    """
    cleaned = HTML_TAG.sub(" ", value)
    cleaned = MALFORMED_TAG.sub(" ", cleaned)
    cleaned = BRACKET_TOKEN.sub(" ", cleaned)
    cleaned = URL_OR_EMAIL.sub(" ", cleaned)
    cleaned = CODE_TOKEN.sub(" ", cleaned)
    cleaned = MALFORMED_NEWLINE.sub(" ", cleaned)
    cleaned = SINGLE_LATIN.sub(" ", cleaned)
    return cleaned


def is_english(value: Any) -> bool:
    # Report Latin text even when it is mixed with Chinese. Proper names and
    # intentional non-prose tokens are handled by exact overlays/allowlists.
    return isinstance(value, str) and bool(ENGLISH.search(visible_text(value)))


def visible_records(events: Any) -> Iterable[tuple[int, str, str, str]]:
    if not isinstance(events, list):
        raise SystemExit("audit-macos-visible-english: events root must be a list")

    def inspect(value: Any, field_kind: str, root_id: int) -> Iterable[tuple[int, str, str, str]]:
        if not isinstance(value, dict) or value.get("Archived") is True:
            return
        identifier = value.get("Id")
        if not isinstance(identifier, int):
            return
        for field in VISIBLE_FIELDS:
            text = value.get(field)
            if is_english(text):
                yield identifier, field, text, f"{field_kind} {field} in event {root_id}"

    for event in events:
        if not isinstance(event, dict) or event.get("Archived") is True:
            continue
        root_id = event.get("Id")
        if not isinstance(root_id, int):
            continue
        yield from inspect(event, "Event Name", root_id)
        for branch in event.get("ChildBranches") or []:
            if not isinstance(branch, dict) or branch.get("Archived") is True:
                continue
            yield from inspect(branch, "Branch Name", root_id)
            for result_field in RESULT_FIELDS:
                yield from inspect(branch.get(result_field), f"{result_field} Name", root_id)


def load_allowlist(path: Path | None) -> set[tuple[int, str, str]]:
    if path is None:
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit("audit-macos-visible-english: allowlist must be a list")
    values: set[tuple[int, str, str]] = set()
    for index, item in enumerate(data):
        if not isinstance(item, dict) or not all(key in item for key in ("id", "field", "source", "reason")):
            raise SystemExit(f"audit-macos-visible-english: allowlist item {index} must contain id/field/source/reason")
        key = (item["id"], item["field"], item["source"])
        if key in values:
            raise SystemExit(f"audit-macos-visible-english: duplicate allowlist item {key!r}")
        values.add(key)
    return values


def main() -> int:
    args = parse_args()
    try:
        events, source = load_events(args)
    except (OSError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        raise SystemExit(f"audit-macos-visible-english: {exc}") from exc
    allowlist_path = args.allowlist
    if allowlist_path is None:
        default_allowlist = Path(__file__).resolve().parent.parent / "localization/macos/visible-english-allowlist.json"
        if default_allowlist.exists():
            allowlist_path = default_allowlist
    allowlist = load_allowlist(allowlist_path)
    findings = [record for record in visible_records(events) if record[:3] not in allowlist]
    print(f"source={source}")
    print(f"visible-english-findings={len(findings)}")
    for identifier, field, source_text, context in findings:
        print(json.dumps({"id": identifier, "field": field, "source": source_text, "context": context}, ensure_ascii=False, sort_keys=True))
    if findings:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
