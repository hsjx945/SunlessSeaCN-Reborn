#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DOTNET_BIN=${DOTNET_BIN:-/opt/homebrew/opt/dotnet@8/bin/dotnet}
DOTNET_ROOT=${DOTNET_ROOT:-$(cd "$(dirname "$DOTNET_BIN")/../libexec" && pwd)}
export DOTNET_ROOT
GAME_MANAGED=${SUNLESS_SEA_MANAGED:-/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/Resources/Data/Managed}
VENDOR_ROOT=${BEPINEX_VENDOR_ROOT:-$REPO_ROOT/../vendor-cache/bepinex-5.4.23.5}
PAYLOAD_ZIP=${SUNLESS_SEA_CN_MAC_PAYLOAD_ZIP:-$REPO_ROOT/../vendor-cache/SunlessSeaCN-macOS-v6.0.4.zip}
EXPECTED_GAME_SHA256=${SUNLESS_SEA_EXPECTED_GAME_SHA256:-b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0}
BUILD_ROOT=${SUNLESS_SEA_STATIC_BUILD_ROOT:-$REPO_ROOT/build/macos-static}
STAGE_ROOT=$BUILD_ROOT/staging
PLUGIN_OUT=$BUILD_ROOT/plugin
PATCHER_OUT=$BUILD_ROOT/patcher

die() {
    printf 'build-macos-static-ui: %s\n' "$1" >&2
    exit 2
}

[[ -x "$DOTNET_BIN" ]] || die "dotnet not found or not executable: $DOTNET_BIN"
[[ -d "$GAME_MANAGED" ]] || die "game Managed directory not found: $GAME_MANAGED"
[[ -f "$GAME_MANAGED/Sunless.Game.dll" ]] || die "Sunless.Game.dll not found under: $GAME_MANAGED"
[[ -f "$PAYLOAD_ZIP" ]] || die "macOS payload ZIP not found; set SUNLESS_SEA_CN_MAC_PAYLOAD_ZIP: $PAYLOAD_ZIP"

INPUT_SHA256=$(shasum -a 256 "$GAME_MANAGED/Sunless.Game.dll" | awk '{print $1}')
[[ "$INPUT_SHA256" == "$EXPECTED_GAME_SHA256" ]] || die "game DLL SHA-256 mismatch: expected $EXPECTED_GAME_SHA256, got $INPUT_SHA256"

rm -rf "$BUILD_ROOT"
mkdir -p "$STAGE_ROOT/Managed" "$PLUGIN_OUT" "$PATCHER_OUT"

"$DOTNET_BIN" restore "$REPO_ROOT/macos-static/SunlessSeaChineseTranslation.csproj" \
    -p:GameManaged="$GAME_MANAGED" -p:VendorRoot="$VENDOR_ROOT" -p:OutputPath="$PLUGIN_OUT/" --nologo
"$DOTNET_BIN" build "$REPO_ROOT/macos-static/SunlessSeaChineseTranslation.csproj" \
    -p:GameManaged="$GAME_MANAGED" -p:VendorRoot="$VENDOR_ROOT" -p:OutputPath="$PLUGIN_OUT/" \
    -c Release --no-restore --nologo

"$DOTNET_BIN" restore "$REPO_ROOT/macos-static/patcher/SunlessSeaStaticPatcher.csproj" \
    -p:VendorRoot="$VENDOR_ROOT" --nologo
"$DOTNET_BIN" build "$REPO_ROOT/macos-static/patcher/SunlessSeaStaticPatcher.csproj" \
    -p:VendorRoot="$VENDOR_ROOT" -c Release --no-restore --nologo -o "$PATCHER_OUT"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/sunlesssea-static-payload.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
unzip -q "$PAYLOAD_ZIP" -d "$SCRATCH/payload"
PLUGIN_PAYLOAD=$(find "$SCRATCH/payload" -type d -name SunlessSeaChineseTranslation -print -quit)
[[ -n "$PLUGIN_PAYLOAD" ]] || die "translation plugin assets were not found in payload ZIP"
[[ -f "$PLUGIN_OUT/SunlessSeaChineseTranslation.dll" ]] || die "standalone translation DLL was not built"

