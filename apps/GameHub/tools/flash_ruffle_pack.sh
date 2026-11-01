#!/usr/bin/env bash
#
# Đóng gói game Adobe Flash (.swf) để chơi được trong app iOS.
#
#   ./flash_ruffle_pack.sh <thư-mục-game> [output-dir]
#
# Cách làm:
#   1. Tìm SWF chính (file .swf lớn nhất, hoặc SWF nhúng trong file .exe
#      của Flash projector).
#   2. Copy toàn bộ .swf phụ + ảnh.
#   3. Đưa runtime **Ruffle** (Flash emulator viết bằng Rust → WebAssembly) vào.
#   4. Tạo index.html gọi Ruffle để chạy SWF chính.
#
# Yêu cầu: runtime Ruffle đã tải ở ~/Documents/Code/ios/apps/GameHub/workspace/ruffle/ext
#
set -euo pipefail

GAME_DIR="${1:?Usage: $0 <thư-mục-game> [output-dir]}"
OUT="${2:-}"

RUFFLE="${RUFFLE_EXT:-$HOME/Documents/Code/ios/apps/GameHub/workspace/ruffle/ext}"
RUFFLE_SELFHOSTED="${RUFFLE_SELFHOSTED:-$HOME/Documents/Code/ios/apps/GameHub/workspace/ruffle/selfhosted}"

if [ ! -d "$GAME_DIR" ]; then
    echo "❌ Không thấy thư mục: $GAME_DIR" >&2
    exit 1
fi
if [ ! -f "$RUFFLE_SELFHOSTED/ruffle.js" ] && [ ! -f "$RUFFLE/dist/ruffle.js" ]; then
    echo "❌ Chưa có runtime Ruffle" >&2
    echo "   Tải: https://github.com/ruffle-rs/ruffle/releases → ruffle-<ver>-web-selfhosted.zip" >&2
    exit 1
fi

GAME_DIR="$(cd "$GAME_DIR" && pwd)"
if [ -z "$OUT" ]; then
    OUT="$GAME_DIR/../$(basename "$GAME_DIR")-web"
fi
rm -rf "$OUT"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

echo "→ Game: $GAME_DIR"
echo "→ Out : $OUT"

# --- 1. Copy toàn bộ .swf ---
SWF_COUNT=0
while IFS= read -r -d '' f; do
    rel="${f#$GAME_DIR/}"
    mkdir -p "$OUT/$(dirname "$rel")"
    cp "$f" "$OUT/$rel"
    SWF_COUNT=$((SWF_COUNT+1))
done < <(find "$GAME_DIR" -name "*.swf" -print0)
echo "→ Copy $SWF_COUNT file .swf"

# Copy ảnh (nếu có)
if [ -d "$GAME_DIR/images" ]; then
    cp -r "$GAME_DIR/images" "$OUT/"
    echo "→ Copy thư mục images/"
fi

# --- 2. Tìm SWF chính (entry point) ---
# Ưu tiên:
#  1. Tên do biết trước: top.swf / Stage.swf / index.swf / game.swf / main.swf
#  2. SWF nhúng trong file .exe của Flash projector → entry point thật
#     (nó load `data/<shell>.swf` bằng đường dẫn tương đối).
#  3. File .swf lớn nhất.
MAIN=""
for cand in top.swf Stage.swf index.swf game.swf main.swf start.swf; do
    if [ -f "$OUT/$cand" ]; then MAIN="$OUT/$cand"; break; fi
done
if [ -n "$MAIN" ]; then
    echo "→ SWF entry point: $(basename "$MAIN") ($(du -h "$MAIN" | cut -f1))"
else
EXE="$(find "$GAME_DIR" -name "*.exe" -size +1M | head -1)"
if [ -n "$EXE" ]; then
    echo "→ Trích SWF entry point từ projector: $(basename "$EXE")"
    python3 - "$EXE" "$OUT" <<'PY'
import struct, sys, os
exe, out = sys.argv[1], sys.argv[2]
d = open(exe, "rb").read()
best = None
for i in range(len(d) - 8):
    if d[i] in (0x46, 0x43, 0x5A) and d[i+1] == 0x57 and d[i+2] == 0x53:
        ver = d[i+3]
        if 5 <= ver <= 100:
            ln = struct.unpack('<I', d[i+4:i+8])[0]
            if 1000 < ln <= len(d) - i and (best is None or ln > best[1]):
                best = (i, ln)
if not best:
    sys.exit("❌ Không tìm thấy SWF hợp lệ trong .exe")
i, ln = best
p = os.path.join(out, "top.swf")
open(p, "wb").write(d[i:i+ln])
print(f"   → top.swf ({ln} bytes) tại offset {i}")
PY
    MAIN="$OUT/top.swf"
else
    MAIN="$(find "$OUT" -name "*.swf" -printf "%s %p\n" | sort -rn | head -1 | cut -d' ' -f2-)"
    echo "→ SWF chính: $(basename "$MAIN") ($(du -h "$MAIN" | cut -f1))"
fi
fi

# --- 3. Runtime Ruffle (bản self-hosted) ---
if [ -d "$RUFFLE_SELFHOSTED" ]; then
    cp "$RUFFLE_SELFHOSTED"/*.js "$RUFFLE_SELFHOSTED"/*.wasm "$OUT"/ 2>/dev/null || true
    echo "→ Copy runtime Ruffle self-hosted"
else
    cp "$RUFFLE/dist/ruffle.js" "$OUT/"
    cp "$RUFFLE/dist/ruffle_web_bg.wasm" "$OUT/"
    echo "→ Copy runtime Ruffle (extension build)"
fi

# --- 4. index.html ---
MAIN_NAME="$(basename "$MAIN")"
cat > "$OUT/index.html" <<EOF
<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<title>Flash Game</title>
<style>
  html, body { margin:0; padding:0; height:100%; background:#000; overflow:hidden; }
  #container { display:flex; align-items:center; justify-content:center; height:100%; }
  ruffle-player { width:100%; height:100%; }
  #status { position:fixed; top:8px; left:8px; color:#8f8; font:12px monospace; z-index:10; }
</style>
</head>
<body>
<div id="container">
  <!-- Bản self-hosted của Ruffle tự polyfill <embed>/<object> và tạo player -->
  <embed id="flash" type="application/x-shockwave-flash" src="$MAIN_NAME" width="100%" height="100%">
</div>
<div id="status">Đang tải…</div>
<script src="ruffle.js"></script>
<script>
  window.addEventListener("load", () => {
    const status = document.getElementById("status");
    // Ruffle self-hosted polyfill sẽ thay <embed> bằng <ruffle-player>.
    setTimeout(() => {
      const p = document.querySelector("ruffle-player");
      if (p) {
        status.textContent = "Đang chạy: $MAIN_NAME";
        // ẩn thông báo sau 5 giây
        setTimeout(() => { status.style.display = "none"; }, 5000);
      } else {
        status.textContent = "Không khởi tạo được Ruffle player";
      }
    }, 1500);
  });
</script>
</body>
</html>
EOF

echo
echo "✅ Xong: $OUT"
ls -la "$OUT" | awk 'NR>3 {print "   "$9"  "$5}'
du -sh "$OUT"
