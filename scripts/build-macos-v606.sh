#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GAME_MANAGED="${SUNLESS_SEA_MANAGED:-/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/Resources/Data/Managed}"
ORIGINAL_SHA256="e40189302338b9bdc879b8474107c5e08d66a706c6a0dcd89250106066d0fdf4"
PATCHED_SHA256="8668468fda20cb1eb700e348f2f2c623a22178a8ac1e33106d5dcd272c37b246"
BSdiff_BIN="${BSDIFF_BIN:-$(command -v bsdiff || true)}"
BUILD_ROOT="$REPO_ROOT/build/macos-static"
DELTA_ROOT="$BUILD_ROOT/delta"
OUTPUT_ROOT="${SUNLESS_SEA_CN_OUTPUT_ROOT:-$(cd "$REPO_ROOT/../../outputs" && pwd)}"

die() { printf 'build-macos-v606: %s\n' "$1" >&2; exit 2; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

[[ -x /usr/bin/bspatch ]] || die "/usr/bin/bspatch not found"
[[ -n "$BSdiff_BIN" && -x "$BSdiff_BIN" ]] || die "bsdiff not found; set BSDIFF_BIN"
[[ -f "$GAME_MANAGED/Sunless.Game.dll" ]] || die "game Managed/Sunless.Game.dll not found: $GAME_MANAGED"
[[ "$(sha256 "$GAME_MANAGED/Sunless.Game.dll")" == "$ORIGINAL_SHA256" ]] || die "game DLL hash mismatch before build"

if [[ "${REBUILD_STATIC:-0}" == "1" || ! -f "$BUILD_ROOT/staging/Managed/Sunless.Game.dll" ]]; then
  "$SCRIPT_DIR/build-macos-static-ui.sh"
else
  printf 'reusing existing static build under %s (set REBUILD_STATIC=1 to rebuild)\n' "$BUILD_ROOT"
fi
TARGET="$BUILD_ROOT/staging/Managed/Sunless.Game.dll"
[[ "$(sha256 "$TARGET")" == "$PATCHED_SHA256" ]] || die "static build target hash mismatch"
mkdir -p "$DELTA_ROOT"
"$BSdiff_BIN" "$GAME_MANAGED/Sunless.Game.dll" "$TARGET" "$DELTA_ROOT/Sunless.Game.bsdiff"
ROUNDTRIP="$DELTA_ROOT/.roundtrip.$$"
rm -f "$ROUNDTRIP"
/usr/bin/bspatch "$GAME_MANAGED/Sunless.Game.dll" "$ROUNDTRIP" "$DELTA_ROOT/Sunless.Game.bsdiff"
cmp -s "$TARGET" "$ROUNDTRIP" || die "bsdiff/bspatch roundtrip mismatch"
rm -f "$ROUNDTRIP"

python3 "$REPO_ROOT/build_packages.py" --macos-only
ZIP="$REPO_ROOT/dist/SunlessSeaCN-macOS-v6.0.6.zip"
[[ -f "$ZIP" ]] || die "macOS ZIP was not generated"
mkdir -p "$OUTPUT_ROOT"
cp "$ZIP" "$OUTPUT_ROOT/SunlessSeaCN-macOS-v6.0.6.zip"
printf 'zip=%s\n' "$OUTPUT_ROOT/SunlessSeaCN-macOS-v6.0.6.zip"
printf 'size=%s\n' "$(stat -f %z "$OUTPUT_ROOT/SunlessSeaCN-macOS-v6.0.6.zip")"
printf 'sha256=%s\n' "$(sha256 "$OUTPUT_ROOT/SunlessSeaCN-macOS-v6.0.6.zip")"