cp "$GAME_MANAGED/Sunless.Game.dll" "$STAGE_ROOT/Managed/Sunless.Game.original.dll"
cp "$PLUGIN_OUT/SunlessSeaChineseTranslation.dll" "$STAGE_ROOT/Managed/SunlessSeaChineseTranslation.dll"
[[ -f "$PLUGIN_OUT/0Harmony.dll" ]] || die "Lib.Harmony 0Harmony.dll was not copied to build output"
cp "$PLUGIN_OUT/0Harmony.dll" "$STAGE_ROOT/Managed/0Harmony.dll"
"$DOTNET_BIN" "$PATCHER_OUT/SunlessSeaStaticPatcher.dll" \
    --check-closure --root "$STAGE_ROOT/Managed" --entry 0Harmony.dll
mkdir -p "$STAGE_ROOT/Managed/SunlessSeaCN/Images" "$STAGE_ROOT/Managed/SunlessSeaCN/Data"
cp "$PLUGIN_PAYLOAD/Images/"*.png "$STAGE_ROOT/Managed/SunlessSeaCN/Images/"
cp "$PLUGIN_PAYLOAD/Data/qualities.json" "$STAGE_ROOT/Managed/SunlessSeaCN/Data/"

"$DOTNET_BIN" "$PATCHER_OUT/SunlessSeaStaticPatcher.dll" \
    --input "$GAME_MANAGED/Sunless.Game.dll" \
    --output "$STAGE_ROOT/Managed/Sunless.Game.dll" \
    --translation "$STAGE_ROOT/Managed/SunlessSeaChineseTranslation.dll" \
    --expected-sha256 "$EXPECTED_GAME_SHA256" \
    --report "$BUILD_ROOT/patch-report.txt"

mkdir -p "$BUILD_ROOT/player-data/addon"
ADDON_PAYLOAD=$(find "$SCRATCH/payload" -type d -path '*/payload/data/addon/Sunless_sea_CN_reborn' -print -quit)
[[ -n "$ADDON_PAYLOAD" ]] || die "translation addon was not found in payload ZIP"
cp -R "$ADDON_PAYLOAD" "$BUILD_ROOT/player-data/addon/"

ADDON_EVENTS="$BUILD_ROOT/player-data/addon/Sunless_sea_CN_reborn/entities/events.json"
OVERRIDE_FILE="$REPO_ROOT/localization/macos/events-name-overrides.json"
OVERRIDE_APPLIER="$REPO_ROOT/scripts/apply-macos-localization-overrides.py"
VISIBLE_ENGLISH_AUDIT="$REPO_ROOT/scripts/audit-macos-visible-english.py"
[[ -f "$ADDON_EVENTS" ]] || die "staged events.json was not found"
[[ -f "$OVERRIDE_FILE" ]] || die "macOS localization overlay was not found: $OVERRIDE_FILE"
python3 "$OVERRIDE_APPLIER" \
    --input "$ADDON_EVENTS" \
    --overlay "$OVERRIDE_FILE" \
    --output "$ADDON_EVENTS"
python3 "$VISIBLE_ENGLISH_AUDIT" --events "$ADDON_EVENTS"

printf 'build-root=%s\n' "$BUILD_ROOT"
printf 'staging-managed=%s\n' "$STAGE_ROOT/Managed"
printf 'player-data=%s\n' "$BUILD_ROOT/player-data"
printf 'input-sha256=%s\n' "$INPUT_SHA256"
printf 'patched-sha256=%s\n' "$(shasum -a 256 "$STAGE_ROOT/Managed/Sunless.Game.dll" | awk '{print $1}')"
printf 'translation-sha256=%s\n' "$(shasum -a 256 "$STAGE_ROOT/Managed/SunlessSeaChineseTranslation.dll" | awk '{print $1}')"
