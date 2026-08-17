#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_ROOT=${SUNLESS_SEA_STATIC_BUILD_ROOT:-$REPO_ROOT/build/macos-static}
GAME_MANAGED=${SUNLESS_SEA_MANAGED:-/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/Resources/Data/Managed}
EXPECTED_GAME_SHA256=${SUNLESS_SEA_EXPECTED_GAME_SHA256:-b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0}
EXPECTED_PATCHED_SHA256=${SUNLESS_SEA_EXPECTED_PATCHED_SHA256:-80076c8ce27f5cd4121afeadf4e4ba7a7e0e266afb06b10cc01e501637677042}
DOTNET_BIN=${DOTNET_BIN:-/opt/homebrew/opt/dotnet@8/bin/dotnet}
DOTNET_ROOT=${DOTNET_ROOT:-$(cd "$(dirname "$DOTNET_BIN")/../libexec" && pwd)}
export DOTNET_ROOT

die() {
    printf 'test-macos-static-ui: %s\n' "$1" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || die "missing file: $1"
}

assert_dir() {
    [[ -d "$1" ]] || die "missing directory: $1"
}

PATCHED="$BUILD_ROOT/staging/Managed/Sunless.Game.dll"
ORIGINAL="$BUILD_ROOT/staging/Managed/Sunless.Game.original.dll"
TRANSLATION="$BUILD_ROOT/staging/Managed/SunlessSeaChineseTranslation.dll"
HARMONY="$BUILD_ROOT/staging/Managed/0Harmony.dll"
PATCH_REPORT="$BUILD_ROOT/patch-report.txt"
PATCHER="$BUILD_ROOT/patcher/SunlessSeaStaticPatcher.dll"
MANAGED_ROOT="$BUILD_ROOT/staging/Managed"

assert_file "$PATCHED"
assert_file "$ORIGINAL"
assert_file "$TRANSLATION"
assert_file "$HARMONY"
assert_file "$PATCH_REPORT"
assert_file "$PATCHER"
assert_dir "$BUILD_ROOT/staging/Managed/SunlessSeaCN/Images"
assert_dir "$BUILD_ROOT/staging/Managed/SunlessSeaCN/Data"
assert_file "$BUILD_ROOT/staging/Managed/SunlessSeaCN/Data/qualities.json"
assert_dir "$BUILD_ROOT/player-data/addon/Sunless_sea_CN_reborn"

actual_game_sha=$(shasum -a 256 "$GAME_MANAGED/Sunless.Game.dll" | awk '{print $1}')
[[ "$actual_game_sha" == "$EXPECTED_GAME_SHA256" || "$actual_game_sha" == "$EXPECTED_PATCHED_SHA256" ]] ||
    die "real game DLL is neither supported original nor installed patch: $actual_game_sha"
original_sha=$(shasum -a 256 "$ORIGINAL" | awk '{print $1}')
[[ "$original_sha" == "$EXPECTED_GAME_SHA256" ]] || die "staged original hash mismatch: $original_sha"
patched_sha=$(shasum -a 256 "$PATCHED" | awk '{print $1}')
[[ "$patched_sha" != "$EXPECTED_GAME_SHA256" ]] || die "patched output is byte-identical to the input"

rg -q '^action=injected$' "$PATCH_REPORT" || die "patch report does not prove a fresh injection"
rg -q 'target=.*TitleScreenInit.*Start' "$PATCH_REPORT" || die "patch report target is not TitleScreenInit.Start"
rg -q 'bootstrap=.*SSTranslator.Bootstrap.*Init' "$PATCH_REPORT" || die "patch report does not identify Bootstrap.Init"
closure_report=$("$DOTNET_BIN" "$PATCHER" --check-closure --root "$MANAGED_ROOT" --entry 0Harmony.dll)
printf '%s\n' "$closure_report" | rg -q '^closure-ok=0Harmony\.dll ' || die "Harmony Managed dependency closure failed: $closure_report"

if strings "$TRANSLATION" | rg -q 'BepInEx|BaseUnityPlugin|PluginInfo'; then
    die "standalone translation DLL still contains BepInEx entry-point references"
fi
file "$PATCHED" "$TRANSLATION" "$HARMONY" | rg -q 'PE32.*Mono/.Net assembly' ||
    die "one or more managed outputs are not PE32 Mono assemblies"

image_count=$(find "$BUILD_ROOT/staging/Managed/SunlessSeaCN/Images" -type f -name '*.png' | wc -l | tr -d ' ')
[[ "$image_count" -gt 0 ]] || die "no translated image assets were staged"
addon_count=$(find "$BUILD_ROOT/player-data/addon/Sunless_sea_CN_reborn" -type f | wc -l | tr -d ' ')
[[ "$addon_count" -gt 0 ]] || die "no translated addon files were staged"

idempotent_root=$(mktemp -d "${TMPDIR:-/tmp}/sunlesssea-static-test.XXXXXX")
trap 'rm -rf "$idempotent_root"' EXIT
idempotent_report="$idempotent_root/report.txt"
idempotent_output="$idempotent_root/Sunless.Game.dll"
"$DOTNET_BIN" "$PATCHER" \
    --input "$PATCHED" \
    --output "$idempotent_output" \
    --translation "$TRANSLATION" \
    --report "$idempotent_report" >/dev/null
rg -q '^action=already-injected$' "$idempotent_report" || die "patcher is not idempotent on an already-patched target"
assert_file "$idempotent_output"

printf 'PASS static outputs=%s patched-sha256=%s images=%s addon-files=%s live-game-known-sha256=%s\n' \
    "$BUILD_ROOT/staging/Managed" "$patched_sha" "$image_count" "$addon_count" "$actual_game_sha"
