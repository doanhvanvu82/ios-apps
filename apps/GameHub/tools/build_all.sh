#!/usr/bin/env bash
#
# Build tất cả game trong ~/Documents/Game/2-CanBuildLai/ thành bản web
# và export vào ~/Documents/Game/2-DaBuildLai/.
#
#   ./tools/build_all.sh              # build game CHƯA có bản web trong 2-DaBuildLai
#   ./tools/build_all.sh --force      # build lại tất cả, kể cả game đã build
#   ./tools/build_all.sh --only <tên> # build (lại) game tên chứa <tên>
#   ./tools/build_all.sh --list       # chỉ liệt kê game sẽ build (dùng cho build_parallel.sh)
#
# Tự nhận diện loại game và dùng pipeline tương ứng:
#   • Unity Mono        → AssetRipper + Unity Editor  → WebGL
#   • Unity IL2CPP có bản Mono gốc → dựng lại Mono → WebGL
#   • Godot (.pck)     → export HTML5 + thay .pck
#   • Godot trong NSIS → giải nén installer → export HTML5
#   • KiriKiri2 (.xp3) → kirikiroid2-web
#   • Flash (.swf)     → Ruffle
#   • Ren'Py desktop   → renpy web build
#
# File trung gian (project Unity, mono-src, NSIS… vẫn nằm ở $OUT_BASE,
# mặc định ~/Documents/Code/ios/apps/GameHub/workspace — có thể xoá sau khi build xong).
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAMES_DIR="${GAMES_DIR:-$HOME/Documents/Game/2-CanBuildLai}"
# Nơi xuất bản web chơi được — copy thư mục này vào iPhone là chơi.
OUT_BASE="${OUT_BASE:-$HOME/Documents/Game/2-DaBuildLai}"
# Nơi chứa file trung gian (project Unity export, mono-src, NSIS tmp…)
WORK_BASE="${WORK_BASE:-$HOME/Documents/Code/ios/apps/GameHub/workspace}"
ONLY=""
FORCE=0
LIST=0

while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="${2:-}"; shift 2 ;;
        --force) FORCE=1; shift ;;
        --list) LIST=1; shift ;;
        *) echo "Tham số không hợp lệ: $1 (dùng --only <tên> / --force / --list)" >&2; exit 2 ;;
    esac
done

LOG_DIR="/tmp/build-all"
mkdir -p "$LOG_DIR"

# Build Unity cần nhiều chỗ tạm (project dựng lại + Library/ hàng chục GB).
# Dưới ngưỡng này thì dừng hẳn, không để đầy ổ.
MIN_FREE_GB="${MIN_FREE_GB:-30}"
free_gb() { df -BG --output=avail "$1" | tail -1 | tr -dc '0-9'; }

declare -A OUTDIR=(
    [unityWebGL]="$OUT_BASE"
    [godotWebGL]="$OUT_BASE"
    [kirikiWeb]="$OUT_BASE"
    [flashWeb]="$OUT_BASE"
    [renpyWeb]="$OUT_BASE"
)

declare -A WORKDIR=(
    [unityProjects]="$WORK_BASE/unity-projects"
    [monoSrc]="$WORK_BASE/unity-mono-src"
    [nsisSrc]="$WORK_BASE/nsis-src"
    [evbSrc]="$WORK_BASE/evb-src"
)

