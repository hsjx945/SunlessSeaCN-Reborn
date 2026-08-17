#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/Install-SunlessSeaCN.sh"
GAME_ROOT="${SUNLESS_SEA_GAME_ROOT:-$HOME/Library/Application Support/Steam/steamapps/common/SunlessSea}"
open "$GAME_ROOT/Sunless Sea.app"
