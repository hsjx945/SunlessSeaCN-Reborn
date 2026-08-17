#!/bin/bash
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
echo "如 Steam 阻止脚本运行，请在终端执行: xattr -dr com.apple.quarantine \"$GAME_ROOT\""
