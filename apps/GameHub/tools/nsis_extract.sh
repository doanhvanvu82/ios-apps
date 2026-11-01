#!/usr/bin/env bash
#
# Giải nén game đóng gói trong installer NSIS (file .exe tự giải nén).
#
#   ./nsis_extract.sh <thư-mục-hoặc-file-exe> [output-dir]
#
# Nhiều game trình duyệt (Ren'Py, Godot, RPG Maker…) được phát hành dưới dạng
# installer NSIS: toàn bộ game nằm trong file .exe. 7-Zip đọc được cấu trúc
# NSIS nên ta lấy được nội dung.
#
# Đặc biệt hữu ích với game Godot: file `pck` bên trong là archive của engine
# → dùng tools/godot_web_export.sh để đưa lên web.
#
set -euo pipefail

SRC="${1:?Usage: $0 <thư-mục-game | file-exe> [output-dir]}"
OUT="${2:-}"

if [ -d "$SRC" ]; then
    # tìm .exe lớn nhất trong thư mục
    EXE="$(find "$SRC" -maxdepth 2 -name "*.exe" -size +50M | head -1)"
    [ -z "$EXE" ] && { echo "❌ Không tìm thấy .exe lớn (>50MB) trong $SRC" >&2; exit 1; }
    SRC_DIR="$(cd "$SRC" && pwd)"
elif [ -f "$SRC" ]; then
    EXE="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
    SRC_DIR="$(dirname "$EXE")"
else
    echo "❌ Không thấy: $SRC" >&2
    exit 1
fi

command -v 7z >/dev/null || { echo "❌ Cần 7-Zip (7z)" >&2; exit 1; }

if [ -z "$OUT" ]; then
    OUT="$SRC_DIR/$(basename "${EXE%.exe}")-extracted"
fi
rm -rf "$OUT"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

echo "→ Installer: $EXE"
echo "→ Out     : $OUT"

# Liệt kê trước khi giải nén
echo "→ Nội dung installer:"
7z l "$EXE" 2>/dev/null | sed -n '/^----------------/,$p' | tail -n +2 | head -25

echo "→ Đang giải nén…"
7z x -y -o"$OUT" "$EXE" > /dev/null 2>&1 || true

echo
echo "✅ Đã giải nén:"
find "$OUT" -maxdepth 2 -type f -printf "   %10s  %p\n" | sort -k2 | head -20

# Nếu có file pck (Godot) → báo cáo version
for p in "$OUT"/*.pck "$OUT"/*/*.pck; do
    [ -f "$p" ] || continue
    python3 - "$p" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    h = f.read(16)
if h[:4] == b'GDPC':
    pack = struct.unpack('<I', h[4:8])[0]
    ma, mi, pa = struct.unpack('<I', h[8:12])[0], struct.unpack('<I', h[12:16])[0], 0
    print(f"   🎮 Godot PCK v{pack} — version {ma}.{mi} → dùng tools/godot_web_export.sh")
PY
done
du -sh "$OUT"
