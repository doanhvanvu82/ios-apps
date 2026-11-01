#!/usr/bin/env bash
#
# Chuyển game Godot (Windows, .pck) sang bản **HTML5** để chơi được trong app.
#
#   ./godot_web_export.sh <thư-mục-game> [output-dir]
#
# Cách làm:
#   1. Tạo project Godot tối giảu (chỉ để có runtime export).
#   2. Export HTML5 bằng Godot CLI → index.html + index.js + index.wasm + <name>.pck
#   3. **Thay <name>.pck bằng .pck của game** → game chạy được trong browser.
#
# Yêu cầu:
#   - Godot 4.x cùng version với game (đọc từ header .pck)
#   - Export templates đã cài ở ~/.local/share/godot/export_templates/<version>
#
set -euo pipefail

GAME_DIR="${1:?Usage: $0 <thư-mục-game> [output-dir]}"
OUT="${2:-}"

GODOT_HOME="${GODOT_HOME:-$HOME/godot-dl}"
TEMPLATES_DIR="${GODOT_TEMPLATES:-$HOME/.local/share/godot/export_templates}"

if [ ! -d "$GAME_DIR" ]; then
    echo "❌ Không thấy thư mục: $GAME_DIR" >&2
    exit 1
fi

GAME_DIR="$(cd "$GAME_DIR" && pwd)"

# --- Tìm .pck chính của game ---
PCK=""
for cand in "$GAME_DIR"/*.pck; do
    [ -f "$cand" ] || continue
    # bỏ qua file .wav.pck (voice pack phụ) — chọn file lớn nhất
    if [ -z "$PCK" ] || [ "$(stat -c%s "$cand")" -gt "$(stat -c%s "$PCK")" ]; then
        PCK="$cand"
    fi
done
if [ -z "$PCK" ]; then
    echo "❌ Không tìm thấy file .pck trong $GAME_DIR" >&2
    exit 1
fi

# --- Đọc version Godot từ header .pck ---
# Header: magic(4) "GDPC" | pack_version(4) | ver_major(4) | ver_minor(4) | ...
read -r GODOT_VER PACK_VER < <(python3 - "$PCK" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    head = f.read(16)
if head[:4] != b'GDPC':
    print("unknown unknown"); sys.exit()
pack = struct.unpack('<I', head[4:8])[0]
major = struct.unpack('<I', head[8:12])[0]
minor = struct.unpack('<I', head[12:16])[0]
print(f"{major}.{minor}", pack)
PY
)

echo "→ Game pck : $PCK"
echo "→ Godot    : $GODOT_VER (pack v$PACK_VER)"

# --- Chọn editor đúng version ---
pick_editor() {
    local v="$1"
    # ưu tiên headless (nhẹ, đủ để export)
    local cands=(
        "$GODOT_HOME/Godot_v${v}-stable_linux_headless.64"
        "$GODOT_HOME/Godot_v${v}-stable_linux.x86_64"
        "$GODOT_HOME/Godot_v${v}-stable_linux.x86_64.exe"
        "$GODOT_HOME/Godot_v${v}-stable_linux_server.64"
    )
    for c in "${cands[@]}"; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    # fallback: tìm trong thư mục
    find "$GODOT_HOME" -maxdepth 1 -type f -name "Godot_v${v}*linux*" -perm -u+x 2>/dev/null | head -1
}

GODOT="${GODOT:-$(pick_editor "$GODOT_VER")}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
    echo "❌ Không tìm thấy Godot editor cho version $GODOT_VER trong $GODOT_HOME" >&2
    echo "   Tải: Godot_v${GODOT_VER}-stable_linux_headless.64.zip" >&2
    exit 1
fi
echo "→ Editor   : $GODOT"

if [ ! -d "$TEMPLATES_DIR/$GODOT_VER.stable" ]; then
    echo "❌ Thiếu export templates cho $GODOT_VER.stable" >&2
    echo "   Cần tải: Godot_v${GODOT_VER}-stable_export_templates.tpz" >&2
    echo "   rồi giải nén vào $TEMPLATES_DIR/${GODOT_VER}.stable/" >&2
    exit 1
fi

if [ -z "$OUT" ]; then
    OUT="$GAME_DIR/../$(basename "$GAME_DIR")-web"
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Project tối giảu ---
cat > "$WORK/project.godot" <<'EOF'
config_version=5

[application]

config/name="GameHubWeb"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.1")

[rendering]

renderer/rendering_method="gl_compatibility"
EOF

cat > "$WORK/main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3 uid="uid://gamehubweb0"]

[ext_resource type="Script" path="res://main.gd" id="1_main"]

[node name="Main" type="Node"]
script = ExtResource("1_main")
EOF

cat > "$WORK/main.gd" <<'EOF'
extends Node
# GameHub: project rỗng — .pck của game sẽ được thay thế sau khi export.
func _ready() -> void:
	pass
EOF

# --- Export preset (Godot 3.x và 4.x dùng format khác nhau) ---
if [[ "$GODOT_VER" == 3.* ]]; then
cat > "$WORK/export_presets.cfg" <<'EOF'
[preset.0]

name="Web"
platform="Web"
runnable=true
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/export_icon=true
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
EOF
else
cat > "$WORK/export_presets.cfg" <<'EOF'
[preset.0]

name="Web"
platform="Web"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/export_icon=true
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
EOF
fi

echo "→ Export HTML5 (có thể mất vài phút)…"
"$GODOT" --headless --path "$WORK" --export-release "Web" "$OUT/index.html" 2>&1 | tail -12

# --- Thay .pck bằng .pck của game ---
# Loader HTML5 tải pack theo TÊN FILE cố định trong index.js/index.html
# (mặc định "index.pck") → phải ghi đè đúng file đó, không đổi tên.
SHIPPED="$OUT/index.pck"
if [ ! -f "$SHIPPED" ]; then
    SHIPPED="$(find "$OUT" -maxdepth 1 -name "*.pck" | head -1)"
fi
if [ -z "$SHIPPED" ] || [ ! -f "$SHIPPED" ]; then
    echo "❌ Không tìm thấy .pck trong output export" >&2
    exit 1
fi

echo "→ Thay .pck: $(basename "$SHIPPED") ← $(basename "$PCK")"
rm -f "$SHIPPED"
cp "$PCK" "$SHIPPED"

# Với game có nhiều .pck (DLC/voice), copy thêm vào cùng thư mục.
for extra in "$GAME_DIR"/*.pck; do
    [ -f "$extra" ] || continue
    [ "$extra" = "$PCK" ] && continue
    bn="$(basename "$extra")"
    [ -f "$OUT/$bn" ] || cp "$extra" "$OUT/$bn"
done

echo
if [ -f "$OUT/index.html" ]; then
    echo "✅ Export thành công: $OUT"
    ls -la "$OUT"
    du -sh "$OUT"
else
    echo "❌ Export thất bại" >&2
    exit 1
fi
