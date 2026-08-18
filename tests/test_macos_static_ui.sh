#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_ROOT=${SUNLESS_SEA_STATIC_BUILD_ROOT:-$REPO_ROOT/build/macos-static}
GAME_MANAGED=${SUNLESS_SEA_MANAGED:-/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/Resources/Data/Managed}
EXPECTED_GAME_SHA256=${SUNLESS_SEA_EXPECTED_GAME_SHA256:-b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0}
EXPECTED_PATCHED_SHA256=${SUNLESS_SEA_EXPECTED_PATCHED_SHA256:-4ecc41ee6112fb9fc350a1662550fc843662861c61d6a9d80a182e0dad32bf6d}
LEGACY_PATCHED_SHA256=80076c8ce27f5cd4121afeadf4e4ba7a7e0e266afb06b10cc01e501637677042
DOTNET_BIN=${DOTNET_BIN:-/opt/homebrew/opt/dotnet@8/bin/dotnet}
DOTNET_ROOT=${DOTNET_ROOT:-$(cd "$(dirname "$DOTNET_BIN")/../libexec" && pwd)}
export DOTNET_ROOT

die() {
    printf 'test-macos-static-ui: %s\n' "$1" >&2
    exit 1
}

# Compile and execute the pure version logic against the exact source used by
# the plugin. This keeps the regression vectors independent of the live game
# and proves that missing GameVersion uses the embedded content baseline while
# an existing key remains on the original path.
VERSION_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sunlesssea-version-test.XXXXXX")
python3 - "$VERSION_TEST_ROOT" "$REPO_ROOT" <<'PY' || die "could not create version regression harness"
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
(out / "VersionHarness.csproj").write_text(f'''<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="{(root / "macos-static/src/SS_VersionLogic.cs").as_posix()}" Link="SS_VersionLogic.cs" />
    <Compile Include="Program.cs" />
  </ItemGroup>
</Project>
''', encoding="utf-8")
(out / "Program.cs").write_text(r'''using System;
using SSTranslator;

static class Program
{
    private static void Compare(string current, string required, int expected)
    {
        if (!SS_VersionLogic.TryCompare(current, required, out var actual) || Math.Sign(actual) != expected)
            throw new Exception($"compare failed: '{current}' vs '{required}', expected {expected}, got {actual}");
    }

    public static void Main()
    {
        Compare("2.3.0.22", "2.2.4.3141", 1);
        Compare("  v2.3.0.22 ", "V2.3.0.22", 0);
        Compare("2.3", "2.3.0", 0);
        Compare("2.3.0.1", "2.3", 1);
        Compare("2.2.4.3141", "2.3.0.22", -1);

        foreach (var invalid in new[] { "", "v", "1..2", "1.a", "1.2." })
        {
            if (SS_VersionLogic.TryCompare("2.3.0.22", invalid, out _))
                throw new Exception($"invalid version was accepted: '{invalid}'");
        }

        var expectedBaseline = new DateTime(2017, 10, 26, 15, 6, 0, DateTimeKind.Unspecified);
        if (!SS_VersionLogic.TryGetBundledBaseline(false, "201710261506", out var baseline) || baseline != expectedBaseline)
            throw new Exception($"missing GameVersion baseline failed: {baseline:O}");
        if (SS_VersionLogic.TryGetBundledBaseline(true, "201710261506", out _))
            throw new Exception("existing GameVersion key was replaced by bundled baseline");
        if (SS_VersionLogic.TryGetBundledBaseline(false, "not-a-date", out _))
            throw new Exception("invalid bundled baseline was accepted");

        Console.WriteLine("PASS version comparison and missing GameVersion baseline");
    }
}
''', encoding="utf-8")
PY
"$DOTNET_BIN" build "$VERSION_TEST_ROOT/VersionHarness.csproj" -c Release --nologo >/dev/null || die "version regression harness did not build"
"$DOTNET_BIN" "$VERSION_TEST_ROOT/bin/Release/net8.0/VersionHarness.dll" | rg -q '^PASS version comparison and missing GameVersion baseline$' ||
    die "version comparison/baseline regression failed"

SOURCE_ROOT="$REPO_ROOT/macos-static/src/Sunless_Game"
for required in \
    'The maximum recommended resolution is 1920x1080' \
    'Cannot connect to the server to retrieve latest news.' \
    'There was a problem connecting to the server' \
    "You're about to open a link" \
    'Sunless Sea will remain running and you can return at any time. Would you like to continue?' \
    'Fatal Error' \
    'and its fallback appear to be corrupt or invalid'; do
    rg -q --fixed-strings "$required" "$SOURCE_ROOT/SS_AlertDialog.cs" "$SOURCE_ROOT/SS_VideoOptionsPanel.cs" "$SOURCE_ROOT/SS_LatestNews.cs" "$SOURCE_ROOT/SS_CharacterRepository.cs" ||
        die "known English source constant is not covered: $required"
done
rg -q 'SSPatch_WarnAboutResolution' "$SOURCE_ROOT/SS_VideoOptionsPanel.cs" || die "resolution warning patch is missing"
rg -q 'TranslateBody' "$SOURCE_ROOT/SS_AlertDialog.cs" || die "alert body translation is missing"
rg -q '无光之海：潜海者 版本' "$REPO_ROOT/macos-static/src/SS_TitleScreenInit.cs" || die "title version translation is missing"
rg -q '支持与帮助（点击打开官网）' "$REPO_ROOT/macos-static/src/SS_TitleScreenInit.cs" || die "support label translation is missing"
rg -q '版权所有：费尔贝特游戏' "$REPO_ROOT/macos-static/src/SS_TitleScreenInit.cs" || die "copyright translation is missing"
if rg -q 'GetImageTexture2D\("TitleZMNew\.png"\)' "$REPO_ROOT/macos-static/src/SS_TitleScreenInit.cs"; then
    die "English Zubmariner title artwork is still loaded"
