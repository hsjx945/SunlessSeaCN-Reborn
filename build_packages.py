from __future__ import annotations

import shutil
import stat
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"
BUILD = ROOT / ".build"
WIN_GAME = Path(r"E:\Program Files (x86)\Steam\steamapps\common\SunlessSea")
WIN_DATA = Path(r"C:\Users\Lenovo\AppData\LocalLow\Failbetter Games\Sunless Sea")
MAC_STATIC_BUILD = ROOT / "build" / "macos-static"
WIN_VERSION = "6.0.4"
MAC_VERSION = "6.0.5"


WIN_PS1 = r'''param(
    [string]$GameRoot,
    [string]$DataRoot,
    [switch]$NonInteractive
)
$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadRoot = Join-Path $ScriptRoot "payload"

function Get-DefaultGameRoot {
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $candidates = @(
        $env:SUNLESS_SEA_GAME_ROOT,
        (Join-Path $pf86 "Steam\steamapps\common\SunlessSea"),
        (Join-Path $env:ProgramFiles "Steam\steamapps\common\SunlessSea"),
        "E:\Program Files (x86)\Steam\steamapps\common\SunlessSea"
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ "Sunless Sea.exe")) }
    if ($candidates) { return ($candidates | Select-Object -First 1) }
    if ($NonInteractive) { throw "找不到 Sunless Sea 安装目录。请设置 SUNLESS_SEA_GAME_ROOT 或传入 -GameRoot。" }
    return Read-Host "请输入 Sunless Sea 游戏目录（包含 Sunless Sea.exe）"
}

if (-not $GameRoot) { $GameRoot = Get-DefaultGameRoot }
if (-not (Test-Path (Join-Path $GameRoot "Sunless Sea.exe"))) { throw "不是有效的 Sunless Sea 游戏目录: $GameRoot" }
if (-not $DataRoot) { $DataRoot = Join-Path $env:USERPROFILE "AppData\LocalLow\Failbetter Games\Sunless Sea" }
$DataRoot = [IO.Path]::GetFullPath($DataRoot)
$GameRoot = [IO.Path]::GetFullPath($GameRoot)

# Reinstalling should not back up the already-installed translation itself.
# Remove the previous package files (and restore its original backup) first.
$oldManifestPath = Join-Path $GameRoot ".sunlessseacn-install.json"
if (Test-Path -LiteralPath $oldManifestPath) {
    $oldManifest = Get-Content -LiteralPath $oldManifestPath -Raw | ConvertFrom-Json
    foreach ($oldRecord in $oldManifest.Files) {
        $oldRoot = if ($oldRecord.Scope -eq "game") { $oldManifest.GameRoot } else { $oldManifest.DataRoot }
        $oldDestination = Join-Path $oldRoot $oldRecord.Relative
        if (Test-Path -LiteralPath $oldDestination -PathType Leaf) {
            $oldHash = (Get-FileHash -LiteralPath $oldDestination -Algorithm SHA256).Hash
            if ($oldHash -eq $oldRecord.Hash) { Remove-Item -LiteralPath $oldDestination -Force }
        }
    }
    foreach ($pair in @(
        @($oldManifest.BackupGame, $oldManifest.GameRoot),
        @($oldManifest.BackupData, $oldManifest.DataRoot)
    )) {
        $oldBackup = $pair[0]; $oldRoot = $pair[1]
        if ($oldBackup -and (Test-Path -LiteralPath $oldBackup)) {
            Get-ChildItem -LiteralPath $oldBackup -Recurse -File | ForEach-Object {
                $oldRelative = $_.FullName.Substring($oldBackup.Length).TrimStart("\")
                $oldDestination = Join-Path $oldRoot $oldRelative
                New-Item -ItemType Directory -Force -Path (Split-Path $oldDestination -Parent) | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination $oldDestination -Force
            }
        }
    }
    Remove-Item -LiteralPath $oldManifestPath -Force
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupGame = Join-Path $GameRoot "SunlessSeaCN-backup-$stamp"
$backupData = Join-Path (Split-Path $DataRoot -Parent) "SunlessSeaCN-backup-$stamp"
$records = @()
$backupCreated = $false

function Copy-PayloadFile([IO.FileInfo]$Source, [string]$Scope, [string]$Relative, [string]$DestinationRoot, [string]$BackupRoot) {
    $destination = Join-Path $DestinationRoot $Relative
    if (Test-Path -LiteralPath $destination) {
        $backupDestination = Join-Path $BackupRoot $Relative
        New-Item -ItemType Directory -Force -Path (Split-Path $backupDestination -Parent) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backupDestination -Force
        $script:backupCreated = $true
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $Source.FullName -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $Source.FullName -Algorithm SHA256).Hash
    $script:records += [pscustomobject]@{ Scope = $Scope; Relative = $Relative; Hash = $hash }
}

foreach ($source in Get-ChildItem -LiteralPath (Join-Path $PayloadRoot "game") -Recurse -File) {
    $relative = $source.FullName.Substring((Join-Path $PayloadRoot "game").Length).TrimStart("\")
    Copy-PayloadFile $source "game" $relative $GameRoot $backupGame
}
foreach ($source in Get-ChildItem -LiteralPath (Join-Path $PayloadRoot "data") -Recurse -File) {
    $relative = $source.FullName.Substring((Join-Path $PayloadRoot "data").Length).TrimStart("\")
    Copy-PayloadFile $source "data" $relative $DataRoot $backupData
}

$manifest = [pscustomobject]@{
    Package = "SunlessSeaCN"
    Version = "6.0.4"
    InstalledAt = (Get-Date).ToString("o")
    GameRoot = $GameRoot
    DataRoot = $DataRoot
    BackupGame = $(if ($backupCreated) { $backupGame } else { $null })
    BackupData = $(if ($backupCreated) { $backupData } else { $null })
    Files = $records
}
$manifestPath = Join-Path $GameRoot ".sunlessseacn-install.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "Sunless Sea 中文补丁已安装。"
Write-Host "游戏目录: $GameRoot"
Write-Host "数据目录: $DataRoot"
if ($backupCreated) { Write-Host "已有文件已备份到: $backupGame / $backupData" }
'''