# Game đóng gói Enigma Virtual Box: cả thư mục *_Data nằm trong exe (section
# .enigma1) → AssetRipper không thấy gì. Giải nén bằng evbunpack (venv riêng).
TOOLS_VENV="$WORK_BASE/.tools-venv"
is_evb_exe() {
    python3 - "$1" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read(4096)
try:
    pe = struct.unpack("<I", d[0x3c:0x40])[0]
    n = struct.unpack("<H", d[pe + 6:pe + 8])[0]
    off = pe + 24 + struct.unpack("<H", d[pe + 20:pe + 22])[0]
    sys.exit(0 if any(d[off + i * 40:off + i * 40 + 8].rstrip(b"\0") == b".enigma1" for i in range(n)) else 1)
except struct.error:
    sys.exit(1)
PY
}
unpack_evb() {  # <thư mục game> <đích> → thư mục game ảo đã giải nén
    local game="$1" dest="$2" exe
    exe="$(find "$game" -maxdepth 3 -name "*.exe" -size +50M | head -1)"
    [ -n "$exe" ] && is_evb_exe "$exe" || return 1
    if [ ! -x "$TOOLS_VENV/bin/python" ]; then
        python3 -m venv "$TOOLS_VENV" && "$TOOLS_VENV/bin/pip" install -q evbunpack || return 1
    fi
    rm -rf "$dest" && mkdir -p "$dest"
    "$TOOLS_VENV/bin/python" -m evbunpack --ignore-pe "$exe" "$dest" || return 1
    # Tệp thật cạnh exe (UnityPlayer.dll, MonoBleedingEdge…) — AssetRipper cần đủ bố cục.
    local f
    for f in "$(dirname "$exe")"/*; do
        [ -e "$dest/$(basename "$f")" ] || ln -s "$f" "$dest/$(basename "$f")"
    done
}

say() { printf "\n\033[1m▶ %s\033[0m\n" "$*"; }

fmt_time() { local s=$1; [ "$s" -ge 3600 ] && printf "%d:%02d:%02d" $((s / 3600)) $((s % 3600 / 60)) $((s % 60)) || printf "%02d:%02d" $((s / 60)) $((s % 60)); }

# Dòng cuối có nội dung của log (bỏ mã màu) — mô tả bước cho extract/script.
last_line() { grep -v '^[[:space:]]*$' "$1" 2>/dev/null | tail -1 | sed 's/\x1b\[[0-9;]*m//g; s/^[[:space:]]*//'; }

# Bước hiện tại của build Unity, đọc từ log mới ghi gần nhất của game $CUR.
unity_phase() {
    local bl="$LOG_DIR/$CUR.build.log" reg="$LOG_DIR/$CUR.unity-register.log" ul="$LOG_DIR/$CUR.unity.log"
    local f label n
    f="$(ls -t "$bl" "$reg" "$ul" 2>/dev/null | head -1)"
    case "$f" in
        "$reg") label="Unity lần 1 (đăng ký URP)" ;;
        "$ul") label="Unity build" ;;
        *) echo "chuẩn bị project: $(last_line "$bl")"; return ;;
    esac
    # Log có thể rất lớn (game spam warning) — chỉ đếm toàn file khi < 200 MB.
    n=""
    [ "$(stat -c %s "$f")" -lt 200000000 ] && n="$(grep -c 'Start importing' "$f")"
    tail -c 2000000 "$f" | awk -v label="$label" -v n="$n" '
        /Start importing/ { t = "import" }
        /^Compiling shader "/ { t = "shader"; split($0, a, "\""); s = a[2] }
        /^\[ *[0-9]+\/[0-9]+ +[0-9]+m?s\] / { t = "bee"; b = $0 }
        /^\[BUSY +[0-9]+m?s\] / { t = "busy"; b = $0 }
        END {
            if (t == "import") print label ": import asset" (n != "" ? " (" n " xong)" : "")
            else if (t == "shader") print label ": biên dịch shader " s
            else if (t == "bee") { match(b, /[0-9]+\/[0-9]+/); split(b, w, "] "); split(w[2], x, " "); print label ": build player " substr(b, RSTART, RLENGTH) " " x[1] }
            else if (t == "busy") { split(b, w, "] "); split(w[2], x, " "); match(b, /[0-9]+m?s/); print label ": " x[1] " (đang chạy " substr(b, RSTART, RLENGTH) ")" }
            else print label ": khởi động / nạp project"
        }'
}

extract_phase() { echo "dựng project (AssetRipper): $(last_line "$LOG_DIR/$CUR.extract.log")"; }
# AssetRipper chỉ nạp được một game một lúc → các build song song xếp hàng ở đây.
# Xong thì tắt luôn: server giữ cả game đã nạp trong RAM (~2,4 GB) suốt lúc Unity build.
extract_unity() {
    flock /tmp/gamehub-extract.lock bash -c '"$@"; rc=$?; pkill -x AssetRipper.GUI; exit $rc' _ \
        "$SCRIPT_DIR/unity_extract.sh" "$1" "$2" > "$LOG_DIR/$CUR.extract.log" 2>&1
}

