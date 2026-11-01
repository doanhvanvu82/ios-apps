#!/usr/bin/env bash
#
# Batch chuyển đổi game Unity (Mono) sang WebGL để chơi được trên iOS.
#
#   ./unity_batch_build.sh [thư-mục-game] [thư-mục-project] [thư-mục-webgl] [số-game-tối-đa]
#
# Mặc định:
#   game     : ~/Documents/Game
#   project  : ~/Documents/Code/ios/apps/GameHub/workspace/unity-projects
#   webgl    : ~/Documents/Code/ios/apps/GameHub/workspace/unity-webgl
#
# Mỗi game gồm 2 bước (mỗi bước tự bỏ qua nếu đã có kết quả):
#   1. tools/unity_extract.sh    → dựng project Unity từ game .exe (AssetRipper)
#   2. tools/unity_build_webgl.sh → build WebGL (Unity Editor)
#
# Game IL2CPP (có GameAssembly.dll) bị bỏ qua: không decompile được logic C#.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAMES_DIR="${1:-$HOME/Documents/Game}"
PROJECTS_DIR="${2:-$HOME/Documents/Code/ios/apps/GameHub/workspace/unity-projects}"
WEBGL_DIR="${3:-$HOME/Documents/Code/ios/apps/GameHub/workspace/unity-webgl}"
MAX_GAMES="${4:-0}"

LOG_DIR="/tmp/unity-batch"
SUMMARY="$LOG_DIR/summary.tsv"
UNITY_DEFAULT="${UNITY_DEFAULT:-$HOME/Unity/Editor/Unity}"
UNITY_VERSIONS="${UNITY_VERSIONS:-$HOME/unity-versions}"
mkdir -p "$LOG_DIR" "$PROJECTS_DIR" "$WEBGL_DIR"

echo "═══════════════════════════════════════════════════════"
echo " Batch Unity → WebGL"
echo "   game    : $GAMES_DIR"
echo "   project : $PROJECTS_DIR"
echo "   webgl   : $WEBGL_DIR"
echo "═══════════════════════════════════════════════════════"

# --- Liệt kê game Unity Mono ---
# Đọc version Unity từ `globalgamemanagers` để biết game cần editor nào.
# Game cũ (< 2022.3) không build được bằng Unity 6000 vì DLL render pipeline
# của chúng không tương thích IL2CPP mới.
unity_version_of() {
    local dir="$1"
    local gm
    gm="$(find "$dir" -maxdepth 3 -name "globalgamemanagers" 2>/dev/null | head -1)"
    [ -z "$gm" ] && { echo ""; return; }
    strings -n 5 "$gm" 2>/dev/null | grep -oE "^[0-9]{4}\.[0-9]+\.[0-9]+[abfp][0-9]+$" | head -1
}

# Editor theo version game: ưu tiên bản cài riêng, không thì dùng Unity 6000.
editor_for_version() {
    local ver="$1"
    if [ -n "$ver" ] && [ -x "$UNITY_VERSIONS/$ver/Editor/Unity" ]; then
        echo "$UNITY_VERSIONS/$ver/Editor/Unity"
    else
        echo "$UNITY_DEFAULT"
    fi
}

unity_mono_games() {
    # Thư mục game có thể nằm trực tiếp trong GAMES_DIR hoặc trong 1 subfolder
    # (sau khi sắp xếp: 1-ChoiDungTrucTiep / 2-CanBuildLai / 3-ChuaChoiDuoc).
    for d in "$GAMES_DIR"/*/ "$GAMES_DIR"/*/*/; do
        [ -d "$d" ] || continue
        # Bỏ qua chính các thư mục phân loại (chúng chứa game, không phải game).
        case "$(basename "$d")" in
            1-ChoiDungTrucTiep|2-CanBuildLai|3-ChuaChoiDuoc) continue ;;
        esac
        # Chỉ nhận game nằm trong GAMES_DIR hoặc trong 1 subfolder phân loại.
        case "$(dirname "$d")" in
            "$GAMES_DIR") ;;
            "$GAMES_DIR"/1-ChoiDungTrucTiep|"$GAMES_DIR"/2-CanBuildLai|"$GAMES_DIR"/3-ChuaChoiDuoc) ;;
            *) continue ;;
        esac
        # có dấu hiệu Unity
        if ! find "$d" -maxdepth 3 \( -name "globalgamemanagers" -o -name "UnityPlayer.dll" \) 2>/dev/null | grep -q .; then
            continue
        fi
        # loại IL2CPP
        if find "$d" -maxdepth 3 -name "GameAssembly.dll" 2>/dev/null | grep -q .; then
            continue
        fi
        echo "$d"
    done
}

mapfile -t GAMES < <(unity_mono_games)
echo "→ Tìm thấy ${#GAMES[@]} game Unity Mono"
echo