WIN_UNINSTALL_PS1 = r'''param(
    [string]$GameRoot,
    [switch]$NonInteractive
)
$ErrorActionPreference = "Stop"
if (-not $GameRoot) {
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $GameRoot = @($env:SUNLESS_SEA_GAME_ROOT, (Join-Path $pf86 "Steam\steamapps\common\SunlessSea"), (Join-Path $env:ProgramFiles "Steam\steamapps\common\SunlessSea")) | Where-Object { $_ -and (Test-Path (Join-Path $_ ".sunlessseacn-install.json")) } | Select-Object -First 1
}
if (-not $GameRoot) { throw "找不到安装清单。请设置 SUNLESS_SEA_GAME_ROOT 或传入 -GameRoot。" }
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
$manifestPath = Join-Path $GameRoot ".sunlessseacn-install.json"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "未找到安装清单: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$removed = 0
$skipped = 0
foreach ($record in $manifest.Files) {
    $root = if ($record.Scope -eq "game") { $manifest.GameRoot } else { $manifest.DataRoot }
    $destination = Join-Path $root $record.Relative
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($hash -eq $record.Hash) { Remove-Item -LiteralPath $destination -Force; $removed++ }
        else { Write-Host "保留用户已修改文件: $destination"; $skipped++ }
    }
}
if ($manifest.BackupGame -and (Test-Path -LiteralPath $manifest.BackupGame)) {
    Get-ChildItem -LiteralPath $manifest.BackupGame -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($manifest.BackupGame.Length).TrimStart("\")
        $destination = Join-Path $manifest.GameRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
    Write-Host "已恢复游戏文件备份: $($manifest.BackupGame)"
}
if ($manifest.BackupData -and (Test-Path -LiteralPath $manifest.BackupData)) {
    Get-ChildItem -LiteralPath $manifest.BackupData -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($manifest.BackupData.Length).TrimStart("\")
        $destination = Join-Path $manifest.DataRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
    Write-Host "已恢复文本数据备份: $($manifest.BackupData)"
}
Remove-Item -LiteralPath $manifestPath -Force
Write-Host "卸载完成。删除文件: $removed；因用户修改而保留: $skipped。备份目录未删除，可手动清理。"
'''