# Log Unity riêng từng game: dùng chung một file thì game sau ghi đè lỗi của
# game trước, và bước thêm shader đọc nhầm log của game khác.
build_unity() {
    UNITY_LOG="$LOG_DIR/$CUR.unity.log" \
        "$SCRIPT_DIR/unity_build_webgl.sh" "$1/ExportedProject" "${OUTDIR[unityWebGL]}/$CUR" \
        > "$LOG_DIR/$CUR.build.log" 2>&1
}

kill_tree() {
    local c
    for c in $(pgrep -P "$1"); do kill_tree "$c"; done
    kill -TERM "$1" 2>/dev/null
}

# Chạy lệnh, trong lúc chờ in thời gian đã chạy + bước hiện tại (lệnh <mô_tả>).
# Terminal: một dòng tự cập nhật; không phải terminal (ghi ra file): mỗi phút một dòng.
run_progress() {
    local probe="$1"; shift
    local start=$SECONDS last=-60 pid rc
    "$@" &
    pid=$!
    # Lệnh chạy nền bỏ qua Ctrl-C (shell không tương tác) → tự dừng cả cây con, kể cả Unity.
    trap 'printf "\n"; kill_tree "$pid"; exit 130' INT TERM
    while kill -0 "$pid" 2>/dev/null; do
        if [ -t 1 ]; then
            printf "\r\033[K  ⏱ %s  %s" "$(fmt_time $((SECONDS - start)))" "$($probe | cut -c1-$(( ${COLUMNS:-120} - 14 )))"
        elif [ $((SECONDS - last)) -ge 60 ]; then
            last=$SECONDS
            printf "  ⏱ %s  %s\n" "$(fmt_time $((SECONDS - start)))" "$($probe | cut -c1-150)"
        fi
        sleep 3
    done
    wait "$pid"
    rc=$?
    trap - INT TERM
    [ -t 1 ] && printf "\r\033[K"
    printf "  ⏱ %s\n" "$(fmt_time $((SECONDS - start)))"
    return $rc
}

# Tên output chuẩn cho game (tra cứu tools/game_names.txt, fallback = tên gốc)
out_name() {
    local src="$1" key val
    if [ -f "$SCRIPT_DIR/game_names.txt" ]; then
        key="$(grep -F "$src|" "$SCRIPT_DIR/game_names.txt" | head -1 | cut -d'|' -f2)"
        if [ -n "$key" ]; then echo "$key"; return; fi
    fi
    echo "$src"
}

