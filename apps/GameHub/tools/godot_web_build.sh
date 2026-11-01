#!/usr/bin/env bash
#
# Dựng bản web cho game Godot **3.x** mà không cần chạy editor.
#
#   ./godot_web_build.sh <thư-mục-game> [output-dir]
#
# Vì sao không dùng `godot --export-release`?
#     Godot 3.3 bản **headless** trên Linux không export được (editor cần X11,
#     bản có GUI chỉ phát hành cho Windows/macOS). Nhưng bản export
#     `webassembly_release.zip` chứa sẵn runtime (godot.js + godot.wasm) và
#     file HTML với các placeholder `$GODOT_*` → thay placeholder bằng tay là
#     xong, không cần editor.
#
# Cách làm:
#   1. Giải nén template `webassembly_release.zip` (Godot 3.x).
#   2. Thay các placeholder:
#        $GODOT_PROJECT_NAME → tên game
#        $GODOT_URL          → godot.js
#        $GODOT_CONFIG       → { "args":[], "executable":"index", … }
#        $GODOT_HEAD_INCLUDE  → (rỗng)
#   3. Copy `.pck` của game vào `index.pck`.
#
# Godot 4.x dùng `godot_web_export.sh` (editor 4.x headless export được).
#
set -euo pipefail

GAME_DIR="${1:?Usage: $0 <thư-mục-game> [output-dir]}"
OUT="${2:-}"

GODOT_HOME="${GODOT_HOME:-$HOME/godot-dl}"
TEMPLATES_DIR="${GODOT_TEMPLATES:-$HOME/.local/share/godot/export_templates}"

GAME_DIR="$(cd "$GAME_DIR" && pwd)"

# --- Tìm .pck chính ---
# Ưu tiên pck trùng tên với file .exe của game (đó là pack engine nạp đầu tiên),
# ví dụ Game.exe → Game.pck. Nếu không có, chọn file lớn nhất.
PCK=""
EXE_BASE=""
for e in "$GAME_DIR"/*.exe; do
    [ -f "$e" ] || continue
    EXE_BASE="$(basename "$e" .exe)"
    break
done
if [ -n "$EXE_BASE" ] && [ -f "$GAME_DIR/$EXE_BASE.pck" ]; then
    PCK="$GAME_DIR/$EXE_BASE.pck"
fi
if [ -z "$PCK" ]; then
    for cand in "$GAME_DIR"/*.pck; do
        [ -f "$cand" ] || continue
        if [ -z "$PCK" ] || [ "$(stat -c%s "$cand")" -gt "$(stat -c%s "$PCK")" ]; then
            PCK="$cand"
        fi
    done
fi
if [ -z "$PCK" ]; then
    echo "❌ Không tìm thấy .pck trong $GAME_DIR" >&2
    exit 1
fi

# --- Đọc version Godot từ header ---
read -r GODOT_VER < <(python3 - "$PCK" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    head = f.read(16)
if head[:4] != b'GDPC':
    print("0"); sys.exit()
major = struct.unpack('<I', head[8:12])[0]
minor = struct.unpack('<I', head[12:16])[0]
print(f"{major}.{minor}")
PY
)

echo "→ Game pck : $PCK"
echo "→ Godot    : $GODOT_VER"

if [ "${GODOT_VER%%.*}" != "3" ]; then
    echo "❌ Script này dành cho Godot 3.x (game là $GODOT_VER)." >&2
    echo "   Dùng godot_web_export.sh cho Godot 4.x." >&2
    exit 1
fi

TPL="$TEMPLATES_DIR/${GODOT_VER}.stable/webassembly_release.zip"
if [ ! -f "$TPL" ]; then
    echo "❌ Thiếu template: $TPL" >&2
    echo "   Tải Godot_v${GODOT_VER}-stable_export_templates.tpz rồi giải nén vào" >&2
    echo "   $TEMPLATES_DIR/${GODOT_VER}.stable/" >&2
    exit 1
fi

if [ -z "$OUT" ]; then
    OUT="$GAME_DIR/../$(basename "$GAME_DIR")-web"
fi
rm -rf "$OUT"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -oq "$TPL" -d "$WORK"

PROJECT_NAME="$(basename "$GAME_DIR" | sed 's/[^A-Za-z0-9 _-]//g')"
PCK_SIZE="$(stat -c%s "$PCK")"
WASM_SIZE="$(stat -c%s "$WORK/godot.wasm")"

# --- Tạo index.html từ godot.html trong template ---
python3 - "$WORK/godot.html" "$OUT/index.html" "$PROJECT_NAME" "$PCK_SIZE" "$WASM_SIZE" <<'PY'
import sys
src, dst, name, pck_size, wasm_size = sys.argv[1:6]
html = open(src, encoding="utf-8").read()
config = (
    '{"args":[],"canvasResizePolicy":2,"executable":"index",'
    f'"experimentalVK":false,"fileSizes":{{"index.pck":{pck_size},'
    f'"index.wasm":{wasm_size}}},"focusCanvas":true,"gdextensionLibs":[]}}'
)
html = html.replace("$GODOT_PROJECT_NAME", name)
html = html.replace("$GODOT_URL", "godot.js")
html = html.replace("$GODOT_CONFIG", config)
html = html.replace("$GODOT_HEAD_INCLUDE", "")
open(dst, "w", encoding="utf-8").write(html)
print(f"   index.html: {len(html)} bytes")
PY

cp "$WORK/godot.js" "$WORK/godot.wasm" "$WORK/godot.audio.worklet.js" "$OUT/"
# Godot 3.x runtime nạp `<executable>.wasm` → với executable="index" là index.wasm
cp "$WORK/godot.wasm" "$OUT/index.wasm"
cp "$PCK" "$OUT/index.pck"

# Copy .pck phụ (DLC/voice) nếu có
for extra in "$GAME_DIR"/*.pck; do
    [ -f "$extra" ] || continue
    [ "$extra" = "$PCK" ] && continue
    bn="$(basename "$extra")"
    [ -f "$OUT/$bn" ] || cp "$extra" "$OUT/$bn"
done

echo
echo "✅ Xong: $OUT"
ls -la "$OUT" | awk 'NR>3 {print "   "$9"  "$5}'
du -sh "$OUT"
