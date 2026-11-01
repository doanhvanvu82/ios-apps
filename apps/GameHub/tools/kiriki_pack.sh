#!/usr/bin/env bash
#
# Đóng gói game KiriKiri (KiriKiri2 / EAIRPG) thành bản chơi được trên web.
#
#   ./kiriki_pack.sh <thư-mục-game> [output-dir]
#
# Cách làm:
#   1. Copy runtime `kirikiroid2-web` (WebAssembly của engine KiriKiri2) vào out/
#   2. Nén toàn bộ thư mục game (mọi file .xp3, .tjs, plugin…) thành `game.zip`
#   3. Runtime nạp game qua `?game=/game.zip` (nó giải nén ZIP vào OPFS).
#
# Yêu cầu: có `zip`, và runtime đã tải ở ~/Documents/Code/ios/apps/GameHub/workspace/kiriki-runtime
#
set -euo pipefail

GAME_DIR="${1:?Usage: $0 <thư-mục-game> [output-dir]}"
OUT="${2:-}"

RUNTIME="${KIRIKI_RUNTIME:-$HOME/Documents/Code/ios/apps/GameHub/workspace/kiriki-runtime}"

if [ ! -d "$GAME_DIR" ]; then
    echo "❌ Không thấy thư mục: $GAME_DIR" >&2
    exit 1
fi
if [ ! -f "$RUNTIME/index.wasm" ]; then
    echo "❌ Chưa có runtime KiriKiri tại $RUNTIME" >&2
    echo "   Tải từ: https://krkr2.fenghengzhi.com/  (index.html index.js index.wasm vlfs.js assets.zip index.worker.js)" >&2
    exit 1
fi

GAME_DIR="$(cd "$GAME_DIR" && pwd)"
if [ -z "$OUT" ]; then
    OUT="$GAME_DIR/../$(basename "$GAME_DIR")-web"
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

echo "→ Game   : $GAME_DIR"
echo "→ Output : $OUT"

# 1. Runtime
cp "$RUNTIME"/index.html "$RUNTIME"/index.js "$RUNTIME"/index.wasm \
   "$RUNTIME"/vlfs.js "$RUNTIME"/assets.zip "$RUNTIME"/index.worker.js "$OUT"/
for extra in manifest.webmanifest sw.js; do
    [ -f "$RUNTIME/$extra" ] && cp "$RUNTIME/$extra" "$OUT"/
done

# 2. Nén game
echo "→ Đang nén game vào game.zip…"
rm -f "$OUT/game.zip"
( cd "$GAME_DIR" && zip -qr "$OUT/game.zip" . \
    -x "*.exe" "savedata/*" "save/*" "*.sav" "*.log" )

# 3. Marker để app nhận diện + biết cách load
cat > "$OUT/gamehub.json" <<EOF
{
  "engine": "kirikiWeb",
  "loader": "zip",
  "game": "game.zip"
}
EOF

echo
echo "✅ Xong: $OUT"
ls -lh "$OUT" | awk '{print "   "$9"  "$5}'
du -sh "$OUT"
