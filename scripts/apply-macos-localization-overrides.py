#!/usr/bin/env python3
"""Apply ID-anchored macOS localization overlays with strict drift checks."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="source JSON")
    parser.add_argument("--overlay", required=True, type=Path, help="overlay JSON")
    parser.add_argument("--output", required=True, type=Path, help="translated JSON")
    return parser.parse_args()


def visible_objects(value: Any):
    """Yield only event graph objects covered by the visible-text audit.

    The source occasionally repeats an ID in a LinkToEvent or test fixture.
    Restricting lookup to the player-visible event graph makes the ID+field
    contract deterministic without silently editing technical metadata.
    """
    if not isinstance(value, list):
        return
    for event in value:
        if not isinstance(event, dict) or event.get("Archived") is True:
            continue
        yield event
        for branch in event.get("ChildBranches") or []:
            if not isinstance(branch, dict) or branch.get("Archived") is True:
                continue
            yield branch
            for result_field in ("DefaultEvent", "SuccessEvent", "RareDefaultEvent", "RareSuccessEvent"):
                result = branch.get(result_field)
                if isinstance(result, dict) and result.get("Archived") is not True:
                    yield result


def fail(message: str) -> None:
    raise SystemExit(f"apply-macos-localization-overrides: {message}")


def main() -> int:
    args = parse_args()
    try:
        data = json.loads(args.input.read_text(encoding="utf-8"))
        overlay = json.loads(args.overlay.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(str(exc))

    entries = overlay.get("overrides")
    if not isinstance(entries, list) or not entries:
        fail("overlay must contain a non-empty overrides list")

    objects = list(visible_objects(data))
    seen_keys: set[tuple[int, str]] = set()
    applied = 0
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            fail(f"override {index} is not an object")
        required = ("id", "field", "source", "translation", "context")
        missing = [key for key in required if key not in entry]
        if missing:
            fail(f"override {index} missing {', '.join(missing)}")
        identifier = entry["id"]
        field = entry["field"]
        source = entry["source"]
        translation = entry["translation"]
        context = entry["context"]
        if not isinstance(identifier, int) or isinstance(identifier, bool):
            fail(f"override {index} id must be an integer")
        if not all(isinstance(value, str) and value for value in (field, source, translation, context)):
            fail(f"override {index} field/source/translation/context must be non-empty strings")
        key = (identifier, field)
        if key in seen_keys:
            fail(f"duplicate override key id={identifier} field={field}")
        seen_keys.add(key)
        if source == translation:
            fail(f"override {index} does not translate id={identifier} field={field}")
        matches = [obj for obj in objects if obj.get("Id") == identifier and obj.get(field) == source]
        if len(matches) != 1:
            fail(f"id={identifier} field={field} expected one match, found {len(matches)} ({context})")
        target = matches[0]
        if target[field] != source:
            fail(
                f"source mismatch id={identifier} field={field}: "
                f"expected {source!r}, found {target[field]!r} ({context})"
            )
        target[field] = translation
        applied += 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    # Replace atomically when the output is the source file, while retaining
    # normal output-path behavior for build staging.
    if args.output.resolve() == args.input.resolve():
        fd, temporary = tempfile.mkstemp(prefix=f".{args.output.name}.", dir=args.output.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
                stream.write(payload)
            os.replace(temporary, args.output)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    else:
        with args.output.open("w", encoding="utf-8", newline="\n") as stream:
            stream.write(payload)
    print(f"applied={applied} output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
