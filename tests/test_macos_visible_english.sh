#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
APPLIER="$ROOT/scripts/apply-macos-localization-overrides.py"
AUDIT="$ROOT/scripts/audit-macos-visible-english.py"
OVERLAY="$ROOT/localization/macos/events-name-overrides.json"
PAYLOAD_ZIP="${SUNLESS_SEA_CN_MAC_PAYLOAD_ZIP:-$ROOT/../vendor-cache/SunlessSeaCN-macOS-v6.0.4.zip}"

die() { printf 'test-macos-visible-english: %s\n' "$1" >&2; exit 1; }
[[ -f "$OVERLAY" ]] || die "missing overlay"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sunlesssea-visible-english.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

[[ -f "$PAYLOAD_ZIP" ]] || die "missing source payload ZIP: $PAYLOAD_ZIP"
SOURCE_ENTRY="$(unzip -Z1 "$PAYLOAD_ZIP" | rg '/payload/data/addon/Sunless_sea_CN_reborn/entities/events.json$' | head -n 1)"
[[ -n "$SOURCE_ENTRY" ]] || die "source payload has no events.json"
unzip -p "$PAYLOAD_ZIP" "$SOURCE_ENTRY" > "$TEST_ROOT/source-events.json"
python3 "$APPLIER" --input "$TEST_ROOT/source-events.json" --overlay "$OVERLAY" --output "$TEST_ROOT/events.json" >/dev/null
python3 "$AUDIT" --events "$TEST_ROOT/events.json" >/dev/null || die "translated event graph still contains visible English"

# The final ZIP is the actual delivery surface; audit its payload when present.
ZIP="$ROOT/dist/SunlessSeaCN-macOS-v6.0.5.zip"
if [[ -f "$ZIP" ]]; then
  python3 "$AUDIT" --zip "$ZIP" >/dev/null || die "final ZIP payload contains visible English"
fi

# A changed source value must fail closed instead of silently applying by ID.
python3 - "$OVERLAY" "$TEST_ROOT/bad-overlay.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
data["overrides"] = [dict(data["overrides"][0], source="changed source")]
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
set +e
python3 "$APPLIER" --input "$TEST_ROOT/source-events.json" --overlay "$TEST_ROOT/bad-overlay.json" --output "$TEST_ROOT/bad.json" >/dev/null 2>&1
bad_status=$?
set -e
[[ "$bad_status" -ne 0 ]] || die "source drift was accepted"

# Duplicate overlay keys must also fail closed.
python3 - "$OVERLAY" "$TEST_ROOT/duplicate-overlay.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
data["overrides"].append(dict(data["overrides"][0]))
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
set +e
python3 "$APPLIER" --input "$TEST_ROOT/source-events.json" --overlay "$TEST_ROOT/duplicate-overlay.json" --output "$TEST_ROOT/duplicate.json" >/dev/null 2>&1
duplicate_status=$?
set -e
[[ "$duplicate_status" -ne 0 ]] || die "duplicate overlay key was accepted"

# Inject a visible English name and ensure the scanner catches it.
python3 - "$TEST_ROOT/events.json" "$TEST_ROOT/injected.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
data[0]["Name"] = "Injected English Event"
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
set +e
python3 "$AUDIT" --events "$TEST_ROOT/injected.json" >/dev/null 2>&1
injected_status=$?
set -e
[[ "$injected_status" -ne 0 ]] || die "scanner missed injected visible English"

# Mixed Chinese/Latin prose must be caught too; markup and one-letter tokens
# are cleaned separately by the scanner and must not mask a real word.
python3 - "$TEST_ROOT/events.json" "$TEST_ROOT/injected-mixed.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
data[0]["Name"] = "中文 Mixed English"
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
set +e
python3 "$AUDIT" --events "$TEST_ROOT/injected-mixed.json" >/dev/null 2>&1
mixed_status=$?
set -e
[[ "$mixed_status" -ne 0 ]] || die "scanner missed mixed Chinese/English"

# RareDefaultEvent is part of the same player-visible result graph and must
# be audited, not silently treated as technical metadata.
python3 - "$TEST_ROOT/events.json" "$TEST_ROOT/injected-rare-default.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
found = False
for event in data:
    for branch in event.get("ChildBranches") or []:
        result = branch.get("RareDefaultEvent")
        if isinstance(result, dict) and isinstance(result.get("Name"), str):
            result["Name"] = "Injected Rare Default English"
            found = True
            break
    if found:
        break
if not found:
    raise SystemExit("fixture has no RareDefaultEvent")
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
set +e
python3 "$AUDIT" --events "$TEST_ROOT/injected-rare-default.json" >/dev/null 2>&1
rare_default_status=$?
set -e
[[ "$rare_default_status" -ne 0 ]] || die "scanner missed RareDefaultEvent English"

# Markup, placeholders, URLs and one-letter technical markers are not prose;
# they must not turn a clean visible field into a false positive.
python3 - "$TEST_ROOT/technical-markup.json" <<'PY'
import json
import sys
json.dump([{
    "Id": 900001,
    "Name": "纯中文",
    "Description": "中文 <i>BR</i> [quality] https://example.invalid Z",
    "ChildBranches": []
}], open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
python3 "$AUDIT" --events "$TEST_ROOT/technical-markup.json" >/dev/null || die "scanner treated markup/technical token as visible English"

printf 'PASS: overlay application, strict source/duplicate guards, translated event graph and ZIP oracle\n'
