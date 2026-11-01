#!/usr/bin/env bash
#
# Batch build bản web cho tất cả game Ren'Py trong thư viện.
#
#   ./renpy_batch_build.sh [library-dir] [output-dir]
#
# Mặc định:
#   library-dir = ~/Documents/Game
#   output-dir  = ~/Documents/Code/ios/apps/GameHub/workspace/renpy-web
#
# Game Ren'Py desktop (có thư mục `game/` + `renpy/`) sẽ được build thành
# bản web chạy được trong trình duyệt — tức là chơi được trên iOS qua GameHub.
#
set -uo pipefail

LIB="${1:-$HOME/Documents/Game}"
OUT="${2:-$HOME/Documents/Code/ios/apps/GameHub/workspace/renpy-web}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

if [ ! -d "$LIB" ]; then
    echo "❌ Không thấy thư mục thư viện: $LIB" >&2
    exit 1
fi

echo "→ Thư viện : $LIB"
echo "→ Output  : $OUT"
echo

ok=0; fail=0; skip=0
failed_list=()

for dir in "$LIB"/*/; do
    name="$(basename "$dir")"

    # Điều kiện là game Ren'Py: có thư mục game/ và renpy/
    if [ ! -d "$dir/game" ] || [ ! -d "$dir/renpy" ]; then
        continue
    fi

    # Bỏ qua nếu đã build rồi
    if [ -f "$OUT/$name/index.html" ]; then
        echo "⏭  $name — đã build (bỏ qua)"
        skip=$((skip+1))
        continue
    fi

    echo "🔨 $name"
    if "$SCRIPT_DIR/renpy_web_build.sh" "$dir" "$OUT/$name" > "/tmp/renpy-build-$$.log" 2>&1; then
        size=$(du -sh "$OUT/$name" 2>/dev/null | cut -f1)
        echo "   ✅ xong ($size)"
        ok=$((ok+1))
    else
        echo "   ❌ thất bại — xem /tmp/renpy-build-$$.log"
        tail -5 "/tmp/renpy-build-$$.log" | sed 's/^/      /'
        failed_list+=("$name")
        fail=$((fail+1))
    fi
done

echo
echo "=== Kết quả ==="
echo "  thành công : $ok"
echo "  thất bại   : $fail"
echo "  bỏ qua     : $skip"
if [ ${#failed_list[@]} -gt 0 ]; then
    printf "  thất bại   : %s\n" "${failed_list[@]}"
fi
echo
echo "Copy thư mục trong '$OUT' vào iPhone: Files → On My iPhone → GameHub → Imports"
