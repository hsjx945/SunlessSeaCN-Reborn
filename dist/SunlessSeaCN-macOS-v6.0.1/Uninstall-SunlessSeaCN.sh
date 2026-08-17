#!/bin/bash
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
