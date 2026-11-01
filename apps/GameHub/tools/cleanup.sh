#!/usr/bin/env bash
#
# Dọn dung lượng do pipeline Unity/Godot tạo ra.
#
#   ./cleanup.sh            → dọn an toàn (cache + tarball đã giải nén)
#   ./cleanup.sh --aggressive → dọn thêm cả project Unity đã build xong
#
# An toàn: KHÔNG xoá thư mục game gốc, KHÔNG xoá bản WebGL đã build.
#
set -uo pipefail

AGGRESSIVE=0
[ "${1:-}" = "--aggressive" ] && AGGRESSIVE=1

SIM="${GAMEHUB_SIM:-$HOME/Documents/Code/ios/apps/GameHub/workspace}"
PROJECTS="$SIM/unity-projects"
WEBGL="$SIM/unity-webgl"

freed=0
freed_mb() { freed=$((freed + $1)); }

echo "══════════════════════════════════════════════════"
echo " Dọn dung lượng GameHub"
echo "══════════════════════════════════════════════════"

# --- 1. Cache import của Unity trong các project đã export ---
if [ -d "$PROJECTS" ]; then
    for d in "$PROJECTS"/*/; do
        [ -d "$d" ] || continue
        lib="$d/ExportedProject/Library"
        [ -d "$lib" ] || continue
        sz=$(du -sm "$lib" 2>/dev/null | cut -f1)
        rm -rf "$lib" 2>/dev/null
        [ "$sz" -gt 0 ] && { echo "  ✅ xoá Library cache: $(basename "$d") (${sz} MB)"; freed_mb "$sz"; }
    done
fi

# --- 2. Tarball đã giải nén ---
for t in "$HOME"/unity-dl/versions/*.tar.xz; do
    [ -f "$t" ] || continue
    v=$(basename "$t" | sed -E 's/^(editor|webgl)-([0-9.]+f[0-9]+)\.tar\.xz/\2/')
    if [ -x "$HOME/unity-versions/$v/Editor/Unity" ]; then
        sz=$(du -sm "$t" | cut -f1)
        rm -f "$t"
        echo "  ✅ xoá tarball đã giải nén: $(basename "$t") (${sz} MB)"
        freed_mb "$sz"
    fi
done
for t in "$HOME"/unity-dl/*.tar.xz "$HOME"/godot-dl/*.tpz "$HOME"/godot-dl/*.zip; do
    [ -f "$t" ] || continue
    sz=$(du -sm "$t" | cut -f1)
    rm -f "$t"
    echo "  ✅ xoá gói tải về: $(basename "$t") (${sz} MB)"
    freed_mb "$sz"
done

# --- 3. Temp / cache ---
for d in "$HOME/assetripper/temp" "$HOME/.cache/Unity" "$HOME/.cache/unity3d"; do
    [ -d "$d" ] || continue
    sz=$(du -sm "$d" 2>/dev/null | cut -f1)
    rm -rf "$d"
    echo "  ✅ xoá cache: $d (${sz} MB)"
    freed_mb "$sz"
done

# --- 4. Editor Unity không còn game nào cần ---
if [ "$AGGRESSIVE" = "1" ] && [ -d "$HOME/unity-versions" ]; then
    for d in "$HOME/unity-versions"/*/; do
        [ -d "$d" ] || continue
        v=$(basename "$d")
        # Còn game nào dùng version này không?
        need=0
        if [ -d "$HOME/Documents/Game" ]; then
            for g in "$HOME/Documents/Game"/*/; do
                [ -d "$g" ] || continue
                gm=$(find "$g" -maxdepth 3 -name "globalgamemanagers" 2>/dev/null | head -1)
                [ -z "$gm" ] && continue
                find "$g" -maxdepth 3 -name "GameAssembly.dll" 2>/dev/null | grep -q . && continue
                gv=$(strings -n 5 "$gm" 2>/dev/null | grep -oE "^[0-9]{4}\.[0-9]+\.[0-9]+[abfp][0-9]+$" | head -1)
                [ "$gv" = "$v" ] && { need=1; break; }
            done
        fi
        if [ "$need" = "0" ]; then
            sz=$(du -sm "$d" | cut -f1)
            rm -rf "$d"
            echo "  ✅ xoá Unity editor không còn dùng: $v (${sz} MB)"
            freed_mb "$sz"
        fi
    done
fi

# --- 5. Project Unity đã build xong (chỉ khi --aggressive) ---
if [ "$AGGRESSIVE" = "1" ] && [ -d "$PROJECTS" ]; then
    for d in "$PROJECTS"/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        if [ -f "$WEBGL/$name/index.html" ]; then
            sz=$(du -sm "$d" | cut -f1)
            rm -rf "$d"
            echo "  ✅ xoá project đã build xong: $name (${sz} MB)"
            freed_mb "$sz"
        fi
    done
fi

echo
echo "══════════════════════════════════════════════════"
printf " Đã giải phóng: ~%d MB (%.1f GB)\n" "$freed" "$(echo "$freed/1024" | bc -l)"
df -h / | tail -1 | awk '{print " Dung lượng còn trống: "$4" ("$5" đã dùng)"}'
echo "══════════════════════════════════════════════════"