WIN_INSTALL_CMD = r'''@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-SunlessSeaCN.ps1" %*
if errorlevel 1 echo 安装失败。
pause
'''

WIN_UNINSTALL_CMD = r'''@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-SunlessSeaCN.ps1" %*
if errorlevel 1 echo 卸载失败。
pause
'''

MAC_INSTALL_SH = r'''#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_GAME="$SCRIPT_DIR/payload/game"
PAYLOAD_DATA="$SCRIPT_DIR/payload/data"

find_game_root() {
  if [[ -n "${SUNLESS_SEA_GAME_ROOT:-}" && -d "$SUNLESS_SEA_GAME_ROOT" ]]; then echo "$SUNLESS_SEA_GAME_ROOT"; return; fi
  local candidates=(
    "$HOME/Library/Application Support/Steam/steamapps/common/SunlessSea"
    "$HOME/Library/Application Support/Steam/steamapps/common/Sunless Sea"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c/Sunless Sea.app" ]]; then echo "$c"; return; fi
  done
  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then return 1; fi
  read -r -p "请输入 Sunless Sea 游戏目录（包含 Sunless Sea.app）: " c
  [[ -d "$c/Sunless Sea.app" ]] || { echo "无效的游戏目录: $c" >&2; return 1; }
  echo "$c"
}

find_data_root() {
  if [[ -n "${SUNLESS_SEA_DATA_ROOT:-}" ]]; then echo "$SUNLESS_SEA_DATA_ROOT"; return; fi
  local candidates=(
    "$HOME/Library/Application Support/Failbetter Games/Sunless Sea"
    "$HOME/Library/Application Support/unity.Failbetter Games.Sunless Sea"
    "$HOME/Library/Caches/unity.Failbetter Games.Sunless Sea"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then echo "$c"; return; fi
  done
  echo "${candidates[0]}"
}

GAME_ROOT="$(find_game_root)"
DATA_ROOT="$(find_data_root)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_GAME="$GAME_ROOT/SunlessSeaCN-backup-$STAMP"
BACKUP_DATA="$(dirname "$DATA_ROOT")/SunlessSeaCN-backup-$STAMP"
MANIFEST="$GAME_ROOT/.sunlessseacn-install-manifest"
mkdir -p "$GAME_ROOT" "$DATA_ROOT"
: > "$MANIFEST"

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
copy_tree() {
  local srcroot="$1" destroot="$2" scope="$3" backuproot="$4"
  while IFS= read -r -d '' src; do
    local rel="${src#"$srcroot/"}" dest="$destroot/${rel}" backup="$backuproot/${rel}"
    if [[ -f "$dest" ]]; then mkdir -p "$(dirname "$backup")"; cp -p "$dest" "$backup"; fi
    mkdir -p "$(dirname "$dest")"; cp -p "$src" "$dest"
    printf '%s\t%s\t%s\n' "$scope" "$rel" "$(sha256 "$src")" >> "$MANIFEST"
  done < <(find "$srcroot" -type f -print0)
}
copy_tree "$PAYLOAD_GAME" "$GAME_ROOT" game "$BACKUP_GAME"
copy_tree "$PAYLOAD_DATA" "$DATA_ROOT" data "$BACKUP_DATA"
chmod u+x "$GAME_ROOT/run_bepinex.sh" 2>/dev/null || true
printf 'GAME_ROOT=%s\nDATA_ROOT=%s\nBACKUP_GAME=%s\nBACKUP_DATA=%s\n' "$GAME_ROOT" "$DATA_ROOT" "$BACKUP_GAME" "$BACKUP_DATA" | cat >> "$MANIFEST"
echo "Sunless Sea 中文补丁已安装。"
echo "游戏目录: $GAME_ROOT"
echo "数据目录: $DATA_ROOT"
echo "Steam 启动选项: ./run_bepinex.sh %command%"
echo "如 Steam 阻止脚本运行，请在终端执行: xattr -dr com.apple.quarantine \"$GAME_ROOT\""
if [[ "${SUNLESS_SEA_CN_LAUNCH_AFTER_INSTALL:-0}" == "1" ]]; then
  echo "正在通过 BepInEx 直接启动 Sunless Sea..."
  export SteamAppId=304650
  export SteamGameId=304650
  if ! pgrep -x "Steam" >/dev/null 2>&1; then
    open -a "Steam" >/dev/null 2>&1 || true
    sleep 3
  fi
  exec "$GAME_ROOT/run_bepinex.sh"
fi
'''

