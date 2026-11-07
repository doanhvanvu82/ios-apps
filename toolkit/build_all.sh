#!/usr/bin/env bash
#
# Build mọi app (apps/*) và mod (mods/*), trừ các mục trong danh sách loại trừ.
#
#   toolkit/build_all.sh                 # build hết (app + mod)
#   toolkit/build_all.sh apps            # chỉ app
#   toolkit/build_all.sh mods            # chỉ mod
#   ONLY=Mangalate toolkit/build_all.sh  # chỉ một mục (tên thư mục)
#   CLEAN=1 toolkit/build_all.sh         # build lại từ đầu
#   CONTINUE_ON_ERROR=1 toolkit/build_all.sh  # lỗi một mục vẫn build tiếp (CI)
#
# Danh sách loại trừ: build-exclude.txt ở gốc repo (mỗi dòng một mục, có thể
# ghi tên thư mục `cherrytale` hoặc đường dẫn `mods/cherrytale`; dòng bắt đầu
# bằng # là ghi chú). Mục bị loại trừ được báo "skip", không tính là lỗi.
#
# Mod cần IPA gốc: dùng biến IPA, IPA_URL, hoặc file mods/<tên>/source.env
# (không commit; ví dụ IPA=/đường/dẫn/YouTube.ipa). Mod thiếu IPA bị báo
# "skip (thiếu IPA)" trừ khi STRICT_MODS=1.
#
# Kết quả mỗi mục: apps/<App>/xtool/*.ipa, mods/<mod>/out/*.ipa.
# Exit code: 0 nếu không mục nào lỗi (bỏ qua/skip không tính lỗi).
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCOPE="${1:-all}"
EXCLUDE_FILE="${BUILD_EXCLUDE:-$ROOT/build-exclude.txt}"
ONLY="${ONLY:-}"
CLEAN="${CLEAN:-0}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"
STRICT_MODS="${STRICT_MODS:-0}"

declare -a EXCLUDED=()
if [ -f "$EXCLUDE_FILE" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -n "$line" ] && EXCLUDED+=("$line")
    done < "$EXCLUDE_FILE"
fi

is_excluded() {
    local rel="$1" base="$2" pat
    for pat in ${EXCLUDED[@]+"${EXCLUDED[@]}"}; do
        [ "$pat" = "$rel" ] && return 0
        [ "$pat" = "$base" ] && return 0
        case "$rel" in "$pat"/*) return 0 ;; esac
    done
    return 1
}

declare -a RESULTS=()
FAILED=0
BUILT=0
SKIPPED=0

run_build() {
    local rel="$1" base="$2"
    local dir="$ROOT/$rel"

    local top="${rel%%/*}"
    local top_singular
    case "$top" in
        apps) top_singular="app" ;;
        mods) top_singular="mod" ;;
        *) top_singular="$top" ;;
    esac
    if [ "$SCOPE" != "all" ] && [ "$SCOPE" != "$top" ] && [ "$SCOPE" != "$top_singular" ]; then
        return
    fi
    if [ -n "$ONLY" ] && [ "$ONLY" != "$base" ] && [ "$ONLY" != "$rel" ]; then
        return
    fi
    if is_excluded "$rel" "$base"; then
        RESULTS+=("SKIP  $rel (danh sách loại trừ)")
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    local script="$dir/build.sh"
    if [ ! -x "$script" ]; then
        RESULTS+=("SKIP  $rel (không có build.sh)")
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    if [ "$top" = "mods" ] && grep -q -- '--check' "$script" 2>/dev/null; then
        # Mod hỗ trợ `build.sh --check`: exit 3 = thiếu IPA gốc → skip, không lỗi.
        local rc=0
        "$script" --check >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 3 ]; then
            RESULTS+=("SKIP  $rel (thiếu IPA gốc — đặt IPA=… hoặc IPA_URL=…)")
            SKIPPED=$((SKIPPED + 1))
            return
        fi
    fi

    echo
    echo "==============================================================="
    echo "▶ $rel"
    echo "==============================================================="
    local args=()
    [ "$CLEAN" = "1" ] && args+=("clean")

    if ( cd "$dir" && ./build.sh ${args[@]+"${args[@]}"} ); then
        RESULTS+=("OK    $rel")
        BUILT=$((BUILT + 1))
    else
        RESULTS+=("FAIL  $rel")
        FAILED=$((FAILED + 1))
        if [ "$CONTINUE_ON_ERROR" != "1" ]; then
            print_summary
            exit 1
        fi
    fi
}

print_summary() {
    echo
    echo "==================== TỔNG KẾT ===================="
    printf '  %s\n' ${RESULTS[@]+"${RESULTS[@]}"}
    echo "-------------------------------------------------"
    echo "  build: $BUILT   skip: $SKIPPED   lỗi: $FAILED"
    echo "================================================="
}

shopt -s nullglob
for d in "$ROOT"/apps/*/; do
    [ -d "$d" ] || continue
    run_build "apps/$(basename "$d")" "$(basename "$d")"
done
for d in "$ROOT"/mods/*/; do
    [ -d "$d" ] || continue
    run_build "mods/$(basename "$d")" "$(basename "$d")"
done
shopt -u nullglob

print_summary
[ "$FAILED" -eq 0 ] || exit 1
[ "$BUILT" -gt 0 ] || { echo "⚠️ Không có mục nào được build (kiểm tra SCOPE/ONLY/build-exclude.txt)." >&2; exit 1; }
