#!/usr/bin/env bash
#
# Dựng lại project Unity từ game đã build (Windows) bằng AssetRipper.
#
#   ./unity_extract.sh "/path/to/unity/game" [output-dir]
#
# AssetRipper 2.0 chạy headless với web UI (Blazor). May chỉ cần gọi HTTP:
#   POST /LoadFolder          path=<thư mục game>
#   POST /Export/UnityProject Path=<thư mục output>  CreateSubfolder=false
#
# LƯU Ý: chỉ hoạt động với game Unity dùng **Mono** scripting backend.
# Game IL2CPP (GameAssembly.dll) không decompile được logic C#.
#
# Yêu cầu: AssetRipper đã giải nén ở ~/assetripper (xem README.md).
#
set -euo pipefail

GAME_DIR="${1:?Usage: $0 <unity-game-dir> [output-dir]}"
OUT_DIR="${2:-}"
ASSETRIPPER_PORT="${ASSETRIPPER_PORT:-8900}"
ASSETRIPPER_HOME="${ASSETRIPPER_HOME:-$HOME/assetripper}"
LOG="/tmp/assetripper.log"

if [ ! -d "$GAME_DIR" ]; then
    echo "❌ Không thấy thư mục: $GAME_DIR" >&2
    exit 1
fi

GAME_DIR="$(cd "$GAME_DIR" && pwd)"

if [ -z "$OUT_DIR" ]; then
    OUT_DIR="$(dirname "$GAME_DIR")/$(basename "$GAME_DIR")-unity-project"
fi
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# Cảnh báo backend
if find "$GAME_DIR" -maxdepth 3 -name "GameAssembly.dll" 2>/dev/null | grep -q .; then
    echo "⚠️  Game này dùng IL2CPP (GameAssembly.dll) — AssetRipper không decompile" >&2
    echo "   được logic C#. Chỉ lấy được assets, không build lại được." >&2
    exit 3
fi

# --- Khởi động AssetRipper nếu chưa chạy ---
if ! curl -sf --max-time 5 "http://127.0.0.1:$ASSETRIPPER_PORT/" >/dev/null 2>&1; then
    echo "→ Khởi động AssetRipper…"
    mkdir -p "$(dirname "$LOG")"
    nohup "$ASSETRIPPER_HOME/AssetRipper.GUI.Free" --headless --port "$ASSETRIPPER_PORT" \
        > "$LOG" 2>&1 &
    for _ in $(seq 1 30); do
        sleep 1
        curl -sf --max-time 3 "http://127.0.0.1:$ASSETRIPPER_PORT/" >/dev/null 2>&1 && break
    done
fi

if ! curl -sf --max-time 5 "http://127.0.0.1:$ASSETRIPPER_PORT/" >/dev/null 2>&1; then
    echo "❌ AssetRipper không khởi động được (xem $LOG)" >&2
    exit 1
fi

echo "→ Game : $GAME_DIR"
echo "→ Out  : $OUT_DIR"

# --- Bước 1: load game ---
echo "→ Đang load game…"
LOAD_MARK="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
curl -s --max-time 600 -X POST --data-urlencode "path=$GAME_DIR" \
    -o /dev/null -w "   LoadFolder: HTTP %{http_code}\n" \
    "http://127.0.0.1:$ASSETRIPPER_PORT/LoadFolder"

# Chờ load xong: log ghi "Finished processing assets" sau mỗi lần load.
echo -n "→ Đang đọc file game"
for _ in $(seq 1 180); do
    sleep 2
    if tail -n +"$LOAD_MARK" "$LOG" 2>/dev/null | grep -q "Finished processing assets"; then
        echo " xong"
        break
    fi
    echo -n "."
done
echo

# --- Bước 2: export Unity project ---
echo "→ Đang export Unity project…"
EXP_MARK="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
curl -s --max-time 1800 -X POST \
    --data-urlencode "Path=$OUT_DIR" \
    --data-urlencode "CreateSubfolder=false" \
    -o /dev/null -w "   Export: HTTP %{http_code}\n" \
    "http://127.0.0.1:$ASSETRIPPER_PORT/Export/UnityProject"

# Chờ export xong
echo -n "→ Đang ghi file"
for _ in $(seq 1 300); do
    sleep 2
    if tail -n +"$EXP_MARK" "$LOG" 2>/dev/null | grep -q "Finished post-export"; then
        echo " xong"
        break
    fi
    echo -n "."
done
echo

if [ -d "$OUT_DIR/ExportedProject" ]; then
    SIZE="$(du -sh "$OUT_DIR/ExportedProject" 2>/dev/null | cut -f1)"
    CSHARP="$(find "$OUT_DIR/ExportedProject" -name '*.cs' 2>/dev/null | wc -l)"
    echo "✅ Export xong: $OUT_DIR/ExportedProject ($SIZE, $CSHARP file .cs)"
else
    echo "⚠️  Không thấy ExportedProject trong $OUT_DIR — xem $LOG" >&2
    exit 2
fi