MAC_UNINSTALL_SH = r'''#!/bin/bash
set -euo pipefail
GAME_ROOT="${SUNLESS_SEA_GAME_ROOT:-}"
if [[ -z "$GAME_ROOT" ]]; then
  GAME_ROOT="$HOME/Library/Application Support/Steam/steamapps/common/SunlessSea"
fi
MANIFEST="$GAME_ROOT/.sunlessseacn-install-manifest"
[[ -f "$MANIFEST" ]] || { echo "未找到安装清单: $MANIFEST" >&2; exit 1; }
DATA_ROOT="$(awk -F= '$1=="DATA_ROOT"{print substr($0,index($0,"=")+1)}' "$MANIFEST")"
BACKUP_GAME="$(awk -F= '$1=="BACKUP_GAME"{print substr($0,index($0,"=")+1)}' "$MANIFEST")"
BACKUP_DATA="$(awk -F= '$1=="BACKUP_DATA"{print substr($0,index($0,"=")+1)}' "$MANIFEST")"
while IFS=$'\t' read -r scope rel expected; do
  [[ "$scope" == "game" || "$scope" == "data" ]] || continue
  root="$GAME_ROOT"; [[ "$scope" == "data" ]] && root="$DATA_ROOT"
  dest="$root/$rel"
  if [[ -f "$dest" && "$(shasum -a 256 "$dest" | awk '{print $1}')" == "$expected" ]]; then rm -f "$dest"; fi
done < "$MANIFEST"
restore_tree() {
  local backup="$1" destroot="$2"
  [[ -d "$backup" ]] || return 0
  while IFS= read -r -d '' src; do
    local rel="${src#"$backup/"}" dest="$destroot/$rel"
    mkdir -p "$(dirname "$dest")"; cp -p "$src" "$dest"
  done < <(find "$backup" -type f -print0)
}
restore_tree "$BACKUP_GAME" "$GAME_ROOT"
restore_tree "$BACKUP_DATA" "$DATA_ROOT"
rm -f "$MANIFEST"
echo "卸载完成。备份目录未删除。"
'''

MAC_INSTALL_CMD = r'''#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/Install-SunlessSeaCN.sh"
'''

MAC_START_SH = r'''#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SUNLESS_SEA_CN_LAUNCH_AFTER_INSTALL=1
exec "$SCRIPT_DIR/Install-SunlessSeaCN.sh"
'''

MAC_START_CMD = r'''#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/Install-And-Start-SunlessSeaCN.sh"
'''

MAC_UNINSTALL_CMD = r'''#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/Uninstall-SunlessSeaCN.sh"
'''

WIN_README = """Sunless Sea 中文补丁 6.0.4 - Windows\n\n安装：双击 Install-SunlessSeaCN.cmd。Steam 安装目录找不到时，可在 PowerShell 中设置：\n  $env:SUNLESS_SEA_GAME_ROOT='D:\\SteamLibrary\\steamapps\\common\\SunlessSea'\n  .\\Install-SunlessSeaCN.ps1\n\n卸载：双击 Uninstall-SunlessSeaCN.cmd。安装器会在覆盖已有文件前创建 SunlessSeaCN-backup-* 备份。\n\n本包包含：BepInEx 5.4.23.5、SunlessSeaChineseTranslation 6.0.0、完整文本 addon。\n"""

