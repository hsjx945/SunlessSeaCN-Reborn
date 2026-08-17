#!/bin/bash
set -euo pipefail

GAME_ROOT="${SUNLESS_SEA_GAME_ROOT:-$HOME/Library/Application Support/Steam/steamapps/common/SunlessSea}"
MANIFEST="$GAME_ROOT/.sunlessseacn-install-manifest"
LOCK_DIR="$GAME_ROOT/.sunlessseacn-install.lock"

die() { printf 'Sunless Sea 中文补丁: %s\n' "$1" >&2; exit 2; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
[[ -f "$MANIFEST" ]] || die "未找到 v6.0.5 安装清单: $MANIFEST"
head -n 1 "$MANIFEST" | grep -q '^SUNLESSSEACN_MANIFEST=2$' || die "不是 v6.0.5 安装清单"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then die "已有另一个安装或卸载正在进行: $LOCK_DIR"; fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

DATA_ROOT="$(awk -F= '$1=="DATA_ROOT"{print substr($0,index($0,"=")+1)}' "$MANIFEST")"
BACKUP_ROOT="$(awk -F= '$1=="BACKUP_ROOT"{print substr($0,index($0,"=")+1)}' "$MANIFEST")"
[[ -n "$DATA_ROOT" && -n "$BACKUP_ROOT" ]] || die "安装清单缺少数据目录或备份目录"
REMOVED=0
RESTORED=0
# Preflight the complete manifest before changing a single path. A missing or
# modified installed file is user state; partial uninstall would leave the app
# unsigned or remove dependencies that the retained file still needs.
PREFLIGHT_ISSUES=0
while IFS=$'\t' read -r marker scope rel expected had backup; do
  [[ "$marker" == "RECORD" ]] || continue
  root="$GAME_ROOT"
  [[ "$scope" == "data" ]] && root="$DATA_ROOT"
  dest="$root/$rel"
  if [[ ! -e "$dest" ]]; then
    printf '检测到已删除的安装文件，未执行卸载: %s\n' "$dest" >&2
    PREFLIGHT_ISSUES=$((PREFLIGHT_ISSUES + 1))
    continue
  fi
  actual="$(sha256 "$dest")"
  if [[ "$actual" != "$expected" ]]; then
    printf '检测到用户修改，未执行卸载: %s\n' "$dest" >&2
    PREFLIGHT_ISSUES=$((PREFLIGHT_ISSUES + 1))
  fi
done < "$MANIFEST"
if [[ "$PREFLIGHT_ISSUES" != "0" ]]; then
  printf '卸载前检查失败；未修改任何已安装文件，安装清单已保留。\n' >&2
  exit 3
fi

while IFS=$'\t' read -r marker scope rel expected had backup; do
  [[ "$marker" == "RECORD" ]] || continue
  root="$GAME_ROOT"
  [[ "$scope" == "data" ]] && root="$DATA_ROOT"
  dest="$root/$rel"
  rm -f "$dest"
  REMOVED=$((REMOVED + 1))
  if [[ "$had" == "1" && -f "$backup" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp -p "$backup" "$dest"
    RESTORED=$((RESTORED + 1))
  fi
done < "$MANIFEST"

APP="$GAME_ROOT/Sunless Sea.app"
command -v codesign >/dev/null 2>&1 || die "找不到 codesign，无法恢复有效应用签名"
codesign --force --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP" >/dev/null
rm -f "$MANIFEST"
printf '卸载完成；删除 %s 个补丁文件，恢复 %s 个备份文件。\n' "$REMOVED" "$RESTORED"
printf '备份目录保留: %s\n' "$BACKUP_ROOT"
