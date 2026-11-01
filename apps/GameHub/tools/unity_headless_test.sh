#!/usr/bin/env bash
#
# Test một bản build Unity WebGL bằng Chrome headless.
#
#   ./unity_headless_test.sh <url> [screenshot-out.png] [wait-seconds]
#
# In ra: các lỗi console, và ảnh chụp màn hình (nếu có yêu cầu).
#
set -uo pipefail

URL="${1:?Usage: $0 <url> [screenshot.png] [wait-seconds]}"
SHOT="${2:-}"
WAIT="${3:-25}"

CHROME="$(command -v google-chrome || command -v chromium || command -v chromium-browser)"
PROFILE="$(mktemp -d)"
LOG="$(mktemp)"

CMD=(
    "$CHROME" --headless=new --disable-gpu --no-sandbox
    # WebGL trong headless: dùng SwiftShader (dựng hình bằng CPU)
    --enable-unsafe-swiftshader --use-gl=angle --use-angle=swiftshader
    --enable-logging=stderr --v=0
    --virtual-time-budget="$((WAIT * 1000))"
    --window-size=1280,720
    --user-data-dir="$PROFILE"
)
[ -n "$SHOT" ] && CMD+=(--screenshot="$SHOT")

echo "→ Mở: $URL"
timeout 180 "${CMD[@]}" "$URL" > "$LOG" 2>&1
rc=$?

echo "=== Console (lỗi / cảnh báo quan trọng) ==="
grep -iE "error|exception|failed|cannot|halting" "$LOG" \
    | grep -viE "getInternalformatParameter|deprecated|GPU stall|Fontconfig|dbus|gbm_|vulkan|GLDisplay|egl|swiftshader|Failed to connect|voice_engine" \
    | sort -u | head -25

echo
echo "=== Đã tải resource ==="
grep -oE '"GET [^"]+"' "$LOG" | sort -u | head -20
echo "(exit=$rc)"

if [ -n "$SHOT" ] && [ -f "$SHOT" ]; then
    echo
    echo "→ Ảnh chụp: $SHOT ($(du -h "$SHOT" | cut -f1))"
fi

rm -rf "$PROFILE"