MAC_README = """Sunless Sea 中文补丁 6.0.4 - macOS\n\n最简单的用法：解压后直接双击 Install-And-Start-SunlessSeaCN.command。它会自动寻找 Steam 游戏目录、安装汉化，然后通过 BepInEx 直接启动游戏；不需要手动复制文件，也不需要设置 Steam 启动选项。Steam 客户端未运行时，脚本会尝试自动打开 Steam。\n\n安装包可以放在下载文件夹、桌面或其他本地目录，不需要把整个安装包文件夹放进游戏目录。高级用法仍可双击 Install-SunlessSeaCN.command，仅安装而不启动游戏。\n\n游戏根目录是：\n  ~/Library/Application Support/Steam/steamapps/common/SunlessSea/\n其中应当能看到 Sunless Sea.app。安装器会把 payload/game 的内容复制到这个目录，把 payload/data 的文本 addon 复制到玩家数据目录。不要把文件复制到 Sunless Sea.app/Contents。\n\n如果 Finder 报“无法运行，因为你没有正确的访问权限”，在终端执行（把路径改成解压后的实际路径）：\n  cd \"/path/to/SunlessSeaCN-macOS-v6.0.4\"\n  chmod u+x Install-And-Start-SunlessSeaCN.command Install-And-Start-SunlessSeaCN.sh Install-SunlessSeaCN.command Install-SunlessSeaCN.sh Uninstall-SunlessSeaCN.command Uninstall-SunlessSeaCN.sh\n  xattr -dr com.apple.quarantine .\n  ./Install-And-Start-SunlessSeaCN.command\n也可以直接绕过执行位运行：\n  bash Install-And-Start-SunlessSeaCN.sh\n\n如果你选择“仅安装”模式，Steam 启动选项仍可作为备用方式：`./run_bepinex.sh %command%`。一键启动模式不需要这个设置。\n\n卸载：双击 Uninstall-SunlessSeaCN.command，或在终端运行 bash Uninstall-SunlessSeaCN.sh。安装器会在覆盖已有文件前创建备份。\n\n注意：本包使用 BepInEx 5.4.23.5 macOS universal loader；Windows 可在本机完整测试，macOS 运行时仍需在 Mac 上第一次启动验证。\n"""

PACKAGE_NOTICE = """第三方来源与许可证说明\n\n本安装包不是 Sunless Sea 游戏本体，也不包含游戏原始资源；使用前请先合法拥有并安装 Sunless Sea。\n\n1. UI 插件：部分内容来自 tinygrox/SunlessSeaCN：\n   https://github.com/tinygrox/SunlessSeaCN\n   上游仓库包含 GPL-3.0 LICENSE；其 README 另有 CC-BY 4.0 说明。这里保留上游版权和许可证，不改变上游条款。\n\n2. 文本 addon：参考并整理自 InstantComet/SunlessSea：\n   https://github.com/InstantComet/SunlessSea\n   该仓库当前未发现独立 LICENSE 文件；其 README 将项目定位为文本汉化并注明项目延续自 diskrubbish 的项目。请保留原作者署名，不将上游文本声称为本人的原创。\n\n3. Mod 加载器：BepInEx 5.4.23.5：\n   https://github.com/BepInEx/BepInEx/releases/tag/v5.4.23.5\n   BepInEx 按其上游 LGPL-2.1 等许可证发布；完整条款和源码请以官方仓库为准。\n\n本仓库原创部分仅包括安装/卸载脚本、打包脚本、兼容性整理、测试记录和说明文档。第三方文件的许可证优先于本仓库原创部分的许可证。\n"""

