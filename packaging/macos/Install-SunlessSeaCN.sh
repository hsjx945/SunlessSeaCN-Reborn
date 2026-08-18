#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_GAME="$SCRIPT_DIR/payload/game"
PAYLOAD_DATA="$SCRIPT_DIR/payload/data"
PACKAGE_VERSION="6.0.5"
ORIGINAL_GAME_SHA256="b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0"
PATCHED_GAME_SHA256="4ecc41ee6112fb9fc350a1662550fc843662861c61d6a9d80a182e0dad32bf6d"

GAME_ROOT=""
DATA_ROOT=""
APP=""
MANIFEST=""
BACKUP_ROOT=""
LOCK_DIR=""
TMP_ROOT=""
RECORDS=""
TOUCHED=""
INSTALLING=0

die() {
  printf 'Sunless Sea 中文补丁: %s\n' "$1" >&2
  exit 2
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

find_game_root() {
  local candidate
  if [[ -n "${SUNLESS_SEA_GAME_ROOT:-}" ]]; then
    [[ -d "$SUNLESS_SEA_GAME_ROOT/Sunless Sea.app" ]] || die "SUNLESS_SEA_GAME_ROOT 不是有效游戏目录: $SUNLESS_SEA_GAME_ROOT"
    printf '%s\n' "$SUNLESS_SEA_GAME_ROOT"
    return
  fi
  candidate="$HOME/Library/Application Support/Steam/steamapps/common/SunlessSea"
  if [[ -d "$candidate/Sunless Sea.app" ]]; then printf '%s\n' "$candidate"; return; fi
  candidate="$HOME/Library/Application Support/Steam/steamapps/common/Sunless Sea"
  if [[ -d "$candidate/Sunless Sea.app" ]]; then printf '%s\n' "$candidate"; return; fi
  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then die "找不到包含 Sunless Sea.app 的 Steam 游戏目录"; fi
  read -r -p "请输入包含 Sunless Sea.app 的游戏目录: " candidate
  [[ -d "$candidate/Sunless Sea.app" ]] || die "无效的游戏目录: $candidate"
  printf '%s\n' "$candidate"
}

find_data_root() {
  # Unity 6 uses this root. Do not select the legacy directory merely because
  # it contains old saves; an explicit override is the only alternate path.
  if [[ -n "${SUNLESS_SEA_DATA_ROOT:-}" ]]; then
    printf '%s\n' "$SUNLESS_SEA_DATA_ROOT"
  else
    printf '%s\n' "$HOME/Library/Application Support/com.failbettergames.sunlesssea"
  fi
}

lock_install() {
  LOCK_DIR="$GAME_ROOT/.sunlessseacn-install.lock"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then die "已有另一个安装或卸载正在进行: $LOCK_DIR"; fi
}

unlock_install() {
  if [[ -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then rmdir "$LOCK_DIR" 2>/dev/null || true; fi
}

cleanup_temp() {
  if [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" ]]; then rm -rf "$TMP_ROOT"; fi
}

backup_path() {
  local scope
  local rel
  scope="$1"
  rel="$2"
  printf '%s/%s/%s\n' "$BACKUP_ROOT" "$scope" "$rel"
}

record_file() {
  local scope
  local rel
  local root
  local dest
  local had
  local backup
  scope="$1"
  rel="$2"
  root="$GAME_ROOT"
  if [[ "$scope" == "data" ]]; then root="$DATA_ROOT"; fi
  dest="$root/$rel"
  had=0
  backup="$(backup_path "$scope" "$rel")"
  if [[ -e "$dest" ]]; then
    [[ -f "$dest" ]] || die "目标不是普通文件，拒绝覆盖: $dest"
    mkdir -p "$(dirname "$backup")"
    cp -p "$dest" "$backup"
    had=1
  fi
  printf 'RECORD\t%s\t%s\t%s\t%s\n' "$scope" "$rel" "$had" "$backup" >> "$RECORDS"
}

mark_touched() {
  printf '%s\t%s\n' "$1" "$2" >> "$TOUCHED"
}

rollback_install() {
  local scope
  local rel
  local root
  local dest
  local had
  local backup
  local marker
  [[ -f "$RECORDS" ]] || return 0
  set +e
  while IFS=$'\t' read -r marker scope rel had backup; do
    [[ "$marker" == "RECORD" ]] || continue
    if ! awk -F $'\t' -v s="$scope" -v r="$rel" '$1==s && $2==r {found=1} END {exit !found}' "$TOUCHED" 2>/dev/null; then continue; fi
    root="$GAME_ROOT"
    if [[ "$scope" == "data" ]]; then root="$DATA_ROOT"; fi
    dest="$root/$rel"
    rm -f "$dest"
    if [[ "$had" == "1" && -f "$backup" ]]; then
      mkdir -p "$(dirname "$dest")"
      cp -p "$backup" "$dest"
    fi
  done < "$RECORDS"
  set -e
}

on_exit() {
  local status
  status="$1"
  if [[ "$INSTALLING" == "1" && "$status" != "0" ]]; then
    printf '安装失败，正在回滚已写入文件。\n' >&2
    rollback_install || true
  fi
  cleanup_temp
  unlock_install
  exit "$status"
}

write_final_manifest() {
  local temp_manifest
  local marker
  local scope
  local rel
  local had
  local backup
  local root
  local dest
  local installed
  temp_manifest="$MANIFEST.tmp.$$"
  {
    printf 'SUNLESSSEACN_MANIFEST=2\n'
    printf 'PACKAGE_VERSION=%s\n' "$PACKAGE_VERSION"
    printf 'GAME_ROOT=%s\n' "$GAME_ROOT"
    printf 'DATA_ROOT=%s\n' "$DATA_ROOT"
    printf 'APP=%s\n' "$APP"
    printf 'BACKUP_ROOT=%s\n' "$BACKUP_ROOT"
    while IFS=$'\t' read -r marker scope rel had backup; do
      [[ "$marker" == "RECORD" ]] || continue
      root="$GAME_ROOT"
      if [[ "$scope" == "data" ]]; then root="$DATA_ROOT"; fi
      dest="$root/$rel"
      installed="$(sha256 "$dest")"
      printf 'RECORD\t%s\t%s\t%s\t%s\t%s\n' "$scope" "$rel" "$installed" "$had" "$backup"
    done < "$RECORDS"
  } > "$temp_manifest"
  mv "$temp_manifest" "$MANIFEST"
}

remove_previous_install() {
  local marker
  local scope
  local rel
  local expected
  local had
  local backup
  local previous_data
  local previous_game
  local root
  local dest
  local actual
  local previous_backup
  previous_game="$GAME_ROOT"
  previous_data="$(awk -F= '$1=="DATA_ROOT"{print substr($0,index($0,"=")+1)}' "$MANIFEST")"
  previous_backup="$(awk -F= '$1=="BACKUP_ROOT"{print substr($0,index($0,"=")+1)}' "$MANIFEST")"
  [[ -n "$previous_data" && -n "$previous_backup" ]] || die "安装清单不完整，请先用对应版本卸载或恢复 Steam 文件"
  while IFS=$'\t' read -r marker scope rel expected had backup; do
    [[ "$marker" == "RECORD" ]] || continue
    root="$previous_game"
    if [[ "$scope" == "data" ]]; then root="$previous_data"; fi
    dest="$root/$rel"
    if [[ -e "$dest" ]]; then
      actual="$(sha256 "$dest")"
      [[ "$actual" == "$expected" ]] || die "检测到用户修改，未自动覆盖: $dest"
    fi
  done < "$MANIFEST"
  while IFS=$'\t' read -r marker scope rel expected had backup; do
    [[ "$marker" == "RECORD" ]] || continue
    root="$previous_game"
    if [[ "$scope" == "data" ]]; then root="$previous_data"; fi
    dest="$root/$rel"
    rm -f "$dest"
    if [[ "$had" == "1" && -f "$backup" ]]; then
      mkdir -p "$(dirname "$dest")"
      cp -p "$backup" "$dest"
    fi
  done < "$MANIFEST"
  rm -f "$MANIFEST"
  printf '已清理上一份 v6.0.5 安装，备份仍保留在: %s\n' "$previous_backup"
}

install_package() {
  local managed
  local patch
  local patched_tmp
  local file
  local rel
  local src
  local dest
  local scope
  local addon_root
  local addon_src
  local addon_file
  local addon_rel
  local app_exec_rel
  local code_resources_rel
  GAME_ROOT="$(find_game_root)"
  DATA_ROOT="$(find_data_root)"
  APP="$GAME_ROOT/Sunless Sea.app"
  MANIFEST="$GAME_ROOT/.sunlessseacn-install-manifest"
  [[ -d "$PAYLOAD_GAME" && -d "$PAYLOAD_DATA" ]] || die "安装包 payload 不完整"
  [[ -x /usr/bin/bspatch ]] || die "找不到 /usr/bin/bspatch"
  command -v codesign >/dev/null 2>&1 || die "找不到 codesign"
  managed="$APP/Contents/Resources/Data/Managed"
  [[ -d "$managed" ]] || die "不是支持的 Sunless Sea.app: 缺少 Managed 目录"
  if [[ -e "$MANIFEST" ]]; then
    head -n 1 "$MANIFEST" | grep -q '^SUNLESSSEACN_MANIFEST=2$' || die "发现旧版或损坏安装清单，请先恢复/卸载旧版补丁"
    remove_previous_install
  fi
  [[ "$(sha256 "$managed/Sunless.Game.dll")" == "$ORIGINAL_GAME_SHA256" ]] || die "Sunless.Game.dll 版本不匹配，拒绝安装"
  mkdir -p "$DATA_ROOT" "$GAME_ROOT"
  BACKUP_ROOT="$GAME_ROOT/.sunlessseacn-backups/$PACKAGE_VERSION-$(date +%Y%m%d-%H%M%S)"
  TMP_ROOT="$GAME_ROOT/.sunlessseacn-tmp.$$"
  RECORDS="$TMP_ROOT/records"
  TOUCHED="$TMP_ROOT/touched"
  mkdir -p "$TMP_ROOT" "$BACKUP_ROOT"
  : > "$RECORDS"
  : > "$TOUCHED"
  app_exec_rel="Sunless Sea.app/Contents/MacOS/Sunless Sea"
  code_resources_rel="Sunless Sea.app/Contents/_CodeSignature/CodeResources"
  record_file game "Sunless Sea.app/Contents/Resources/Data/Managed/Sunless.Game.dll"
  record_file game "Sunless Sea.app/Contents/Resources/Data/Managed/SunlessSeaChineseTranslation.dll"
  record_file game "Sunless Sea.app/Contents/Resources/Data/Managed/0Harmony.dll"
  record_file game "$app_exec_rel"
  record_file game "$code_resources_rel"
  while IFS= read -r -d '' file; do
    rel="${file#"$PAYLOAD_GAME/Managed/"}"
    [[ "$rel" == "Sunless.Game.bsdiff" ]] && continue
    [[ "$rel" == "SunlessSeaChineseTranslation.dll" || "$rel" == "0Harmony.dll" ]] && continue
    record_file game "Sunless Sea.app/Contents/Resources/Data/Managed/$rel"
  done < <(find "$PAYLOAD_GAME/Managed" -type f -print0)
  addon_root="$DATA_ROOT/addon/Sunless_sea_CN_reborn"
  addon_src="$PAYLOAD_DATA/addon/Sunless_sea_CN_reborn"
  [[ -d "$addon_src" ]] || die "安装包缺少文本 addon"
  while IFS= read -r -d '' addon_file; do
    addon_rel="${addon_file#"$addon_src/"}"
    record_file data "addon/Sunless_sea_CN_reborn/$addon_rel"
  done < <(find "$addon_src" -type f -print0)
  mark_touched game "$app_exec_rel"
  mark_touched game "$code_resources_rel"
  INSTALLING=1
  patch="$PAYLOAD_GAME/Sunless.Game.bsdiff"
  [[ -f "$patch" ]] || die "安装包缺少 Sunless.Game.bsdiff"
  # Keep every not-yet-validated output under TMP_ROOT so the EXIT trap removes
  # it even when bspatch succeeds but the target hash check fails.
  patched_tmp="$TMP_ROOT/Sunless.Game.dll.patched"
  mark_touched game "Sunless Sea.app/Contents/Resources/Data/Managed/Sunless.Game.dll"
  /usr/bin/bspatch "$managed/Sunless.Game.dll" "$patched_tmp" "$patch"
  [[ "$(sha256 "$patched_tmp")" == "$PATCHED_GAME_SHA256" ]] || die "补丁结果 hash 不匹配"
  mv "$patched_tmp" "$managed/Sunless.Game.dll"
  while IFS= read -r -d '' file; do
    rel="${file#"$PAYLOAD_GAME/Managed/"}"
    [[ "$rel" == "Sunless.Game.bsdiff" ]] && continue
    dest="$managed/$rel"
    src="$PAYLOAD_GAME/Managed/$rel"
    mark_touched game "Sunless Sea.app/Contents/Resources/Data/Managed/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -p "$src" "$dest"
  done < <(find "$PAYLOAD_GAME/Managed" -type f -print0)
  while IFS= read -r -d '' addon_file; do
    addon_rel="${addon_file#"$addon_src/"}"
    dest="$DATA_ROOT/addon/Sunless_sea_CN_reborn/$addon_rel"
    mark_touched data "addon/Sunless_sea_CN_reborn/$addon_rel"
    mkdir -p "$(dirname "$dest")"
    cp -p "$addon_file" "$dest"
  done < <(find "$addon_src" -type f -print0)
  codesign --force --sign - "$APP" >/dev/null
  codesign --verify --deep --strict "$APP" >/dev/null
  [[ "$(sha256 "$managed/Sunless.Game.dll")" == "$PATCHED_GAME_SHA256" ]] || die "安装后游戏程序集 hash 不匹配"
  write_final_manifest
  INSTALLING=0
  printf 'Sunless Sea 中文补丁 v%s 已安装。\n' "$PACKAGE_VERSION"
  printf '游戏目录: %s\n' "$GAME_ROOT"
  printf 'Unity 6 数据目录: %s\n' "$DATA_ROOT"
  printf '旧版 legacy 数据目录不会被自动选用。\n'
}

trap 'on_exit "$?"' EXIT
GAME_ROOT="$(find_game_root)"
lock_install
install_package
