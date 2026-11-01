#!/usr/bin/env bash
#
# Build nhiều game song song (mặc định 2 game cùng lúc) — nhanh hơn build_all.sh
# vì import asset của Unity chỉ dùng ~4/12 nhân, và AssetRipper dựng project cho
# game sau trong lúc Unity build game trước.
#
#   ./tools/build_parallel.sh                # game chưa có bản web, 2 game cùng lúc
#   ./tools/build_parallel.sh -j 3           # 3 game cùng lúc
#   ./tools/build_parallel.sh --force        # build lại cả game đã build
#   ./tools/build_parallel.sh "Shame Chain" Fox.Sex.Farm.v0106   # chỉ các game này, đúng thứ tự
#
# Mỗi game chạy bằng `build_all.sh --only <tên>`, log riêng: /tmp/build-all/<tên>.run.log
# (dòng "⏱" cuối cùng là bước đang chạy). Dựng project (AssetRipper) xếp hàng từng game một.
# Chỉ mở game mới khi RAM trống ≥ MIN_AVAIL_MB (mặc định 3000), tránh swap làm chậm hơn.
# Đếm cả build_all.sh do nơi khác chạy (vd đang build tay một game) và bỏ qua game đó.
#
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/tmp/build-all"
JOBS=2
MIN_AVAIL_MB="${MIN_AVAIL_MB:-3000}"
FORCE=()
NAMES=()

while [ $# -gt 0 ]; do
    case "$1" in
        -j) JOBS="${2:?-j cần số}"; shift 2 ;;
        --force) FORCE=(--force); shift ;;
        -*) echo "Tham số không hợp lệ: $1 (dùng -j <số> / --force / <tên game>…)" >&2; exit 2 ;;
        *) NAMES+=("$1"); shift ;;
    esac
done

mkdir -p "$LOG_DIR"
# Các `build_all.sh --only <tên>` cấp cao nhất đang chạy (bỏ tiến trình con cùng dòng lệnh).
running_builds() {
    ps -eo pid,ppid,args | awk '/build_all\.sh --only / && !/awk/ { pid[$1] = 1; ppid[$1] = $2; sub(/^ *[0-9]+ +[0-9]+ +/, ""); name[$0] = 1 }
        END { for (p in pid) if (!(ppid[p] in pid)) print p }'
}
is_building() {  # game này đang có build_all.sh --only <tên> chạy?
    ps -eo args | awk -v s="build_all.sh --only $1" '{ i = index($0, s) } i && length($0) - i + 1 == length(s) { f = 1 } END { exit !f }'
}

if [ "${#NAMES[@]}" -gt 0 ]; then ALL_GAMES=("${NAMES[@]}"); else mapfile -t ALL_GAMES < <("$SCRIPT_DIR/build_all.sh" --list "${FORCE[@]}"); fi
GAMES=()
for g in "${ALL_GAMES[@]}"; do
    if is_building "$g"; then echo "• $g đang được build ở nơi khác — bỏ qua"; else GAMES+=("$g"); fi
done
[ "${#GAMES[@]}" -gt 0 ] || { echo "Không có game nào cần build."; exit 0; }

fmt_time() { local s=$1; printf "%02d:%02d" $((s / 60)) $((s % 60)); }
avail_mb() { awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo; }

declare -A PID_NAME PID_START
OK=(); FAIL=()
t0=$SECONDS

reap() {
    local pid
    for pid in "${!PID_NAME[@]}"; do
        kill -0 "$pid" 2>/dev/null && continue
        wait "$pid" 2>/dev/null
        local name="${PID_NAME[$pid]}" took=$((SECONDS - ${PID_START[$pid]}))
        # run.log có thể có dòng ✅ phụ (vd chép DLL) dù build lỗi → lỗi nếu có ❌.
        if grep -q '✅' "$LOG_DIR/$name.run.log" 2>/dev/null && ! grep -q '❌' "$LOG_DIR/$name.run.log"; then
            OK+=("$name"); printf "✅ %s — %s\n" "$name" "$(fmt_time "$took")"
        else
            FAIL+=("$name"); printf "❌ %s — %s (xem %s/%s.run.log)\n" "$name" "$(fmt_time "$took")" "$LOG_DIR" "$name"
        fi
        unset "PID_NAME[$pid]" "PID_START[$pid]"
    done
}

status() {
    local pid last
    for pid in "${!PID_NAME[@]}"; do
        last="$(grep '⏱' "$LOG_DIR/${PID_NAME[$pid]}.run.log" 2>/dev/null | tail -1 | sed 's/^ *//')"
        printf "  … %-40s %s\n" "${PID_NAME[$pid]:0:40}" "${last:-đang khởi động}"
    done
}

echo "Build ${#GAMES[@]} game, $JOBS game cùng lúc:"
printf '  • %s\n' "${GAMES[@]}"

last_status=$SECONDS
for game in "${GAMES[@]}"; do
    while :; do
        reap
        [ "$(running_builds | wc -l)" -lt "$JOBS" ] && [ "$(avail_mb)" -ge "$MIN_AVAIL_MB" ] && break
        if [ $((SECONDS - last_status)) -ge 60 ]; then
            printf "[%s] RAM trống %s MB\n" "$(fmt_time $((SECONDS - t0)))" "$(avail_mb)"; status; last_status=$SECONDS
        fi
        sleep 5
    done
    "$SCRIPT_DIR/build_all.sh" --only "$game" "${FORCE[@]}" > "$LOG_DIR/$game.run.log" 2>&1 &
    PID_NAME[$!]="$game"; PID_START[$!]=$SECONDS
    printf "▶ %s\n" "$game"
    sleep 20   # để bước chiếm RAM đầu tiên (AssetRipper) bắt đầu rồi mới đo RAM cho game kế
done

while [ "${#PID_NAME[@]}" -gt 0 ]; do
    reap
    if [ $((SECONDS - last_status)) -ge 60 ]; then
        printf "[%s] RAM trống %s MB\n" "$(fmt_time $((SECONDS - t0)))" "$(avail_mb)"; status; last_status=$SECONDS
    fi
    sleep 5
done

echo
echo "Tổng kết ($(fmt_time $((SECONDS - t0)))): ${#OK[@]} thành công, ${#FAIL[@]} lỗi"
[ "${#FAIL[@]}" -eq 0 ] || printf '  ❌ %s\n' "${FAIL[@]}"