fi
rg -q 'new Rect\(0, 0, texture\.width, texture\.height\)' "$REPO_ROOT/macos-static/src/SS_TitleScreenInit.cs" ||
    die "title replacement sprite does not use the replacement texture bounds"
if rg -q 'Sprite\.Create\(\s*texture,\s*oldSprite\.rect' "$REPO_ROOT/macos-static/src/SS_TitleScreenInit.cs"; then
    die "title replacement still passes the original sprite rect"
fi
rg -q 'Resources\.FindObjectsOfTypeAll<Text>' "$REPO_ROOT/macos-static/src/SS_TitleScreenInit.cs" ||
    die "title footer localization is still tied to guessed object names"
rg -q 'EAWarningWatcher\.StartWatching' "$REPO_ROOT/macos-static/Bootstrap.cs" ||
    die "EAWarning watcher is missing"
rg -q 'Resources\.FindObjectsOfTypeAll<Image>' "$REPO_ROOT/macos-static/Bootstrap.cs" ||
    die "EAWarning fallback does not inspect the created hierarchy"
rg -q 'new Rect\(0, 0, newTexture\.width, newTexture\.height\)' "$REPO_ROOT/macos-static/src/SS_Utility.cs" ||
    die "shared sprite helper still uses the original sprite rect"
rg -q 'SSPatch_SoftwareNewEnough' "$SOURCE_ROOT/SS_SoftwareVersionRequirement.cs" ||
    die "strict software version patch is missing"
rg -q 'SS_VersionLogic\.TryCompare' "$SOURCE_ROOT/SS_SoftwareVersionRequirement.cs" ||
    die "software version patch does not use segmented comparison"
rg -q 'SSPatch_CheckIfNewContent' "$SOURCE_ROOT/SS_Importer.cs" ||
    die "missing GameVersion content baseline patch is missing"
rg -q 'GetInitialContentBaseline' "$SOURCE_ROOT/SS_Importer.cs" ||
    die "missing GameVersion baseline helper is missing"
rg -q 'TryGetBundledBaseline' "$SOURCE_ROOT/SS_Importer.cs" ||
    die "bundled content baseline is not guarded by the GameVersion key"
if rg -q 'return true;' "$SOURCE_ROOT/SS_SoftwareVersionRequirement.cs" &&
   ! rg -q 'preserving original game logic' "$SOURCE_ROOT/SS_SoftwareVersionRequirement.cs"; then
    die "software version parse failure does not document original fallback"
fi

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
[[ "$actual_game_sha" == "$EXPECTED_GAME_SHA256" || "$actual_game_sha" == "$EXPECTED_PATCHED_SHA256" || "$actual_game_sha" == "$LEGACY_PATCHED_SHA256" ]] ||
    die "real game DLL is neither supported original nor installed patch: $actual_game_sha"
original_sha=$(shasum -a 256 "$ORIGINAL" | awk '{print $1}')
[[ "$original_sha" == "$EXPECTED_GAME_SHA256" ]] || die "staged original hash mismatch: $original_sha"
patched_sha=$(shasum -a 256 "$PATCHED" | awk '{print $1}')
[[ "$patched_sha" != "$EXPECTED_GAME_SHA256" ]] || die "patched output is byte-identical to the input"

rg -q '^action=injected$' "$PATCH_REPORT" || die "patch report does not prove a fresh injection"
rg -q '^target-intro=.*IntroScript.*PlayEAWarning' "$PATCH_REPORT" || die "patch report target is not IntroScript.PlayEAWarning"
rg -q '^bootstrap-intro-action=(injected|already-injected)$' "$PATCH_REPORT" || die "patch report does not verify IntroScript injection"
rg -q '^target-title=.*TitleScreenInit.*Start' "$PATCH_REPORT" || die "patch report target is not TitleScreenInit.Start"
rg -q '^bootstrap-title-action=(injected|already-injected)$' "$PATCH_REPORT" || die "patch report does not verify TitleScreenInit injection"
rg -q 'bootstrap=.*SSTranslator.Bootstrap.*Init' "$PATCH_REPORT" || die "patch report does not identify Bootstrap.Init"
closure_report=$("$DOTNET_BIN" "$PATCHER" --check-closure --root "$MANAGED_ROOT" --entry 0Harmony.dll)
printf '%s\n' "$closure_report" | rg -q '^closure-ok=0Harmony\.dll ' || die "Harmony Managed dependency closure failed: $closure_report"

if strings "$TRANSLATION" | rg -q 'BepInEx|BaseUnityPlugin|PluginInfo'; then
    die "standalone translation DLL still contains BepInEx entry-point references"
fi
python3 - "$TRANSLATION" <<'PY' || die "translation DLL is missing title Chinese strings"
import sys
payload = open(sys.argv[1], "rb").read()
for value in ("无光之海：潜海者 版本", "支持与帮助（点击打开官网）", "版权所有：费尔贝特游戏"):
    if value.encode("utf-16le") not in payload:
        raise SystemExit(value)
PY
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
