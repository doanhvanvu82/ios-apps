#!/usr/bin/env bash
#
# Build bản web cho game Ren'Py (desktop) để chơi được trên iOS.
#
#   ./renpy_web_build.sh "/path/to/game"          # build 1 game
#   ./renpy_web_build.sh "/path/to/game" "outdir"  # build, chỉ định thư mục đích
#
# Ren'Py 8.3+ hỗ trợ "web export": đóng gói game thành `index.html` + `game.zip`
# chạy được trong trình duyệt. Đây chính là dạng mà GameHub nhận diện là
# engine "Ren'Py (Web)".
#
# Yêu cầu: Ren'Py SDK đã cài tại ~/renpy (xem README.md).
#
set -euo pipefail

GAME_DIR="${1:?Usage: $0 <game-dir> [out-dir]}"
OUT_DIR="${2:-}"

RENPY_HOME="${RENPY_HOME:-$HOME/renpy}"
RENPY="$RENPY_HOME/renpy.sh"

if [ ! -x "$RENPY" ]; then
    echo "❌ Không tìm thấy Ren'Py SDK tại $RENPY" >&2
    echo "   Tải từ https://www.renpy.org/dl/8.5.2/renpy-8.5.2-sdk.tar.bz2" >&2
    echo "   rồi giải nén vào $RENPY_HOME" >&2
    exit 1
fi

if [ ! -d "$GAME_DIR/game" ]; then
    echo "❌ '$GAME_DIR' không phải thư mục game Ren'Py (thiếu thư mục game/)" >&2
    exit 1
fi

GAME_DIR="$(cd "$GAME_DIR" && pwd)"

if [ -z "$OUT_DIR" ]; then
    # Xuất ra thư mục cha của game, tên "<game>-web".
    OUT_DIR="$(dirname "$GAME_DIR")/$(basename "$GAME_DIR")-web"
fi
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

echo "→ Game   : $GAME_DIR"
echo "→ Output : $OUT_DIR"
echo

# Cú pháp: renpy.sh <base-dir> <command> [args...]
# base-dir phải là thư mục launcher của SDK (chứa game/ của launcher).
"$RENPY" "$RENPY_HOME/launcher" web_build "$GAME_DIR" --destination "$OUT_DIR" 2>&1 | tail -40

echo
if [ -f "$OUT_DIR/index.html" ]; then
    echo "✅ Build thành công!"
    echo "   $OUT_DIR/index.html"
    echo
    echo "   Copy thư mục này vào iPhone: Files → On My iPhone → GameHub → Imports"
    du -sh "$OUT_DIR"
else
    echo "⚠️  Không tìm thấy index.html trong output — xem log ở trên." >&2
    exit 1
fi
