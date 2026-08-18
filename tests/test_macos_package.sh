#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="$ROOT/dist/SunlessSeaCN-macOS-v6.0.5.zip"
PACKAGE="$ROOT/dist/SunlessSeaCN-macOS-v6.0.5"
ORIGINAL_SHA256="b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0"
PATCHED_SHA256="4ecc41ee6112fb9fc350a1662550fc843662861c61d6a9d80a182e0dad32bf6d"

die() { printf 'test_macos_package: %s\n' "$1" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

[[ -f "$ZIP" ]] || die "missing ZIP; run scripts/build-macos-v605.sh"
unzip -t "$ZIP" >/dev/null
python3 "$ROOT/scripts/audit-macos-visible-english.py" --zip "$ZIP" >/dev/null || die "ZIP payload contains visible English event text"
zip_entries="$(unzip -Z1 "$ZIP")"
grep -q '^SunlessSeaCN-macOS-v6.0.5/payload/game/Sunless.Game.bsdiff$' <<< "$zip_entries"
if grep -Eq '/Sunless\.Game(\.original)?\.dll$' <<< "$zip_entries"; then
  die "ZIP contains a complete game DLL"
fi
json_count="$(grep -Ec '/payload/data/addon/Sunless_sea_CN_reborn/.*\.json$' <<< "$zip_entries")"
[[ "$json_count" == "17" ]] || die "expected 17 addon JSON files, got $json_count"
for name in Install-SunlessSeaCN.sh Install-And-Start-SunlessSeaCN.sh Uninstall-SunlessSeaCN.sh Install-SunlessSeaCN.command Install-And-Start-SunlessSeaCN.command Uninstall-SunlessSeaCN.command; do
  grep -q "/$name$" <<< "$zip_entries" || die "missing $name"
done
grep -q '/LICENSE-GPL-3.0.txt$' <<< "$zip_entries" || die "missing upstream GPL-3.0 license"
grep -q '/LICENSE-HARMONY-MIT.txt$' <<< "$zip_entries" || die "missing Harmony MIT license"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sunlesssea-package.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
unzip -q "$ZIP" -d "$TEST_ROOT/unpacked"
for name in Install-SunlessSeaCN.sh Install-And-Start-SunlessSeaCN.sh Uninstall-SunlessSeaCN.sh Install-SunlessSeaCN.command Install-And-Start-SunlessSeaCN.command Uninstall-SunlessSeaCN.command; do
  mode="$(stat -f '%Lp' "$TEST_ROOT/unpacked/SunlessSeaCN-macOS-v6.0.5/$name")"
  [[ "$mode" == "755" ]] || die "$name mode is $mode, expected 755"
  /bin/bash -n "$TEST_ROOT/unpacked/SunlessSeaCN-macOS-v6.0.5/$name"
done

# Build a small signed app-shaped sandbox around the real input DLL. No Steam
# app or player save is touched. The source data root deliberately has a
# legacy saves marker; installer must still use the Unity 6 com.* root.
GAME_ROOT="$TEST_ROOT/game"
APP="$GAME_ROOT/Sunless Sea.app"
MANAGED="$APP/Contents/Resources/Data/Managed"
mkdir -p "$MANAGED" "$APP/Contents/MacOS" "$APP/Contents/_CodeSignature"
cp "$ROOT/build/macos-static/staging/Managed/Sunless.Game.original.dll" "$MANAGED/Sunless.Game.dll"
printf '%s\n' '#!/bin/sh' > "$APP/Contents/MacOS/Sunless Sea"
chmod 755 "$APP/Contents/MacOS/Sunless Sea"
codesign --force --sign - "$APP" >/dev/null
mkdir -p "$TEST_ROOT/home/Library/Application Support/unity.Failbetter Games.Sunless Sea/saves"
printf 'legacy\n' > "$TEST_ROOT/home/Library/Application Support/unity.Failbetter Games.Sunless Sea/saves/sentinel"

PKG="$TEST_ROOT/unpacked/SunlessSeaCN-macOS-v6.0.5"
SUNLESS_SEA_GAME_ROOT="$GAME_ROOT" HOME="$TEST_ROOT/home" NONINTERACTIVE=1 /bin/bash "$PKG/Install-SunlessSeaCN.sh"
[[ "$(sha256 "$MANAGED/Sunless.Game.dll")" == "$PATCHED_SHA256" ]] || die "patched hash mismatch after install"
[[ -f "$TEST_ROOT/home/Library/Application Support/com.failbettergames.sunlesssea/addon/Sunless_sea_CN_reborn/entities/events.json" ]] || die "addon was not installed to Unity 6 root"
[[ ! -f "$TEST_ROOT/home/Library/Application Support/unity.Failbetter Games.Sunless Sea/addon/Sunless_sea_CN_reborn/entities/events.json" ]] || die "addon was incorrectly installed to legacy root"

# Reinstall is idempotent and must leave exactly one manifest.
SUNLESS_SEA_GAME_ROOT="$GAME_ROOT" HOME="$TEST_ROOT/home" NONINTERACTIVE=1 /bin/bash "$PKG/Install-SunlessSeaCN.sh"
[[ "$(sha256 "$MANAGED/Sunless.Game.dll")" == "$PATCHED_SHA256" ]] || die "patched hash mismatch after reinstall"

SUNLESS_SEA_GAME_ROOT="$GAME_ROOT" HOME="$TEST_ROOT/home" /bin/bash "$PKG/Uninstall-SunlessSeaCN.sh"
[[ "$(sha256 "$MANAGED/Sunless.Game.dll")" == "$ORIGINAL_SHA256" ]] || die "original hash was not restored"
[[ ! -e "$GAME_ROOT/.sunlessseacn-install-manifest" ]] || die "manifest remains after clean uninstall"
codesign --verify --deep --strict "$APP" >/dev/null

# A syntactically valid bsdiff that produces the wrong target must fail before
# touching the sealed app and must leave no temporary DLL or manifest behind.
BAD_PKG="$TEST_ROOT/bad-package"
cp -R "$PKG" "$BAD_PKG"
python3 - "$BAD_PKG/payload/game/Sunless.Game.bsdiff" <<'PY'
import bz2
import sys

def offtout(value):
    raw = bytearray(8)
    magnitude = abs(value)
    for index in range(8):
        raw[index] = magnitude & 0xff
        magnitude >>= 8
    if value < 0:
        raw[7] |= 0x80
    return bytes(raw)

output = b"valid bsdiff, deliberately wrong target\n"
control = offtout(0) + offtout(len(output)) + offtout(0)
control_block = bz2.compress(control)
diff_block = bz2.compress(b"")
extra_block = bz2.compress(output)
header = b"BSDIFF40" + offtout(len(control_block)) + offtout(len(diff_block)) + offtout(len(output))
with open(sys.argv[1], "wb") as stream:
    stream.write(header + control_block + diff_block + extra_block)
PY
set +e
SUNLESS_SEA_GAME_ROOT="$GAME_ROOT" HOME="$TEST_ROOT/home" NONINTERACTIVE=1 /bin/bash "$BAD_PKG/Install-SunlessSeaCN.sh" >/dev/null 2>&1
bad_install_status="$?"
set -e
[[ "$bad_install_status" == "2" ]] || die "bad patch install status is $bad_install_status, expected 2"
[[ "$(sha256 "$MANAGED/Sunless.Game.dll")" == "$ORIGINAL_SHA256" ]] || die "bad patch changed original game DLL"
[[ ! -e "$GAME_ROOT/.sunlessseacn-install-manifest" ]] || die "bad patch left a completed manifest"
temp_residue="$(find "$GAME_ROOT" \( -name '.Sunless.Game.dll.tmp.*' -o -name 'Sunless.Game.dll.patched' \) -print -quit)"
[[ -z "$temp_residue" ]] || die "bad patch left a temporary DLL: $temp_residue"
codesign --verify --deep --strict "$APP" >/dev/null

# A user-modified installed file must make uninstall a zero-write operation.
SUNLESS_SEA_GAME_ROOT="$GAME_ROOT" HOME="$TEST_ROOT/home" NONINTERACTIVE=1 /bin/bash "$PKG/Install-SunlessSeaCN.sh" >/dev/null
MODIFIED_ADDON="$TEST_ROOT/home/Library/Application Support/com.failbettergames.sunlesssea/addon/Sunless_sea_CN_reborn/entities/events.json"
printf '\nuser-edit\n' >> "$MODIFIED_ADDON"
before_game="$(sha256 "$MANAGED/Sunless.Game.dll")"
before_translation="$(sha256 "$MANAGED/SunlessSeaChineseTranslation.dll")"
before_harmony="$(sha256 "$MANAGED/0Harmony.dll")"
before_addon="$(sha256 "$MODIFIED_ADDON")"
before_manifest="$(sha256 "$GAME_ROOT/.sunlessseacn-install-manifest")"
codesign --verify --deep --strict "$APP" >/dev/null
set +e
SUNLESS_SEA_GAME_ROOT="$GAME_ROOT" HOME="$TEST_ROOT/home" /bin/bash "$PKG/Uninstall-SunlessSeaCN.sh" >/dev/null 2>&1
modified_uninstall_status="$?"
set -e
[[ "$modified_uninstall_status" == "3" ]] || die "modified uninstall status is $modified_uninstall_status, expected 3"
[[ "$(sha256 "$MANAGED/Sunless.Game.dll")" == "$before_game" ]] || die "modified uninstall changed game DLL"
[[ "$(sha256 "$MANAGED/SunlessSeaChineseTranslation.dll")" == "$before_translation" ]] || die "modified uninstall removed translation DLL"
[[ "$(sha256 "$MANAGED/0Harmony.dll")" == "$before_harmony" ]] || die "modified uninstall removed Harmony DLL"
[[ "$(sha256 "$MODIFIED_ADDON")" == "$before_addon" ]] || die "modified uninstall changed user-edited addon"
[[ "$(sha256 "$GAME_ROOT/.sunlessseacn-install-manifest")" == "$before_manifest" ]] || die "modified uninstall changed manifest"
codesign --verify --deep --strict "$APP" >/dev/null

printf 'PASS: ZIP structure, Bash 3.2 syntax, new data root, install/reinstall/uninstall, failure rollback, zero-write preflight, signature and hash gates\n'