if [ ! -x "$HOME/Unity/Editor/Unity" ]; then
    echo "❌ Không thấy Unity Editor tại ~/Unity/Editor/Unity" >&2
    exit 1
fi

# --- Khởi động AssetRipper một lần cho cả batch ---
if ! curl -sf --max-time 5 "http://127.0.0.1:8900/" >/dev/null 2>&1; then
    echo "→ Khởi động AssetRipper…"
    mkdir -p "$HOME/assetripper"
    if [ -x "$HOME/assetripper/AssetRipper.GUI.Free" ]; then
        nohup "$HOME/assetripper/AssetRipper.GUI.Free" --headless --port 8900 \
            > /tmp/assetripper.log 2>&1 &
        for _ in $(seq 1 30); do
            sleep 1
            curl -sf --max-time 3 "http://127.0.0.1:8900/" >/dev/null 2>&1 && break
        done
    fi
fi

done_count=0
for src in "${GAMES[@]}"; do
    [ "$MAX_GAMES" -gt 0 ] && [ "$done_count" -ge "$MAX_GAMES" ] && break

    name="$(basename "$src")"
    proj="$PROJECTS_DIR/$name"
    out="$WEBGL_DIR/$name"

    # Đã xong?
    if [ -f "$out/index.html" ]; then
        echo "⏭  $name — đã có bản WebGL"
        continue
    fi

    echo "───────────────────────────────────────────────────────"
    echo "▶ $name"
    echo "───────────────────────────────────────────────────────"

    # Editor tương ứng với version Unity của game
    game_ver="$(unity_version_of "$src")"
    editor="$(editor_for_version "$game_ver")"
    echo "   Unity $game_ver → editor: $(basename "$(dirname "$(dirname "$editor")")")"

    # Game Unity < 2022.3 không build được bằng Unity 6000 (DLL render pipeline
    # cũ không tương thích IL2CPP mới) → cần editor đúng version.
    if [ -n "$game_ver" ] && [ "$game_ver" \< "2022.3" ]; then
        if [ ! -x "$UNITY_VERSIONS/$game_ver/Editor/Unity" ]; then
            echo "⏭  Bỏ qua — cần Unity $game_ver (chưa cài tại $UNITY_VERSIONS/$game_ver)"
            printf "%s\tNEED_EDITOR_%s\t-\n" "$name" "$game_ver" >> "$SUMMARY"
            continue
        fi
    fi

    # Bước 1: dựng project
    if [ ! -f "$proj/ExportedProject/ProjectSettings/ProjectVersion.txt" ]; then
        "$SCRIPT_DIR/unity_extract.sh" "$src" "$proj" > "$LOG_DIR/$name.extract.log" 2>&1
        rc=$?
        if [ $rc -ne 0 ] || [ ! -f "$proj/ExportedProject/ProjectSettings/ProjectVersion.txt" ]; then
            echo "❌ Extract thất bại (rc=$rc) — xem $LOG_DIR/$name.extract.log"
            printf "%s\tEXTRACT_FAIL\t-\n" "$name" >> "$SUMMARY"
            continue
        fi
    else
        echo "→ Project đã có, bỏ qua bước extract"
    fi

    # Bước 2: build WebGL
    # Log riêng cho từng game (nếu không, mỗi game đè lên log của game trước).
    UNITY_LOG="$LOG_DIR/$name.unity.log" \
    UNITY_HOME="$(dirname "$(dirname "$editor")")" \
    "$SCRIPT_DIR/unity_build_webgl.sh" "$proj/ExportedProject" "$out" \
        > "$LOG_DIR/$name.build.log" 2>&1
    rc=$?

    if [ $rc -eq 0 ] && [ -f "$out/index.html" ]; then
        size="$(du -sh "$out" | cut -f1)"
        echo "✅ $name — WebGL OK ($size)"
        printf "%s\tOK\t%s\n" "$name" "$size" >> "$SUMMARY"
        done_count=$((done_count + 1))
    else
        echo "❌ Build thất bại (rc=$rc) — xem $LOG_DIR/$name.build.log"
        grep -iE "error CS|Exception|emcc: error" "$LOG_DIR/$name.unity.log" 2>/dev/null \
            | sed -E 's/.*(error CS[0-9]+: .{0,90}).*/\1/' | sort -u | head -5
        printf "%s\tBUILD_FAIL\t-\n" "$name" >> "$SUMMARY"
    fi
done

echo
echo "═══════════════════════════════════════════════════════"
echo " Tổng kết (xem $SUMMARY):"
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo "═══════════════════════════════════════════════════════"

# Dọn cache Unity cho toàn bộ project (mỗi project có thể vài GB cache import).
if [ -x "$SCRIPT_DIR/cleanup.sh" ]; then
    "$SCRIPT_DIR/cleanup.sh" 2>&1 | tail -5
fi