for d in "$GAMES_DIR"/*/; do
    [ -d "$d" ] || continue
    raw_name="$(basename "$d")"
    name="$(out_name "$raw_name")"
    if [ -n "$ONLY" ] && [[ "$name" != *"$ONLY"* ]] && [[ "$raw_name" != *"$ONLY"* ]]; then
        continue
    fi

    # Đã có bản web → bỏ qua (Unity build mất vài phút mỗi game). Chỉ định
    # --only <tên> hoặc --force là muốn build lại.
    if [ "$FORCE" = 0 ] && [ -z "$ONLY" ] && [ -f "$OUT_BASE/$name/index.html" ]; then
        [ "$LIST" = 1 ] || printf "\n• %s — đã build, bỏ qua (--force để build lại)\n" "$name"
        continue
    fi

    if [ "$LIST" = 1 ]; then echo "$raw_name"; continue; fi

    say "$name"

    if [ "$(free_gb "$WORK_BASE")" -lt "$MIN_FREE_GB" ]; then
        echo "  ⛔ Ổ chỉ còn $(free_gb "$WORK_BASE") GB trống (< ${MIN_FREE_GB} GB) — dừng build."
        break
    fi

    # --- 1. Unity (Mono hoặc IL2CPP có Mono backup) ---
    if find "$d" -maxdepth 4 \( -name "globalgamemanagers" -o -name "UnityPlayer.dll" \) 2>/dev/null | grep -q .; then
        src="$d"
        if ! find "$d" -maxdepth 3 -type d -name "*_Data" 2>/dev/null | grep -q . \
            && unpack_evb "$d" "${WORKDIR[evbSrc]}/$name" > "$LOG_DIR/$name.evb.log" 2>&1; then
            src="${WORKDIR[evbSrc]}/$name"
            echo "  ↻ Giải nén Enigma Virtual Box"
        fi
        if find "$d" -maxdepth 4 -name "GameAssembly.dll" 2>/dev/null | grep -q .; then
            # IL2CPP → dựng lại bản Mono nếu có
            mono_src="${WORKDIR[monoSrc]}/$name"
            if python3 "$SCRIPT_DIR/unity_il2cpp_to_mono.py" "$d" --out "$mono_src" --apply > "$LOG_DIR/$name.il2cpp.log" 2>&1; then
                src="$mono_src"
                echo "  ↻ Dựng lại bản Mono từ bản backup của dev"
            else
                echo "  ❌ IL2CPP không có bản Mono gốc → bỏ qua"
                continue
            fi
        fi
        proj="${WORKDIR[unityProjects]}/$name"
        CUR="$name"
        # Lần extract trước hỏng giữa chừng có thể để lại project không có Assets/.
        if [ ! -f "$proj/ExportedProject/ProjectSettings/ProjectVersion.txt" ] || [ ! -d "$proj/ExportedProject/Assets" ]; then
            rm -rf "$proj"
            run_progress extract_phase extract_unity "$src" "$proj" \
                || { echo "  ❌ Extract lỗi — xem $LOG_DIR/$name.extract.log"; continue; }
        fi
        python3 "$SCRIPT_DIR/unity_missing_plugins.py" "$proj/ExportedProject" "$src" || true
        if run_progress unity_phase build_unity "$proj" && [ -f "${OUTDIR[unityWebGL]}/$name/index.html" ]; then
            echo "  ✅ Unity WebGL: ${OUTDIR[unityWebGL]}/$name"
            # Đã có bản web → bỏ project trung gian (vài GB/game). Cần build lại
            # thì AssetRipper dựng lại được. GAMEHUB_KEEP_PROJECT=1 để giữ.
            if [ "${GAMEHUB_KEEP_PROJECT:-0}" != "1" ]; then
                rm -rf "$proj" "${WORKDIR[monoSrc]}/$name" "${WORKDIR[evbSrc]}/$name"
            fi
        else
            echo "  ❌ Unity build lỗi — xem $LOG_DIR/$name.build.log (log Unity: $name.unity.log)"
            grep -m3 -E "error CS[0-9]+|Segmentation fault" "$LOG_DIR/$name.build.log" | sed 's/^/     /' | cut -c1-220
        fi
        continue
    fi

    # --- 2. Godot: .pck rời ---
    # (Godot gốc chạy được nhờ runtime trong app — pipeline này chỉ dành cho
    #  bản muốn chuyển thành web, vd khi cần iOS 17.)
    if find "$d" -maxdepth 2 -name "*.pck" 2>/dev/null | grep -q .; then
        ver="$(python3 - "$d" <<'PY'
import os, struct, sys
d = sys.argv[1]
best = ""
for dp, dn, fn in os.walk(d):
    for f in fn:
        if not f.lower().endswith(".pck"): continue
        p = os.path.join(dp, f)
        try:
            h = open(p, "rb").read(16)
        except OSError: continue
        if h[:4] != b"GDPC": continue
        ma, mi = struct.unpack('<I', h[8:12])[0], struct.unpack('<I', h[12:16])[0]
        v = f"{ma}.{mi}"
        if v > best: best = v
print(best)
PY
)"
        echo "  → Godot $ver"
        if [[ "$ver" == 3.* ]]; then
            "$SCRIPT_DIR/godot_web_build.sh" "$d" "${OUTDIR[godotWebGL]}/$name" > "$LOG_DIR/$name.godot.log" 2>&1
        else
            "$SCRIPT_DIR/godot_web_export.sh" "$d" "${OUTDIR[godotWebGL]}/$name" > "$LOG_DIR/$name.godot.log" 2>&1
        fi
        [ -f "${OUTDIR[godotWebGL]}/$name/index.html" ] && echo "  ✅ Godot WebGL" || echo "  ❌ Godot export lỗi — xem $LOG_DIR/$name.godot.log"
        continue
    fi

    # --- 3. Godot trong installer NSIS ---
    big_exe="$(find "$d" -maxdepth 2 -name "*.exe" -size +50M 2>/dev/null | head -1)"
    if [ -n "$big_exe" ] && 7z l "$big_exe" 2>/dev/null | grep -qE " pck\s*$"; then
        tmp="${WORKDIR[nsisSrc]}/$name"
        echo "  → Giải nén installer NSIS"
        "$SCRIPT_DIR/nsis_extract.sh" "$big_exe" "$tmp" > "$LOG_DIR/$name.nsis.log" 2>&1 \
            || { echo "  ❌ Giải nén lỗi"; continue; }
        mkdir -p "$tmp/game" && mv "$tmp"/pck "$tmp/game/game.pck" 2>/dev/null
        "$SCRIPT_DIR/godot_web_export.sh" "$tmp/game" "${OUTDIR[godotWebGL]}/$name" > "$LOG_DIR/$name.godot.log" 2>&1
        [ -f "${OUTDIR[godotWebGL]}/$name/index.html" ] && echo "  ✅ Godot WebGL" || echo "  ❌ Godot export lỗi — xem $LOG_DIR/$name.godot.log"
        continue
    fi

    # --- 4. KiriKiri2 (.xp3) ---
    # (KiriKiri gốc chạy được qua WebDAV trong app — bản này cho iOS 17.)
    if find "$d" -maxdepth 3 -name "*.xp3" 2>/dev/null | grep -q .; then
        "$SCRIPT_DIR/kiriki_pack.sh" "$d" "${OUTDIR[kirikiWeb]}/$name" > "$LOG_DIR/$name.kiriki.log" 2>&1
        [ -f "${OUTDIR[kirikiWeb]}/$name/game.zip" ] && echo "  ✅ KiriKiri WASM" || echo "  ❌ xem $LOG_DIR/$name.kiriki.log"
        continue
    fi

    # --- 5. Flash (.swf) ---
    if find "$d" -maxdepth 3 -name "*.swf" 2>/dev/null | grep -q .; then
        "$SCRIPT_DIR/flash_ruffle_pack.sh" "$d" "${OUTDIR[flashWeb]}/$name" > "$LOG_DIR/$name.flash.log" 2>&1
        [ -f "${OUTDIR[flashWeb]}/$name/index.html" ] && echo "  ✅ Flash / Ruffle" || echo "  ❌ xem $LOG_DIR/$name.flash.log"
        continue
    fi

    # --- 6. Ren'Py desktop ---
    if [ -d "$d/renpy" ] && [ -d "$d/game" ]; then
        ver="$(sed -n "s/^version = '\([0-9]*\.[0-9]*\).*/\1/p" "$d/renpy/vc_version.py" 2>/dev/null)"
        case "$ver" in
            8.3|8.5) echo "  → Ren'Py $ver — app chơi thẳng bản PC (RenPyNative), không cần build" ;;
            *) echo "  → Ren'Py ${ver:-?} — app chưa có runtime này, build web: tools/renpy_web_build.sh \"$d\"" ;;
        esac
        continue
    fi

    echo "  ⚠️  Không nhận diện được loại — bỏ qua"
done

[ "$LIST" = 1 ] && exit 0
say "Tổng kết — bản web nằm ở $OUT_BASE"
n=$(ls -d "$OUT_BASE"/*/ 2>/dev/null | wc -l)
printf "  2-DaBuildLai: %s game\n" "$n"
printf "  Tổng thời gian: %s\n" "$(fmt_time "$SECONDS")"