PLUGIN_README = """Sunless Sea 中文 UI 插件说明（兼容包 6.0.4）

本包的安装器会自动放置 BepInEx、插件和文本 addon，不需要手动覆盖游戏原文件。

Windows：双击包根目录的 Install-SunlessSeaCN.cmd。
macOS：双击包根目录的 Install-And-Start-SunlessSeaCN.command；它会安装后直接启动游戏。

不要照搬旧版教程把 BepInEx.cfg 的 `Type = Application` 改成 `Type = Camera`；当前已验证的 Sunless Sea 安装使用 `Application` 即可正常加载插件。

卸载请使用包根目录的卸载脚本。安装器会创建备份并尽量恢复用户原有文件。
"""


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Windows CMD requires CRLF; LF-only .cmd files can lose the first
    # character of commands when launched through cmd.exe.
    newline = "\r\n" if path.suffix.lower() in {".cmd", ".bat"} else "\n"
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write(normalized.replace("\n", newline))


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def copy_tree(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def zip_dir(src: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        target.unlink()
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in sorted(src.rglob("*")):
            if p.is_file():
                arcname = str(p.relative_to(src.parent)).replace("\\", "/")
                info = zipfile.ZipInfo(arcname)
                info.compress_type = zipfile.ZIP_DEFLATED
                # Mark entries as Unix files so macOS Archive Utility preserves
                # executable bits. Without create_system=3, a Windows-built
                # ZIP can turn .command/.sh files into non-executable files.
                info.create_system = 3
                mode = 0o755 if p.suffix in {".sh", ".command"} else 0o644
                info.external_attr = (mode & 0xFFFF) << 16
                zf.writestr(info, p.read_bytes())


def build_windows() -> Path:
    out = DIST / f"SunlessSeaCN-Windows-v{WIN_VERSION}"
    if out.exists():
        shutil.rmtree(out)
    payload_game = out / "payload" / "game"
    payload_data = out / "payload" / "data"
    for name in (".doorstop_version", "doorstop_config.ini", "winhttp.dll"):
        copy_file(WIN_GAME / name, payload_game / name)
    copy_tree(WIN_GAME / "BepInEx" / "core", payload_game / "BepInEx" / "core")
    copy_file(WIN_GAME / "BepInEx" / "config" / "BepInEx.cfg", payload_game / "BepInEx" / "config" / "BepInEx.cfg")
    copy_tree(WIN_GAME / "BepInEx" / "plugins" / "SunlessSeaChineseTranslation", payload_game / "BepInEx" / "plugins" / "SunlessSeaChineseTranslation")
    plugin_dir = payload_game / "BepInEx" / "plugins" / "SunlessSeaChineseTranslation"
    for old_note in plugin_dir.glob("*.txt"):
        old_note.unlink()
    write_text(plugin_dir / "README-插件说明.txt", PLUGIN_README)
    copy_tree(WIN_DATA / "addon" / "Sunless_sea_CN_reborn", payload_data / "addon" / "Sunless_sea_CN_reborn")
    write_text(out / "Install-SunlessSeaCN.ps1", WIN_PS1)
    write_text(out / "Uninstall-SunlessSeaCN.ps1", WIN_UNINSTALL_PS1)
    write_text(out / "Install-SunlessSeaCN.cmd", WIN_INSTALL_CMD)
    write_text(out / "Uninstall-SunlessSeaCN.cmd", WIN_UNINSTALL_CMD)
    write_text(out / "README-安装说明.txt", WIN_README)
    write_text(out / "THIRD-PARTY-NOTICES.txt", PACKAGE_NOTICE)
    copy_file(ROOT / "LICENSE-ORIGINAL.txt", out / "LICENSE-ORIGINAL.txt")
    zip_dir(out, DIST / f"SunlessSeaCN-Windows-v{WIN_VERSION}.zip")
    return out


def build_macos() -> Path:
    out = DIST / f"SunlessSeaCN-macOS-v{MAC_VERSION}"
    if out.exists():
        shutil.rmtree(out)
    payload_game = out / "payload" / "game"
    payload_data = out / "payload" / "data"
    managed = MAC_STATIC_BUILD / "staging" / "Managed"
    addon = MAC_STATIC_BUILD / "player-data" / "addon" / "Sunless_sea_CN_reborn"
    delta = MAC_STATIC_BUILD / "delta" / "Sunless.Game.bsdiff"
    required = (
        delta,
        managed / "SunlessSeaChineseTranslation.dll",
        managed / "0Harmony.dll",
        managed / "SunlessSeaCN" / "Data" / "qualities.json",
        addon,
    )
    for path in required:
        if not path.exists():
            raise SystemExit(f"Missing macOS static build artifact: {path}")
    copy_file(delta, payload_game / "Sunless.Game.bsdiff")
    # Only the standalone patch, Harmony, and localization resources are
    # distributed. The original and patched full game DLLs stay out of ZIP.
    for name in ("SunlessSeaChineseTranslation.dll", "0Harmony.dll"):
        copy_file(managed / name, payload_game / "Managed" / name)
    copy_tree(managed / "SunlessSeaCN", payload_game / "Managed" / "SunlessSeaCN")
    copy_tree(addon, payload_data / "addon" / "Sunless_sea_CN_reborn")
    source_macos = ROOT / "packaging" / "macos"
    for name in (
        "Install-SunlessSeaCN.sh",
        "Install-And-Start-SunlessSeaCN.sh",
        "Uninstall-SunlessSeaCN.sh",
        "Install-SunlessSeaCN.command",
        "Install-And-Start-SunlessSeaCN.command",
        "Uninstall-SunlessSeaCN.command",
    ):
        copy_file(source_macos / name, out / name)
    mac_readme = """Sunless Sea 中文补丁 6.0.5 - macOS\n\n本版针对 Steam AppID 304650、BuildID 24437295、Unity 6000.3.2f1 的 macOS universal Mono 版本。请先关闭游戏和 Steam 的 Sunless Sea 进程。\n\n安装：双击 Install-And-Start-SunlessSeaCN.command；只安装则双击 Install-SunlessSeaCN.command。安装器将对 Sunless.Game.dll 做版本校验后使用 bsdiff 临时生成目标文件，复制 UI 插件和文本 addon，并对 app 进行 ad-hoc codesign 严格校验。\n\nUnity 6 的玩家数据目录固定优先为：\n  ~/Library/Application Support/com.failbettergames.sunlesssea\n旧版 unity.Failbetter Games.Sunless Sea 目录不会因为存在旧存档而被自动选用。\n\n卸载：双击 Uninstall-SunlessSeaCN.command。安装器会校验补丁文件哈希，只移除仍未被用户修改的文件，并恢复备份；备份目录不会自动删除。\n\n本包不含游戏本体、完整原始 DLL 或完整 patched DLL；Steam 更新后若 Sunless.Game.dll hash 不匹配，安装器会拒绝修改。\n"""
    write_text(out / "README-安装说明.txt", mac_readme)
    write_text(out / "THIRD-PARTY-NOTICES.txt", PACKAGE_NOTICE + "\n\n4. 静态 UI 路线：本 macOS 包复用 tinygrox/SunlessSeaCN GPL-3.0 源码快照，新增 Bootstrap 与 Mono.Cecil 注入器；对应源码和归属见仓库 macos-static/。\n\n5. Harmony：Lib.Harmony 2.4.2，MIT；NuGet nupkg SHA-256 见 SOURCES-LOCK.json。\n")
    copy_file(ROOT / "packaging" / "macos" / "sources.lock.json", out / "SOURCES-LOCK.json")
    copy_file(ROOT / "macos-static" / "LICENSE-GPL-3.0.txt", out / "LICENSE-GPL-3.0.txt")
    copy_file(ROOT / "macos-static" / "LICENSE-HARMONY-MIT.txt", out / "LICENSE-HARMONY-MIT.txt")
    copy_file(ROOT / "LICENSE-ORIGINAL.txt", out / "LICENSE-ORIGINAL.txt")
    for p in (out / "Install-SunlessSeaCN.sh", out / "Install-And-Start-SunlessSeaCN.sh", out / "Uninstall-SunlessSeaCN.sh", out / "Install-SunlessSeaCN.command", out / "Install-And-Start-SunlessSeaCN.command", out / "Uninstall-SunlessSeaCN.command"):
        p.chmod(p.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    zip_dir(out, DIST / f"SunlessSeaCN-macOS-v{MAC_VERSION}.zip")
    return out


def main() -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    if mode not in {"all", "--macos-only", "--windows-only"}:
        raise SystemExit("usage: build_packages.py [--macos-only|--windows-only]")
    if mode in {"all", "--windows-only"}:
        print(f"built {build_windows()}")
    if mode in {"all", "--macos-only"}:
        print(f"built {build_macos()}")


if __name__ == "__main__":
    main()
